# CoreHwpTests

XCTest target. **Nimble 단독 사용** — `XCTAssert*`는 SwiftLint custom rule
`no_xctassert` (severity: error)로 금지.

## 구조

```
CoreHwpTests/
├── Utils.swift              # openHwp() + createHwp() helper (아래 참조)
├── SectionRecordBuilder.swift  # 레코드 스트림 프레이밍 단일 출처 (아래 참조)
├── Assembly/                # HwpFile assembly/entrypoint regression tests
│   ├── ControlObjects/
│   ├── ControlText/
│   ├── DocInfo/
│   ├── Entrypoints/
│   ├── Records/
│   └── Streams/
├── Controls/                # control ID, payload, fallback/preservation tests
│   ├── Common/
│   ├── Field/
│   ├── List/
│   ├── Other/
│   ├── ShapeComponents/
│   ├── ShapeObjects/
│   └── Table/
├── Entries/                 # OLE DirectoryEntry mutation/entrypoint tests
│   ├── DirectoryEntry/
│   └── FileHeader/
├── FixtureHarness/          # manifest 기반 harness/assertion/gate tests
│   ├── DocInfoCore/
│   ├── DocInfoRaw/
│   ├── FieldControls/
│   ├── FixtureCore/
│   ├── FixtureRegression/
│   ├── ListControls/
│   ├── Manifest/
│   ├── OtherControls/
│   ├── PageControls/
│   ├── Paragraphs/
│   ├── ShapeObjects/
│   ├── Streams/
│   └── TableColumn/
├── LoadOptions/             # HwpLoadOptions (rawPayload opt-out) tests
├── Models/                  # standalone model tests
│   ├── Document/
│   └── Layout/
├── Performance/             # HWP_PERF 게이트 + 합성 대형 문서 빌더
├── Stability/               # parser/model malformed, unknown, stability tests
│   ├── Core/
│   ├── Formats/
│   ├── Paragraphs/
│   └── Parsing/
├── Streams/                 # stream, preview, decompression, binary-data tests
│   ├── BinaryData/
│   ├── Preview/
│   └── Readers/
├── Utils/                   # reader/error/project utility tests
│   ├── Core/
│   ├── Project/
│   └── Readers/
├── Fixtures/                # fixture-id/document.hwp + manifest.json + README.md
├── Fixture*.swift           # tests that read manifest support files by root path
├── FileHeader/
├── Blank/
├── Noori/
├── Versions/
├── DocInfo/{BinData,CharShape,Core,IdMappingRecords,IdMappingShapes,RawRecords,TrackChanges}/
└── Section/Column/
```

상위 폴더의 `Tests/LinuxMain.swift`는 SwiftPM Linux의 legacy 진입점이다.
`swift test --enable-test-discovery`가 깨지지 않는 한 건드릴 일 없음.

## Fixture 구조

새 fixture는 다음 구조로 추가한다.

```text
Tests/CoreHwpTests/Fixtures/<fixture-id>/
  document.hwp
  manifest.json
  README.md
```

- `document.hwp`: 실제 한컴오피스 저장본, 기존 repo fixture 이관본, 또는
  명시적으로 표시한 derived fixture.
- `manifest.json`: 생성 도구, HWP 버전, 출처, feature tag, 의미 있는 기대값
  (section/paragraph/text/control count, payload sample, unsupported error 등).
- `README.md`: 재생성 절차와 파생 fixture라면 원본/변형 절차.

새 기대값은 가능하면 `FixtureLoader`/`FixtureManifest`/`FixtureAssertions` 계열
harness에 추가하고, 단순히 "열린다"가 아니라 manifest 값과 실제 파싱 결과를
비교한다. 저수준 corrupt/malformed regression만 synthetic data를 사용한다.

## Fixture 로딩

[`Utils.swift`](file:///Users/sboh/Repos/hwp-swift/Tests/CoreHwpTests/Utils.swift)의
두 helper로 로드한다. helper는 기존 colocated fixture를 먼저 찾고, 없으면
중앙 fixture root의 `Fixtures/<name>/document.hwp`를 사용한다.

```swift
let hwp = try openHwp(#file, "plain-text-minimal")
let (this, official) = try createHwp(#file, "blank-win2020")
```

`#file`은 컴파일러가 주입하는 절대 경로다. **항상 `#file`을 넘길 것** —
경로 하드코딩이나 `Bundle.module` 사용 금지 (`Package.swift`에 SwiftPM
resource bundle을 선언하지 않았다).

## 합성 레코드 스트림

손상·적대 입력 테스트가 쓰는 레코드 프레이밍은
[`SectionRecordBuilder.swift`](file:///Users/sboh/Repos/hwp-swift/Tests/CoreHwpTests/SectionRecordBuilder.swift)가
단일 출처다.

| 함수 | 언제 |
|------|------|
| `record(tagId:level:payload:)` | 정상 레코드. payload ≥ 0xFFF면 확장 크기 형식을 알아서 쓴다 |
| `header(tagId:level:size:)` | size 필드를 **그대로** 심는 적대 입력 (0xFFF sentinel만 두고 뒤 UInt32를 생략하는 등) |
| `nestedChain(depth:)` | level 0 ..< depth 체인. 결과 스트림의 최대 level은 `depth - 1` |

프레이밍을 손으로 쓰지 말 것. private 사본 대부분이 확장 크기 분기를 빠뜨려
payload가 0xFFF 이상이면 size 비트가 level 필드로 넘쳐 헤더가 조용히 깨졌다.
아직 사본이 남은 파일이 30여 개 있다 — 새로 만들지 말고, 만지는 김에 이관한다.

깊이 한도 회귀(`Stability/Parsing/RecordDepthLimitTests.swift`)는 전 픽스처를
`maxNestingDepth: 8`로 잠그고, `noori`가 `maxNestingDepth: 2`에서 거부되는지를
함께 검사해 가드가 공허하지 않음을 증명한다. 새 픽스처가 8에서 실패하면
**한도를 올려 덮지 말 것** — 실측 최대 level은 5이므로 픽스처나 파서 쪽을 먼저
의심한다.

## 부분 복구 스위트 (#65·#67)

`recoverPartialContent` 복구는 손상 입력이 대상이라 합성 레코드 스트림
(`SectionRecordBuilder`)으로 검증한다. 계약과 함정은 루트 `AGENTS.md` "부분
복구"에 있고, 여기 스위트는:

- `Utils/Core/HwpErrorTests.swift`의
  `testRecoveryExemptSetCoversResourceLimitsAndUnsupportedFeature` — recovery-exempt
  집합(`isRecoveryExempt`: 자원 한도 2종 + `unsupportedFeature`)을 `HwpError`
  **케이스 단위로** 고정한다. 새 error 케이스를 추가하면 이 스펙이 분류를
  강제한다 — **`invalidRecordTree`가 exempt로 새어 들면 여기서 빨개진다**
  (그 케이스를 비-exempt로 명시 단언).
- `Stability/Parsing/ControlFallbackErrorSetSpecTests.swift` — 별개 축이다.
  복구 exempt가 아니라 문단의 `canFallbackToRaw*` 세 판정(표/리스트/도형 컨트롤을
  `.notImplemented`·other로 raw 보존할지 vs 전파할지)을 error 케이스 단위로
  잠근다. 이름이 비슷하나 `isRecoveryExempt`와 혼동하지 말 것.
- `Stability/Paragraphs/ParagraphRecoveryPlaceholderTests.swift` — 문단·구역·
  메모 placeholder 생성과 `parseFailure` 진단. 복구가 켜져야만 대체되고 꺼진
  기본 모드는 계속 throw함을 대조군으로 함께 단언한다 (깊이 한도의 "공허하지
  않음" 증명과 같은 규율). **첫 문단 손상의 구역 단위 승격**(#110)도 여기서
  잠그되, 중간 문단 손상이 종전대로 문단 placeholder로 남는 대조군을 짝으로
  둔다 — 한쪽만 있으면 승격을 전 문단으로 넓힌 구현도 통과한다.
  **손상 문단을 첫 자리에 두는 합성 스트림은 이제 의미가 다르다**: 문단
  placeholder 경로를 검증하려면 앞에 정상 문단을 둬야 한다 (이 규칙을 어겨
  `ControlFallbackErrorSetSpecTests`·ViewText 폐기 테스트가 한 번씩
  잘못된 이유로 통과할 뻔했다).
- `Stability/Paragraphs/ParaTextWcharCountTests.swift` — didSet 재동기화와
  round-trip 동등성(wcharCount 비교 제외)을 고정.
- `Stability/Parsing/SectionNestedAdversarialTests.swift`,
  `Stability/Paragraphs/ParagraphMemoRecursionTests.swift` — 중첩·메모 복구의
  적대 입력. 뷰어 진단 노출(`kind: .placeholder`)은 `HwpKitCoreTests`의
  `HwpPaginatorRecoveryPlaceholderTests`가 본다.

## 압축 해제 기준선 (#68, #101)

`Streams/Readers/HwpInflateTests.swift`는 두 프로덕션 경로(Apple `Compression`,
비-Apple system zlib)가 순수 Swift 기준선(oracle)인 `SWCompression`과 **바이트
단위로 같은 출력**을 내는지 고정한다. #101에서 프로덕션이 SWCompression 의존을
끊었으므로 `Package.swift`의 CoreHwpTests가 **유일한** 의존 지점이다.

- **`SWCompression`에 임의 바이트를 먹이지 말 것.** `Deflate.decompress`는
  deflate가 아닌 입력에서 throw가 아니라 **프로세스를 중단**시킨다 (실측:
  `bookmark`의 `PrvText` 64 byte —
  `testNonDeflatePlainTextStreamIsRejectedInsteadOfTrapping`이 그 바이트열을
  `HwpInflate`에만 넣어 고정한다). 그래서 코퍼스를 "SWCompression이 푸는가"로
  정의할 수 없다. 절단·손상 단언은 `HwpInflate`에만 하고, 이 파일이 다는
  단언은 두 백엔드가 같은 판정을 내는 입력만 다루므로 플랫폼으로 가르지
  않는다 — 판정이 갈리는 구간(huffman block 뒤 stored block의 `NLEN`, 손상과
  상한 초과 동시 입력)은 `Sources/CoreHwp/Utils/AGENTS.md`에 적어 두었으니
  거기에 가드 없는 단언을 새로 달지 말 것. 문서 레벨의 손상 판정은
  `StreamDecompressionStabilityTests`가 계속 맡는다.
- 코퍼스는 프로덕션이 실제로 푸는 stream만 모은다 (`DocInfo` +
  `BodyText`/`ViewText` 자식). 암호·DRM·배포용 4종은 압축 해제 **전에**
  `unsupportedFeature`로 거부되어 압축 경로에 닿지 못하므로 `expectedError`
  매니페스트로 거른다 — 그 문서들의 stream은 deflate가 아니다.
- **이 파일에는 디코더 가드(`#if canImport(Compression)`)가 없다.** #101 전에는
  비-Apple 경로가 기준선 자신이라 동등성 비교가 항등식이었지만, 지금은 zlib과
  SWCompression이 서로 독립이라 Linux 잡이 그 비교의 실효 검증이다. 도중 상한과
  error 분류 계약도 마찬가지로 전 플랫폼 공통이다. 되살리지 말 것 — 가드를
  다시 넣으면 zlib 경로가 CI에서 한 번도 판정되지 않는다.
- 코퍼스를 **전수로 도는** 3종의 `beGreaterThanOrEqualTo(100)`은 코퍼스가
  비거나 경로가 어긋나 **아무것도 비교하지 않은 채 초록**이 되는 것을 막는다.
  픽스처는 늘어나는 방향으로만 움직이므로 내려서 통과시키지 말 것.

## 테스트 스타일

| 패턴 | 예시 | 언제 |
|------|------|------|
| 속성 단순 비교 | `expect(hwp.fileHeader.version) == HwpVersion(5, 0, 2, 2)` | 단일 값 검증 |
| 패턴 매칭 | `switch ctrl { case let .table(t): ... }` | 컨트롤 enum dispatch 검증 |
| Round-trip diff | `expect(this.fileHeader) == official.fileHeader` | `Create*Tests.swift` — `HwpFile()`가 파싱된 빈 파일과 일치함을 증명 |
| Negative TODO | `expect(...) != true`와 `// TODO: Investigate why false` | 알려진 파서 미구현 영역 (삭제 금지) |

## 컨벤션

- 테스트 클래스는 `final class XyzTests: XCTestCase`.
- 정체불명 payload를 살펴볼 때는 `dump(...)` 활용 — 조사 중에만 남기고
  merge 전 제거.
- `// TODO: Investigate why false` 주석이 붙은 negative 테스트는 의도된
  자리표시자다. **`expect(...) == false`로 바꿔서 "깔끔하게" 통과시키지
  말 것** — TODO 자체가 의미.

## 안티 패턴

- `XCTAssertEqual`, `XCTAssertTrue` 등 — `no_xctassert`로 CI fail.
- 픽스처 lookup에 `Bundle.module` / `Bundle(for:)` 사용 — `Package.swift`에
  resource 선언이 없으므로 `openHwp(#file, ...)` 사용.
- 새 `.hwp` 파일을 `Blank/`, `FileHeader/`, `Noori/` 같은 legacy test 폴더에
  직접 추가하기 — 새 fixture는 `Fixtures/<fixture-id>/` 구조로 추가한다.
- 주석 처리된 테스트 (예: `testIsDepolymentDocument`) 삭제 — 스펙 갭을
  표시하는 자리표시자다. 정식 테스트로 바꾸려면 누락된 파서 경로를 먼저
  구현해야 한다.
