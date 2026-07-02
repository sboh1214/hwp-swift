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
                try CoreHwp.HwpFile(fromPath: url.path)
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
                try CoreHwp.HwpFile(fromData: data)
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
        let paginator = HwpPaginator(
            sections: file.sectionArray,
            index: index,
            fontResolver: fontResolver
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
        return HwpDocument(
            pages: pages,
            metadata: metadata,
            unsupportedElements: []
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
