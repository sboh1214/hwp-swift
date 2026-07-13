# 프로젝트 지식 베이스

**Branch:** feat/hwpkit-viewer

## 개요

한글과컴퓨터의 한글 문서 파일(`.hwp`)을 파싱하고 렌더링하는 Swift package.
HWP 파일은 OLE compound document이며, 그 안의 stream들은 record tree 구조로
인코딩되어 있다. Swift 5.9+, macOS 14+/iOS 17+, LGPL.

**4개 library target**:
- `CoreHwp` — 파서 (read-only, binary HWP → typed model)
- `HwpKitCore` — 렌더 코어 (platform-neutral, CoreGraphics/CoreText/Foundation only)
- `HwpKitNative` — 플랫폼 브릿지 (AppKit + UIKit)
- `HwpKit` — SwiftUI 공개 API

## 구조

```
hwp-swift/
├── Sources/CoreHwp/       # 파서
├── Sources/HwpKitCore/    # 렌더 코어 — 파이프라인/모델/paint list (AGENTS.md 참조)
├── Sources/HwpKitNative/  # 플랫폼 브릿지 — CALayer/View (AGENTS.md 참조)
├── Sources/HwpKit/        # SwiftUI 공개 API (AGENTS.md 참조)
├── Tests/{CoreHwp,HwpKitCore,HwpKitNative,HwpKit}Tests/
├── Sample/                # HwpSwiftSample.xcodeproj (xcodegen, path: ..)
├── Package.swift          # swift-tools-version:5.9
├── .github/workflows/     # ci.yml, cd.yml
└── .github/pages/         # DocC 사이트 루트 랜딩
```

폴더명과 파일명은 **공백 없는 PascalCase**를 사용한다 (예:
`CtrlHeader/`, `DocumentProperties/`, `IdMappings/`). 한컴 공개 문서의
절 제목은 public doc-comment와 문서 설명에서 보존하고, 실제 경로명에서는
공백을 제거한다.

## 어디를 볼 것인가

| 작업 | 위치 |
|------|------|
| 새 stream 파서 추가 | `Sources/CoreHwp/Streams/` + `HwpFile.init(fromOLE:)`에 등록 |
| 새 record 태그 추가 | `Sources/CoreHwp/Enums/Hwp{DocInfo,Section}Tag.swift` |
| 새 컨트롤 ID 추가 | `Sources/CoreHwp/Enums/CtrlId/` + `Models/Section/CtrlHeader/` + `HwpCtrlId` enum |
| 새 모델 추가 | `Sources/CoreHwp/Models/...` 하위에 `Utils/Protocols/`의 프로토콜을 채택하여 작성 |
| 기본 타입 확장 | `Sources/CoreHwp/Utils/Extensions/` |
| 테스트 픽스처 추가 | 테스트 파일과 같은 폴더에 `.hwp` 배치 (`openHwp(#file, "name")` 사용) |

## 코드 맵

| 심볼 | 위치 | 역할 |
|------|------|------|
| `HwpFile` | [HwpFile.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpFile.swift) | 유일한 public 진입점: `init(fromPath:)`/`init(fromData:)`/`init(fromWrapper:)` (각각 `readLimits:` 또는 `options:` 오버로드), `init()` |
| `HwpLoadOptions` | [HwpLoadOptions.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpLoadOptions.swift) | `readLimits` + `preserveRawPayload`(기본 true). `.viewer` 프리셋은 rawPayload 보존을 꺼 압축 해제 버퍼를 파싱 후 즉시 해제 (뷰어 상주 메모리 대폭 절감) |
| `HwpError` | [HwpError.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpError.swift) | `CustomStringConvertible` + `LocalizedError`를 채택한 public error enum |
| `HwpStreamName` | [Enums/HwpStreamName.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Enums/HwpStreamName.swift) | OLE stream 이름 (`FileHeader`, `DocInfo`, `BodyText`, `\005HwpSummaryInformation`, `PrvText`, `PrvImage`) |
| `parseTreeRecord` | [Utils/HwpRecord.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/HwpRecord.swift) | stream에서 tag/level/size record tree를 구성 |
| `StreamReader` | [Utils/Readers/StreamReader.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Readers/StreamReader.swift) | OLE → `Data` 변환 (SWCompression으로 deflate 처리) |

## 파싱 파이프라인

```
.hwp 파일
  → OLEFile (OLEKit)              # OLE compound document
  → StreamReader                   # 이름 있는 stream → Data (필요시 deflate)
  → DataReader / BitsReader        # Data 위의 cursor
  → parseTreeRecord (Utils)        # 10-bit tag / 10-bit level / 12-bit size 헤더로 record tree 구성
  → Hwp* 모델 (Models/)            # Hwp{FromData,FromRecord,...} 프로토콜을 통해 디코딩
  → HwpFile (public struct)
```

압축 여부는 `HwpFileHeader.fileProperty.isCompressed`에 있고, 이후 모든
하위 `load` 호출에 인자로 전달된다.

`HwpReadLimits`는 OLE directory의 `streamSize`를 이용해 압축 입력과 비압축
stream을 읽기 전에 제한하고, 압축 해제 결과가 한도를 넘으면 typed
`HwpError.streamSizeLimitExceeded`로 후처리 거부한다. 현재 `SWCompression`
Deflate API는 bounded streaming inflate를 노출하지 않으므로, 압축 해제 결과
한도는 메모리 할당 cap이 아니다. PR/문서에서 decompression-bomb 방어를 설명할 때
이 한계를 명시한다.

## 컨벤션

- **`HwpPrimitive = Codable & Hashable & Sendable`** — 모든 모델이 채택 (typealias는 [`HwpPrimitive.swift`](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Protocols/HwpPrimitive.swift)). 전 모델이 값 타입이라 `Sendable`은 자동 충족 — 백그라운드 파싱 → UI 전달이 컴파일러 검증된다.
- [`Utils/Protocols/`](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Protocols/)의 **loader 프로토콜**은 `static load(...)`를 default 구현으로 제공하며 EOF를 강제한다 — reader에 잔여 byte가 있으면 `HwpError.bytesAreNotEOF`를 throw. 채택 측은 `init(_ reader: inout DataReader, ...)`만 작성.
- public 타입의 **한국어 doc-comment**는 한컴 공개 문서의 절을 참조한다. 편집 시 보존할 것.
- **`Tests/` 외부에서 `import XCTest` 금지.**
- **SwiftFormat** (`--swiftversion 5.9 --disable hoistTry`)과 **SwiftLint**가 CI 및 `pre-commit`에서 강제됨.

## 안티 패턴 (이 프로젝트 한정)

- 테스트에서 `XCTAssert*` 사용 — SwiftLint custom rule `no_xctassert` (severity: error)로 금지. Nimble `expect(...) == ...` 사용.
- EOF를 검사하지 않고 silent하게 byte 잔여 — loader 프로토콜의 `load`가 `bytesAreNotEOF`를 throw하도록 설계되어 있으므로, manual `init` 호출로 우회 금지.
- 공백이 있는 새 파일/디렉터리명 추가 — 경로명은 PascalCase + 무공백을 유지.
- `Package.swift`의 Darwin platform 최소 버전을 더 낮추기 — 의존성 `SWCompression 4.9.1` / `BitByteData 2.1.0`이 macOS 14+/iOS 17+를 요구한다. Linux는 CoreHwp·CoreHwpTests만 지원한다 (뷰어 타깃은 Apple 전용 프레임워크 의존 — `Package.swift`의 `canImport(Darwin)` 분기; CI matrix: macOS + ubuntu-latest).
- `swift-tools-version` 변경 시 `.swift-version`, `.swiftformat`, **양쪽** `Test-*.yml` matrix 동시 갱신 누락 (`CONTRIBUTING.md` 참조).

## 명령어

```bash
swift build                                    # 빌드
swift test                                     # 테스트 실행
swift test --enable-code-coverage              # 커버리지 (lcov 추출은 .github/workflows/Coverage.yml 참조)
HWP_PERF=1 swift test --filter Performance     # 성능 실측 (N=20,000 합성 + 타이트 임계; 기본은 N=1,000 스모크)
HWP_SNAPSHOT_TESTS=1 swift test --filter "FixtureRenderHash|FixtureBlockLayout|FixturePreviewFidelity"  # 환경 의존 스냅샷·fidelity 스위트 (기본 swift test·CI에서는 skip)
RECORD_RENDER_HASHES=1 swift test --filter FixtureRenderHash     # 렌더 픽셀 해시 기준선 레코딩 (Snapshots/ — gitignore, 이 머신 전용)
RECORD_BLOCK_SNAPSHOTS=1 swift test --filter FixtureBlockLayout  # 블록 좌표 스냅샷 재생성 (diff 리뷰 필수)
xcodebuild test -scheme Hwp-Swift-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'  # iOS 테스트 (#if os(iOS) 코드는 여기서만 실행)
swiftformat .                                  # 포맷
swiftformat --lint .                           # CI lint 체크
swiftlint                                      # lint
pre-commit install && pre-commit run --all     # hook 설치 + 전체 실행
```

성능 게이트: CI는 스모크 파라미터만 상시 실행 (공유 러너 wall-time 하드
게이트는 flaky). 타이트 임계는 로컬 `HWP_PERF=1`로 확인 — 성능에 닿는
PR은 실측 수치를 커밋 메시지에 기록한다.

## 의존성 (모두 exact pinning)

- `OLEKit 0.3.1` — OLE compound document 파싱
- `SWCompression 4.9.1` — 압축 stream의 deflate (4.9.0에서 untrusted Deflate 입력에 대한 crash 패치 포함)
- `Nimble 9.2.1` — 테스트 DSL (testTarget 전용)

## 노트

- `HwpFile.init()`는 완전 빈 객체가 아니라 빈 `HwpSection` 하나가 들어있는 default 객체를 만든다. `Tests/CoreHwpTests/Blank/Create*Tests.swift`에서 파싱된 픽스처와 비교할 때 이를 사용.
- `Streams/HwpDocInfo.swift`의 여러 `// TODO: HWPTAG_*` 주석은 의도된 것으로, 아직 구현되지 않은 기능이다. 리팩토링 중에 조용히 제거하지 말 것.
- `HwpCtrlId` enum의 `Codable`은 hand-rolled 구현이다. 이종(heterogeneous) payload를 가진 associated value enum은 Swift가 자동 합성하지 못하기 때문.
