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
