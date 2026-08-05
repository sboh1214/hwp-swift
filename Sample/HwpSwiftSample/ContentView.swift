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
    /// 진행 중 로드 task — 새 로드 시작 시 이전 것을 취소한다 (#6)
    @State private var loadTask: Task<Void, Never>?
    @State private var currentPage: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    /// PDF 내보내기 진행률 (진행 중일 때만 non-nil — 시트 표시 조건을 겸한다)
    @State private var exportProgress: Double?
    @State private var exportTask: Task<Void, Never>?
    /// 내보내기가 끝난 임시 PDF — 저장 패널/인쇄가 이 파일을 가리킨다
    @State private var exportedPDF: URL?
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
    @State private var showSavePanel = false
    /// 내보내기·인쇄 실패 사유 (빈 화면의 errorMessage와 별개 — 문서를 보는
    /// 중에는 그쪽이 화면에 없다)
    @State private var exportError: String?

    /// 내보내기를 마친 뒤 할 일 — 저장 대화상자냐 인쇄냐.
    private enum PDFDestination {
        case save
        case print
    }

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
                UTType(importedAs: "dev.sboh.hwp"),
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
        .task {
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

            HwpDocumentView(
                document: document,
                zoomScale: $zoomScale,
                currentPage: $currentPage,
                onHyperlinkTapped: { url in
                    print("Hyperlink tapped: \(url)")
                },
                onUnsupportedElement: { element in
                    print("Unsupported: \(element)")
                }
            )
        }
    }

    private func toolbar(document: HwpDocument) -> some View {
        HwpDocumentToolbar {
            Button {
                showPicker = true
            } label: {
                toolbarLabel("Re-open", systemImage: "folder")
            }
            .buttonStyle(.bordered)

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

            Spacer()

            HwpZoomControls(zoomScale: $zoomScale)
        }
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
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Open a .hwp file to preview")
                .foregroundStyle(.secondary)
            Button("Open .hwp") { showPicker = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        discardExportedPDF()
    }

    /// 임시 PDF를 지우고 참조를 놓는다. 이 앱은 내보낼 때마다 새 UUID 파일을
    /// 만들므로, 지우지 않으면 1,030쪽짜리가 세션 내내 쌓인다.
    private func discardExportedPDF() {
        if let exportedPDF {
            try? FileManager.default.removeItem(at: exportedPDF)
        }
        exportedPDF = nil
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
            .appendingPathComponent("hwp-sample-export-\(UUID().uuidString).pdf")
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
                    // 시트를 닫고, 저장 패널·인쇄는 onDismiss가 이어받는다.
                    pendingDestination = destination
                    exportProgress = nil
                }
            } catch HwpPDFExportError.cancelled {
                await MainActor.run { exportProgress = nil }
            } catch {
                await MainActor.run {
                    // 시트를 닫는 것과 알림을 띄우는 것을 같은 갱신 주기에 겹치면
                    // 두 번째가 유실된다 — 저장·인쇄와 같이 onDismiss로 미룬다.
                    pendingError = error.localizedDescription
                    exportProgress = nil
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
        switch destination {
        case .save:
            showSavePanel = true
        case .print:
            let cleanup: @Sendable () -> Void = { Task { @MainActor in discardExportedPDF() } }
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
        isLoading = true
        loadProgress = nil
        loadGeneration += 1
        let generation = loadGeneration
        let didStart = url.startAccessingSecurityScopedResource()
        loadTask = Task {
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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
                        }
                        document = snapshot.document
                        loadProgress = snapshot.isComplete ? nil : snapshot.progress
                        isLoading = false
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
