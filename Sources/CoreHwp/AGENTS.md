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
2. `init(_ reader: inout DataReader, ...)`만 구현. `load(...)`는 프로토콜의
   default 구현이 제공하며 EOF를 강제한다.
3. `init` 안에서 **모든 byte를 정확히 소진**할 것. 잔여가 있으면
   `HwpError.bytesAreNotEOF`가 throw 된다.
4. 사용자 코드에서 접근이 필요하면 타입과 stored property를 `public`으로.

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

1. 4-byte ID를 `Enums/Ctrl Id/` 아래 알맞은 파일(Common, Other, Field)에 추가.
2. `Models/Section/Ctrl Header/`에 payload struct 추가.
3. `Enums/Ctrl Id/HwpCtrlId.swift`의 enum에 case 추가하고, manual
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
- 모델 `init` 안에서 `reader.readToEnd()` 호출 — 잔여 byte 검사가 무효화된다.
  `parseTreeRecord` 호출 측에서만 사용.
- `Sources/`에 `import XCTest`, `@testable`, Nimble 추가 — 모두 금지.
- `HwpPrimitive` 미채택 타입을 `public`으로 승격.
