# HwpSwiftSample

`HwpKit`이 노출하는 모든 UI 컴포넌트를 실제로 조작해 볼 수 있는 SwiftUI 샘플 앱. macOS 14+ / iOS 17+ 대응.

**포함된 HwpKit 컴포넌트** (전부 실제 상호작용 가능):

| 컴포넌트 | 역할 | 이 앱에서의 사용 |
|---|---|---|
| `HwpDocumentView` | HWP 문서 렌더러 | 문서 로드 후 메인 영역에 렌더 |
| `HwpDocumentToolbar` | 툴바 컨테이너 (재질 배경 + 분리선) | 상단 툴바로 사용 |
| `HwpPageNavigator` | 페이지 이동 컨트롤 (`- / Page X of Y / +`) | 툴바 좌측 |
| `HwpZoomControls` | 확대/축소 컨트롤 (`- / Zoom N% / + / Reset`) | 툴바 우측 |
| `HwpDocumentLoader` | 비동기 문서 로더 | `.fileImporter` 결과를 async 로드 |

- `.hwp` 파일을 사용자에게 선택받아 (`SwiftUI.fileImporter`) 위 4개 컴포넌트로 렌더링/조작
- 하이퍼링크 탭 + 미지원 요소 콜백을 콘솔에 로그
- App Sandbox 유지 + `User Selected File (Read Only)` entitlement 만 사용
- 서드파티 의존성 없음, 현재 저장소의 `Package.swift`를 그대로 사용

---

## 사전 준비

- macOS + Xcode 15 이상 (테스트: Xcode 27)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (프로젝트 재생성 시에만 필요)

```bash
brew install xcodegen
```

## 빌드 & 실행

```bash
open Sample/HwpSwiftSample.xcodeproj
```

Xcode에서 스킴 `HwpSwiftSample` 선택 → 대상 지정:

- **macOS**: Destination = `My Mac` → Run
- **iOS**: Destination = `iPhone 17 Pro` (또는 다른 시뮬레이터) → Run

앱이 실행되면 다음 중 하나로 파일 선택:

- 빈 상태의 **"Open .hwp"** 버튼 클릭 (또는 Return 키)
- 우상단 툴바의 **"Open"** 버튼 (또는 Cmd+O)

문서가 로드되면 화면 상단에 다음 툴바가 나타남:

```
[Re-open]  |  [-] Page 1 of N [+]         [-] Zoom 100% [+] [Reset]
└─────────────────────  HwpDocumentToolbar  ─────────────────────┘
```

- 페이지 넘김 / 확대 / 축소 / 초기화 모두 실시간 반영
- Re-open 클릭 시 다른 `.hwp` 파일로 교체

저장소 안의 fixture로 스모크 테스트 가능:

- `Tests/CoreHwpTests/Blank/Blank.hwp` — 빈 문서 (빈 페이지 1장)
- `Tests/CoreHwpTests/Fixtures/bookmark/document.hwp` — 텍스트/북마크 포함
- `Tests/CoreHwpTests/Fixtures/**/*.hwp` — 그 밖의 fixture 목록

## CLI 빌드 검증

```bash
cd Sample

# macOS
xcodebuild -project HwpSwiftSample.xcodeproj \
  -scheme HwpSwiftSample \
  -destination 'platform=macOS' \
  -configuration Debug build

# iOS Simulator
xcodebuild -project HwpSwiftSample.xcodeproj \
  -scheme HwpSwiftSample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

두 명령 모두 `** BUILD SUCCEEDED **` 로 종료되어야 정상.

## 폴더 구조

```
Sample/
├── HwpSwiftSample.xcodeproj/     # xcodegen이 생성 (커밋 가능)
├── project.yml                    # xcodegen spec (편집 후 regen)
├── HwpSwiftSample/
│   ├── HwpSwiftSampleApp.swift    # @main 진입점
│   ├── ContentView.swift          # .fileImporter + HwpDocumentView
│   └── HwpSwiftSample.entitlements
└── README.md
```

`project.yml`의 `packages.hwp-swift.path: ..` 가 부모 저장소 루트(`Package.swift`가 있는 위치)를 가리킴. 상대 경로이므로 저장소를 어디로 옮겨도 그대로 동작.

## 프로젝트 재생성

`project.yml`을 수정했거나 `HwpSwiftSample.xcodeproj/`를 다시 만들고 싶을 때:

```bash
cd Sample
xcodegen generate
```

SwiftUI 소스 파일(`HwpSwiftSampleApp.swift`, `ContentView.swift`) 추가/삭제는 xcodegen이 디렉터리를 자동 스캔하므로 별도 편집 없이 `xcodegen generate`만 다시 돌리면 됨.

## 설정 요약

| 항목 | 값 |
|---|---|
| Bundle ID | `com.sboh.HwpSwiftSample` |
| Deployment | macOS 14.0 / iOS 17.0 |
| Swift | 5.9 |
| Signing | Manual, ad-hoc identity (`-`) — "Sign to Run Locally" |
| iOS Simulator | `CODE_SIGNING_ALLOWED=NO` |
| Sandbox | ON (macOS) + `com.apple.security.files.user-selected.read-only` |
| SPM Product | `HwpKit`, `HwpKitCore` (부모 저장소 로컬 참조) |

## 문제 해결

**`Signing for "HwpSwiftSample" requires a development team.`**
`project.yml`의 `CODE_SIGN_STYLE`이 `Manual`인지 확인. Automatic으로 바뀌었다면 팀 없이 빌드 불가.

**`no versions of 'nimble' match the requirement`**
DerivedData의 패키지 캐시가 오래된 경우 발생. 초기화 후 다시 시도:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/HwpSwiftSample-*
cd Sample && xcodebuild -project HwpSwiftSample.xcodeproj -resolvePackageDependencies
```

**`.hwp` 파일을 열었는데 렌더링이 비어 있음**
Blank fixture는 원래 빈 페이지. 다른 fixture(예: `Tests/CoreHwpTests/**/Read/*.hwp`)로 시도.

**하이퍼링크 클릭 / 미지원 요소 로그**
Xcode 콘솔에 `print()`로 출력됨:
- `Hyperlink tapped: <url>`
- `Unsupported: <HwpUnsupportedElement>`

## 스코프

이 샘플은 **`HwpKit`이 노출하는 모든 SwiftUI 컴포넌트를 실제로 조작해 볼 수 있는 최소 앱**. 실 서비스 UX (최근 파일, 검색, 사이드바, 편집 등)는 포함하지 않으며, 이는 `HwpKit` v1의 read-only 스코프와도 일치.

`HwpDocumentView` / `HwpDocumentToolbar` / `HwpPageNavigator` / `HwpZoomControls` / `HwpDocumentLoader` 5개 public surface가 모두 이 앱 안에서 활성화됨.
