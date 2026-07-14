import CoreHwp
import Foundation
import HwpKitCore

/// 프로그레시브 로딩의 중간/최종 산출물. `document.pages`는 지금까지 확정된
/// 페이지 전량 (뷰는 값 교체로 소비 — metadata.loadToken으로 증분 판정).
public struct HwpDocumentSnapshot: Sendable {
    public let document: HwpDocument
    public let isComplete: Bool
    /// 전체 문단 대비 진행률 근사 (0...1). 완료 스냅샷은 1.
    public let progress: Double?

    public init(document: HwpDocument, isComplete: Bool, progress: Double?) {
        self.document = document
        self.isComplete = isComplete
        self.progress = progress
    }
}

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
            let file = try await Self.parse { try CoreHwp.HwpFile(fromPath: url.path, options: .viewer) }
            try Task.checkCancellation()
            return try await self.buildDocument(from: file)
        }
        loadTask = task
        // 호출자 취소를 비구조적 task로 전파해 파싱/페이지네이션을 실제로 멈춘다.
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func loadDocument(from data: Data) async throws -> HwpDocument {
        loadTask?.cancel()
        let task = Task<HwpDocument, Error> {
            let file = try await Self.parse { try CoreHwp.HwpFile(fromData: data, options: .viewer) }
            try Task.checkCancellation()
            return try await self.buildDocument(from: file)
        }
        loadTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 백그라운드 파싱을 취소 전파와 함께 실행한다 — 상위 로드가 취소되면
    /// detached 파서를 취소해, 아직 시작 안 한 파싱은 즉시 중단하고 결과를
    /// 버린다 (빠른 문서 교체 시 파싱 stacking 완화, #18). 이미 실행 중인
    /// 동기 파싱은 협조 지점이 없어 끝까지 가지만 결과는 폐기된다.
    private static func parse(
        _ work: @escaping @Sendable () throws -> CoreHwp.HwpFile
    ) async throws -> CoreHwp.HwpFile {
        let parseTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try work()
        }
        return try await withTaskCancellationHandler {
            try await parseTask.value
        } onCancel: {
            parseTask.cancel()
        }
    }

    public func loadDocument(from file: CoreHwp.HwpFile) async throws -> HwpDocument {
        // 다른 로드와 같은 loadTask 슬롯으로 추적한다 — 겹치는 로드가 서로
        // paginator/progress 상태를 덮어쓰지 않게 취소·추적한다 (#22).
        loadTask?.cancel()
        let task = Task<HwpDocument, Error> {
            try Task.checkCancellation()
            return try await self.buildDocument(from: file)
        }
        loadTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 프로그레시브 로딩 — 첫 `firstBatch`쪽 확정 즉시 1차 스냅샷을,
    /// 이후 `batchSize`쪽마다 중간 스냅샷을, 완료 시 최종 스냅샷
    /// (`isComplete == true`, unsupportedElements 포함)을 방출한다.
    /// 최종 스냅샷의 문서는 `loadDocument`와 동일하다 (loadToken 제외).
    public func loadDocumentUpdates(
        from url: URL,
        firstBatch: Int = 1,
        batchSize: Int = 24
    ) -> AsyncThrowingStream<HwpDocumentSnapshot, Error> {
        loadTask?.cancel()
        // 누적 스냅샷 무제한 버퍼링 방지 — 최신 소수만 유지 (#10)
        let (stream, continuation) = AsyncThrowingStream<HwpDocumentSnapshot, Error>
            .makeStream(bufferingPolicy: .bufferingNewest(8))
        let loadToken = UUID()
        let task = Task<HwpDocument, Error> {
            do {
                let file = try await Self.parse {
                    try CoreHwp.HwpFile(fromPath: url.path, options: .viewer)
                }
                let document = try await self.buildDocument(
                    from: file,
                    loadToken: loadToken,
                    firstBatch: firstBatch,
                    batchSize: batchSize
                ) { snapshot in
                    continuation.yield(snapshot)
                }
                continuation.yield(HwpDocumentSnapshot(
                    document: document, isComplete: true, progress: 1
                ))
                continuation.finish()
                return document
            } catch {
                continuation.finish(throwing: error)
                throw error
            }
        }
        loadTask = task
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    private func buildDocument(
        from file: CoreHwp.HwpFile,
        loadToken: UUID? = nil,
        firstBatch: Int = 1,
        batchSize: Int = 24,
        onPartial: ((HwpDocumentSnapshot) -> Void)? = nil
    ) async throws -> HwpDocument {
        // 각 로드에 고유 토큰을 부여해 뷰 갱신 가드(document != oldValue)가 렌더
        // 지문이 우연히 같은 다른 문서도 구분하게 한다 — 프로그레시브 스냅샷은
        // 넘겨받은 같은 토큰을 공유해 증분 적용으로 판정된다.
        let token = loadToken ?? UUID()
        let index = HwpIndex(from: file)
        let imageStore = HwpImageStore(from: file)
        let paginator = HwpPaginator(
            // ViewText (변경 추적 표시본)가 있으면 한글.app처럼 그걸 그린다
            sections: file.displaySectionArray,
            index: index,
            fontResolver: fontResolver,
            imageStore: imageStore
        )
        // 취소된 로드(다른 로드가 시작됨)가 detached 파싱을 마친 뒤 actor 상태를
        // 덮어쓰지 않도록, paginator 설치 직전에 취소를 재확인한다 (#4).
        try Task.checkCancellation()
        self.paginator = paginator

        let previewText = file.previewText.text
        let preview = previewText.isEmpty ? nil : String(previewText.prefix(500))

        var pages: [HwpPage] = []
        var pageIndex = 0
        var nextYieldCount = max(1, firstBatch)
        while let page = try await paginator.page(at: pageIndex) {
            try Task.checkCancellation()
            pages.append(page)
            pageIndex += 1
            if let onPartial, pages.count >= nextYieldCount {
                nextYieldCount = pages.count + max(1, batchSize)
                let partial = HwpDocument(
                    pages: pages,
                    metadata: HwpDocumentMetadata(
                        title: nil,
                        pageCount: pages.count,
                        previewText: preview,
                        loadToken: token
                    ),
                    unsupportedElements: [],
                    imageStore: imageStore
                )
                let progress = await paginator.progressEstimate()
                onPartial(HwpDocumentSnapshot(
                    document: partial, isComplete: false, progress: progress
                ))
            }
        }

        let metadata = HwpDocumentMetadata(
            title: nil,
            pageCount: pages.count,
            previewText: preview,
            loadToken: token
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
