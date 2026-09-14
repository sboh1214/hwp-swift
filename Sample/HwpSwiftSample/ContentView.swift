import Combine
import HwpKit
import HwpKitCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // 상태는 이 파일 한 곳에만 있다 — extension에는 저장 프로퍼티를 둘 수 없고,
    // 애초에 `@State` 소유권을 옮기지 않는 것이 이 분할(#140)의 전제다.
    // 다른 파일의 extension(`ContentView+Toolbar`·`+PDFExport`·
    // `+DocumentLoading`)이 만지는 것만 `private`을 뗐다 — 같은 타입이라도
    // `private`은 **같은 파일** 안에서만 보이기 때문이다. 타입 밖에서 이 값들을
    // 읽는 곳은 없다.
    //
    // 아래 `init() {}`은 그 승격의 부작용을 되돌린다. "private 프로퍼티가 하나라도
    // 있으면 메모와이즈 이니셜라이저도 private"은 **초기값이 없을 때만** 참이다 —
    // 초기값이 있는 private 프로퍼티는 파라미터 목록에서 아예 빠질 뿐 접근 수준을
    // 낮추지 않는다(컴파일러 실측). 그대로 두면 `ContentView(document:…:)` 같은
    // 27인자 이니셜라이저가 앱 타깃에 열려, 뷰가 재생성되면 되돌아갈 값을 `@State`에
    // 씨앗으로 심는 경로가 생긴다. 이니셜라이저를 하나라도 직접 선언하면 메모와이즈
    // 합성이 멈추므로, 생성 경로는 분리 전과 같이 `ContentView()` 하나로 남는다.
    @State var document: HwpDocument?
    @State var errorMessage: String?
    @State var showPicker = false
    @State var isLoading = false
    /// 프로그레시브 로딩 진행률 (완료되면 nil)
    @State var loadProgress: Double?
    @State var loadGeneration = 0
    /// 열기 요청 세대 (#126) — 드롭 provider 적재가 비동기라, 느린 항목의 완료가
    /// 그 사이 시작된 다른 열기를 덮는 것을 막는다. `loadGeneration`으로는 못
    /// 막는다: 그것은 `loadDocument` 안에서만 올라서, 낡은 드롭 완료가 스스로
    /// 세대를 올리며 새 문서를 밀어낸다.
    @State var openGeneration = 0
    /// 진행 중 로드 task — 새 로드 시작 시 이전 것을 취소한다 (#6)
    @State var loadTask: Task<Void, Never>?
    /// 진행 중 드롭 적재의 취소 손잡이 (#126) — 세대 검사는 완료의 **결과**만
    /// 버리고 전송은 계속 돌므로, 추월·뷰 해체 시 이것으로 전송 자체를 끊는다.
    @State var dropRequest: DropOpenRequest?
    @State var currentPage: Int = 1
    @State var zoomScale: CGFloat = 1.0
    /// 배율 맞춤 **원샷 명령** — 툴바가 값을 넣으면 문서 뷰가 한 번 적용하고
    /// nil로 되돌린다. 뷰포트를 아는 것은 뷰뿐이라 배율 계산은 그쪽 몫이고,
    /// 호스트는 같은 바인딩을 뷰와 툴바에 함께 넘기기만 한다.
    @State var fitZoom: HwpZoomFit?
    // 사이드바 상태는 **직교하는 두 값**이다 (#77 개요·책갈피 → #76에서 축소판
    // 축 추가): 어느 축을 고르고 있는가(`sidebarMode`)와 지금 보이는가
    // (`sidebarVisible`). 축마다 불리언을 두면 "둘 다 켜짐"이라는 없는 상태가
    // 생기지만, 이 둘은 조합이 전부 유효하다. 하나로 접어 `SidebarMode?`를 쓰면
    // **감출 때 고른 축이 사라져** 다시 열 때 다른 축이 되는 문제가 있다.
    @State var sidebarMode: SidebarMode = .outline
    // **기본값이 플랫폼마다 다르다**: macOS는 인라인 열이라 켜 두고, iOS는
    // 시트라 꺼 둔다 (켜 두면 문서를 열자마자 모달이 뜬다).
    #if os(macOS)
        @State var sidebarVisible = true
    #else
        @State var sidebarVisible = false
    #endif
    /// 축소판 렌더러는 **호스트가** 소유한다 — 사이드바 뷰가 소유하면 모드를
    /// 토글하거나 iPhone 시트를 닫을 때마다 뷰가 사라지면서 그때까지 그린
    /// 축소판을 통째로 버린다.
    @State var thumbnails = HwpPageThumbnails()
    /// 문서 검색 세션 (#75). 호스트가 소유해 뷰와 검색 바에 **같은 인스턴스**를
    /// 넘긴다 — 라이브러리가 하이라이트·매치 노출 스크롤을 알아서 배선한다.
    @State private var search = HwpSearchController()
    /// Cmd+F가 검색 필드로 포커스를 옮기는 훅. 라이브러리는 전역 단축키를
    /// 소유하지 않으므로 호스트가 잡아서 넘긴다.
    @FocusState var searchFieldFocused: Bool
    /// PDF 내보내기 진행률 (진행 중일 때만 non-nil — 시트 표시 조건을 겸한다)
    @State var exportProgress: Double?
    @State var exportTask: Task<Void, Never>?
    /// 내보내기가 끝난 임시 PDF — 저장 패널/인쇄가 이 파일을 가리킨다
    @State var exportedPDF: URL?
    /// 그 파일을 목적지 UI(저장 패널·인쇄)에 이미 넘겼는지. 넘긴 뒤에는 그쪽이
    /// 다 쓸 때까지 살려 둬야 한다 — 창이 닫힐 때 지우면 사용자가 확정한
    /// 인쇄·저장이 깨진다 (`UIPrintInteractionController`는 스풀링 동안,
    /// `fileExporter`는 완료 핸들러까지 이 파일을 읽는다).
    @State var exportedPDFIsHandedOff = false
    /// 사용자에게 보일 이름 (저장 패널 기본 파일명·인쇄 작업명). 임시 파일명은
    /// UUID라 그대로 쓸 수 없다
    @State var exportedName = "document"
    /// 진행 시트가 닫힌 **뒤에** 할 일 — 두 모달을 같은 갱신 주기에 겹치면
    /// 두 번째 표시가 유실된다 (닫는 중인 시트 위로 띄우는 꼴).
    @State var pendingDestination: PDFDestination?
    /// 진행 시트가 닫힌 **뒤에** 띄울 실패 사유 (같은 이유로 미룬다)
    @State var pendingError: String?
    #if !os(macOS)
        @State var printAnchor = HwpPrintAnchor.Box()
    #endif
    /// 진행 시트가 실제로 표시됐는지. 표시된 적이 없으면 `onDismiss`가 오지
    /// 않아 저장·인쇄·오류가 `pending*`에 갇힌다 — 작은 문서는 시트가 뜨기 전에
    /// 끝나서 `0 → nil` 전이가 한 갱신 주기로 합쳐질 수 있다.
    @State var exportSheetDidPresent = false
    @State var showSavePanel = false
    /// 내보내기·인쇄 실패 사유 (빈 화면의 errorMessage와 별개 — 문서를 보는
    /// 중에는 그쪽이 화면에 없다)
    @State var exportError: String?
    /// 최근 문서 목록 (#126) — 진실 원본은 `RecentDocumentsStore`(defaults)이고
    /// 이 상태는 그 거울이다. 기록·제거 helper가 돌려주는 목록으로 맞춘다.
    @State var recents = RecentDocumentsStore.load()
    /// 드래그가 창 위에 있는 동안 true — 드롭 가능 시각 피드백 (#126).
    @State private var isDropTargeted = false
    /// 미지원 요소 목록 표시 여부 — macOS는 인라인 열, iOS는 시트 (#126).
    /// 요소 자체는 상태로 들지 않고 `document.unsupportedElements`(공개 배열,
    /// 최종 스냅샷에만 실림)를 그대로 읽는다 — `onUnsupportedElement` 콜백은
    /// 배열 전체를 매번 재방출해 "재방출 중복"과 "같은 쪽의 동종 요소"(값이
    /// 완전히 같다)를 구분할 수 없어, 콜백 집계는 append든 `Set`이든 어느
    /// 쪽으로도 개수가 틀린다 (전자는 과다, 후자는 과소).
    @State var showUnsupportedList = false
    /// 하이퍼링크를 시스템 브라우저로 여는 통로. 라이브러리는 콜백만 내고
    /// 여는 것은 앱 책임이다 (`Sources/HwpKit/AGENTS.md`).
    @Environment(\.openURL) private var openURL

    init() {}

    /// 내보내기를 마친 뒤 할 일 — 저장 대화상자냐 인쇄냐.
    enum PDFDestination {
        case save
        case print
    }

    static let exportFilePrefix = "hwp-sample-export-"
    /// 이 프로세스가 시작된 시각 — 이보다 오래된 임시 파일(내보내기 PDF·드롭
    /// 사본)만 이전 실행의 잔해다.
    static let processStart = Date()

    var body: some View {
        Group {
            if let document {
                loadedView(document: document)
            } else if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(
                    errorMessage: errorMessage,
                    recents: recents,
                    onOpen: { showPicker = true },
                    onSelectRecent: openRecent,
                    onRemoveRecent: { recents = RecentDocumentsStore.remove($0) }
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Open") { showPicker = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [
                DropOpenSupport.hwpType,
                DropOpenSupport.hwpxType,
            ]
        ) { result in
            switch result {
            case let .success(url):
                loadDocument(from: url)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            loadDocument(from: url)
        }
        // 드롭 대상은 **루트**다 — 빈 상태에는 열기, 문서를 보는 중에는
        // Re-open과 같은 교체로 동작한다 (#126).
        .onDrop(of: DropOpenSupport.acceptedTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            // 드래그가 창 위에 있는 동안의 시각 피드백. 히트 테스트를 끄지
            // 않으면 이 오버레이가 드롭 대상(아래 Group)을 가린다.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        // WindowGroup의 다른 창이 기록·제거한 최근 문서를 이 창의 거울에도
        // 반영한다 — 같은 프로세스의 defaults 변경마다 발화하고, 목록이 최대
        // 10개라 재적재 비용은 무시된다. 이것이 없으면 빈 상태로 남아 있는
        // 창이 낡은 목록을 계속 보이고, 다른 창에서 제거한 항목을 그 창에서
        // 눌러 부활시킬 수 있다.
        .onReceive(
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            recents = RecentDocumentsStore.load()
        }
        .task {
            Self.removeStaleExports()
            DropOpenSupport.removeStaleDropCopies(olderThan: Self.processStart)
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                // 시뮬레이터 QA 자동 로드 — hwp가 우선이고 없으면 hwpx다.
                let candidates = ["document.hwp", "document.hwpx"]
                    .map(docs.appendingPathComponent)
                if let candidate = candidates.first(where: {
                    FileManager.default.fileExists(atPath: $0.path)
                }), document == nil {
                    loadDocument(from: candidate)
                }
            }
        }
        .onDisappear(perform: cancelExportOnTeardown)
        // 내보내기 모달은 **문서와 무관한 루트**에 건다. 로드된 뷰에 걸면
        // 내보내기 중 재로드(`onOpenURL`·Re-open)가 `document = nil`로 표시자를
        // 통째로 없애, 뒤늦게 끝난 내보내기가 시트를 닫을 곳도 저장·인쇄를 띄울
        // 곳도 잃는다 (임시 PDF도 남는다).
        .sheet(
            isPresented: Binding(
                get: { exportProgress != nil },
                set: { isPresented in
                    // 시트를 닫는 것은 곧 취소다 — 백그라운드로 이어 가면 진행
                    // 상황을 볼 곳이 없다.
                    if !isPresented {
                        exportTask?.cancel()
                    }
                }
            ),
            onDismiss: presentPendingDestination
        ) {
            exportProgressSheet
        }
        .fileExporter(
            isPresented: $showSavePanel,
            document: exportedPDF.map(PDFFileDocument.init(url:)),
            contentType: .pdf,
            defaultFilename: exportedName
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
            // 저장 패널이 닫혔으면 파일 내용은 이미 목적지로 복사됐다.
            discardExportedPDF()
        }
        .alert(
            "PDF 오류",
            isPresented: Binding(
                get: { exportError != nil },
                set: {
                    if !$0 {
                        exportError = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func loadedView(document: HwpDocument) -> some View {
        VStack(spacing: 0) {
            #if os(macOS)
                toolbar(document: document)
            #else
                // iPhone 폭에는 컨트롤이 다 안 들어간다. `HwpDocumentToolbar`는
                // 그냥 `HStack`이라 넘치면 **글자 단위로** 줄바꿈해 "Zoom 100%"가
                // 세 줄이 되므로(시뮬레이터 실측), 가로 스크롤로 한 줄을 지킨다.
                ScrollView(.horizontal, showsIndicators: false) {
                    toolbar(document: document)
                }
                .fixedSize(horizontal: false, vertical: true)
            #endif

            // 툴바 **밖** 별도 행이다. `HwpDocumentToolbar`는 순수 `HStack`이라
            // 가변 폭 필드를 그 안에 넣으면 iPhone 폭에서 레이아웃이 무너지고,
            // 툴바 컴포넌트 자체는 고치지 않는 것이 이 저장소 규약이다.
            HwpSearchBar(controller: search, isFocused: $searchFieldFocused)
                .padding(.horizontal)
                .padding(.vertical, 6)

            // 미지원 요소 배너 (#126) — 툴바 행이 아니라 문서 영역 상단이다
            // (툴바에는 이미 재열기·사이드바·페이지 네비·내보내기·찾기·줌이
            // 들어차 있다). 중간 스냅샷의 배열은 항상 비어 있어 이 배너는
            // 로드 완료 후 한 번의 전이로 나타난다.
            if !document.unsupportedElements.isEmpty {
                UnsupportedElementsBanner(elements: document.unsupportedElements) {
                    showUnsupportedList.toggle()
                }
            }

            documentArea(document: document)
        }
        #if !os(macOS)
        // iPhone 폭에는 사이드바 열이 들어가지 않는다 — iOS는 시트로 낸다
        // (툴바를 가로 스크롤에 넣은 것과 같은 이유: 호스트 레이아웃은
        // 호스트 몫이고, 라이브러리 컴포넌트는 고치지 않는다).
        .sheet(
            item: Binding(
                get: { visibleSidebar(for: document) },
                set: { sidebarVisible = $0 != nil }
            )
        ) { mode in
            NavigationStack {
                sidebarContent(mode, document: document, onSelect: { sidebarVisible = false })
                    .navigationTitle(mode.title)
                    .toolbar {
                        Button("닫기") { sidebarVisible = false }
                    }
            }
        }
        // 미지원 요소 목록 — 사이드바와 같은 이유로 iOS는 시트다 (#126).
        .sheet(isPresented: $showUnsupportedList) {
            NavigationStack {
                UnsupportedElementsList(
                    elements: document.unsupportedElements,
                    pageCount: document.pages.count,
                    currentPage: $currentPage,
                    onSelect: { showUnsupportedList = false }
                )
                .navigationTitle("미지원 요소")
                .toolbar {
                    Button("닫기") { showUnsupportedList = false }
                }
            }
        }
        #endif
    }

    /// 고른 축의 사이드바. 호스트가 소유한 두 가지(`currentPage` 바인딩과
    /// 축소판 렌더러)를 여기 한 곳에서만 묶어 넘긴다 — 호출부(macOS 열·iOS
    /// 시트)마다 다시 적으면 그중 하나가 새 렌더러를 만들거나 다른 쪽 바인딩을
    /// 잡는 실수가 들어올 자리가 생긴다.
    private func sidebarContent(
        _ mode: SidebarMode,
        document: HwpDocument,
        onSelect: (() -> Void)? = nil
    ) -> DocumentSidebar {
        DocumentSidebar(
            mode: mode,
            document: document,
            currentPage: $currentPage,
            thumbnails: thumbnails,
            onSelect: onSelect
        )
    }

    /// 지금 화면에 낼 사이드바 (없으면 nil).
    private func visibleSidebar(for document: HwpDocument) -> SidebarMode? {
        guard sidebarVisible else { return nil }
        let mode = sidebarMode.resolved(for: document)
        // 배치가 끝나기 전의 빈 개요는 "개요가 없는 문서"가 아니라 "아직 안 온
        // 문서"다 — 빈 목록을 내느니 열 자체를 접는다 (종전 동작과 같다).
        if mode == .outline, document.metadata.outline.isEmpty {
            return nil
        }
        return mode
    }

    /// 사이드바(macOS) + 문서 뷰.
    private func documentArea(document: HwpDocument) -> some View {
        HStack(spacing: 0) {
            #if os(macOS)
                if let mode = visibleSidebar(for: document) {
                    sidebarContent(mode, document: document)
                        .frame(width: 260)
                    Divider()
                }
            #endif

            HwpDocumentView(
                document: document,
                zoomScale: $zoomScale,
                fitZoom: $fitZoom,
                currentPage: $currentPage,
                searchController: search,
                onHyperlinkTapped: { url in
                    openHyperlink(url)
                }
            )

            #if os(macOS)
                // 개요·축소판(왼쪽 열)과 달리 **오른쪽** 열이다 — 왼쪽은 탐색,
                // 오른쪽은 진단이라는 구분이다. iOS는 사이드바와 같은 이유로
                // 시트다 (`loadedView`).
                if showUnsupportedList, !document.unsupportedElements.isEmpty {
                    Divider()
                    UnsupportedElementsList(
                        elements: document.unsupportedElements,
                        pageCount: document.pages.count,
                        currentPage: $currentPage
                    )
                    .frame(width: 260)
                }
            #endif
        }
    }

    /// 허용 scheme 화이트리스트 (#126). 콜백 값은 `URL`이 아니라 `String`이고,
    /// HWP 하이퍼링크에는 웹 URL 외에 문서 내부 앵커·로컬 파일 경로도 온다 —
    /// 그런 값은 열지 않는다. 특히 `file:`을 목록에 넣으면 문서가 임의 로컬
    /// 파일을 여는 통로가 되므로 넣지 말 것.
    private static let allowedHyperlinkSchemes: Set<String> = ["http", "https", "mailto"]

    /// 하이퍼링크 탭 → scheme 검증 후 `openURL` (#126). URL은 필드 명령의
    /// 트레일링 플래그를 뗀 값으로 이미 정규화되어 오므로, 앱이 할 일은
    /// `URL(string:)` 변환과 scheme 검증뿐이다.
    private func openHyperlink(_ raw: String) {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              Self.allowedHyperlinkSchemes.contains(scheme)
        else { return }
        openURL(url)
    }

    /// 창·scene이 사라질 때 진행 중인 내보내기·드롭·축소판 작업을 끊고 산출물을
    /// 치운다. `Task {}`는 비구조적이라 뷰 수명에 묶이지 않는다 — 그대로 두면
    /// 뷰가 없는 채로 렌더가 이어지고, 성공하면 그 PDF를 지워 줄 주체가 아무도
    /// 없다. (내보내기 자체의 설계 근거는 `ContentView+PDFExport`의 `exportPDF`.)
    private func cancelExportOnTeardown() {
        exportTask?.cancel()
        exportTask = nil
        // 받아 줄 뷰가 없는 드롭 전송도 끊는다 — 창이 닫혀도 iCloud 적재가
        // 네트워크·디스크를 계속 쓰지 않게 (#126). 세대를 먼저 올리는 것은
        // 취소가 물리지 못하는 **이미 큐잉된 완료** 때문이다: teardown과 완료
        // 배달이 같은 메인 액터라 여기서 올리면 그 완료는 반드시 스테일 가드에
        // 걸리고, 소유 사본 정리까지 기존 경로가 한다.
        openGeneration += 1
        dropRequest?.cancel()
        dropRequest = nil
        // 창이 사라지면 축소판 디코드도 놓는다 — 그러지 않으면 옛 문서의
        // store/cache를 붙든 태스크가 남는다 (PDF 내보내기와 같은 이유).
        thumbnails.cancelOutstanding()
        // 넘긴 뒤라면 지우지 않는다. 그 완료 콜백이 scene 파괴로 오지 않으면
        // 파일이 남지만, 그건 다음 실행의 `removeStaleExports`가 거둔다 —
        // 확정된 인쇄를 깨는 것보다 잠시 남는 편이 낫다.
        guard !exportedPDFIsHandedOff else { return }
        discardExportedPDF()
    }
}

#Preview {
    ContentView()
}
