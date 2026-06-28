# CoreHwpTests

XCTest target. **Nimble 단독 사용** — `XCTAssert*`는 SwiftLint custom rule
`no_xctassert` (severity: error)로 금지.

## 구조

```
CoreHwpTests/
├── Utils.swift              # openHwp() + createHwp() helper (아래 참조)
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
├── Models/                  # standalone model tests
│   ├── Document/
│   └── Layout/
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
├── DocInfo/{BinData,CharShape}/
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
