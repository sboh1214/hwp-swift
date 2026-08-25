# HwpKit

SwiftUI 공개 API target. HwpKitNative 위에 `NSViewRepresentable` / `UIViewRepresentable` 로 래핑. **AppKit/UIKit direct import 금지** (플랫폼 뷰는 HwpKitNative 통해).

**`CoreHwp`에 직접 의존하되 `CoreHwp` 타입은 공개 API에 노출하지 않는다** (#117에서 `Package.swift`에 의존 관계를 추가했다). 이 타깃에서 `CoreHwp`를 사용하는 곳은 `HwpDocumentLoader` 구현 파일 하나뿐이다 (`import CoreHwp`도 그 파일에만 있다). 그 역할은 `HwpError.unsupportedFeature`를 일반 오류 문자열로 변환하기 전에 포착하는 것이다. **`CoreHwp` 타입을 `public` 시그니처에 넣지 말 것** (현재 노출 0건): 호스트가 분기하기 위해 `CoreHwp`를 `import`해야 한다면 `HwpUnsupportedDocumentKind`를 별도의 공개 타입으로 둔 의미가 사라진다. `AppKit`/`UIKit` 금지와 달리 이 규약에는 코드 가드가 없다 — `HwpKitScopeGuardTests`의 `import` 스캔은 `AppKit`/`UIKit`/`PDFKit`만 본다.

## 공개 API 표면

- `HwpDocumentLoader(fontResolver:)` — 렌더에 쓸 폰트 해석기 주입 (기본 `HwpFontResolver()`). 커밋된 기준선을 쓰는 렌더 가드가 전부 이 인자 하나에 기대 기기 독립을 얻는다 (`.testDeterministic` — 루트 AGENTS.md "렌더 가드 4층"). 호스트도 재현 가능한 조판이 필요하면 같은 방식으로 고정 resolver를 넘긴다
- `HwpDocumentLoader.load(from:)` — URL / Data / FileWrapper 오버로드. 내부적으로 `HwpDocumentActor` 사용. 오류는 `HwpDocumentLoadError`로 매핑 (`CustomStringConvertible` + `LocalizedError` 채택 — 오류 설명은 한국어이므로 호스트가 `error.localizedDescription`을 그대로 표시하면 된다. `presentationBuildFailed`는 하위 파서나 페이지네이터가 보고한 원인을 `reason`에 원문 그대로 보존한다. 새 케이스를 추가하면 `description`도 함께 채우고 `HwpDocumentLoaderTests.testErrorDescriptionsCoverEveryCase`의 배열에도 넣을 것) (#117)
  - **미지원 문서의 종류를 보존한다** — 암호로 보호된 문서·배포용 문서·DRM 문서를 읽을 때 발생하는 `CoreHwp.HwpError.unsupportedFeature`를 `presentationBuildFailed`로 변환하기 전에 포착하고 `unsupportedDocument(HwpUnsupportedDocumentKind)`로 매핑한다 (`mapLoadFailure`가 매핑을 담당하며 세 로드 경로가 이를 공유한다). `HwpUnsupportedDocumentKind`는 `CoreHwp`의 `HwpUnsupportedFeature`에 대응하는 공개 타입이므로 호스트가 `CoreHwp`를 `import`하지 않고도 분기할 수 있다 — 매핑 `switch`가 모든 케이스를 나열하므로 `CoreHwp`에 새 종류가 추가되면 해당 종류의 매핑 누락이 컴파일 오류로 드러난다
  - **오류 설명의 한국어화는 로더에만 적용한다** (#117의 A안) — `CoreHwp.HwpError`의 오류 설명은 영문을 유지한다. 이를 번역하면 manifest에서 미지원 픽스처 4종에 지정한 `expectedError.description` 값이 모두 달라질 뿐 아니라 (`문서암호설정-보안수준높음`·`문서암호설정-보안수준보통`·`배포용문서`·`drm-unsupported-derived`), 번역 범위도 `HwpError`의 나머지 케이스 전체로 넓어진다. 미지원 오류는 타입으로 매핑되므로 로더가 `CoreHwp`의 영문 설명을 사용할 일도 없다 — 하위 오류의 원문을 그대로 보존하는 경우는 `presentationBuildFailed`의 `reason`뿐이다
  - 회귀 검증에는 같은 픽스처 4종을 쓴다 — URL 로드 경로에서는 네 픽스처를 모두 순회해 세 문서 종류를 검증하고 (`testUnsupportedFixturesThrowTypedUnsupportedDocument`), `Data`와 프로그레시브 로드 경로에서는 한 종류씩만 확인한다 (`testUnsupportedDataThrowsTypedUnsupportedDocument`·`testLoadUpdatesSurfacesTypedUnsupportedDocument` — 세 경로가 `mapLoadFailure` 하나를 공유하므로 세 종류를 모두 검증하는 경로는 하나면 충분하다). `mapLoadFailure`가 `internal`인 이유는 오류를 그대로 통과시키는 분기를 공개 API만으로 재현하기 어렵기 때문이다. 따라서 `testMapLoadFailureBranches`가 이 함수를 직접 호출해 세 분기를 검증한다
- `HwpDocumentLoader.loadUpdates(from:)` — 프로그레시브 로딩. `AsyncThrowingStream<HwpDocumentSnapshot, Error>` 로 첫 페이지 확정 즉시 스냅샷을 방출하고 배치 단위로 이어가다 최종 스냅샷(`isComplete`)으로 끝난다. 최종 문서는 `load(from:)` 결과와 동일. 뷰는 `HwpDocumentMetadata.loadToken` 으로 증분 적용(스크롤 유지) vs 전체 리셋을 판정
- `HwpDocumentView` — SwiftUI View. optional `zoomScale: Binding<CGFloat>?` + `fitZoom: Binding<HwpZoomFit?>?` + `currentPage: Binding<Int>?` + `searchController: HwpSearchController?` + `isKeyboardPageNavigationEnabled: Bool = true` + hyperlink/unsupported 콜백
  - **키보드 페이지 이동은 첫 응답자 한정이다** (#120). PageUp/Down·Home/End를 네이티브 뷰가 쪽 단위로 해석하되, 뷰가 first responder일 때만 이벤트가 온다 (macOS는 클릭, iOS는 탭·롱프레스로 잡는다 — 문서 대입·창 부착에서 스스로 잡는 경로는 없다). 전역 단축키를 소유하지 않는 규약(`HwpSearchBar` 참조)은 코드 가드가 없어 문서와 리뷰로만 지켜진다 — 새 키 처리를 더할 때 이 경계를 넘지 말 것. 호스트가 이 키들을 직접 쓰면 `isKeyboardPageNavigationEnabled: false`로 끈다 (네이티브 뷰의 같은 이름 프로퍼티에 배선되는 값 타입이라 동일성 가드 없이 매 업데이트 대입한다). 구현과 가드 테스트는 `Sources/HwpKitNative/AGENTS.md`의 "키보드 페이지 이동"
  - **`fitZoom` 은 원샷 명령이다** (#78). 값을 넣으면 뷰가 한 번 맞추고 바인딩을 `nil` 로 되돌린다 (되돌리기는 `normalizeOutOfRange*Binding` 과 같은 계약 — 업데이트 **밖**에서, 문서 세대·값 불변 가드를 지나). 지속 모드가 아닌 이유는 창 리사이즈마다 다시 맞추면 그 사이 사용자가 핀치로 바꾼 배율을 조용히 덮기 때문이다. 결과 배율은 `zoomScale` 바인딩으로 돌아오므로 툴바 라벨이 저절로 맞는다
  - **뷰포트 크기는 공개하지 않는다.** 그것이 이 API 가 명령 바인딩인 이유다 — 산식을 호스트에 내주려면 뷰포트를 넘길 통로를 새로 뚫어야 하는데, 지오메트리 계층은 가상화 세부가 공개 표면이 되지 않도록 **의도적으로** internal 이다. 산식(`HwpDocumentViewSupport.fitZoomScale`)은 HwpKitNative 에 internal 로 남고 뷰가 자기 캔버스·뷰포트를 넣어 부른다
- `HwpDocumentToolbar<Content>` — trailing content 를 받는 컨테이너 (툴바 chrome)
- `HwpPageNavigator(currentPage: Binding<Int>, totalPages: Int)` — "Page [N] of Y" (번호 입력 필드) + ± 버튼. 필드는 Enter로만 커밋하고 (`1...totalPages` 클램프, 숫자 아님·오버플로는 무시) 포커스를 잃으면 되돌린다 — 커밋 전 중간 값("1"을 거쳐 "12")이 바인딩에 새면 타이핑마다 문서가 스크롤되므로 초안은 `@State`다 (#120). 파사드에서 유일한 `@State` 예외이고, 판정 로직은 초안을 인자로 받는 `commitPageEntry(_:)`라 `HwpToolsTests` 관례로 검증된다
- `HwpZoomControls(zoomScale: Binding<CGFloat>, fitZoom: Binding<HwpZoomFit?>?, range: ClosedRange<CGFloat>)` — 기본 range `0.25...5.0`. `fitZoom` 을 넘기면 폭 맞춤·쪽 맞춤 버튼이 함께 나온다 (안 넘기면 안 그린다 — 뷰에 연결되지 않은 버튼을 내지 않기 위해서다). 이 컴포넌트는 **명령만 세운다**: 배율 산식은 뷰포트를 아는 문서 뷰가 쥐고 있다
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
- `HwpAccessibilityContent` (HwpKitCore) — 문서 접근성 요소 합성 (#79).
  `pageUnits(page:bodyUnits:headingTitles:)`/`memoPanelUnits(panel:)`가
  (라벨, 페이지·패널 로컬 top-down rect) 목록을 준다. 번들 뷰는 이것을 가시
  (±2) 페이지에서 플랫폼 AX 요소로 감싸 자동 노출하므로 호스트가 할 일은
  없고, 커스텀 뷰를 만드는 호스트만 같은 재료로 AX 트리를 만든다. 낭독
  순서·수명 규약은 `Sources/HwpKitNative/AGENTS.md`의 "문서 접근성 요소 합성"
- **툴바 VoiceOver 라벨 정책** (#79) — `HwpZoomControls`·`HwpPageNavigator`·
  `HwpSearchNavigator`·`HwpSearchBar`의 컨트롤 12개(버튼 11 + 쪽 번호 입력
  필드)가 한국어 String 라벨을
  단다 (`-`·`+`·`‹`·`›`는 문장부호라 VoiceOver가 문맥 없이 읽는다). 라벨이
  `LocalizedStringKey`가 아니라 **`String` 계산 프로퍼티**인 이유: 키 문자열을
  꺼낼 공개 경로가 없어 문구를 테스트로 고정할 수 없다
  (`HwpAccessibilityLabelTests`가 문구와 12개 상호 구별을 단언한다). 한국어
  하드코딩은 #78 1번(에러 한국어화)과 같은 정책이다 — 로컬라이제이션 인프라가
  없어 유일한 경로. 새 버튼을 더하면 라벨도 함께 달고 구별 단언에 넣을 것
- `HwpPageThumbnails` — 쪽 축소판 (#76). `update(document:)`로 대상을 걸고 `image(forPageAt:pixelWidth:) async throws -> CGImage`로 **0-기반** 쪽을 받는다 (`HwpPageNavigator`·`HwpOutlineItem.pageNumber`가 1-기반이므로 그쪽 값은 `- 1`을 하거나 `HwpOutlineItem.pageIndex`를 쓴다). 화면·PDF와 **같은 paint list·같은 조판**이다 — 구현은 HwpKitNative의 `HwpPageThumbnailRenderer`이고 `HwpPDFExporter` ↔ `HwpPDFRenderer`와 같은 관계다. 종횡비는 `HwpPageThumbnails.pixelHeight(for:pixelWidth:)`가 준다 (셀 자리를 미리 잡을 때 쓴다). 에러는 `HwpThumbnailError`
  - **공개 수치 인자는 `Int.max`가 들어와도 트랩하지 않는다** (#76 리뷰, 위 "바인딩 방어"와 같은 기준). 범위 밖 쪽은 안전하게 `.pageOutOfRange`로 분류되는데 그 오류를 `localizedDescription`으로 **표시하는 순간** 1-기반 변환이 트랩하던 자리가 있었다 — 재시도 가능 상태를 알리려고 만든 타입이 프로세스를 죽이면 안 되므로 변환을 포화시킨다. 픽셀 크기에도 축별 상한이 있다 (`HwpPageBitmapRenderer.maximumPixelDimension`): 종횡비가 병적인 문서에서 높이는 **클램프**되고(축소판이 눌려 나온다 — 쪽을 통째로 잃는 것보다 낫다), 상한을 넘는 폭을 직접 넘기면 `.renderFailed`다
  - **PDF와 두 군데서 갈린다.** (1) 미완성 문서를 거부하지 않는다 — 중간 스냅샷도 받아 지금까지 확정된 쪽을 그린다. 축소판은 사용자가 보관하는 산출물이 아니라 진행 중인 문서를 훑는 수단이라 쪽이 늘면 목록이 함께 자라는 것이 맞고, `update(document:)`가 그 증분을 알아봐 이미 그린 축소판을 유지한다 (스냅샷마다 불러도 1,030쪽이 다시 그려지지 않는다). (2) 바이트 예산에 걸린 그림을 실패로 보지 않고 회색 플레이스홀더로 남긴다 — 그림 하나 때문에 쪽 전체를 잃는 것이 더 나쁘다. (1)의 대가로 **범위 밖 쪽이 정상 경로에 들어온다**: 아직 안 온 쪽을 그리드가 요청하는 일이 로딩 중에는 흔하다. 그래서 `.pageOutOfRange(index:pageCount:)`가 `.renderFailed` 문자열로 접히지 않는 제 case다 — PDF의 `.incompleteDocument`와 같은 이유로, 호스트가 **다음 스냅샷에서 성공할 상태**와 진짜 실패를 갈라야 한다
  - 요청은 **직렬화**된다 (쪽 순회 규율이 공급자 전역이라 동시 렌더가 서로의 확정을 버린다). 이미 그린 쪽은 같은 인스턴스로 즉시 온다. 호출 태스크를 취소하면 **대기가 끊기고** `.cancelled`가 나며 남은 디코드는 시작되지 않는다 — 디코드 스로틀이 **가시 페이지와 공유되는 전역 3슬롯**이라 이 취소가 성능 장치가 아니라 계약이다 (`Sample`의 셀이 `.task`로 그렇게 한다). **이미 스폰된 디코드까지** 놓으려면 `cancelOutstanding()`이다 (공급자가 비구조적 태스크로 들고 있어 호출자 취소가 닿지 않는다)
  - **UI는 넘기지 않는다** — 그리드·목록 레이아웃은 호스트 몫이다 (아래 "v1 스코프 밖"의 개요 목록과 같은 기준). 배선 예는 `Sample/HwpSwiftSample/ThumbnailSidebar.swift`

## 인덱싱 컨벤션

**`HwpPageNavigator` 는 1-indexed** (`currentPage ∈ 1...totalPages`). 하지만 native view (`HwpDocumentNSView` / `HwpDocumentUIView`) 는 0-indexed page range 를 사용.

`HwpDocumentView` 의 wrapper 가 변환:
- SwiftUI → native: `currentPage - 1`
- native → SwiftUI: `page + 1` (`handlePageChanged` 에서)

바인딩 테스트 (`HwpDocumentViewTests.testBindingsPropagateThroughNativeWrapper`) 는 이 오프셋 3 (= 2 + 1) 을 검증.

## 바인딩 방어 (public Binding 은 임의 값이 들어온다)

호스트 앱의 상태 복원/버그로 극단값이 들어와도 트랩하지 않아야 한다.

- 페이지: `hwpScrollPageIndex(fromOneBased:)` 가 **클램프를 뺄셈보다 먼저** 한다 (`max(1, page) - 1`). `page - 1` 을 먼저 하면 `Int.min` 에서 오버플로 트랩. macOS·iOS 분기가 이 헬퍼를 공유해 산식이 갈라지지 않는다
- 줌: 표시와 쓰기가 **다른 게이트**를 쓴다 (#107 리뷰). 쓰기는 `sanitized` — 비-finite 는 1.0 폴백 후 `range` 클램프 (`Int(nan * 100)` 은 트랩, `min`/`max` 만으로는 NaN 이 통과). 표시는 `displayScale` — 같은 비-finite 폴백에 `Int` 변환 트랩만 막는 넓은 한계를 걸고 **`range` 로는 클램프하지 않는다**. `range` 는 `±` 버튼의 이동 경계일 뿐 문서 뷰의 실제 배율 한계(`0.25...5.0`)를 구속할 통로가 없어, 표시까지 클램프하면 좁은 `range` 를 넘긴 호스트에서 라벨이 거짓말을 한다 (실측: `range` 0.5...2.0 에 배율 0.25 → "50%" 표시). 배율이 핀치로 들어왔든 맞춤으로 들어왔든 같은 바인딩 하나를 지나므로 표시는 출처를 구분할 수 없다 — 맞춤이 만든 결함이 아니라 그 전부터 있던 것이고, 그래서 고치는 자리도 맞춤이 아니라 표시다. 라벨이 실제로 내보내는 값은 `displayPercent` 이고 가드가 그것을 잡는다 (`zoomText` 가 private 이라 표시를 다시 `sanitized` 로 돌리는 변경은 이 값에서만 걸린다)
- 줌 writeback 판정은 톨러런스 비교 **전에** 비-finite 를 처리한다 (`hwpZoomNeedsWriteback` / `hwpZoomBindingUnchanged`). NaN 은 abs 비교가 전부 false 라, 그냥 두면 핀치 echo·정규화가 모두 막혀 바인딩이 영구 NaN 으로 고착된다

## Wrapper 재사용 규약

- `HwpDocumentView.updateNSView/UIView` 는 매번 `context.coordinator.update(...)` 로 콜백 참조를 갱신 (SwiftUI 가 뷰를 재사용해도 최신 클로저가 발화되도록)
- `Coordinator` 클래스가 hyperlink/unsupported/pageChanged 발화를 SwiftUI 쪽 콜백으로 프록시
- **해체 훅을 반드시 구현한다** (#75 리뷰) — `dismantleNSView`/`dismantleUIView` 가 `searchController = nil` 로 세션을 뗀다. 호스트가 `@State` 로 소유한 컨트롤러는 뷰보다 오래 살고 선택 컨트롤러를 **강참조**하므로, 안 떼면 문서 전체가 상주한다 (문서를 닫거나 재로드가 실패해 새 뷰가 안 붙는 경로). 참조 타입을 뷰에 주입하는 API 를 새로 낼 때마다 같은 훅이 필요하다
- **참조 타입 프로퍼티 대입에는 동일성 가드가 필수다** (#75) — `view.searchController !== searchController` 일 때만 넣는다. 콜백과 달리 이쪽 didSet 은 배선을 다시 하므로, 무조건 대입하면 재배선 → 재스캔 → 관찰자 통지 → 호스트 body 무효화 → 다시 이 configure 로 **타이핑 없이도 도는 자기 급전 루프**가 된다 (문서 대입의 중복-대입 스킵과 같은 성격). 콜백은 값이 매번 새 클로저라 이 가드를 걸 수 없고 걸 필요도 없다 (didSet 이 일을 하지 않는다)
- **같은 갱신에 명시 배율과 fit 이 함께 오면 fit 이 이긴다** (#78) — `configure` 가 문서 대입·배율·페이지 요청을 처리한 **뒤** `applyFitZoom` 을 부른다. 배율 다음인 것은 명시 배율보다 fit 이 나중에 온 뜻이기 때문이고, 페이지 다음인 것은 쪽 맞춤이 **그 요청이 실제로 안착한 쪽**을 기준으로 삼게 하려는 것이다. 순서를 뒤집으면 맞춤이 같은 프레임에서 옛 쪽·옛 배율 위에 얹힌다
  - **"안착한 쪽"이지 "요청한 쪽"이 아니다** (#78 리뷰). 프로그레시브 중간 스냅샷에 아직 없는 쪽을 요청하면 `scrollToPage` 가 마지막 로드 쪽으로 클램프하므로 `.page` 는 그 클램프된 쪽에 맞춰지고, 원샷이라 그대로 소비된다. `.page` 의 정의가 "현재 쪽을 통째로" 이고 그 시점의 현재 쪽이 클램프된 쪽이므로 동작 자체는 정의와 일치하지만, **요청 인덱스와는 갈린다**. 실측: 2쪽 스냅샷 + `currentPage = 5` 에서 배율이 0.7126(842pt 쪽의 맞춤)으로 정해지고, 나중에 호스트가 쪽을 다시 걸어 2000pt 쪽으로 이동해도 그 배율이 남는다 (그 쪽의 맞춤은 0.3 — 2.4배 크게 그려져 맞춤이 성립하지 않는다)
  - **그래도 연기하지 않는 것이 의도다.** 명령을 스냅샷 사이에 살려 두면 1,030쪽 로딩 내내 대기하다가 그 사이 사용자가 핀치로 바꾼 배율을 조용히 덮어, 원샷으로 만든 이유(`HwpZoomFit` doc)가 그대로 사라진다. 구제책은 다른 모든 로딩 중 맞춤과 같다 — 쪽이 도착한 뒤 다시 누른다. 연기를 정말 넣는다면 `consumeFitZoomCommand` 도 함께 막아야 한다: 그것은 적용 여부와 무관하게 바인딩을 비우므로 "적용만 건너뛰기" 는 연기가 아니라 명령 **소실**이다
  - **명령에는 문서 세대 소유권이 있다** (#107 리뷰). `configure` 는 명령을 **적용하기 전에** `HwpDocumentCoordinator.fitToApply` 를 지난다 — 같은 값이 nil 을 거치지 않고 세대를 넘으면 옛 문서를 향한 것이라 적용하지 않는다. 소비 Task 가 돌기 전에 문서가 바뀌면 `configure` 가 같은 non-nil 바인딩을 다시 보는데, 세대 비교가 명령을 **지우는** 쪽에만 있어 A 의 `.page` 가 B 에 적용됐다 (실측: 배율이 B 의 쪽 맞춤 0.3 으로, `.page` 라 스크롤도 B 의 쪽 머리로). 네이티브 뷰가 예약을 교체에서 버리는 가드를 래퍼가 명령을 다시 건네 **우회**하던 것이다. `HwpZoomFit?` 에는 신원이 없어 "호스트가 같은 값을 새로 넣은 경우"와 구분되지 않으므로 그때도 적용하지 않는다 — 대가는 버튼을 다시 누르는 것이고 반대 방향의 대가는 확인된 오적용이다. 값이 **다르면** 새 요청이므로 적용한다: 그 갈래가 없으면 "모든 교체를 거부"하는 구현도 가드 테스트를 통과해 "새 문서를 열자마자 맞춤"이 조용히 죽는다
  - 덧붙여 그 페이지 요청 자체도 살아남지 않는다 — 레이아웃 패스의 `onPageChanged` 가 `applyingBinding` **밖**이라 클램프된 쪽을 바인딩에 되쓴다 (실측 `5 → 2`). `handlePageChanged` 주석이 약속한 "첫 프로그레시브 스냅샷 이후의 페이지 요청이 echo 로 덮어써져 유실되지 않게" 와 어긋나는 **선행 별건**이고 #78 이 만든 것이 아니다

## v1 스코프 밖 (추가 금지)

- File picker / document browser — 앱 책임
- 개요·책갈피 **목록 UI** (`HwpOutlineSidebar`) — v1 OUT, 검색 결과 목록과 **같은
  기준**이다: `List` 행 레이아웃·수준 들여쓰기·현재 위치 강조·접근성 라벨·
  플랫폼 chrome 분기(macOS 인라인 열 / iPhone 시트)가 붙어 현행 Tools
  (21~53줄 순수 `HStack`) 관례를 넘는다. 재료는 `HwpDocumentMetadata.outline`이
  `Identifiable` + 1-기반 쪽 번호 + 수준까지 채워 내므로 호스트가 열 줄로
  만든다 — 배선 예는 `Sample/HwpSwiftSample/OutlineSidebar.swift`
- 쪽 축소판 **그리드 UI** (`HwpThumbnailSidebar`) — v1 OUT, 개요 목록과 **같은
  기준**이다. 그리고 여기는 한 겹 더 있다: `LazyVGrid` 셀마다 지연 요청·취소를
  걸어야 하고(전역 디코드 슬롯 3개를 가시 페이지와 나눠 쓴다) 현재 쪽 자동
  스크롤·자리 예약 같은 호스트 레이아웃 판단이 붙는다. 엔진(`HwpPageThumbnails`)은
  제공하므로 호스트가 그 위에 그린다 — 배선 예는
  `Sample/HwpSwiftSample/ThumbnailSidebar.swift`
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

사이드바는 **표시 여부가 아니라 내용**이 상태다 (`SidebarMode?`, #76). 불리언을 축마다 두면 "개요와 축소판이 둘 다 켜짐"이라는 없는 상태가 생겨 macOS 인라인 열과 iPhone 시트에서 서로 다르게 깨진다. 개요를 골랐지만 그 문서에 개요가 없으면 축소판으로 **대신 그린다** — 개요가 없는 문서에서 사이드바가 통째로 사라지던 것이 그 축을 추가한 이유이고, 사용자의 선택을 덮어쓰지는 않는다(개요가 있는 문서를 다음에 열면 다시 개요다). 축소판 렌더러(`HwpPageThumbnails`)는 **호스트가** 소유한다: 사이드바 뷰가 소유하면 모드를 토글하거나 시트를 닫을 때마다 그때까지 그린 축소판을 통째로 버린다. 그렇게 오래 사는 만큼 **문서를 버릴 때 `update(document: .empty)`로 교체**해야 한다 (#76 리뷰) — `cancelOutstanding()`은 요청만 끊고 보유는 유지하므로, 새 로드가 첫 스냅샷을 내기 전에 실패하면 옛 문서(쪽·공급자·디코드 이미지·축소판)가 오류 화면 내내 상주한다.

`#if os(macOS)` 분기가 여기서 처음 들어왔다: 인쇄 API(`PDFExportSupport.swift`)와 툴바 라벨이다. **iPhone 폭에는 컨트롤이 다 안 들어간다** — `HwpDocumentToolbar`가 그냥 `HStack`이라 넘치면 글자 단위로 줄바꿈해 "Zoom 100%"가 세 줄이 된다(시뮬레이터 실측, 내보내기 버튼 추가 전에도 두 줄이었다). 샘플은 iOS에서 버튼을 아이콘만으로 바꾸고 툴바를 가로 `ScrollView`에 넣어 해결한다 — **툴바 컴포넌트 자체를 고치지 않는다** (호스트 레이아웃은 호스트 몫).
