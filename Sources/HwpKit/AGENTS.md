# HwpKit

SwiftUI 공개 API target. HwpKitNative 위에 `NSViewRepresentable` / `UIViewRepresentable` 로 래핑. **AppKit/UIKit direct import 금지** (플랫폼 뷰는 HwpKitNative 통해).

## 공개 API 표면

- `HwpDocumentLoader(fontResolver:)` — 렌더에 쓸 폰트 해석기 주입 (기본 `HwpFontResolver()`). 커밋된 기준선을 쓰는 렌더 가드가 전부 이 인자 하나에 기대 기기 독립을 얻는다 (`.testDeterministic` — 루트 AGENTS.md "렌더 가드 4층"). 호스트도 재현 가능한 조판이 필요하면 같은 방식으로 고정 resolver를 넘긴다
- `HwpDocumentLoader.load(from:)` — URL / Data / FileWrapper 오버로드. 내부적으로 `HwpDocumentActor` 사용. 에러는 `HwpDocumentLoadError` 로 매핑 (`CustomStringConvertible` + `LocalizedError` 채택 — 호스트가 `error.localizedDescription` 을 그대로 표시하면 감싼 파서/페이지네이터 원인이 나온다. 새 case 추가 시 `description` 도 함께 채울 것)
- `HwpDocumentLoader.loadUpdates(from:)` — 프로그레시브 로딩. `AsyncThrowingStream<HwpDocumentSnapshot, Error>` 로 첫 페이지 확정 즉시 스냅샷을 방출하고 배치 단위로 이어가다 최종 스냅샷(`isComplete`)으로 끝난다. 최종 문서는 `load(from:)` 결과와 동일. 뷰는 `HwpDocumentMetadata.loadToken` 으로 증분 적용(스크롤 유지) vs 전체 리셋을 판정
- `HwpDocumentView` — SwiftUI View. optional `zoomScale: Binding<CGFloat>?` + `currentPage: Binding<Int>?` + `searchController: HwpSearchController?` + hyperlink/unsupported 콜백
- `HwpDocumentToolbar<Content>` — trailing content 를 받는 컨테이너 (툴바 chrome)
- `HwpPageNavigator(currentPage: Binding<Int>, totalPages: Int)` — "Page X of Y" + ± 버튼
- `HwpZoomControls(zoomScale: Binding<CGFloat>, range: ClosedRange<CGFloat>)` — 기본 range `0.25...5.0`
- `HwpSearchController` — 문서 검색 세션 (HwpKitCore). 호스트가 `@State` 로 소유해 `HwpDocumentView(searchController:)` 와 `HwpSearchBar(controller:)` 에 **같은 인스턴스**를 넘긴다. 뷰가 붙는 순간 `HwpSelectionController` 의 지오메트리를 공유해 (단위 캐시 이중화 금지) 하이라이트·매치 노출 스크롤·프로그레시브 증분 재스캔이 자동 배선된다. 검색 대상은 본문 (`role == .body`) 뿐 — 머리말/꼬리말/쪽 번호와 메모 풍선은 빠지고 각주·표 셀·글상자·중첩 표는 포함된다. 매치는 텍스트 단위 (`HwpTextUnit`) 안에서만 성립한다 (단/쪽·셀 경계를 넘지 않는다)
- `HwpTextSearcher` — 상태 없는 순수 스캐너. nonisolated + 입출력 Sendable 이라 오프메인·CLI 에서도 쓴다 (대가: 뷰의 unit 캐시를 공유하지 못해 전개 이중화)
- `HwpSearchBar` / `HwpSearchNavigator` — 검색 UI. **순수 서브트리**다: navigation 컨테이너를 요구하지 않고, 호스트 chrome 을 점유하지 않으며, 환경에 아무것도 심지 않고, Cmd+F 같은 전역 단축키를 소유하지 않는다 (호스트가 `.keyboardShortcut` 로 잡아 `isFocused` 를 넘긴다). SwiftUI `.searchable` 을 쓰지 않는 이유가 정확히 이 네 가지다 — 안티 패턴 절 참조
- `HwpDocumentMetadata.outline: [HwpOutlineItem]` (HwpKitCore) — 개요·책갈피
  탐색 목록 (#77). 조판이 확정한 쪽을 들고 오므로 호스트는 `item.pageNumber`
  (1-기반, `HwpPageNavigator.currentPage`와 같은 규약)를 그대로 쓰거나
  `item.pageIndex`(0-기반)를 네이티브 뷰에 넘긴다. `HwpOutlineItem`은
  `Identifiable`(문서 순서 `ordinal`) + 1-기반 `level`(책갈피는 nil) +
  `kind`(.heading/.bookmark)이고, 컬렉션 확장 `headings`/`bookmarks`/
  `items(onPage:)`가 갈래를 나눈다. 책갈피 스코프는 검색과 같다 —
  본문만이고 머리말/꼬리말은 빠진다. 프로그레시브 **중간 스냅샷에도** 접두가
  실린다 (`unsupportedElements`와 갈리는 지점 — 근거는 루트 `AGENTS.md`의
  "개요·책갈피 탐색 (#77)")
- `HwpPDFExporter` — `export(document:to:onProgress:)` / `exportData(document:onProgress:)` (둘 다 `async throws`). 화면과 **같은 paint list·같은 조판**으로 PDF를 만든다 (`HwpPageLayer.draw(in:)`가 뷰 계층 없이 임의 `CGContext`에 그리는 순수 오프스크린 렌더러라 가능하다 — 구현은 HwpKitNative의 `HwpPDFRenderer`). 페이지 단위 스트리밍이라 상주 메모리는 1페이지 몫이고, 페이지 경계마다 `Task.checkCancellation()` + `onProgress`(`HwpPDFExportProgress`) 발화. 에러는 `HwpPDFExportError`
  - **미완성 문서는 거부한다** (#74 리뷰) — `loadUpdates(from:)`의 중간 스냅샷(`metadata.isComplete == false`)은 확정된 페이지 접두만 들고 있어, 그대로 내보내면 페이지가 빠진 PDF가 **성공으로** 나간다. 열리고 페이지 수도 맞아 산출물 검증(`incompleteOutput`)마저 통과하므로 아래 층이 잡지 못한다 — `.incompleteDocument`로 끝낸다. `.exportFailed` 문자열이 아니라 제 타입인 이유는 이것이 로드가 끝나면 성공하는 **재시도 가능** 상태라 호스트가 진짜 실패와 갈라 다뤄야 하기 때문이다. 접두를 의도적으로 내보내려면 그 페이지로 문서를 직접 구성한다 (`isComplete` 기본값이 true라 통과). 샘플이 로드 중 버튼을 잠그는 것은 호스트 UI 관례일 뿐 이 계약을 대신하지 않는다
  - **UI는 넘기지 않는다** — 저장 패널·공유 시트·인쇄 대화상자는 호스트 몫이다 (`Sample`이 `fileExporter` / `PDFDocument.printOperation` / `UIPrintInteractionController`로 배선하는 예를 보인다). 뷰를 직접 인쇄하는 경로는 없다: 레이어 가상화가 `visible ± 2`쪽만 들고 있어 인쇄 페이지네이션과 충돌한다

## 인덱싱 컨벤션

**`HwpPageNavigator` 는 1-indexed** (`currentPage ∈ 1...totalPages`). 하지만 native view (`HwpDocumentNSView` / `HwpDocumentUIView`) 는 0-indexed page range 를 사용.

`HwpDocumentView` 의 wrapper 가 변환:
- SwiftUI → native: `currentPage - 1`
- native → SwiftUI: `page + 1` (`handlePageChanged` 에서)

바인딩 테스트 (`HwpDocumentViewTests.testBindingsPropagateThroughNativeWrapper`) 는 이 오프셋 3 (= 2 + 1) 을 검증.

## 바인딩 방어 (public Binding 은 임의 값이 들어온다)

호스트 앱의 상태 복원/버그로 극단값이 들어와도 트랩하지 않아야 한다.

- 페이지: `hwpScrollPageIndex(fromOneBased:)` 가 **클램프를 뺄셈보다 먼저** 한다 (`max(1, page) - 1`). `page - 1` 을 먼저 하면 `Int.min` 에서 오버플로 트랩. macOS·iOS 분기가 이 헬퍼를 공유해 산식이 갈라지지 않는다
- 줌: `HwpZoomControls` 는 표시·쓰기 **양쪽**에서 `sanitized` 를 거친다 — 비-finite 는 1.0 폴백 후 range 클램프 (`Int(nan * 100)` 은 트랩, `min`/`max` 만으로는 NaN 이 통과)
- 줌 writeback 판정은 톨러런스 비교 **전에** 비-finite 를 처리한다 (`hwpZoomNeedsWriteback` / `hwpZoomBindingUnchanged`). NaN 은 abs 비교가 전부 false 라, 그냥 두면 핀치 echo·정규화가 모두 막혀 바인딩이 영구 NaN 으로 고착된다

## Wrapper 재사용 규약

- `HwpDocumentView.updateNSView/UIView` 는 매번 `context.coordinator.update(...)` 로 콜백 참조를 갱신 (SwiftUI 가 뷰를 재사용해도 최신 클로저가 발화되도록)
- `Coordinator` 클래스가 hyperlink/unsupported/pageChanged 발화를 SwiftUI 쪽 콜백으로 프록시
- **해체 훅을 반드시 구현한다** (#75 리뷰) — `dismantleNSView`/`dismantleUIView` 가 `searchController = nil` 로 세션을 뗀다. 호스트가 `@State` 로 소유한 컨트롤러는 뷰보다 오래 살고 선택 컨트롤러를 **강참조**하므로, 안 떼면 문서 전체가 상주한다 (문서를 닫거나 재로드가 실패해 새 뷰가 안 붙는 경로). 참조 타입을 뷰에 주입하는 API 를 새로 낼 때마다 같은 훅이 필요하다
- **참조 타입 프로퍼티 대입에는 동일성 가드가 필수다** (#75) — `view.searchController !== searchController` 일 때만 넣는다. 콜백과 달리 이쪽 didSet 은 배선을 다시 하므로, 무조건 대입하면 재배선 → 재스캔 → 관찰자 통지 → 호스트 body 무효화 → 다시 이 configure 로 **타이핑 없이도 도는 자기 급전 루프**가 된다 (문서 대입의 중복-대입 스킵과 같은 성격). 콜백은 값이 매번 새 클로저라 이 가드를 걸 수 없고 걸 필요도 없다 (didSet 이 일을 하지 않는다)

## v1 스코프 밖 (추가 금지)

- File picker / document browser — 앱 책임
- 개요·책갈피 **목록 UI** (`HwpOutlineSidebar`) — v1 OUT, 검색 결과 목록과 **같은
  기준**이다: `List` 행 레이아웃·수준 들여쓰기·현재 위치 강조·접근성 라벨·
  플랫폼 chrome 분기(macOS 인라인 열 / iPhone 시트)가 붙어 현행 Tools
  (21~53줄 순수 `HStack`) 관례를 넘는다. 재료는 `HwpDocumentMetadata.outline`이
  `Identifiable` + 1-기반 쪽 번호 + 수준까지 채워 내므로 호스트가 열 줄로
  만든다 — 배선 예는 `Sample/HwpSwiftSample/OutlineSidebar.swift`
- 검색 **결과 목록 UI** (`HwpSearchResultsList`) — v1 OUT. 엔진·검색 바·탐색기는 제공한다 (#75). 목록은 `List` 행 레이아웃·선택 강조·스니펫 truncation·접근성·플랫폼 chrome 분기가 붙어 현행 Tools (21~53줄 순수 `HStack`) 관례를 넘고 검증 형판도 없다. `HwpSearchMatch: Identifiable` + `HwpSearchSnippet.matchRange` + `pageNumber` 를 공개했으므로 호스트가 10줄로 만든다
- 정규식 검색 / 바꾸기 (replace) / 필드 한정 검색 — v1 OUT
- 편집 API (v2)
- 하이퍼링크 URL 라우팅 — 콜백만 제공, 실제 오픈은 앱 책임
- 인쇄/공유 **UI** — PDF 바이트까지가 우리 몫 (`HwpPDFExporter`), 저장 패널·인쇄
  대화상자·공유 시트는 앱 책임. PDF 링크 애노테이션(`.hyperlink` paint 명령이
  rect+url을 들고 있어 가능은 하다)도 v1 밖

## 안티 패턴

- `HwpDocumentView` 에서 `AppKit`/`UIKit` 을 직접 import — HwpKitNative 의 `Representable` wrapper 만 사용
- HwpKit 안에서 `openURL` / `ShareLink` / `fileExporter` / `searchable` / `NSSavePanel` / `printOperation` 류의 **호스트 UI 액션**을 직접 호출 — 스코프 크리프. `Tests/HwpKitTests/HwpKitScopeGuardTests.swift`가 `Sources/HwpKit/**.swift`의 비-주석 줄을 스캔해 막는다 (#74에서 신설 — 그전까지 이 줄은 "테스트로 grep 검증 있음"이라 적고 있었지만 HwpKit 소스를 훑는 테스트는 없었다. `SourceSafetyTests`는 `Sources/CoreHwp`만 본다). `searchable` 이 이 목록에 있는 것은 검색이 스코프 밖이라서가 **아니다** (#75 로 들어왔다) — `.searchable` 이 호스트의 navigation chrome 에 검색 필드를 설치하고 `\.isSearching` 을 환경에 심기 때문이다. 검색 UI 는 `HwpSearchBar` 가 독립 `View` 로 낸다. 가드가 부분 문자열 매칭이므로 HwpKit 안에서는 소문자 `searchable` 어근을 쓴 식별자 (`isSearchable`, `searchableUnits`) 도 금지 — 명명은 `HwpSearch*` 로 고정. 가드 자신도 **두 단언이 서로를 지탱**한다 (`HwpSearchBar.swift` 실재 + `searchable` 토큰 생존): 누가 검색 바를 `.searchable` 로 갈아엎으면 둘 중 하나가 반드시 깨진다
- `HwpDocumentLoader` 결과를 SwiftUI `@State` 에 담아 재로드 시 clear 를 생략 — Sample 에서 `document = nil` 초기화 패턴 유지

## Sample 앱

`Sample/HwpSwiftSample.xcodeproj` 는 xcodegen 산출 (`Sample/project.yml` 이 spec). SwiftPM 로컬 참조 `packages.hwp-swift.path: ..` (repo 루트). 재생성: `cd Sample && xcodegen generate`.

Sandbox ON + `com.apple.security.files.user-selected.read-write` entitlement — PDF 내보내기가 저장 패널로 고른 위치에 쓰므로 read-only로는 부족하다 (#74). 시뮬레이터 QA 는 `Documents/document.hwp` 자동 로드 (`.task` 훅).

내보내기는 **앱 임시 디렉터리에 먼저 쓰고** 그 파일을 `fileExporter`/인쇄로 넘긴다. 진행률·취소를 우리가 쥐어야 하고(1,030쪽이면 수 초), 사용자가 고른 위치에 직접 쓰면 취소 시 열리지 않는 부분 파일이 그 자리에 남기 때문이다. 저장 패널·인쇄는 진행 시트의 `onDismiss`에서 띄운다 — 두 모달을 같은 갱신 주기에 겹치면 두 번째 표시가 유실된다.

`#if os(macOS)` 분기가 여기서 처음 들어왔다: 인쇄 API(`PDFExportSupport.swift`)와 툴바 라벨이다. **iPhone 폭에는 컨트롤이 다 안 들어간다** — `HwpDocumentToolbar`가 그냥 `HStack`이라 넘치면 글자 단위로 줄바꿈해 "Zoom 100%"가 세 줄이 된다(시뮬레이터 실측, 내보내기 버튼 추가 전에도 두 줄이었다). 샘플은 iOS에서 버튼을 아이콘만으로 바꾸고 툴바를 가로 `ScrollView`에 넣어 해결한다 — **툴바 컴포넌트 자체를 고치지 않는다** (호스트 레이아웃은 호스트 몫).
