import Combine
import HwpKit
import HwpKitCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var document: HwpDocument?
    @State private var errorMessage: String?
    @State private var showPicker = false
    @State private var isLoading = false
    /// 프로그레시브 로딩 진행률 (완료되면 nil)
    @State private var loadProgress: Double?
    @State private var loadGeneration = 0
    /// 열기 요청 세대 (#126) — 드롭 provider 적재가 비동기라, 느린 항목의 완료가
    /// 그 사이 시작된 다른 열기를 덮는 것을 막는다. `loadGeneration`으로는 못
    /// 막는다: 그것은 `loadDocument` 안에서만 올라서, 낡은 드롭 완료가 스스로
    /// 세대를 올리며 새 문서를 밀어낸다.
    @State private var openGeneration = 0
    /// 진행 중 로드 task — 새 로드 시작 시 이전 것을 취소한다 (#6)
    @State private var loadTask: Task<Void, Never>?
    @State private var currentPage: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    /// 배율 맞춤 **원샷 명령** — 툴바가 값을 넣으면 문서 뷰가 한 번 적용하고
    /// nil로 되돌린다. 뷰포트를 아는 것은 뷰뿐이라 배율 계산은 그쪽 몫이고,
    /// 호스트는 같은 바인딩을 뷰와 툴바에 함께 넘기기만 한다.
    @State private var fitZoom: HwpZoomFit?
    // 사이드바 상태는 **직교하는 두 값**이다 (#77 개요·책갈피 → #76에서 축소판
    // 축 추가): 어느 축을 고르고 있는가(`sidebarMode`)와 지금 보이는가
    // (`sidebarVisible`). 축마다 불리언을 두면 "둘 다 켜짐"이라는 없는 상태가
    // 생기지만, 이 둘은 조합이 전부 유효하다. 하나로 접어 `SidebarMode?`를 쓰면
    // **감출 때 고른 축이 사라져** 다시 열 때 다른 축이 되는 문제가 있다.
    @State private var sidebarMode: SidebarMode = .outline
    // **기본값이 플랫폼마다 다르다**: macOS는 인라인 열이라 켜 두고, iOS는
    // 시트라 꺼 둔다 (켜 두면 문서를 열자마자 모달이 뜬다).
    #if os(macOS)
        @State private var sidebarVisible = true
    #else
        @State private var sidebarVisible = false
    #endif
    /// 축소판 렌더러는 **호스트가** 소유한다 — 사이드바 뷰가 소유하면 모드를
    /// 토글하거나 iPhone 시트를 닫을 때마다 뷰가 사라지면서 그때까지 그린
    /// 축소판을 통째로 버린다.
    @State private var thumbnails = HwpPageThumbnails()
    /// 문서 검색 세션 (#75). 호스트가 소유해 뷰와 검색 바에 **같은 인스턴스**를
    /// 넘긴다 — 라이브러리가 하이라이트·매치 노출 스크롤을 알아서 배선한다.
    @State private var search = HwpSearchController()
    /// Cmd+F가 검색 필드로 포커스를 옮기는 훅. 라이브러리는 전역 단축키를
    /// 소유하지 않으므로 호스트가 잡아서 넘긴다.
    @FocusState private var searchFieldFocused: Bool
    /// PDF 내보내기 진행률 (진행 중일 때만 non-nil — 시트 표시 조건을 겸한다)
    @State private var exportProgress: Double?
    @State private var exportTask: Task<Void, Never>?
    /// 내보내기가 끝난 임시 PDF — 저장 패널/인쇄가 이 파일을 가리킨다
    @State private var exportedPDF: URL?
    /// 그 파일을 목적지 UI(저장 패널·인쇄)에 이미 넘겼는지. 넘긴 뒤에는 그쪽이
    /// 다 쓸 때까지 살려 둬야 한다 — 창이 닫힐 때 지우면 사용자가 확정한
    /// 인쇄·저장이 깨진다 (`UIPrintInteractionController`는 스풀링 동안,
    /// `fileExporter`는 완료 핸들러까지 이 파일을 읽는다).
    @State private var exportedPDFIsHandedOff = false
    /// 사용자에게 보일 이름 (저장 패널 기본 파일명·인쇄 작업명). 임시 파일명은
    /// UUID라 그대로 쓸 수 없다
    @State private var exportedName = "document"
    /// 진행 시트가 닫힌 **뒤에** 할 일 — 두 모달을 같은 갱신 주기에 겹치면
    /// 두 번째 표시가 유실된다 (닫는 중인 시트 위로 띄우는 꼴).
    @State private var pendingDestination: PDFDestination?
    /// 진행 시트가 닫힌 **뒤에** 띄울 실패 사유 (같은 이유로 미룬다)
    @State private var pendingError: String?
    #if !os(macOS)
        @State private var printAnchor = HwpPrintAnchor.Box()
    #endif
    /// 진행 시트가 실제로 표시됐는지. 표시된 적이 없으면 `onDismiss`가 오지
    /// 않아 저장·인쇄·오류가 `pending*`에 갇힌다 — 작은 문서는 시트가 뜨기 전에
    /// 끝나서 `0 → nil` 전이가 한 갱신 주기로 합쳐질 수 있다.
    @State private var exportSheetDidPresent = false
    @State private var showSavePanel = false
    /// 내보내기·인쇄 실패 사유 (빈 화면의 errorMessage와 별개 — 문서를 보는
    /// 중에는 그쪽이 화면에 없다)
    @State private var exportError: String?
    /// 최근 문서 목록 (#126) — 진실 원본은 `RecentDocumentsStore`(defaults)이고
    /// 이 상태는 그 거울이다. 기록·제거 helper가 돌려주는 목록으로 맞춘다.
    @State private var recents = RecentDocumentsStore.load()
    /// 드래그가 창 위에 있는 동안 true — 드롭 가능 시각 피드백 (#126).
    @State private var isDropTargeted = false
    /// 미지원 요소 목록 표시 여부 — macOS는 인라인 열, iOS는 시트 (#126).
    /// 요소 자체는 상태로 들지 않고 `document.unsupportedElements`(공개 배열,
    /// 최종 스냅샷에만 실림)를 그대로 읽는다 — `onUnsupportedElement` 콜백은
    /// 배열 전체를 매번 재방출해 "재방출 중복"과 "같은 쪽의 동종 요소"(값이
    /// 완전히 같다)를 구분할 수 없어, 콜백 집계는 append든 `Set`이든 어느
    /// 쪽으로도 개수가 틀린다 (전자는 과다, 후자는 과소).
    @State private var showUnsupportedList = false
    /// 하이퍼링크를 시스템 브라우저로 여는 통로. 라이브러리는 콜백만 내고
    /// 여는 것은 앱 책임이다 (`Sources/HwpKit/AGENTS.md`).
    @Environment(\.openURL) private var openURL

    /// 내보내기를 마친 뒤 할 일 — 저장 대화상자냐 인쇄냐.
    private enum PDFDestination {
        case save
        case print
    }

    /// 사이드바가 보이는 내용. `Identifiable`인 것은 iOS `.sheet(item:)`이
    /// 요구해서다 (표시 여부와 내용이 한 값이라 둘이 어긋날 수 없다).
    private enum SidebarMode: Identifiable {
        case outline
        case thumbnails

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .outline: "개요"
            case .thumbnails: "축소판"
            }
        }

        var systemImage: String {
            switch self {
            case .outline: "list.bullet.indent"
            case .thumbnails: "square.grid.2x2"
            }
        }
    }

    private static let exportFilePrefix = "hwp-sample-export-"
    /// 이 프로세스가 시작된 시각 — 이보다 오래된 임시 파일(내보내기 PDF·드롭
    /// 사본)만 이전 실행의 잔해다.
    private static let processStart = Date()

    var body: some View {
        Group {
            if let document {
                loadedView(document: document)
            } else if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
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
                let candidate = docs.appendingPathComponent("document.hwp")
                if FileManager.default.fileExists(atPath: candidate.path), document == nil {
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

    /// 이 문서에서 **실제로 그려질 축** (표시 여부와 무관).
    ///
    /// 개요를 골랐는데 그 문서에 개요가 없으면 축소판으로 대신한다 — 개요가 없는
    /// 문서에서 사이드바가 통째로 사라지던 것이 이 축을 추가한 이유다 (#76).
    /// 대체는 **그리기에서만** 일어나고 `sidebarMode`를 덮어쓰지 않으므로, 개요가
    /// 있는 문서를 다음에 열면 다시 개요가 나온다.
    ///
    /// `isComplete`를 함께 보는 것이 중요하다. 개요는 프로그레시브라 1쪽에 제목이
    /// 없는 문서(표지·서식)는 **첫 스냅샷에서 빈 목록**으로 오는데, 그때 대체하면
    /// 축소판 그리드가 마운트돼 쪽을 그리기 시작했다가 다음 스냅샷에서 헐린다
    /// (그 작업은 세대 가드에 막혀 캐시되지도 않는다).
    private func resolvedSidebarMode(for document: HwpDocument) -> SidebarMode {
        guard sidebarMode == .outline,
              document.metadata.isComplete,
              document.metadata.outline.isEmpty
        else { return sidebarMode }
        return .thumbnails
    }

    /// 지금 화면에 낼 사이드바 (없으면 nil).
    private func visibleSidebar(for document: HwpDocument) -> SidebarMode? {
        guard sidebarVisible else { return nil }
        let mode = resolvedSidebarMode(for: document)
        // 배치가 끝나기 전의 빈 개요는 "개요가 없는 문서"가 아니라 "아직 안 온
        // 문서"다 — 빈 목록을 내느니 열 자체를 접는다 (종전 동작과 같다).
        if mode == .outline, document.metadata.outline.isEmpty {
            return nil
        }
        return mode
    }

    @ViewBuilder
    private func sidebarContent(
        _ mode: SidebarMode,
        document: HwpDocument,
        onSelect: (() -> Void)? = nil
    ) -> some View {
        switch mode {
        case .outline:
            OutlineSidebar(
                outline: document.metadata.outline,
                currentPage: $currentPage,
                onSelect: onSelect
            )
        case .thumbnails:
            ThumbnailSidebar(
                document: document,
                currentPage: $currentPage,
                thumbnails: thumbnails,
                onSelect: onSelect
            )
        }
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

    private func toolbar(document: HwpDocument) -> some View {
        HwpDocumentToolbar {
            Button {
                showPicker = true
            } label: {
                toolbarLabel("Re-open", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            // 목록이 비어 있으면 누를 것이 없으므로 버튼 자체를 내지 않는다.
            // 축소판 버튼에는 그런 조건이 없다 — 쪽은 언제나 있다.
            if !document.metadata.outline.isEmpty {
                sidebarButton(.outline, document: document)
                    .help("개요·책갈피 \(document.metadata.outline.count)개")
            }
            sidebarButton(.thumbnails, document: document)
                .help("쪽 축소판 \(document.pages.count)개")

            Divider().frame(height: 20)

            HwpPageNavigator(
                currentPage: $currentPage,
                totalPages: max(document.pages.count, 1)
            )

            if let loadProgress {
                ProgressView(value: loadProgress)
                    .frame(width: 120)
                    .help("페이지 배치 중… \(Int(loadProgress * 100))%")
            }

            Divider().frame(height: 20)

            // 배치가 끝나기 전 문서는 페이지가 모자란 채로 내보내진다
            Button {
                exportPDF(document: document, then: .save)
            } label: {
                toolbarLabel("PDF로 내보내기", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .disabled(loadProgress != nil || exportProgress != nil)

            Button {
                exportPDF(document: document, then: .print)
            } label: {
                toolbarLabel("인쇄", systemImage: "printer")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(loadProgress != nil || exportProgress != nil)

            #if !os(macOS)
                // iPad 팝오버 앵커 — 이 자리에 있어야 인쇄를 누른 창에 뜬다.
                HwpPrintAnchor(box: printAnchor)
                    .frame(width: 1, height: 1)
            #endif

            // Cmd+F는 **호스트가** 소유한다 — 라이브러리(`HwpSearchBar`)는
            // 전역 단축키를 선점하지 않고 포커스 훅만 받는다. Cmd+O·Cmd+P와
            // 같은 관례다. 툴바가 `loadedView` 안에만 있으므로 이 단축키도
            // 문서가 열려 있는 동안에만 산다 (인쇄와 같은 성질).
            Button {
                searchFieldFocused = true
            } label: {
                toolbarLabel("찾기", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: [.command])

            Spacer()

            HwpZoomControls(zoomScale: $zoomScale, fitZoom: $fitZoom)
        }
    }

    /// 사이드바 모드 토글. 이미 그 모드가 보이는 중이면 눌러서 감춘다.
    ///
    /// 활성 표시는 **실제로 그려질** 축을 따른다: 개요가 없는 문서에서 `.outline`
    /// 선택이 축소판으로 대체되면 그 사실이 버튼에 보여야 한다. 그리고 그 버튼을
    /// 눌러 여닫아도 `sidebarMode`는 건드리지 않는다 — 대체된 축을 그대로 써
    /// 넣으면 한 번의 감췄다 열기로 사용자의 개요 선택이 조용히 사라진다.
    @ViewBuilder
    private func sidebarButton(_ mode: SidebarMode, document: HwpDocument) -> some View {
        let draws = resolvedSidebarMode(for: document) == mode
        let isActive = sidebarVisible && draws
        Button {
            if isActive {
                sidebarVisible = false
            } else if draws {
                sidebarVisible = true
            } else {
                sidebarMode = mode
                sidebarVisible = true
            }
        } label: {
            toolbarLabel(mode.title, systemImage: mode.systemImage)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? Color.accentColor : nil)
    }

    /// 좁은 화면(iPhone)에서는 아이콘만 쓴다 — 툴바는 그냥 `HStack`이라 한 줄에
    /// 안 들어가면 SwiftUI가 **글자 단위로** 줄바꿈해 버튼이 세로로 늘어난다
    /// (시뮬레이터 실측). macOS는 폭이 남으므로 글자를 그대로 보인다.
    @ViewBuilder
    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        #if os(macOS)
            Text(title)
        #else
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        #endif
    }

    private var exportProgressSheet: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportProgress ?? 0) {
                Text("PDF 만드는 중…")
            }
            .frame(width: 220)
            Button("취소") { exportTask?.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .onAppear { exportSheetDidPresent = true }
    }

    /// 진행 표시를 끝낸다. 시트가 떠 있었으면 `onDismiss`가 뒤를 잇고, 뜬 적이
    /// **없으면** 그 콜백이 영영 오지 않으므로 직접 이어 간다. 다음 주기로
    /// 넘기는 것은 "모달을 같은 갱신 주기에 겹치지 않는다"는 이 파일의 규약을
    /// 시트가 없었을 때도 지키기 위해서다.
    private func finishExportProgress() {
        let wasPresented = exportSheetDidPresent
        exportSheetDidPresent = false
        exportProgress = nil
        guard !wasPresented else { return }
        Task { @MainActor in presentPendingDestination() }
    }

    /// 스크롤로 감싸는 이유: 최근 문서가 10개까지 쌓이면 내용이 낮은 뷰포트
    /// (iPhone 가로 모드)를 넘는데, 스크롤이 없으면 넘친 행을 눌러서 열 방법이
    /// 없다. 내용이 짧을 때는 `minHeight`가 뷰포트를 채워 종전처럼 중앙 정렬된다.
    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Open a .hwp file to preview")
                        .foregroundStyle(.secondary)
                    Button("Open .hwp") { showPicker = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Text("또는 .hwp 파일을 여기로 끌어다 놓기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if !recents.isEmpty {
                        recentDocumentsList
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    /// 빈 상태 아래에 붙는 최근 문서 목록 (#126). 픽스처가 전부 `document.hwp`라
    /// 이름만으로는 구별되지 않아 폴더를 보조 행으로 함께 보인다.
    private var recentDocumentsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 문서")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(recents) { item in
                Button {
                    openRecent(item)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.folderDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("목록에서 제거", role: .destructive) {
                        recents = RecentDocumentsStore.remove(item)
                    }
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// 드롭된 provider에서 URL을 뽑아 연다 (#126). 확장자 검증 실패 등의
    /// 사유는 `errorMessage`로 올린다 — 문서를 보는 중에는 그 라벨이 화면에
    /// 없지만, 그때는 열려 있는 문서가 그대로라 조용히 무시되는 것이 맞다.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // 세대를 **먼저** 올려 두는 것은 완료가 동기로 오는 경우까지 덮기
        // 위해서다. 드롭이 거절되면(후보 없음) 완료는 오지 않으므로 되돌린다 —
        // 안 되돌리면 폴더처럼 열 수 없는 것을 떨어뜨린 것만으로 진행 중이던
        // 드롭이 취소된다.
        let previous = openGeneration
        openGeneration += 1
        let generation = openGeneration
        let accepted = DropOpenSupport.open(providers: providers) { result in
            // 이 요청이 시작된 뒤 다른 열기가 있었으면 결과를 버린다 — 성공만이
            // 아니라 실패도 버려야 낡은 사유가 새 문서 위에 오류로 남지 않는다.
            guard generation == openGeneration else { return }
            switch result {
            case let .success(url):
                loadDocument(from: url)
            case let .failure(failure):
                errorMessage = failure.message
            }
        }
        if !accepted {
            openGeneration = previous
        }
        return accepted
    }

    /// 최근 항목을 연다. 열 수 없는 항목은 그 자리에서 거둔다 — 눌러도 아무 일이
    /// 없는 시체 행을 남기지 않는다.
    private func openRecent(_ item: RecentDocument) {
        switch RecentDocumentsStore.resolve(item) {
        case let .resolved(url):
            loadDocument(from: url)
        case .inaccessible:
            recents = RecentDocumentsStore.remove(item)
            errorMessage = "\(item.name)을(를) 열 권한이 없어 목록에서 제거했습니다. 다시 선택해 주세요."
        case .unavailable:
            recents = RecentDocumentsStore.remove(item)
            errorMessage = "\(item.name)을(를) 찾을 수 없어 최근 문서에서 제거했습니다."
        }
    }

    /// 문서를 앱 임시 디렉터리에 PDF로 만든 뒤 저장 대화상자 또는 인쇄로 넘긴다.
    ///
    /// 먼저 컨테이너 안에 쓰고 나중에 `fileExporter`로 내보내는 순서인 이유:
    /// 진행률·취소를 우리가 통제해야 하고 (1,030쪽이면 수 초가 걸린다),
    /// 사용자가 고른 위치에 직접 쓰면 취소 시 부분 파일을 그 자리에 남긴다.
    /// 창·scene이 사라질 때 진행 중인 내보내기를 끊고 산출물을 치운다.
    /// `Task {}`는 비구조적이라 뷰 수명에 묶이지 않는다 — 그대로 두면 뷰가 없는
    /// 채로 렌더가 이어지고, 성공하면 그 PDF를 지워 줄 주체가 아무도 없다.
    private func cancelExportOnTeardown() {
        exportTask?.cancel()
        exportTask = nil
        // 창이 사라지면 축소판 디코드도 놓는다 — 그러지 않으면 옛 문서의
        // store/cache를 붙든 태스크가 남는다 (PDF 내보내기와 같은 이유).
        thumbnails.cancelOutstanding()
        // 넘긴 뒤라면 지우지 않는다. 그 완료 콜백이 scene 파괴로 오지 않으면
        // 파일이 남지만, 그건 다음 실행의 `removeStaleExports`가 거둔다 —
        // 확정된 인쇄를 깨는 것보다 잠시 남는 편이 낫다.
        guard !exportedPDFIsHandedOff else { return }
        discardExportedPDF()
    }

    /// 임시 PDF를 지우고 참조를 놓는다. 이 앱은 내보낼 때마다 새 UUID 파일을
    /// 만들므로, 지우지 않으면 1,030쪽짜리가 세션 내내 쌓인다.
    private func discardExportedPDF() {
        if let exportedPDF {
            try? FileManager.default.removeItem(at: exportedPDF)
        }
        exportedPDF = nil
        exportedPDFIsHandedOff = false
    }

    /// 이전 실행이 남긴 임시 PDF를 거둔다. 목적지 UI에 넘긴 파일은 그 완료
    /// 콜백이 지우지만 scene이 파괴되면 그 콜백이 오지 않으므로, 그 잔해까지
    /// 거둬야 "넘긴 파일은 지우지 않는다"가 누수로 퇴화하지 않는다.
    ///
    /// **이번 실행에서 만든 것은 건드리지 않는다**: `WindowGroup`은 창마다 이
    /// 뷰를 만들어서, 전부 지우면 나중에 연 창이 먼저 창의 내보내기를 깬다.
    private static func removeStaleExports() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries
            where entry.lastPathComponent.hasPrefix(Self.exportFilePrefix)
        {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let modified, modified < Self.processStart else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    private func exportPDF(document: HwpDocument, then destination: PDFDestination) {
        exportTask?.cancel()
        discardExportedPDF()
        exportError = nil
        exportProgress = 0
        exportedName = Self.exportFileName(for: document)
        // 파일명은 UUID로 짓는다. 제목에서 뽑으면 `WindowGroup`의 두 창이 같은
        // 경로를 써, 한쪽 저장 패널이 열려 있는 사이 다른 쪽 내보내기가 그 파일을
        // 갈아 치운다 (다른 문서가 저장된다). 긴 제목의 파일명 한도(255바이트)
        // 문제도 함께 사라진다.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.exportFilePrefix)\(UUID().uuidString).pdf")
        exportTask = Task {
            do {
                try await HwpPDFExporter().export(document: document, to: url) { progress in
                    Task { @MainActor in
                        // 진행 중일 때만 갱신 — 취소 후 늦게 도착한 보고가 시트를
                        // 되살리지 않게 한다.
                        if exportProgress != nil {
                            exportProgress = progress.fractionCompleted
                        }
                    }
                }
                // 취소된 뒤에 끝난 결과는 주인이 없다 — 뷰가 사라졌으면 저장·인쇄
                // 콜백도, 다음 내보내기도 이 파일을 지워 주지 않는다. 렌더러의
                // 마지막 취소 확인은 파일을 옮기기 **전**이라 이 창이 남는다.
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                await MainActor.run {
                    exportedPDF = url
                    // 시트를 닫고, 저장 패널·인쇄는 그 뒤가 이어받는다 (시트가
                    // 떴으면 onDismiss가, 뜬 적이 없으면 finishExportProgress가).
                    pendingDestination = destination
                    finishExportProgress()
                }
            } catch HwpPDFExportError.cancelled {
                await MainActor.run { finishExportProgress() }
            } catch {
                await MainActor.run {
                    // 시트를 닫는 것과 알림을 띄우는 것을 같은 갱신 주기에 겹치면
                    // 두 번째가 유실된다 — 저장·인쇄와 같이 onDismiss로 미룬다.
                    pendingError = error.localizedDescription
                    finishExportProgress()
                }
            }
        }
    }

    /// 진행 시트가 완전히 닫힌 뒤 저장 패널·인쇄를 띄운다. 취소로 닫힌
    /// 경우에는 `pendingDestination`이 비어 있어 아무 일도 하지 않는다.
    private func presentPendingDestination() {
        if let failure = pendingError {
            pendingError = nil
            exportError = failure
            return
        }
        guard let destination = pendingDestination, let url = exportedPDF else { return }
        pendingDestination = nil
        // 이 시점부터 파일 소유권은 목적지 UI에 있다 — 창이 닫혀도 그쪽이 다
        // 쓸 때까지 남긴다. 표시가 곧바로 실패하면 아래에서 되돌린다.
        exportedPDFIsHandedOff = true
        switch destination {
        case .save:
            showSavePanel = true
        case .print:
            let cleanup: @Sendable (String?) -> Void = { reason in
                Task { @MainActor in
                    discardExportedPDF()
                    // 인쇄 UI가 닫힌 뒤라 진행 시트와 겹치지 않는다 (모달을 같은
                    // 갱신 주기에 겹치면 알림이 유실된다는 이 파일의 규약).
                    if let reason {
                        exportError = reason
                    }
                }
            }
            #if os(macOS)
                let failure = HwpSamplePrinter.print(
                    pdfAt: url, jobName: exportedName, onFinish: cleanup
                )
            #else
                let failure = HwpSamplePrinter.print(
                    pdfAt: url, jobName: exportedName, anchor: printAnchor.view, onFinish: cleanup
                )
            #endif
            if let failure {
                exportError = failure
                discardExportedPDF()
            }
        }
    }

    /// 문서 제목을 파일 이름으로 쓰되 경로 구분자는 지운다.
    private static func exportFileName(for document: HwpDocument) -> String {
        let title = document.metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? ""
        let clipped = Self.clippedToFilenameLimit(title)
        return clipped.isEmpty ? "document" : clipped
    }

    /// 파일명 성분 한도(255바이트)에서 확장자 몫을 빼고 **UTF-8 바이트로** 자른다.
    /// 문자 수로 자르면 한도를 못 지킨다 — 결합 이모지 하나가 25바이트라 80자가
    /// 2,000바이트다. 자르는 단위는 Character라 자소가 쪼개지지 않는다.
    private static func clippedToFilenameLimit(_ title: String) -> String {
        let limit = 255 - ".pdf".utf8.count
        var clipped = ""
        var bytes = 0
        for character in title {
            let size = String(character).utf8.count
            guard bytes + size <= limit else { break }
            clipped.append(character)
            bytes += size
        }
        return clipped
    }

    private func loadDocument(from url: URL) {
        // 이전 로드를 취소해 겹치는 파싱·첫 페이지 레이아웃이 동시에 자원을
        // 소모하지 않게 한다 (#6). 스트림 취소는 actor의 파싱까지 전파된다.
        loadTask?.cancel()
        errorMessage = nil
        document = nil
        // 요소 목록의 내용은 문서 교체가 알아서 갈지만, 표시 여부는 상태라
        // 직접 접는다 — 새 문서를 열자마자 옛 문서의 진단 열이 떠 있지 않게 (#126).
        showUnsupportedList = false
        // 새 로드가 첫 스냅샷을 내기 전에 실패하면 이 렌더러를 갱신할 주체가 없어
        // 옛 문서(쪽·공급자·디코드 이미지·축소판)가 오류 화면 내내 상주한다.
        // `cancelOutstanding()`은 요청만 끊고 보유는 유지하므로 폐기는 교체로 한다.
        thumbnails.update(document: .empty)
        isLoading = true
        #if !os(macOS)
            // 시트는 사용자가 열 때만 뜬다 — 새 문서를 열면 닫힌 상태로 돌아간다.
            sidebarVisible = false
        #endif
        loadProgress = nil
        loadGeneration += 1
        // 어느 경로로 열든 대기 중인 드롭 완료를 무효화한다 — fileImporter·최근
        // 문서로 새 문서를 연 뒤 느린 드롭이 도착해 그것을 덮지 않게 (#126).
        openGeneration += 1
        let generation = loadGeneration
        let didStart = url.startAccessingSecurityScopedResource()
        loadTask = Task {
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            var didRecordRecent = false
            do {
                // 프로그레시브 로딩: 첫 페이지 확정 즉시 표시, 잔여 페이지는
                // 배치 스냅샷으로 이어 붙는다 (뷰가 loadToken으로 증분 적용).
                let loader = HwpDocumentLoader()
                for try await snapshot in await loader.loadUpdates(from: url) {
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard generation == loadGeneration else { return }
                        if document == nil {
                            currentPage = 1
                            zoomScale = 1.0
                            // 옛 문서를 향한 맞춤 요청이 새 문서에 적용되지 않게
                            // 함께 비운다 (뷰는 문서 세대로 한 번 더 거른다).
                            fitZoom = nil
                        }
                        document = snapshot.document
                        // 스냅샷마다 넘겨도 프로그레시브 증분이면 라이브러리가
                        // 알아보고 이미 그린 축소판을 유지한다 (같은 loadToken +
                        // 쪽 수 비감소). 사이드바가 닫혀 있어도 갱신해 둬야
                        // 나중에 여는 순간 최신 쪽 수로 열린다.
                        thumbnails.update(document: snapshot.document)
                        loadProgress = snapshot.isComplete ? nil : snapshot.progress
                        isLoading = false
                    }
                    // 첫 스냅샷이 나온 **뒤** 한 번만 기록한다 (#126) — 파싱에
                    // 실패하는 파일은 목록에 들어가지 않고, 보안 범위 접근이
                    // 살아 있는 이 task가 북마크를 만들 수 있는 유일한 시점이다.
                    if !didRecordRecent {
                        didRecordRecent = true
                        if let updated = RecentDocumentsStore.record(url: url) {
                            await MainActor.run { recents = updated }
                        }
                    }
                    if generation != loadGeneration {
                        break
                    }
                }
            } catch is CancellationError {
                // 취소된 로드는 조용히 종료 (새 로드가 UI를 갱신한다)
            } catch {
                await MainActor.run {
                    guard generation == loadGeneration else { return }
                    errorMessage = "\(error)"
                    isLoading = false
                    loadProgress = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
