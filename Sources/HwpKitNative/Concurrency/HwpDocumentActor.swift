@preconcurrency import CoreHwp
import Foundation
import HwpKitCore

public actor HwpDocumentActor {
    private var paginator: HwpPaginator?
    private let fontResolver: HwpFontResolver
    private let cache: HwpImageCache
    private var loadTask: Task<HwpDocument, Error>?

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
        cache = HwpImageCache()
    }

    public func loadDocument(from url: URL) async throws -> HwpDocument {
        loadTask?.cancel()
        let task = Task<HwpDocument, Error> {
            let file = try await Task.detached(priority: .userInitiated) {
                // 뷰어는 원본 rawPayload 보존이 필요 없다 — 압축 해제 버퍼 즉시 해제
                try CoreHwp.HwpFile(fromPath: url.path, options: .viewer)
            }.value
            return try await self.buildDocument(from: file)
        }
        loadTask = task
        return try await task.value
    }

    public func loadDocument(from data: Data) async throws -> HwpDocument {
        loadTask?.cancel()
        let task = Task<HwpDocument, Error> {
            let file = try await Task.detached(priority: .userInitiated) {
                // 뷰어는 원본 rawPayload 보존이 필요 없다 — 압축 해제 버퍼 즉시 해제
                try CoreHwp.HwpFile(fromData: data, options: .viewer)
            }.value
            return try await self.buildDocument(from: file)
        }
        loadTask = task
        return try await task.value
    }

    public func loadDocument(from file: CoreHwp.HwpFile) async throws -> HwpDocument {
        try await buildDocument(from: file)
    }

    private func buildDocument(from file: CoreHwp.HwpFile) async throws -> HwpDocument {
        let index = HwpIndex(from: file)
        let imageStore = HwpImageStore(from: file)
        let paginator = HwpPaginator(
            // ViewText (변경 추적 표시본)가 있으면 한글.app처럼 그걸 그린다
            sections: file.displaySectionArray,
            index: index,
            fontResolver: fontResolver,
            imageStore: imageStore
        )
        self.paginator = paginator

        var pages: [HwpPage] = []
        var pageIndex = 0
        while let page = try await paginator.page(at: pageIndex) {
            try Task.checkCancellation()
            pages.append(page)
            pageIndex += 1
        }

        let previewText = file.previewText.text
        let metadata = HwpDocumentMetadata(
            title: nil,
            pageCount: pages.count,
            previewText: previewText.isEmpty ? nil : String(previewText.prefix(500))
        )
        let unsupported = await paginator.unsupportedElements()
        return HwpDocument(
            pages: pages,
            metadata: metadata,
            unsupportedElements: unsupported,
            imageStore: imageStore
        )
    }

    public func page(at index: Int) async throws -> HwpPage? {
        try await paginator?.page(at: index)
    }

    public func totalPages() async -> Int {
        await paginator?.totalPages() ?? 0
    }

    public func imageCache() async -> HwpImageCache {
        cache
    }

    public func cancelLoad() async {
        loadTask?.cancel()
        loadTask = nil
    }
}
