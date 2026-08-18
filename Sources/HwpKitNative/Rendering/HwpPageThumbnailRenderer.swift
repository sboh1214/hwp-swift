import CoreGraphics
import Foundation
import HwpKitCore

/// 문서 하나의 쪽 축소판을 만들고 들고 있는 렌더러.
///
/// `HwpPageBitmapRenderer.render`를 쪽마다 부르는 것과 다르다 — 그쪽은 호출마다
/// 공급자와 캐시를 새로 만들어 원본 디코드를 처음부터 다시 한다. 축소판은 정의상
/// **쪽 순회**라 공급자를 재사용해야 하고, 그러면 쪽 경계마다 이전 쪽 래스터를
/// 버리는 규율이 필요하다 (`HwpPDFRenderer`의 페이지 루프와 같은 문제).
///
/// - **순회 규율**: 쪽마다 `retainOnlyImages` → `predecodeImageReferences`.
///   `setPinnedImages`만으로는 안 된다 — 그것이 부르는 축출은 예산 초과 시에만
///   돌아서, 예산 안이면 이전 쪽 래스터가 그대로 남아 문서를 훑는 동안 상주량이
///   한도까지 자란다 (**unpin은 해제가 아니다**).
/// - **예산 둘을 함께 건다**: 변형 예산(`resolvedByteLimit`)과 원본 캐시 예산은
///   독립 회계라 한쪽만 낮추면 상한이 두 배가 된다.
/// - **캐시는 문서 전용이다**: `HwpImageCache`의 키가 `binItemId` 하나라 문서 간에
///   공유하면 다른 문서의 비트맵이 그대로 히트한다. 그래서 뷰의 캐시를 받지 않고
///   문서 교체마다 새로 만든다.
/// - **미확정은 플레이스홀더로 둔다**: 축소판은 보조 표시라, 그림 하나가 예산에
///   걸렸다고 쪽 전체를 잃는 것이 더 나쁘다 (PDF·픽스처 하네스와 갈리는 지점).
///
/// 동시성: 요청은 **직렬화**된다. `retainOnlyImages`가 공급자 전역이라 두 쪽을
/// 동시에 그리면 한쪽이 다른 쪽의 확정된 변형을 그리기 직전에 버린다.
public final class HwpPageThumbnailRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private let imageByteLimit: Int
    private let cache: HwpThumbnailCache
    /// 쪽 렌더 상호 배제. 취소 시 슬롯 없이 false를 주는 계약이 그대로 필요해서
    /// 디코드 스로틀을 한도 1로 재사용한다 (별도 세마포어를 두면 그 취소 규약을
    /// 다시 구현하게 된다).
    private let gate = HwpDecodeThrottle(limit: 1)

    private var pages: [HwpPage] = []
    private var document: HwpDocument?
    private var provider: HwpPageImageProvider?
    /// 문서 교체 세대. 교체 시점에 이미 게이트를 통과한 렌더가 있으면 그 결과는
    /// **옛 문서의 쪽**이므로 새 캐시에 넣으면 안 된다.
    private var generation = 0

    /// 렌더된 축소판 보유 예산 기본값 (`HwpThumbnailCache`가 소유하는 값이지만
    /// 그 타입이 internal이라 기본 인자로 쓰려면 여기서 공개해야 한다).
    public static let defaultThumbnailCacheBytes = HwpThumbnailCache.defaultMaxBytes

    public init(
        imageByteLimit: Int = HwpPageBitmapRenderer.defaultImageByteLimit,
        thumbnailCacheBytes: Int = HwpPageThumbnailRenderer.defaultThumbnailCacheBytes
    ) {
        self.imageByteLimit = imageByteLimit
        cache = HwpThumbnailCache(maxBytes: thumbnailCacheBytes)
    }

    deinit {
        provider?.cancelOutstanding()
    }

    public var pageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pages.count
    }

    /// 대상 문서를 갈아 끼운다.
    ///
    /// 프로그레시브 스냅샷(같은 `loadToken` + 쪽 수 비감소)이면 공급자·이미지
    /// 캐시·이미 그린 축소판을 **그대로 두고** 쪽 배열만 늘린다. 그 판정은 뷰가
    /// 쓰는 것과 같은 함수다 — 판정이 갈리면 뷰는 증분인데 축소판만 전부 버린다.
    ///
    /// 전체 교체(다른 `loadToken`)에서만 공급자·캐시를 새로 만들고 진행 중 디코드를
    /// 끊는다. `cancelOutstanding`만으로는 부족하다: 그것은 요청 상태를 비울 뿐
    /// 이미 디코드된 결과와 실패 키를 지우지 않으므로, `binItemId` 캐시 오염은
    /// 공급자·캐시 교체가 담당한다.
    public func update(document: HwpDocument) {
        lock.lock()
        let progressive = HwpDocumentViewSupport.isProgressiveUpdate(
            from: self.document, to: document
        )
        self.document = document
        pages = document.pages
        if progressive {
            lock.unlock()
            return
        }
        let previous = provider
        generation &+= 1
        provider = HwpPageBitmapRenderer.makeProvider(
            for: document.imageStore, imageByteLimit: imageByteLimit
        )
        // 세대 증가와 축소판 폐기는 **같은 임계 구역**이어야 한다. 갈라 두면 그
        // 사이에 렌더가 세대 검사를 통과해, 방금 비운 캐시에 옛 문서의 비트맵을
        // 넣는다 (그 키는 `(쪽, 픽셀 폭)`뿐이라 새 문서의 같은 쪽이 영구히 그것에
        // 히트한다). `cancelOutstanding`은 대기자를 깨우며 우리 락을 다시 잡을 수
        // 있는 경로라 **밖에서** 부른다.
        cache.removeAll()
        lock.unlock()
        previous?.cancelOutstanding()
    }

    /// 진행 중인 이미지 디코드를 끊는다 (사이드바가 사라질 때). 이미 만든
    /// 축소판은 그대로 둔다 — 다시 열 때 재렌더할 이유가 없다.
    ///
    /// 세대를 올리는 것이 함께여야 한다: 이 호출은 그리는 중인 쪽의 이미지 확정을
    /// 중간에 끊는데, `.drawPlaceholder` 정책은 그것을 오류로 보지 않으므로 그
    /// 결과가 그대로 캐시되면 **회색 사각형이 그 쪽의 답으로 굳는다** (호출자
    /// 태스크의 취소는 `Task.checkCancellation`이 잡지만, 이쪽 취소는 그 태스크에
    /// 전파되지 않는다).
    public func cancelOutstanding() {
        lock.lock()
        let current = provider
        generation &+= 1
        lock.unlock()
        current?.cancelOutstanding()
    }

    /// 0-기반 쪽 인덱스의 축소판. 종횡비는 그 쪽의 용지 크기를 따른다
    /// (구역마다 용지가 다른 문서가 있다).
    ///
    /// 이미 만든 축소판은 **같은 인스턴스**로 돌려준다. 취소되면 아무것도 캐시하지
    /// 않는다 — 취소는 이미지 확정을 중간에 끊으므로 그 결과를 굳히면 회색
    /// 사각형이 그 쪽의 답으로 남는다.
    public func image(forPageAt index: Int, pixelWidth: Int) async throws -> CGImage {
        // 캐시 히트도 취소를 이기지 못한다. 이 조회가 게이트보다 **앞**이라,
        // 검사가 없으면 이미 그린 쪽을 요청한 취소된 셀은 취소 경로를 아예 지나지
        // 않고 성공한다.
        try Task.checkCancellation()
        let key = HwpThumbnailCache.Key(pageIndex: index, pixelWidth: pixelWidth)
        if let cached = cache.image(for: key) {
            return cached
        }
        guard await gate.acquire() else { throw CancellationError() }
        defer { Task { await gate.release() } }
        // 슬롯을 **넘겨받은 뒤**의 취소는 스로틀이 무시하고 호출부에 맡긴다
        // (`HwpDecodeThrottle.cancelWaiter` 주석) — release가 이양한 대기자의 늦은
        // 취소가 그 창이고, 아래 캐시 조회보다 먼저 서야 닫힌다.
        try Task.checkCancellation()
        // 게이트를 기다리는 사이 같은 쪽이 그려졌을 수 있다 (그리드 셀이 스크롤로
        // 두 번 나타나는 흔한 형상). 진입 시 조회만 하면 그대로 재렌더한다.
        if let cached = cache.image(for: key) {
            return cached
        }

        let snapshot = try snapshot(at: index)
        // 값싼 기하 검증이 **디코드보다 먼저**다 (`validatedGeometry` 주석) —
        // 상한 밖 폭이 페이지 그림을 전부 디코드한 뒤에야 거절되면 안 된다.
        let geometry = try HwpPageBitmapRenderer.validatedGeometry(
            page: snapshot.page,
            pixelWidth: pixelWidth,
            pixelHeight: HwpPageBitmapRenderer.pixelHeight(
                for: snapshot.page, pixelWidth: pixelWidth
            ),
            sourceRect: nil
        )
        if let pageProvider = snapshot.provider {
            try await HwpPageBitmapRenderer.resolveImages(
                in: snapshot.page, provider: pageProvider, policy: .drawPlaceholder
            )
        }
        try Task.checkCancellation()
        let image = try HwpPageBitmapRenderer.rasterize(
            page: snapshot.page, geometry: geometry, provider: snapshot.provider
        )
        // 래스터화는 동기라 그 사이 도착한 취소는 여기서만 잡힌다. 결과 자체는
        // 온전하지만(이미지 확정은 위에서 이미 끝났다) "취소는 아무것도 캐시하지
        // 않는다"를 문자 그대로 지키는 자리가 여기다 — 옛 문서 비트맵을 막는 것은
        // 아래 세대 가드의 몫으로 갈라 둔다.
        try Task.checkCancellation()
        // 그리는 동안 문서가 바뀌었으면 이 비트맵은 옛 문서의 쪽이다 — 새 캐시에
        // 넣으면 다른 문서의 쪽이 그 자리에 굳는다 (`HwpImageCache`가 `binItemId`
        // 하나로 키를 잡아 문서 간 오염을 만드는 것과 같은 성격의 실수다).
        insertIfCurrent(image, for: key, generation: snapshot.generation)
        return image
    }

    /// 세대가 아직 유효할 때만 캐시에 넣는다.
    ///
    /// 확인과 삽입이 **한 임계 구역**이어야 한다. 나누면 그 사이 `update`가
    /// 세대를 올리고 캐시를 비워, 이 삽입이 새 문서의 빈 캐시에 옛 문서의
    /// 비트맵을 남긴다 — 세대 가드가 막겠다고 선언한 바로 그 오염이다.
    /// 락 순서는 언제나 이 락 → 캐시 락 한 방향이다 (캐시는 되부르지 않는다).
    func insertIfCurrent(_ image: CGImage, for key: HwpThumbnailCache.Key, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation else { return }
        cache.insert(image, for: key)
    }

    /// 한 번의 렌더가 보는 대상. 셋을 따로 읽으면 그 사이 문서가 바뀌어 **옛
    /// 공급자로 새 쪽을 그리거나**, 새 세대 도장이 찍힌 옛 쪽이 캐시에 들어간다.
    private struct RenderTarget {
        let page: HwpPage
        let provider: HwpPageImageProvider?
        let generation: Int
    }

    private func snapshot(at index: Int) throws -> RenderTarget {
        lock.lock()
        defer { lock.unlock() }
        guard pages.indices.contains(index) else {
            throw HwpPageBitmapRenderError.pageOutOfRange(index: index, pageCount: pages.count)
        }
        return RenderTarget(page: pages[index], provider: provider, generation: generation)
    }

    /// 테스트 관측점 — 세대 가드의 대조군을 만들려면 현재 세대를 알아야 한다.
    var currentGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// 테스트 관측점 — 순회 규율(이전 쪽 래스터 해제)을 공급자에 직접 물어본다.
    var imageProvider: HwpPageImageProvider? {
        lock.lock()
        defer { lock.unlock() }
        return provider
    }

    /// 테스트 관측점.
    var thumbnailCache: HwpThumbnailCache {
        cache
    }
}
