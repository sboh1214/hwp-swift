# CoreHwpTests

XCTest target. **Nimble 단독 사용** — `XCTAssert*`는 SwiftLint custom rule
`no_xctassert` (severity: error)로 금지.

## 구조

```
CoreHwpTests/
├── Utils.swift              # openHwp() + createHwp() helper (아래 참조)
├── HwpUtilTests.swift
├── HwpErrorTests.swift
├── CtrlIdTests.swift
├── FileHeader/              # *.hwp 픽스처 + *Tests.swift 같은 폴더에 배치
├── Blank/                   # Create2014Tests, Create2018Tests, BlankTests
├── Noori/                   # NooriPreviewTests, NooriDocInfoTests, NooriSectionTests
├── Versions/                # 2007.hwp, 2014VP.hwp + VersionTests
├── DocInfo/{BinData,CharShape}/   # 서브시스템별 픽스처
└── Section/Column/
```

상위 폴더의 `Tests/LinuxMain.swift`는 SwiftPM Linux의 legacy 진입점이다.
`swift test --enable-test-discovery`가 깨지지 않는 한 건드릴 일 없음.

## 픽스처 로딩

픽스처 `.hwp` 파일은 **그 파일을 사용하는 테스트 파일과 같은 폴더에**
배치한다. [`Utils.swift`](file:///Users/sboh/Repos/hwp-swift/Tests/CoreHwpTests/Utils.swift)의 두 helper로 로드:

```swift
let hwp = try openHwp(#file, "noori")          // → ./noori.hwp 파싱
let (this, official) = try createHwp(#file, "blank-win2020")
                                                // → 빈 HwpFile() + 파싱된 official
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
- 공용 `Fixtures/` 폴더에 픽스처 모으기 — colocation 컨벤션 위반.
  helper는 `#file.deletingLastPathComponent`로 경로를 해석한다.
- 주석 처리된 테스트 (예: `testIsDepolymentDocument`) 삭제 — 스펙 갭을
  표시하는 자리표시자다. 정식 테스트로 바꾸려면 누락된 파서 경로를 먼저
  구현해야 한다.
