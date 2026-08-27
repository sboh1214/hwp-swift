# HwpSwiftSample

`HwpKit`이 노출하는 모든 UI 컴포넌트를 실제로 조작해 볼 수 있는 SwiftUI 샘플 앱. macOS 14+ / iOS 17+ 대응.

**포함된 HwpKit 컴포넌트** (전부 실제 상호작용 가능):

| 컴포넌트 | 역할 | 이 앱에서의 사용 |
|---|---|---|
| `HwpDocumentView` | HWP 문서 렌더러 | 문서 로드 후 메인 영역에 렌더 |
| `HwpDocumentToolbar` | 툴바 컨테이너 (재질 배경 + 분리선) | 상단 툴바로 사용 |
| `HwpPageNavigator` | 페이지 이동 컨트롤 (`- / Page [N] of Y / +`, 번호 직접 입력) | 툴바 좌측 |
| `HwpZoomControls` | 확대/축소 컨트롤 (`- / Zoom N% / + / Reset / Fit Width / Fit Page`) | 툴바 우측 |
| `HwpSearchController` | 문서 검색 세션 (엔진은 HwpKitCore) | `@State`로 소유해 뷰와 검색 바에 **같은 인스턴스** |
| `HwpSearchBar` | 검색 필드 + 카운터 + 이전/다음 + 지우기 | 툴바 **아래 별도 행** |
| `HwpSearchNavigator` | 매치 카운터 + 이전/다음 | `HwpSearchBar`가 내부에서 조립 |
| `HwpDocumentLoader` | 비동기 문서 로더 | `.fileImporter` 결과를 async 로드 |
| `HwpDocumentMetadata.outline` | 개요·책갈피 탐색 목록 (HwpKitCore) | 사이드바(`OutlineSidebar.swift`)가 이 배열 하나로 만들어진다 |
| `HwpPageThumbnails` | 쪽 축소판 렌더러 (진행·취소·캐시) | 축소판 사이드바(`ThumbnailSidebar.swift`)가 이 하나로 만들어진다 |
| `HwpPDFExporter` | PDF 내보내기 (진행률·취소) | 툴바 `PDF로 내보내기` / `인쇄` |

- `.hwp` 파일을 사용자에게 선택받아 (`SwiftUI.fileImporter`) 위 컴포넌트로 렌더링/조작
- 최근 문서 목록 (#126) — 성공적으로 연 파일을 **보안 범위 북마크**로 기록해
  빈 상태에 목록으로 보인다 (경로 문자열로는 안 된다 — `fileImporter`가 준
  샌드박스 접근 권한이 프로세스와 함께 사라진다). 파싱에 실패한 파일은
  기록하지 않고, 열 수 없게 된 항목은 누르는 순간 목록에서 거둔다.
  **iOS에서는 이 접근이 재부팅을 넘기지 못한다** — `.withSecurityScope`가
  iOS에 없어(`API_UNAVAILABLE`) 옵션 없이 만든 북마크는 implicit ephemeral
  security scope를 달고, SDK 문서가 그 범위를 "valid until reboot at the
  latest"로 못박는다(`NSURL.h`의 `WithoutImplicitSecurityScope` 항목).
  재부팅 뒤 북마크는 **URL로는 풀리는데 읽히지는 않으므로**, 되살리기가
  읽기 가능 여부까지 확인해 그 항목을 거두고 다시 선택하라고 안내한다
- 드래그앤드롭으로 열기 (#126) — 빈 상태·문서 화면 어디에 놓아도 그 파일로
  교체한다. macOS(Finder)는 드래그가 파일 URL + 샌드박스 접근 확장을 실어
  원본을 그대로 열고, iOS(Files 등)는 URL 대신 파일 표현이 와 **앱 임시
  디렉터리로 복사한 사본**을 연다 — 그 파일은 완료 핸들러가 반환되면
  시스템이 지우기 때문이다 (`DropOpenSupport.swift`). 사본은 임시 경로라
  최근 문서에는 기록되지 않고, 다음 실행의 시작 시 잔해 청소가 거둔다
  (내보내기 임시 PDF와 같은 정책)
- 하이퍼링크 열기 + 미지원 요소 배너 (#126) — `onHyperlinkTapped`는 scheme
  검증(`http`/`https`/`mailto`) 후 시스템 브라우저로 열고, 문서 내부 앵커·로컬
  경로 값은 열지 않는다 (콜백 값은 `URL`이 아니라 `String`이다 — 라이브러리는
  콜백만 내고 **여는 것은 앱 책임**이라는 `HwpKit` 규약의 소비처).
  미지원 요소는 최종 스냅샷의 `document.unsupportedElements`(공개 배열)를
  그대로 읽어 문서 영역 상단 배너 + 목록(행 탭 → 그 쪽으로 이동)으로 보인다.
  `onUnsupportedElement` **콜백으로 집계하지 않는 이유**: 콜백은 델타가 아니라
  배열 전체를 매번 재방출하고, 같은 쪽의 동종 요소는 값까지 완전히 같아서
  (kind·page·hint가 전부) append 집계는 재방출을 중복 계수하고 `Set` 집계는
  실존 요소를 접는다 — 배열만이 정확한 다중도를 준다. 목록은 macOS 인라인
  열 / iOS 시트 (사이드바와 같은 형태)
- 문서 내 검색 — 컨트롤러 하나를 `HwpDocumentView(searchController:)`와
  `HwpSearchBar(controller:)`에 넘기면 하이라이트·매치 노출 스크롤·프로그레시브
  재스캔이 자동 배선된다. **Cmd+F는 이 앱이 잡는다** — 라이브러리는 전역
  단축키를 소유하지 않고 `@FocusState` 훅만 받는다 (Cmd+O·Cmd+P와 같은 관례)
- 키보드 쪽 이동 — PageUp/Down·Home/End는 **라이브러리가** 해석한다. 위 Cmd+F
  관례와 어긋나지 않는다: 문서 뷰가 first responder일 때만 오는 키라 전역
  단축키가 아니고, 포커스는 문서를 클릭·탭해야 잡힌다. 이 앱은
  `isKeyboardPageNavigationEnabled`를 넘기지 않아 기본값(켜짐)을 쓴다 — 호스트가
  이 키들을 직접 쓰려면 그 인자를 `false`로 넘긴다
- 개요·책갈피 사이드바 — `document.metadata.outline`만으로 만든다. 라이브러리는
  **목록 UI를 내지 않는다**(검색 결과 목록과 같은 기준). 항목이 `Identifiable` +
  1-기반 `pageNumber` + 1-기반 `level`이라 `List` 하나로 끝나고, 누르면
  `currentPage`에 그대로 쓴다. macOS는 인라인 열, iOS는 시트 — `HwpDocumentToolbar`가
  순수 `HStack`인 것과 같은 이유로 **호스트 레이아웃은 호스트 몫**이다.
  개요도 책갈피도 없는 문서에서는 **개요 버튼**이 사라진다 — 그 자리를 축소판이
  받는다(아래)
- 쪽 축소판 사이드바 — `HwpPageThumbnails`만으로 만든다. 라이브러리는 여기서도
  **그리드 UI를 내지 않는다**. 이 앱이 더하는 것은 셋이다: `LazyVGrid` 셀별
  **지연 요청·취소**(`.task` — 전역 디코드 슬롯 3개를 가시 페이지와 나눠 쓴다),
  비어 있는 동안의 **자리 예약**(높이가 0이면 셀이 화면 안팎을 오가며 요청·취소가
  반복된다 — 그 높이는 `HwpPageThumbnails.pixelHeight`에서 파생시킨다. 비율을
  손으로 계산하면 종횡비가 병적인 문서에서 렌더는 상한에서 접히는데 셀만
  1억 pt로 남는다), 현재 쪽 **자동 스크롤**(1,030쪽 목록에서는 이것이 없으면 현재 위치를
  못 찾는다). 사이드바 상태는 불리언이 아니라 `SidebarMode?` 하나다 — 축마다
  불리언을 두면 "둘 다 켜짐"이라는 없는 상태가 생긴다
- PDF 내보내기·인쇄 — 라이브러리는 PDF 바이트까지만 만들고, 저장 패널
  (`fileExporter`)·인쇄 UI(macOS `PDFDocument.printOperation`, iOS
  `UIPrintInteractionController`)는 이 앱이 배선한다 (`PDFExportSupport.swift`)
- App Sandbox 유지 + `User Selected File (Read/Write)` entitlement 사용 —
  저장 패널로 고른 위치에 PDF를 쓰려면 read-only로는 부족하다
- **인쇄에는 `Printing` entitlement가 따로 필요하다** (`com.apple.security.print`).
  파일 entitlement는 파일 접근만 주므로, 없으면 샌드박스가 인쇄 서비스를 막는다 —
  그것도 **조용히**: `NSPrintOperation.run()`의 Bool은 취소와 실패를 구분하지 않아
  사유를 올릴 수 없다(아래 인쇄 실패 항목). 눌러도 아무 일이 없는 것처럼 보인다
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
- 빈 상태의 **최근 문서** 목록에서 항목 클릭 (한 번이라도 성공적으로 연 파일이
  있을 때만 나타난다)
- `.hwp` 파일을 창으로 **끌어다 놓기** (문서를 보는 중이면 그 파일로 교체)

문서가 로드되면 화면 상단에 다음 툴바가 나타남:

```
[Re-open] [개요] [축소판] | [-] Page [1] of N [+] | [PDF로 내보내기] [인쇄] [찾기]  [-] Zoom 100% [+] [Reset]
└──────────────────────────  HwpDocumentToolbar  ──────────────────────────────┘
[ Find in document          ] 1 of 19 ‹ › [Clear]
└────────────  HwpSearchBar (툴바 밖 별도 행)  ────────────┘
```

- 페이지 넘김 / 확대 / 축소 / 초기화 모두 실시간 반영 — 쪽은 `-`/`+` 외에
  번호 필드에 직접 입력하고 Enter로도 옮긴다 (숫자가 아니거나 범위를 벗어난
  입력은 현재 쪽·경계 쪽으로 되돌아온다)
- `개요` 버튼은 개요·책갈피가 **있는 문서에서만** 나타난다. 눌러 사이드바를
  여닫고, 항목을 누르면 그 쪽으로 이동한다. 개요는 수준만큼 들여쓰고 지금
  보고 있는 쪽을 여는 항목(현재 쪽 이하의 마지막 개요)을 강조한다.
  개요가 실제로 쌓여 있는 문서는
  `Tests/CoreHwpTests/Fixtures/legacy-common-control-property/document.hwp`
  (1,030쪽·개요 1,944개), 책갈피는
  `Tests/CoreHwpTests/Fixtures/bookmark/document.hwp`다
- `축소판` 버튼은 **언제나** 있다 — 쪽은 언제나 있기 때문이다. 개요가 없는
  문서(`Tests/CoreHwpTests/Fixtures/noori/document.hwp`)에서는 이것이 유일한
  시각적 탐색 수단이고, macOS 기본값이 개요라도 그 문서에서는 축소판이 대신
  열린다(사용자 선택 자체는 덮어쓰지 않는다). 스크롤해서 화면 밖으로 나간 셀은
  요청을 **취소한다** — 디코드 슬롯이 문서 뷰와 공유되는 전역 3개라 그러지 않으면
  1,030쪽 문서에서 본문 스크롤이 눈에 띄게 느려진다
- Re-open 클릭 시 다른 `.hwp` 파일로 교체
- `찾기`(Cmd+F)는 검색 필드로 **포커스만** 옮긴다. 검색 바를 툴바 **안**에 넣지
  않은 이유는 `HwpDocumentToolbar`가 순수 `HStack`이라 가변 폭 필드가 iPhone
  폭에서 레이아웃을 무너뜨리기 때문 — 툴바 컴포넌트 자체는 고치지 않는다
  (호스트 레이아웃은 호스트 몫). 툴바가 `loadedView` 안에만 있으므로 이
  단축키도 문서가 열려 있는 동안에만 산다 (인쇄와 같은 성질)
- `PDF로 내보내기` / `인쇄`(Cmd+P)는 진행률 시트를 띄우고 취소를 받는다. 앱
  임시 디렉터리에 먼저 쓴 뒤 그 파일을 저장 패널·인쇄로 넘기므로, 취소해도
  열리지 않는 부분 파일이 사용자 디렉터리에 남지 않는다
- 창이 닫히면 진행 중인 내보내기를 **취소한다**(`onDisappear`). 다만 저장
  패널·인쇄에 **이미 넘긴** 파일은 지우지 않는다 — 그쪽이 다 쓸 때까지
  살아 있어야 한다(`UIPrintInteractionController`는 스풀링 동안,
  `fileExporter`는 완료 핸들러까지 읽는다). 사용자가 확정한 인쇄를 창을 닫았다는
  이유로 깨뜨리지 않기 위해서다. 대신 그 완료 콜백이 scene 파괴로 오지 않으면
  파일이 남으므로, **앱 시작 시 이전 실행의 잔해를 거둔다**(프로세스 시작보다
  오래된 `hwp-sample-export-*.pdf`만 — 이번 실행 것을 지우면 나중에 연 창이 먼저
  창의 내보내기를 깬다).
  `Task {}`는 비구조적이라 뷰 수명에 묶이지 않아, 그대로 두면 뷰 없이 렌더가
  이어지고 성공한 PDF를 지워 줄 주체가 없다. 취소가 파일 이동 뒤에 도착한
  경우도 태스크가 직접 치운다
- 임시 파일은 저장·인쇄가 **끝난 뒤 지운다**(새 내보내기를 시작할 때도 이전
  것을 지운다). UUID 이름이라 덮어쓰기로 재사용되지 않아, 안 지우면 내보낼
  때마다 쌓인다
- 임시 파일명은 **UUID**다. 제목에서 뽑으면 `WindowGroup`의 두 창이 같은 경로를
  써, 한쪽 저장 패널이 열려 있는 사이 다른 쪽 내보내기가 그 파일을 갈아 치운다
  (다른 문서가 저장된다). 사용자에게 보이는 이름(저장 패널 기본 파일명·인쇄
  작업명)만 제목에서 만들고, 파일명 한도(255바이트)를 넘지 않게 자른다
- 내보내기 모달(진행 시트·저장 패널·오류 알림)은 문서가 아니라 **루트 뷰**에
  건다. 로드된 뷰에 걸면 내보내기 중 재로드가 표시자를 없애, 끝난 내보내기가
  저장·인쇄를 띄울 곳을 잃고 임시 PDF도 남는다
- 실패는 진행 시트가 **닫힌 뒤** 알림으로 띄운다(저장·인쇄와 같은 규약) —
  같은 갱신 주기에 겹치면 알림이 유실돼 오류가 조용히 사라진다
- **진행 시트가 아예 안 뜰 수도 있다.** 작은 문서는 표시되기 전에 내보내기가
  끝나 `0 → nil` 전이가 한 갱신 주기로 합쳐질 수 있고, 그러면 닫힐 시트가 없어
  `onDismiss`가 오지 않는다 — 저장·인쇄와 오류가 `pending*`에 갇히고 임시 PDF도
  남는다. 시트의 `onAppear`로 표시 여부를 기록하고, 뜬 적이 없으면 후속 동작을
  직접 예약한다(다음 주기로 넘겨 위 겹침 규약은 그대로 지킨다)
- **인쇄는 실패 통로가 둘이다.** 표시 자체의 실패는 `print(...)`의 반환값으로,
  표시가 **된 뒤의** 실패(프린터 도달 불가 등)는 `onFinish`가 나르는 사유로
  온다. 반환값만 보면 뒤엣것을 놓친다 — 그 시점엔 이미 성공(nil)을 받은
  뒤다. iOS는 `UIPrintInteractionController`가 completion handler로 `Error`를
  주므로 그것을 올리고, 사용자 취소(`completed == false` + `error == nil`)는
  실패가 아니라 사유 없이 끝낸다. macOS는 `NSPrintOperation.run()`의 Bool이
  취소와 실패를 구분하지 않아 사유를 올리지 않는다 — 올리면 취소할 때마다
  거짓 알림이 뜬다
- 인쇄는 **한 번에 하나만** 받는다 — `UIPrintInteractionController.shared`가
  프로세스 전역이라 두 창이 동시에 쓰면 뒤 요청이 앞 작업의 문서를 덮어쓴다
- **iPad에서는** 인쇄 UI를 앵커에서 띄운다. UIKit 헤더가 `presentAnimated:`를
  `// iPhone`, `presentFromRect:inView:`를 `// iPad`로 가르기 때문이다
  (`PDFExportSupport.swift`). 이 앱의 인쇄 버튼은 SwiftUI라 대응 `UIView`가 없어
  창 중앙을 앵커로 쓴다 — 실서비스라면 버튼에 맞춘다
- **iPhone에서는** 버튼이 아이콘만 되고 툴바 전체가 가로 스크롤된다.
  `HwpDocumentToolbar`는 그냥 `HStack`이라 폭이 모자라면 **글자 단위로**
  줄바꿈해 "Zoom 100%"가 세 줄이 된다 (시뮬레이터 실측)

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
│   ├── ContentView.swift          # .fileImporter + HwpDocumentView + 검색·내보내기·사이드바 배선
│   ├── RecentDocuments.swift      # 보안 범위 북마크 기반 최근 문서 저장소 (#126)
│   ├── DropOpenSupport.swift      # 드롭 provider → .hwp URL (플랫폼별 경로) (#126)
│   ├── OutlineSidebar.swift       # metadata.outline만으로 만든 개요·책갈피 목록 (#77)
│   ├── ThumbnailSidebar.swift     # HwpPageThumbnails만으로 만든 쪽 축소판 그리드 (#76)
│   ├── UnsupportedElementsList.swift  # 미지원 요소 배너 + 목록 (#126)
│   ├── PDFExportSupport.swift     # fileExporter용 FileDocument + 플랫폼 인쇄 (#if os)
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

SwiftUI 소스 파일 추가/삭제는 xcodegen이 디렉터리를 자동 스캔하므로 별도 편집 없이 `xcodegen generate`만 다시 돌리면 됨 (파일 목록은 위 "폴더 구조"가 진실 원본이다 — 여기 열거를 두 번 두면 한쪽이 낡는다). **다만 생성된 `.xcodeproj`는 파일을 명시 참조하므로 재생성 결과를 같은 커밋에 넣어야 한다** — CI는 샘플을 빌드하지 않아 이 누락이 초록으로 지나간다.

## 설정 요약

| 항목 | 값 |
|---|---|
| Bundle ID | `com.sboh.HwpSwiftSample` |
| Deployment | macOS 14.0 / iOS 17.0 |
| Swift | 5.9 |
| Signing | Manual, ad-hoc identity (`-`) — "Sign to Run Locally" |
| iOS Simulator | `CODE_SIGNING_ALLOWED=NO` |
| Sandbox | ON (macOS) + `com.apple.security.files.user-selected.read-write` + `com.apple.security.print` + `com.apple.security.files.bookmarks.app-scope` |
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

**하이퍼링크 클릭 / 미지원 요소**
하이퍼링크는 scheme 검증(`http`/`https`/`mailto`) 후 시스템 브라우저로 열리고,
그 밖의 값(문서 내부 앵커·로컬 경로)은 조용히 무시된다. 미지원 요소는 로드
완료 시 문서 영역 상단 배너로 집계된다 (`목록` → 행 탭 → 해당 쪽으로 이동).
육안 확인 재료: 하이퍼링크는 `Tests/CoreHwpTests/Fixtures/CCL`·`공공누리`,
미지원 배너는 `equation`·`chart`의 `document.hwp`.

## 스코프

이 샘플은 **`HwpKit`이 노출하는 모든 SwiftUI 컴포넌트를 실제로 조작해 볼 수 있는 최소 앱**. 편집 같은 실 서비스 UX는 포함하지 않으며, 이는 `HwpKit` v1의 read-only 스코프와도 일치. 최근 문서 목록은 예외로 들어왔다(#126) — 라이브러리 표면이 아니라 뷰어 앱이라면 어차피 만들게 되는 최소 편의라서다.

개요·책갈피 사이드바와 쪽 축소판 사이드바는 예외처럼 보이지만 같은 규칙의
결과다 — **라이브러리가 목록·그리드 UI를 내지 않기로** 했으므로(검색 결과
목록과 같은 기준) 그 자리를 샘플이 채워, `HwpDocumentMetadata.outline` 하나로
개요 사이드바가, `HwpPageThumbnails` 하나로 축소판 사이드바가 만들어짐을 보인다.

`HwpDocumentView` / `HwpDocumentToolbar` / `HwpPageNavigator` / `HwpZoomControls` / `HwpSearchBar` / `HwpSearchNavigator` / `HwpSearchController` / `HwpDocumentLoader` / `HwpPDFExporter` / `HwpPageThumbnails` 10개 public surface가 모두 이 앱 안에서 활성화됨. 여기에 데이터 표면 `HwpDocumentMetadata.outline`(#77)이 사이드바로, 명령 표면 `HwpZoomFit`(#78)이 툴바 → 문서 뷰로 소비됨 — 후자는 **같은 바인딩을 둘에 함께 넘기는 것**이 사용법의 전부다 (배율 산식은 뷰포트를 아는 뷰가 쥔다).

인쇄·저장·공유 **UI는 의도적으로 라이브러리 밖**이다 — `HwpKit`은 PDF 바이트까지만 만들고 그 앞뒤는 앱이 정한다. 이 앱의 `PDFExportSupport.swift`가 그 배선의 최소 예시다. 하이퍼링크도 같은 경계다 — 라이브러리는 탭 콜백까지만 내고, scheme 검증과 `openURL`은 이 앱이 한다 (`Tests/HwpKitTests/HwpKitScopeGuardTests.swift`가 `Sources/HwpKit` 안의 `openURL` 류 호출을 막는다 — 샘플은 그 가드 밖이고, 여기가 의도된 사용처다).
