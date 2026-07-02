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
            let index = HwpIndex(from: file)
            self.paginator = HwpPaginator(
                sections: file.sectionArray,
                index: index,
                fontResolver: self.fontResolver
            )
            return .empty
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
            let index = HwpIndex(from: file)
            self.paginator = HwpPaginator(
                sections: file.sectionArray,
                index: index,
                fontResolver: self.fontResolver
            )
            return .empty
        }
        loadTask = task
        return try await task.value
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
