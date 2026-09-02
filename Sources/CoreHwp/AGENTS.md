# CoreHwp 모듈

라이브러리 target. Public 인터페이스 = `HwpFile`, `HwpError`, `HwpLoadOptions`,
그리고 `Models/` 하위의 모든 `public` 모델 (전부
`HwpPrimitive = Hashable & Sendable` 채택).

**로드 옵션**: `HwpFile(fromPath:options:)` 등에 `HwpLoadOptions`를 넘길 수 있다.
`preserveRawPayload`(기본 true)를 끄면 (`.viewer` 프리셋) 모델의
rawPayload/rawTrailing 보존을 생략해 압축 해제 스트림 버퍼가 파싱 후 즉시
해제된다. 옵션은 `DataReader`가 보유하고 `consumedData` 중앙 관문 + `HwpRecord`를
통해 파싱 트리 전체에 전파된다 — 새 raw-backed 모델은 `HwpLoadOptions`의
`preservedPayload`(off면 비움)/`decoupledPayload`(load 후 재디코딩되는 필드는
off에서도 분리 복사)를 거쳐야 뷰어 모드 메모리 이득이 유지된다.

## 구조

```
CoreHwp/
├── HwpFile.swift        # public 진입점 - 새 public 타입을 여기 직접 추가하지 말 것
├── HwpError.swift       # public error enum
├── CoreHwp.docc/        # 모듈 시작 페이지와 Topics 구성 (배포 사이트의 CoreHwp 문서)
├── Enums/               # tag ID, stream 이름, 컨트롤 ID (raw-value enum)
├── Streams/             # OLE stream별 파일 하나씩 (FileHeader, DocInfo, BodyText, ...)
├── Models/              # stream이 디코딩되는 타입 정의
└── Utils/               # reader, 프로토콜, extension, record tree (Utils/AGENTS.md 참조)
```

## 새 모델 추가하기

1. `Utils/Protocols/`에서 알맞은 프로토콜 선택:
   - `HwpFromData` — 원시 `Data` payload, version·children 모두 불필요
   - `HwpFromDataWithVersion` — `Data` payload + `HwpVersion`
   - `HwpFromRecord` — child record가 있는 record
   - `HwpFromRecordWithVersion` — child record + version
   - `HwpTagValidatedRecord`(`WithVersion`) — record tag 검증이 선행되는
     record. `static let expectedTag`(`HwpSectionTag` 또는 `HwpDocInfoTag`)만
     선언하면 default `load`가 tag 검증 + init + EOF 강제를 제공한다 (#83)
   - `HwpFromUInt` — bit packing된 `DWORD`/`UInt32` 속성 struct
2. 기본은 `init(_ reader: inout DataReader, ...)`만 구현한다. `load(...)`는
   프로토콜의 default 구현이 제공하며 EOF를 강제한다.
   - load 후 record 전체 payload를 `rawPayload`로 복원하는 tag-검증 모델은
     `HwpRawPayloadRestoringRecord`를 함께 채택한다 — 복원 default가 보존
     off(`.viewer`)에서 rawPayload를 비우므로, load 후 rawPayload를 다시 읽는
     모델(`HwpListControl` 참조)에는 쓰지 말 것.
   - `enforcesEOF`는 커스텀 load 시절 EOF를 검사하지 않던 기존 타입의 현행
     동작 보존 스위치다 — 새 타입에서 끄지 말 것. 일괄 강제 전환은 후속
     이슈로 분리한다 (#83).
3. 예외: stream 전체 record-tree 파싱, unknown/raw payload 보존처럼 default
   loader로 표현할 수 없는 경우에는 `load(...)`를 override할 수 있다
   (단순 tag 검증은 예외가 아니다 — `HwpTagValidatedRecord`를 채택한다).
   새 예외를 추가하거나 기존 예외를 수정할 때는
   `// MARK: loader contract exemption - <reason>` 주석으로 이유를 남기고,
   override 안에서 동일한 EOF/typed-error 보장을 직접 유지한다.
4. 기본 모델 `init`은 해석한 byte만 소비한다. unknown payload, raw trailing,
   preview/summary/blob 보존, record-tree stream처럼 남은 byte 자체가 모델 값인
   경우에만 `readToEnd()` 또는 `readBytes(reader.remainBytes)`를 사용할 수 있다.
   이 경우에도 field 이름을 `rawPayload`, `rawTrailing`, `unknown`처럼 보존
   목적이 드러나게 둔다.
5. 사용자 코드에서 접근이 필요하면 타입과 stored property를 `public`으로.
6. 새 공개 진입점이나 기존 범주를 대표하는 모델을 추가했다면
   `CoreHwp.docc/CoreHwp.md`의 `## Topics`에도 등재한다. **모든 공개 모델을
   등재하지는 않는다.** 카탈로그에는 스트림·DocInfo·문단·컨트롤 범주별
   대표 항목만 선별하고, 나머지는 종류별 자동 그룹에 맡긴다. Topics에서
   빠져도 빌드가 성공하므로, 새 공개 진입점이나 대표 모델을 추가할 때는 등재가
   누락되지 않았는지 직접 확인한다(루트 AGENTS.md의 "DocC 문서 사이트").

## 새 stream 추가하기

1. `Enums/HwpStreamName.swift`에 OLE 원시 이름 추가.
2. `Streams/Hwp<Name>.swift` 생성, loader 프로토콜 중 하나 채택.
3. `HwpFile.init(fromOLE:)`에서 `reader.getDataFromStream(...)` 또는
   `reader.getDataFromStorage(...)`로 연결 (후자는 child stream 배열을 반환).
4. version 처리: 기존 호출과 동일하게 `fileHeader.version`과
   `isCompressed`를 그대로 전달할 것. 둘 다 version 별 디코딩에 필요.
5. 새 stream도 `HwpReadLimits` 경로를 거쳐야 한다. 압축 입력과 비압축 stream은
   OLE directory `streamSize`로 사전 제한하고, deflate 출력 한도는 `HwpInflate`가
   전 플랫폼에서 압축 해제 도중에 적용한다. 파일 단위 집계 한도(`maxAggregateStreamBytes`)는
   `StreamReader.readData`가 모든 경로에서 누적하므로 새 stream도 자동 적용된다 —
   reader를 우회해 직접 `ole.stream(...)`을 읽으면 이 방어가 사라진다.
6. storage(자식 stream 배열)를 읽을 때 아는 자식 수가 있으면
   `expectedChildCount`로 넘긴다. 초과·부족 자식 구성은 **압축 해제 전에** typed
   error로 거부된다 — 뒤에 정렬된 초과 자식을 조용히 잘라 내면 남은 자식이
   개수 검증을 통과해 손상된 storage가 유효한 본문을 대체한다.

## 새 컨트롤 ID 추가하기

HWP의 "컨트롤"(표, 다단, 도형, 구역 등)은 단락 stream에 박힌 4-byte 컨트롤
ID로 dispatch된다.

1. 4-byte ID를 `Enums/CtrlId/` 아래 알맞은 파일(Common, Other, Field)에 추가.
2. `Models/Section/CtrlHeader/`에 payload struct 추가.
3. `Enums/CtrlId/HwpCtrlId.swift`의 enum에 case 추가.
4. `Models/HwpParseDiagnostic.swift`의 `collect(ctrl:)`에 진단 순회 case를
   추가한다. `default:` 없는 exhaustive switch라 컴파일러가 누락을 잡아 준다 —
   **`default:`를 넣어 통과시키지 말 것** (그 순간 새 컨트롤의 미해석 자식이
   집계에서 조용히 빠진다). 렌더 스택의
   `HwpUnsupportedDetector.unsupportedHint`와 같은 컨벤션이고, 현재 `HwpCtrlId`
   전수 switch는 이 둘뿐이다 (`unsupportedComponentHint`는 `default:`가 있다).

## 컨벤션

- 공개 타입의 문서 주석은 한컴 공개 문서를 참조하되 한국어로 작성한다. 다만
  **진입점과 스트림 타입의 첫 문단을 절 제목만으로 쓰지 않는다.** DocC가 첫
  문단을 목록 요약으로 사용하므로, `HwpSection`의 "본문"이나 `HwpDocInfo`의
  "문서 정보"처럼 정보가 거의 없는 요약이 생긴다. 한컴 공개 문서의 절 제목은
  첫 문단에 역할 설명과 함께 두고, 기존 설명은 필요한 경우 다음 문단으로 옮겨
  보존한다(루트 AGENTS.md의 "DocC 문서 사이트").
- `Streams/Hwp*.swift`는 최상위 오케스트레이터다 — `parseTreeRecord`로 record를
  꺼내 모델로 dispatch만 수행. 파싱 로직은 stream이 아니라 모델 쪽에 두기.
- **DocInfo children은 단일 분류 패스로 소비한다** (`HwpDocInfo.classify`, #125).
  태그마다 `.first(where:)`/`.filter`를 새로 돌면 최상위 레코드를 태그 수만큼
  훑는다 (종전 12회). keypath 사전 둘(singleton 6종 / multi-record 5종)이
  children을 **한 번** 훑어 슬롯에 담고 나머지는 `unconsumed`로 간다.
  **소비 계약은 그대로 지켜야 한다** — 그 결과가 곧 `unknownRecords`이고
  `parseDiagnostics()`의 입력이다: singleton은 **첫 레코드만** 이기고 중복은
  unknown으로, 미지 태그도 unknown으로, 둘 다 **children 원래 순서**를 보존한다
  (#66의 결정적 순서 계약). `layoutCompatibility`의 `compatibleDocument` 폴백은
  분류가 아니라 **로드 순서**가 지킨다 — 분류는 두 레코드를 나란히 담을 뿐이라
  폴백이 성립하려면 compatibleDocument를 먼저 확정해야 한다. 가드는
  `Tests/CoreHwpTests/Streams/HwpDocInfoClassificationTests.swift`.
- public struct의 default `init()`은 **빈 템플릿 대조용** 객체를 만든다 —
  파싱된 빈 문서와 필드 단위로 비교한다 (`Tests/.../Blank/Create*Tests.swift`
  참조. 직렬화 왕복이 아니다 — 모델은 `Codable`을 채택하지 않는다). 새 public
  모델 추가 시 이 패턴을 따를 것.
- **파생 필드는 저장보다 재계산**을 우선한다. `HwpChar`는 문서 전체 문자 수만큼
  존재하므로 컨트롤 payload를 클래스 박스로 분리해 stride를 16 byte로 유지하고
  (`inlineControl`은 payload에서 지연 계산), setter는 `rawPayload`로 박스를
  재구성해 payload와 desync될 수 없게 한다.
- **caller가 넘긴 한도를 받는 public 파싱 진입점은 먼저
  `options.readLimits.validate()`를 부른다.** 현재 그 지점은 `HwpFile`
  이니셜라이저 4개와 `HwpSection.load`뿐이다. 검증을 빠뜨리면 비-양수 한도가
  typed 진단(`invalidDataLength`) 대신 "모든 레코드가 거부됨"이라는 오해를 부르는
  동작으로 나타난다.

## 안티 패턴

- 모델 안에서 `HwpError`를 catch해서 default 값을 반환 — `HwpFile.init`까지
  전파시킬 것. **명시 예외 (#65)**: `HwpLoadOptions.recoverPartialContent`가
  켜진 경우의 문단·구역·메모 문단 placeholder 대체
  (`HwpParagraph.parseFailurePlaceholder`/`HwpSection.parseFailurePlaceholder`,
  게이트는 `error.isRecoveryExempt`). 이때도 default 값이 아니라 `parseFailure`
  진단과 원본 레코드(`unknownChildren`)를 남기는 placeholder여야 하고, 기본
  모드는 계속 fail-fast다. 이 예외를 다른 모델·다른 error로 넓히지 말 것.
- 이유 없는 `load(...)` override 또는 `reader.readToEnd()` 호출 — EOF 검사를
  우회한다. raw 보존, record-tree 파싱, tag 검증 같은 예외 목적이 명확해야 한다.
- `Sources/`에 `import XCTest`, `@testable`, Nimble 추가 — 모두 금지.
- `HwpPrimitive` 미채택 타입을 `public`으로 승격.

## Reader 지원 범위

최상위 README를 간결하게 유지하기 위해 reader 지원 범위와 검증 증거를 이 문서에 둔다.

## 지원 범위

현재 목표는 읽기 전용 binary HWP reader입니다. 파싱 실패는 crash가 아니라
`HwpError`로 반환하고, 아직 완전히 해석하지 못한 record/control은 raw payload를
보존하는 방향으로 확장하고 있습니다.

HWPX(OWPML, `.hwpx`)는 **변환 파싱**으로 읽습니다 — `HwpFile`의 public init
3종이 파일 선두 바이트로 OLE/ZIP을 자동 감지해, ZIP이면 `Sources/CoreHwp/Hwpx/`
파이프라인이 OWPML XML을 같은 `Hwp*` 모델로 합성합니다 (별도 모델·별도 public
타입 없음, 상세 규약은 `Hwpx/AGENTS.md`). 1차 범위는 본문 텍스트·글자/문단
모양·스타일·구역/쪽 설정·단·표·그림·쪽 번호 위치·OLE 개체(내장 차트)이고, 그 밖의
요소(각주·머리말 내용·도형·수식·번호 매기기 등)는 실제 4CC를 실은 `.notImplemented`와 합성 tagId(0)의
`unknownRecords`로 강등되어 `parseDiagnostics()`에 보고됩니다. 같은 문서의
HWP↔HWPX 파싱 등가는 `Tests/CoreHwpTests/FixtureHarness/Hwpx/`의
`HwpxHwpEquivalenceTests`가 실물 변환 쌍 10종으로 고정합니다.

`HwpReadLimits`는 OLE directory의 stream size를 기준으로 압축 입력과 비압축
stream을 읽기 전에 제한하고, 압축 해제 결과가 한도를 넘으면
`HwpError.streamSizeLimitExceeded`로 거부합니다. `HwpInflate`는 전 플랫폼에서
스트리밍 루프로 이 한도를 압축 해제 **도중**에 적용하므로 실제 메모리 할당
상한입니다 (Apple은 `Compression`, 그 외는 시스템 zlib). 아래 도중 상한의 error
분류 규칙도 플랫폼 구분 없이 같습니다. 개별 stream이 모두 한도 안이어도 자식이 많으면
합계가 커지므로, 파일 단위 `maxAggregateStreamBytes`(기본 1 GiB)를 초과하면
`HwpError.aggregateStreamSizeLimitExceeded`로 거부합니다.

도중 상한은 두 한도의 min으로 걸지만, 보고하는 error와 `limit` payload는 실제로
걸린 쪽의 **원래 한도**를 유지합니다. 두 한도가 같으면 개별 stream 한도를
우선합니다 (후처리 거부 시절의 검사 순서와 같음). 대신 `actual`은 정확한 압축
해제 크기가 아니라 중단 시점까지의 **하한**입니다 — 전체 크기를 알려면 끝까지
풀어야 하는데 그것이 이 상한이 막으려는 동작입니다.

분류가 종전과 갈리는 칸이 **하나** 있습니다. 두 한도를 동시에 넘고 남은 집계
예산이 개별 stream 한도보다 작으면, 후처리 거부 시절에는 개별 stream 검사가 집계
소비보다 먼저라 `streamSizeLimitExceeded`였지만 지금은
`aggregateStreamSizeLimitExceeded`입니다. 역방향(집계 → 개별)은 없습니다.

**복원하지 마십시오.** min에서 멈추므로 개별 한도 초과는 증명되지 않았고,
확인하려면 남은 집계 예산을 넘겨 풀어야 하는데 그것이 이 상한이 막으려는
할당입니다. 증명 없이 개별 error를 고르면 실제로는 개별 한도 안이었던
입력(`남은 예산 < 크기 ≤ 개별 한도`)에 거짓 분류를 주므로, 분기를 없애는 것이
아니라 옮기는 셈입니다. 회귀 가드는
`HwpInflateTests.testDualLimitViolationReportsAggregateWhenAggregateBindsFirst`.

byte 한도와 별개로 레코드 트리 깊이 한도 `maxNestingDepth`(기본 64)가 있습니다.
typed 디코더가 트리를 재귀로 내려가므로(표 셀 문단·리스트 컨트롤·글상자 문단·메모)
깊게 조작된 문서는 스택 오버플로로 crash할 수 있습니다. `parseTreeRecord`에서
`record.level == 트리 깊이` 불변식을 이용해 단일 지점으로 상한하며, 초과 시
payload를 읽기 전에 `HwpError.invalidRecordTree`로 거부합니다. 실문서 실측
최대 level은 5입니다.

2026-06-28 기준 `swift test --enable-code-coverage`를 실행한 뒤
`.build/out/Products/Debug/codecov/Hwp-Swift.json`에서 `Sources/CoreHwp`만
집계했을 때 line coverage는 98.60% (5481/5559), region coverage는
97.56% (2483/2545)입니다.

2026-08-19 기준으로 CI와 같은 방식(`llvm-cov export -format=lcov`에서
`Sources/CoreHwp/`만 집계)으로 다시 재면 line coverage는 97.45%
(8078/8289)입니다. `ci.yml` `Test (macOS)` 잡의 `Enforce coverage thresholds`
스텝은 경로별 lcov line coverage를 재서 `Sources/CoreHwp/`가 95%,
`Sources/HwpKitCore/`가 91% 미만이면 실패시키고, HwpKitNative·HwpKit 두
경로는 값만 기록합니다. Export lcov 스텝은 macOS Debug 산출물 중 SF 레코드가 가장 많은
테스트 번들 하나를 골라 export합니다 — 공유 경로의 수치는 어느 번들로 뽑아도
같지만, 번들마다 담는 경로의 집합이 다르기 때문입니다.

2026-08-25 기준(#81 Codable 제거 직후) 같은 방식으로 재면 line coverage는
97.39% (7831/8041)입니다 — 잘 커버되던 수기 Codable 라인이 분모와 함께
빠져 게이트 마진은 거의 그대로입니다.

| 영역 | 상태 |
| --- | --- |
| OLE compound document 열기 | 지원 |
| `FileHeader`, `DocInfo`, `BodyText/Section*` | 부분 지원. DocInfo/section stream raw payload는 fixture manifest에서 byte 검증하고, 실제 fixture stream 기반 주입 테스트로 unknown section record와 corrupt record 처리를 확인 |
| `U+0005 HwpSummaryInformation` | raw payload 보존. fixture manifest에서 summary length/prefix/suffix bytes를 검증하고, `missing-summary-derived` fixture와 directory-entry mutation 테스트로 stream 부재 시 빈 summary로 처리되는지 검증 |
| `PrvText` | UTF-16LE text와 raw payload 보존. `missing-preview-text-derived` fixture와 directory-entry mutation 테스트로 stream 부재 시 기본 preview text raw payload(`[0x0D, 0x00, 0x0A, 0x00]`)를 반환하는지 검증 |
| `PrvImage` | raw payload와 image format signature 보존, fixture manifest에서 prefix/suffix bytes 검증, 없으면 빈 preview image로 처리 |
| `BinData` storage | stream 이름, stream id, 확장자, raw payload 보존. fixture manifest에서 storage metadata와 payload prefix/suffix bytes 검증하고, `chart` 실제 fixture의 OLE object가 참조하는 `BIN0001.OLE` stream 연결과 payload sample을 별도 회귀 테스트로 확인. 없으면 빈 배열로 처리 |
| `BodyText/Section*` 정렬 | `Section0`, `Section1` 숫자 순 정렬 |
| 추가 root entry (`DocOptions`, `Scripts` 등) | 현재 별도 public model로 노출하지 않음. 실제 한컴오피스 저장본 fixture에서 존재 여부를 manifest로 검증하고, 알려진 stream 파싱이 영향받지 않는지 확인 |
| DocInfo 미해석 record | `unknownRecords`에 raw payload 보존 |
| DocInfo id mappings | fixture manifest에서 주요 mapping count와 raw payload total 검증 |
| DocInfo raw records | `DOC_DATA`는 실제 fixture 기반으로 32-bit word 배열과 trailing bytes를 typed raw model로 노출하고 payload/child를 검증. `DISTRIBUTE_DOC_DATA`도 32-bit word 배열과 trailing bytes를 typed raw model로 보존하며 synthetic/stream 주입 테스트로 확인한다. `MEMO_SHAPE`, `TRACK_CHANGE_CONTENT`, `TRACK_CHANGE_AUTHOR`는 top-level 및 `ID_MAPPINGS` child record를 typed raw model로 보존하고 `track-changes` fixture/synthetic test로 확인. `TRACK_CHANGE_CONTENT`는 kind와 변경 시각, `TRACK_CHANGE_AUTHOR`는 작성자 이름, `TRACK_CHANGE`는 선행 32-bit header 값을 typed model로 노출한다. DocInfo `TRACK_CHANGE`는 `noori` fixture의 compatible document child record(`compatible-track-change-records`)로 검증. 전체 `HwpFile` 조립 경로는 `plain-text-minimal`의 실제 `DocInfo`/`BodyText` stream에 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` raw record를 주입해 보존을 검증한다. 실제 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` fixture(`top-level-track-change-records`)는 추가 필요 |
| `DOC_DATA` 하위 `FORBIDDEN_CHAR` | 실제 fixture 기반 typed model로 파싱하고 raw payload/child records 보존 |
| DocInfo compatible/layout compatibility | 실제 fixture 기반 typed model로 파싱하고 raw payload/child records 보존 |
| section/column/page-number controls | typed model로 파싱하고 raw payload/child records 보존. page-number position은 property와 장식 문자 필드를 fixture manifest로 검증 |
| header/footer/footnote/endnote controls | list header와 내부 paragraph를 typed raw model로 파싱하고 raw payload/child records 보존 |
| list header 속성 (표 89) | 실측 이중 레이아웃: 한/글 윈도우 저장본 (noori)은 방향/줄바꿈/세로 정렬을 bits 16-22에, 한컴오피스 mac 저장본 (text-box)은 스펙 그대로 bits 0-6에 둔다. `HwpListHeaderProperty`는 상위 레이아웃 우선, 전부 0이면 하위 폴백 |
| 내장 OLE 개체 (BinData `.OLE`) | `HwpEmbeddedChart.chartXML`이 4바이트 길이 프리픽스 + CFB에서 `OOXMLChartContents` XML을 추출. OLEKit은 miniFAT 없는 내장 CFB를 거부해 자체 최소 CFB 리더 (`EmbeddedCompoundFile`) 사용 |
| `ViewText` 스토리지 (표시용 본문) | 변경 추적 저장본은 표시 본문 (삭제 텍스트 포함)을 ViewText에 둔다 — `viewSectionArray`로 파싱 (실패 시 빈 배열 폴백), `displaySectionArray`가 렌더 본문 선택. 자식 구성이 BodyText 구역 수와 다르면 압축 해제 전에 거부해 빈 폴백으로 보낸다 (초과분 절단은 손상본을 유효 본문으로 통과시킴). 단 자원 한도 error 2종은 폴백하지 않고 전파. PARA_RANGE_TAG는 한 레코드에 태그 N개 (12바이트씩) — `HwpParaRangeTag.loadArray` |
| table control (`tbl `) | table property와 cell paragraph를 typed model로 파싱하고 cell header raw payload 보존 |
| field hyperlink control (`%hlk`) | URL을 typed model로 파싱하고 raw payload/trailing bytes 보존 |
| field controls | known field ctrl id를 enum으로 보존하고 raw payload/trailing bytes/child records 보존. `memo` 실제 fixture의 `MEMO/...` parameter를 가진 unknown field는 memo control로 분류하고 parameter marker/components/author 보존을 검증. 메모 본문은 문단의 MEMO_LIST(93) 뒤 문단(66) 자식 — `HwpParagraph.memoParagraphArray`로 파싱 (unknownChildren에서 소비) |
| 일반 개체 controls (`$pic`, `$lin`, `eqed`/`equd`, `$ole`, 글상자 등) | typed raw model로 분리하고 common property/shape component/raw payload 보존. `ctrlData` child record는 `HwpCtrlData` typed raw model로 보존. 수식 `eqed`는 `eqEdit` raw record와 수식 문자열을 별도 보존. 글상자는 `genShapeObject` + `rectangle` shape component 및 내부 list/paragraph records를 typed model로 노출하고 미해석 rectangle detail record를 raw payload로 보존. `legacy-common-control-property`의 legacy 44바이트 common property와 polygon component raw payload는 실제 fixture로 검증 |
| gen shape object control (`gso `) | 공통 속성, shape component ctrl id, picture/OLE BinData id를 typed model로 파싱하고 raw payload 보존. `chart` 실제 fixture의 OLE shape component는 raw payload/BinData id를 보존하는지 검증 |
| 기타 known controls (`bokm`, `atno`, `nwno`, `pghd`, `idxm`, `tdut` 등) | typed raw model로 분리하고 raw payload/trailing bytes/child records 보존. `bokm`은 `ctrlData`의 책갈피 이름, `pghd`는 쪽 감추기 raw bit field, `idxm`은 찾아보기 표식 문자열, `atno`는 표 142 전체 필드 (속성/번호/사용자 기호/앞·뒤 장식 문자 — `autoNumberInfo`), `nwno`는 표 144 (속성/번호 — `newNumberInfo`)를 typed model로 노출 (실저장본 byte로 검증). `legacy-common-control-property`의 `hiddenComment` unknown child/grandchild raw payload를 실제 fixture로 검증 |
| 미구현/알 수 없는 control | `.notImplemented` 또는 `.unknown`으로 raw payload 보존. 실제 fixture section stream 기반 주입 테스트로 unknown control payload/child 보존을 확인 |
| 암호 문서 | `HwpError.unsupportedFeature(.encryptedDocument)`. 공인 인증서 암호화 bit도 같은 unsupported로 처리 |
| 배포용 문서 | `HwpError.unsupportedFeature(.deploymentDocument)` |
| 미해석 요소 집계 | `HwpFile.parseDiagnostics()`가 unknown record/control·복구 placeholder를 kind+path로 집계 (`Models/HwpParseDiagnostic.swift`). BodyText·ViewText·DocInfo·메모·중첩 컨트롤 전부 순회, `.default`/`.viewer` 진단 동일. 이중 보고 방지 별칭 규칙은 루트 AGENTS.md "미해석 요소 집계 (#66)" |
| DRM 문서 | `HwpError.unsupportedFeature(.drmDocument)`. 일반 DRM 및 공인 인증서 DRM bit 모두 차단 |
| 쓰기/저장 | 미지원 |
