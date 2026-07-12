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
    @State private var currentPage: Int = 1
    @State private var zoomScale: CGFloat = 1.0

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
                UTType(filenameExtension: "hwp") ?? .data,
                .data,
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
            HwpDocumentToolbar {
                Button("Re-open") { showPicker = true }
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

                Spacer()

                HwpZoomControls(zoomScale: $zoomScale)
            }

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

    private func loadDocument(from url: URL) {
        errorMessage = nil
        document = nil
        isLoading = true
        loadProgress = nil
        loadGeneration += 1
        let generation = loadGeneration
        let didStart = url.startAccessingSecurityScopedResource()
        Task {
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
