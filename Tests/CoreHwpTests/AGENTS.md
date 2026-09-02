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

HWPX fixture는 **별도 루트** `Tests/CoreHwpTests/HwpxFixtures/<fixture-id>/`
(`document.hwpx` + `manifest.json` + `README.md`)를 쓴다 — 이 루트의 가드
(`HwpxFixtureManifestTests`)와 아래 스윕 핀은 `document.hwp`/`.hwp`만 보므로
서로 간섭하지 않는다. 로더는 `HwpxFixtureLoader`, 열기는
`openHwpx(#file, "id")`(public 자동 감지 진입점 경유), 원본 HWP와의 파싱
등가는 `HwpxHwpEquivalenceTests`가 `sourceHwpFixture` 링크로 비교한다. 생성
정책은 `HwpxFixtures/README.md` 참조.

**픽스처 추가는 이 타깃 밖으로도 번진다** (#80). `HwpKitCoreTests`의
`HwpLayoutRenderParitySweepTests`가 `Fixtures/*/document.hwp`를 **디렉터리에서
직접 훑어** 측정·렌더 등가를 대조하므로, 새 픽스처는 harness 등록 없이 자동으로
그 스윕에 들어오고 실측 핀(`expectedFixtureVisited`·`expectedFixtureMeasured`·
`expectedFixtureContainers`)이 어긋나 빨개진다 — 재측정해 갱신한다. FileHeader
단계에서 거부되는 픽스처(암호·배포용·DRM)를 더했다면 그쪽 `unreadableFixtureIds`
집합에도 넣어야 한다: 스윕은 읽기 실패를 `try?`로 조용히 넘기지 않고 **집합
자체를 단언**해, 파서 회귀로 멀쩡한 픽스처가 순회에서 빠져도 초록이 되는 것을
막는다.

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
  집합(`isRecoveryExempt`: 자원 한도 3종 + `unsupportedFeature`)을 `HwpError`
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
- `Stability/Paragraphs/ParaTextWcharCountTests.swift` — 파스 루프 누적값과
  didSet 재동기화를 고정 (wcharCount는 동등성 비교에서 제외).
- `Stability/Parsing/SectionNestedAdversarialTests.swift`,
  `Stability/Paragraphs/ParagraphMemoRecursionTests.swift` — 중첩·메모 복구의
  적대 입력. 뷰어 진단 노출(`kind: .placeholder`)은 `HwpKitCoreTests`의
  `HwpPaginatorRecoveryPlaceholderTests`가 본다.

## 미해석 요소 집계 스위트 (#66)

`HwpFile.parseDiagnostics()`의 kind·path 계약은 네 파일이 잠근다 (합성 빌더는
`Models/Document/ParseDiagnosticsTestSupport.swift` 공용, 프레이밍은
`SectionRecordBuilder` 위임).

- `Models/Document/ParseDiagnosticsTests.swift` — 합성 스트림으로 unknown
  record/control·`.child[i]` 재귀·표 셀 중첩 path·raw 폴백(.notImplemented)
  컨트롤·ViewText path 분리·`.default`/`.viewer` 동일성을 고정한다.
- `Models/Document/ParseDiagnosticsRecoveryTests.swift` — 복구 placeholder
  3층(구역/문단/메모)의 kind·detail·placeholder 원본 record의 unknownChild
  동반 방출·메모 그룹 path 인덱스를 고정한다.
- `Models/Document/ParseDiagnosticsFallbackTests.swift` — 제네릭 raw 래퍼로
  떨어진 승격 실패(`.other` 4종 경로·`.field` 하이퍼링크)가 보고되는지, 그리고
  **같은 래퍼가 제자리인** 컨트롤(`.bookmark`·정상 `.field`)에는 붙지 않는지를
  짝으로 고정한다 — 음성 대조군이 없으면 "래퍼면 무조건 보고"라는 오탐 구현도
  통과한다. 각 테스트가 정말 그 폴백 경로에 떨어졌는지 전제 단언으로 확인하며,
  구역 정의만 자식을 절단해 넣는다 (자식 부재는 `recordDoesNotExist`라 폴백
  집합 밖이라 전파된다).
- `FixtureHarness/FixtureRegression/FixtureParseDiagnosticsTests.swift` —
  픽스처 전수 무크래시·결정성·두 모드 동일성·복구 kind 부재 + manifest의
  `sectionUnknownRecordCount`/`docInfoUnknownRecordCount` 계열 대조 (실제
  manifest 기대값이 전부 0이라, 합성 manifest + 합성 문서 **양성 대조군**이
  필터 정규식의 공허화를 막는다). 실저장본 비-공허 앵커는
  `legacy-common-control-property`의 hiddenComment unknown child 3건이고,
  track-changes는 실제 BodyText/ViewText stream에 unknown record를 **주입**해
  두 본문의 진단이 path 접두사로 갈림을 고정한다 (원본 저장본 자체는 진단
  0건 — 여기서 진단이 생기면 typed 파싱 회귀 신호).

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

## tag 검증 load 스위트 (#83)

`DocInfo/RawRecords/DocInfoRawRecordTagValidationTests.swift`가
**`loadDocInfoRecord`의 유일한 소비자**다 — 프로덕션 호출부는 전부 프로토콜
default `load`로 옮겨졌다. 프로덕션 미참조라고 지우지 말 것: 임의
`HwpFromRecord` 타입에 DocInfo tag 검증을 조합했을 때의 typed-error 계약은 그
진입점에서만 검사할 수 있다 (채택 타입은 자기 `expectedTag`가 이미 박혀 있다).

- **그 헬퍼에 tag-검증 채택 타입을 넘기면 두 번 검증된다** (헬퍼 인자 tag +
  타입 고유 `expectedTag`). 그래서 이 파일의 tag 불일치 단언은 헬퍼가 아니라
  모델의 `load`를 직접 부른다 — 감싸면 어느 쪽 검증이 던졌는지 구별되지 않는다.
- **`enforcesEOF` default(`true`)를 잠그는 것은 `Models/Layout/`의 두 파일이다** —
  `CompatibleDocumentStabilityTests`·`LayoutCompatibilityStabilityTests`가
  tag-검증 모델의 `load`에서 `bytesAreNotEOF`를 단언하므로 default가 뒤집히면
  여기서 빨개진다. `Stability/Core/LoaderProtocolStabilityTests.swift`는 base
  프로토콜 5종의 EOF만 보므로 이 갈래를 대신 증명하지 않는다.

## Codable 제거 이후 (#81)

CoreHwp 모델이 `Codable`을 채택하지 않으므로 이 타깃에 직렬화 왕복 스위트는
없다 (근거는 루트 `AGENTS.md` 노트). 남은 자리 둘만 기억할 것.

- **매니페스트가 CoreHwp enum을 문자열로 싣는 필드**는
  [`FixtureManifestSupport.swift`](file:///Users/sboh/Repos/hwp-swift/Tests/CoreHwpTests/FixtureManifestSupport.swift)가
  **디코딩만** 되살린다 — 현재 `previewImageFormat`(`HwpPreviewImageFormat`)
  하나이고, `RawRepresentable`이라 `extension …: Decodable {}` 한 줄이면 된다.
  **`@retroactive`를 붙이지 말 것**: CoreHwp는 다른 모듈이지만 같은
  **패키지**라 SwiftPM이 넘기는 `-package-name` 덕에 소급 채택 진단 대상이
  아니고, 붙이면 Swift 5 모드에서 경고(`'retroactive' attribute does not
  apply; … is declared in the same package`)·Swift 6 language mode에서
  **에러**다 (실측: swift 6.4). 컴파일러 버전 분기도 필요 없다 — plain 채택이
  5.9와 6.x 양쪽에서 진단 0건이다. 새 매니페스트 필드에 CoreHwp enum을 쓰면
  여기에 한 줄을 더하고, **모델 쪽 Codable을 되살려 해결하지 말 것.**
- **왕복 스위트가 유일한 커버리지였던 파스 단언**이 있었다. 삭제 과정에서
  드러난 실례: 표 40 문단 머리 글자 모양 ID의 **양수** 파싱을 단언하던 곳은
  `…SurviveCodableRoundTrip` 하나뿐이었고, 남는 테스트는 기본값 `-1`만 봐서
  **슬롯을 소비만 하고 상수를 저장하는 회귀와 구별되지 않았다**
  (`DocInfo/IdMappingShapes/StyleRawPayloadTests.swift`의
  `testBulletParsesPositiveHeadCharShapeIdFromTable40Layout`으로 직접 로드
  단언을 복원). 스위트를 통째로 지우기 전에 그 파일이 직렬화가 아니라
  **파싱**에 대해 유일하게 단언하던 것이 없는지 확인한다.

## 테스트 스타일

| 패턴 | 예시 | 언제 |
|------|------|------|
| 속성 단순 비교 | `expect(hwp.fileHeader.version) == HwpVersion(5, 0, 2, 2)` | 단일 값 검증 |
| 패턴 매칭 | `switch ctrl { case let .table(t): ... }` | 컨트롤 enum dispatch 검증 |
| 빈 템플릿 대조 | `expect(this.fileHeader) == official.fileHeader` | `Create*Tests.swift` — `HwpFile()`가 파싱된 빈 파일과 일치함을 증명 (직렬화 왕복이 아니다) |
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
