import SwiftUI
import UniformTypeIdentifiers
import HwpKit
import HwpKitCore

struct ContentView: View {
    @State private var document: HwpDocument?
    @State private var errorMessage: String?
    @State private var showPicker = false
    @State private var isLoading = false
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
                .data
            ]
        ) { result in
            switch result {
            case .success(let url):
                loadDocument(from: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
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
        isLoading = true
        let didStart = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let loaded = try await HwpDocumentLoader().load(from: url)
                await MainActor.run {
                    document = loaded
                    currentPage = 1
                    zoomScale = 1.0
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "\(error)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
