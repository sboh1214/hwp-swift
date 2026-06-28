# Utils

내부 인프라: loader 프로토콜, byte/bit reader, record tree, 타입 extension.
public API는 여기 없다.

## 구조

```
Utils/
├── HwpRecord.swift       # HwpRecord class + parseTreeRecord(data:) -> root
├── HwpColor.swift        # 색상 helper
├── Type.swift            # DWORD / WORD / WCHAR typealias (HWP 스펙 이름)
├── ExcludeEquatable.swift # == 비교에서 특정 필드를 제외하는 property wrapper
├── Extensions/           # Data, Character, StringProtocol, BinaryInteger, Array, WCHAR
├── Protocols/            # 5개 loader 프로토콜 + HwpPrimitive typealias
└── Readers/              # StreamReader (OLE), DataReader (byte), BitsReader (bit)
```

## Loader 프로토콜 계약

`Protocols/Hwp*From*.swift`의 모든 프로토콜은 동일한 형태를 따른다:

```swift
protocol HwpFromX: HwpPrimitive {
    init(_ reader: inout DataReader, /* 추가 인자 */) throws
    static func load(/* 입력 */) throws -> Self
}

extension HwpFromX {
    static func load(/* 입력 */) throws -> Self {
        var reader = DataReader(data)
        let value = try self.init(&reader, /* 추가 인자 */)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return value
    }
}
```

기본 원칙은 **채택 측이 `init(...)`만 작성하고 `load`는 override하지 않는 것**이다.
EOF 체크는 load-bearing 규약이다 — 스펙 오독뿐 아니라 silent하게 truncate된
payload도 잡아낸다.

예외는 다음 경우에만 허용한다.

- record tag 검증이 default `load`보다 먼저 필요하다.
- stream payload 전체를 `parseTreeRecord(data:)`에 넘겨야 한다.
- unknown record/control 또는 아직 해석하지 않는 trailing bytes를
  `rawPayload`/`rawTrailing`/`unknown`으로 보존해야 한다.
- public convenience loader가 OLE/FileWrapper 같은 다른 입력 형태를 다룬다.

새 예외를 추가하거나 기존 예외를 수정할 때는
`// MARK: loader contract exemption - <reason>` 주석을 `load` override 또는
consumes-all `init` 근처에 남긴다. override는 default loader와 동등하게
`bytesAreNotEOF` 또는 더 구체적인 typed `HwpError`를 보장해야 하며,
`readToEnd()`/`readBytes(reader.remainBytes)`는 그 byte 자체가 모델 값으로 보존될
때만 사용한다.

| 프로토콜 | 언제 사용 |
|----------|-----------|
| `HwpFromData` | 평탄한 `Data` payload, version 무관 |
| `HwpFromDataWithVersion` | 평탄한 `Data` payload, `HwpVersion`에 따라 분기 |
| `HwpFromRecord` | child record가 있는 record; `init(_:_ children:)` |
| `HwpFromRecordWithVersion` | child record + version |
| `HwpFromUInt` | bit packing된 속성을 `DWORD`/`UInt32`에서 디코딩 |

## Reader

- **`StreamReader`** — `(OLEFile, [String: DirectoryEntry])`를 보관. 이름 있는
  stream 또는 storage를 가져와 필요시 `SWCompression`으로 deflate.
  `HwpFile.init(fromOLE:)`에서만 사용.
- **`DataReader`** — `Data` 위의 cursor. `read(T.Type)`은 정수 폭(1/2/4
  byte)으로 분기하며, 미지원 타입은 `HwpError.unsupportedDataReadType`을
  throw한다. `readBytes`/array read는 음수·overflow·범위 초과를
  `HwpError.invalidDataLength` 또는 `HwpError.truncatedData`로 반환한다.
- **`BitsReader`** — `HwpFromUInt` 채택 타입이 packing된 `DWORD`에서 bit를
  떼낼 때 사용. 범위 초과와 잘못된 bit 길이는 `HwpError.truncatedBits` 또는
  `HwpError.invalidDataLength`로 반환한다.

## Record tree

`parseTreeRecord(data:)`는 byte stream을 한 번 순회하며 32-bit 헤더
(`tag:10 | level:10 | size:12`)를 읽는다. `size == 0xFFF`이면 다음 4 byte가
실제 크기. child는 `level`로 중첩된다. 부모가 없는 level jump, 잘린 header,
잘린 payload는 crash가 아니라 typed `HwpError`로 반환한다. root record는
`tagId == 0`이고 payload가 비어 있다. `root.children`을 순회하며 tag로
dispatch.

## 컨벤션

- `Type.swift`의 typealias (`DWORD`, `WORD`, `WCHAR`)는 의도적으로 HWP
  스펙 이름과 일치시킨다 — 한컴 공개 문서를 같이 참조할 것.
- extension은 `Extensions/<Type>+Extension.swift` 형식. 기존 명명과 정확히
  일치.
- `ExcludeEquatable`은 같은 의미로 파싱되지만 실제 값이 다를 수 있는
  필드(예: raw unknown blob)에만 적용. 남용 금지.

## 안티 패턴

- extension에서 `Foundation` 전용 API에 의존 — `Sources/`는 Linux 빌드 가능해야
  한다 (`NSString`, `CoreFoundation` 금지).
- reader/record tree 경계 검증에 `precondition`, force unwrap, `fatalError`를
  사용 — malformed HWP 입력은 모두 typed `HwpError`로 반환해야 한다.
- 여섯 번째 loader 프로토콜 추가 — (Data|Record) × (Version|noVersion) + UInt의
  matrix로 이미 충분하다. 기존 것을 확장할 것.
- 프로토콜 `init`에서 이유 없이 모든 byte를 소진하지 않거나, 반대로
  `readToEnd()`로 잔여 byte를 숨긴다. 기본 모델은 해석한 byte만 소비하고 default
  loader가 EOF를 검증하게 둔다. raw 보존/record-tree 파싱 예외는 위 계약에 맞춰
  명시한다.
