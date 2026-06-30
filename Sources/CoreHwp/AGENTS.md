# CoreHwp 모듈

라이브러리 target. Public 인터페이스 = `HwpFile`, `HwpError`, 그리고
`Models/` 하위의 모든 `public` 모델 (전부 `HwpPrimitive = Hashable & Codable`
채택).

## 구조

```
CoreHwp/
├── HwpFile.swift        # public 진입점 - 새 public 타입을 여기 직접 추가하지 말 것
├── HwpError.swift       # public error enum
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
   - `HwpFromUInt` — bit packing된 `DWORD`/`UInt32` 속성 struct
2. 기본은 `init(_ reader: inout DataReader, ...)`만 구현한다. `load(...)`는
   프로토콜의 default 구현이 제공하며 EOF를 강제한다.
3. 예외: record tag 검증, stream 전체 record-tree 파싱, unknown/raw payload
   보존처럼 default loader로 표현할 수 없는 경우에는 `load(...)`를 override할 수
   있다. 새 예외를 추가하거나 기존 예외를 수정할 때는
   `// MARK: loader contract exemption - <reason>` 주석으로 이유를 남기고,
   override 안에서 동일한 EOF/typed-error 보장을 직접 유지한다.
4. 기본 모델 `init`은 해석한 byte만 소비한다. unknown payload, raw trailing,
   preview/summary/blob 보존, record-tree stream처럼 남은 byte 자체가 모델 값인
   경우에만 `readToEnd()` 또는 `readBytes(reader.remainBytes)`를 사용할 수 있다.
   이 경우에도 field 이름을 `rawPayload`, `rawTrailing`, `unknown`처럼 보존
   목적이 드러나게 둔다.
5. 사용자 코드에서 접근이 필요하면 타입과 stored property를 `public`으로.

## 새 stream 추가하기

1. `Enums/HwpStreamName.swift`에 OLE 원시 이름 추가.
2. `Streams/Hwp<Name>.swift` 생성, loader 프로토콜 중 하나 채택.
3. `HwpFile.init(fromOLE:)`에서 `reader.getDataFromStream(...)` 또는
   `reader.getDataFromStorage(...)`로 연결 (후자는 child stream 배열을 반환).
4. version 처리: 기존 호출과 동일하게 `fileHeader.version`과
   `isCompressed`를 그대로 전달할 것. 둘 다 version 별 디코딩에 필요.
5. 새 stream도 `HwpReadLimits` 경로를 거쳐야 한다. 압축 입력과 비압축 stream은
   OLE directory `streamSize`로 사전 제한하지만, deflate 출력 한도는
   `SWCompression`이 반환한 뒤 typed error로 후처리 거부하는 제한이며 압축 해제 중
   메모리 할당 cap이 아니다.

## 새 컨트롤 ID 추가하기

HWP의 "컨트롤"(표, 다단, 도형, 구역 등)은 단락 stream에 박힌 4-byte 컨트롤
ID로 dispatch된다.

1. 4-byte ID를 `Enums/CtrlId/` 아래 알맞은 파일(Common, Other, Field)에 추가.
2. `Models/Section/CtrlHeader/`에 payload struct 추가.
3. `Enums/CtrlId/HwpCtrlId.swift`의 enum에 case 추가하고, manual
   `Codable` 구현 (`CodingKeys`, `init(from:)`, `encode(to:)`)도 갱신할 것.
   이종 associated value 때문에 자동 합성되지 않는다.

## 컨벤션

- public 타입의 doc-comment는 한컴 공개 문서를 참조하는 한국어로 유지.
- `Streams/Hwp*.swift`는 최상위 오케스트레이터다 — `parseTreeRecord`로 record를
  꺼내 모델로 dispatch만 수행. 파싱 로직은 stream이 아니라 모델 쪽에 두기.
- public struct의 default `init()`은 round-trip 비교용 빈 객체를 만든다
  (`Tests/.../Blank/Create*Tests.swift` 참조). 새 public 모델 추가 시
  이 패턴을 따를 것.

## 안티 패턴

- 모델 안에서 `HwpError`를 catch해서 default 값을 반환 — `HwpFile.init`까지
  전파시킬 것.
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

`HwpReadLimits`는 OLE directory의 stream size를 기준으로 압축 입력과 비압축
stream을 읽기 전에 제한하고, 압축 해제 결과가 한도를 넘으면
`HwpError.streamSizeLimitExceeded`로 거부합니다. 단, 현재 `SWCompression`
Deflate API는 bounded streaming inflate를 제공하지 않으므로 압축 해제 결과 한도는
inflate가 끝난 뒤 검사하는 후처리 거부입니다. 이 제한은 typed error 반환을 위한
검증이지, 압축 해제 중 메모리 할당 상한을 보장하지 않습니다.

2026-06-28 기준 `swift test --enable-code-coverage`를 실행한 뒤
`.build/out/Products/Debug/codecov/Hwp-Swift.json`에서 `Sources/CoreHwp`만
집계했을 때 line coverage는 98.60% (5481/5559), region coverage는
97.56% (2483/2545)입니다.

| 영역 | 상태 |
| --- | --- |
| OLE compound document 열기 | 지원 |
| `FileHeader`, `DocInfo`, `BodyText/Section*` | 부분 지원. DocInfo/section stream raw payload는 fixture manifest에서 byte 검증하고, 실제 fixture stream 기반 주입 테스트로 unknown section record와 corrupt record 처리를 확인 |
| `U+0005 HwpSummaryInformation` | raw payload 보존. fixture manifest에서 summary length/prefix/suffix bytes를 검증하고, `missing-summary-derived` fixture와 directory-entry mutation/Codable round-trip 테스트로 stream 부재 시 빈 summary로 처리되는지 검증 |
| `PrvText` | UTF-16LE text와 raw payload 보존. `missing-preview-text-derived` fixture와 directory-entry mutation/Codable round-trip 테스트로 stream 부재 시 기본 preview text raw payload(`[0x0D, 0x00, 0x0A, 0x00]`)를 반환하는지 검증 |
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
| table control (`tbl `) | table property와 cell paragraph를 typed model로 파싱하고 cell header raw payload 보존 |
| field hyperlink control (`%hlk`) | URL을 typed model로 파싱하고 raw payload/trailing bytes 보존 |
| field controls | known field ctrl id를 enum으로 보존하고 raw payload/trailing bytes/child records 보존. `memo` 실제 fixture의 `MEMO/...` parameter를 가진 unknown field는 memo control로 분류하고 parameter marker/components/author 및 Codable round-trip 보존을 검증 |
| 일반 개체 controls (`$pic`, `$lin`, `eqed`/`equd`, `$ole`, 글상자 등) | typed raw model로 분리하고 common property/shape component/raw payload 보존. `ctrlData` child record는 `HwpCtrlData` typed raw model로 보존. 수식 `eqed`는 `eqEdit` raw record와 수식 문자열을 별도 보존. 글상자는 `genShapeObject` + `rectangle` shape component 및 내부 list/paragraph records를 typed model로 노출하고 미해석 rectangle detail record를 raw payload로 보존. `legacy-common-control-property`의 legacy 44바이트 common property와 polygon component raw payload는 실제 fixture와 Codable round-trip으로 검증 |
| gen shape object control (`gso `) | 공통 속성, shape component ctrl id, picture/OLE BinData id를 typed model로 파싱하고 raw payload 보존. `chart` 실제 fixture의 OLE shape component는 raw payload/BinData id를 `HwpCtrlId` Codable round-trip 후에도 보존하는지 검증 |
| 기타 known controls (`bokm`, `atno`, `nwno`, `pghd`, `idxm`, `tdut` 등) | typed raw model로 분리하고 raw payload/trailing bytes/child records 보존. `bokm`은 `ctrlData`의 책갈피 이름, `pghd`는 쪽 감추기 raw bit field, `idxm`은 찾아보기 표식 문자열을 typed model로 노출. `legacy-common-control-property`의 `hiddenComment` unknown child/grandchild raw payload를 실제 fixture와 Codable round-trip으로 검증 |
| 미구현/알 수 없는 control | `.notImplemented` 또는 `.unknown`으로 raw payload 보존. 실제 fixture section stream 기반 주입 테스트로 unknown control payload/child 보존을 확인 |
| 암호 문서 | `HwpError.unsupportedFeature(.encryptedDocument)`. 공인 인증서 암호화 bit도 같은 unsupported로 처리 |
| 배포용 문서 | `HwpError.unsupportedFeature(.deploymentDocument)` |
| DRM 문서 | `HwpError.unsupportedFeature(.drmDocument)`. 일반 DRM 및 공인 인증서 DRM bit 모두 차단 |
| 쓰기/저장 | 미지원 |
