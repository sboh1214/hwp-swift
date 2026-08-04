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
    /// 진행 시트가 닫힌 **뒤에** 할 일 — 두 모달을 같은 갱신 주기에 겹치면
    /// 두 번째 표시가 유실된다 (닫는 중인 시트 위로 띄우는 꼴).
    @State private var pendingDestination: PDFDestination?
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
            defaultFilename: exportedPDF?.deletingPathExtension().lastPathComponent
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
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
    private func exportPDF(document: HwpDocument, then destination: PDFDestination) {
        exportTask?.cancel()
        exportError = nil
        exportProgress = 0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.exportFileName(for: document)).pdf")
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
                    exportProgress = nil
                    exportError = error.localizedDescription
                }
            }
        }
    }

    /// 진행 시트가 완전히 닫힌 뒤 저장 패널·인쇄를 띄운다. 취소로 닫힌
    /// 경우에는 `pendingDestination`이 비어 있어 아무 일도 하지 않는다.
    private func presentPendingDestination() {
        guard let destination = pendingDestination, let url = exportedPDF else { return }
        pendingDestination = nil
        switch destination {
        case .save:
            showSavePanel = true
        case .print:
            exportError = HwpSamplePrinter.print(pdfAt: url)
        }
    }

    /// 문서 제목을 파일 이름으로 쓰되 경로 구분자는 지운다.
    private static func exportFileName(for document: HwpDocument) -> String {
        let title = document.metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? ""
        return title.isEmpty ? "document" : title
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
