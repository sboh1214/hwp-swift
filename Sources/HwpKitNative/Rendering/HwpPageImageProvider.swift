import CoreGraphics
@preconcurrency import CoreHwp
import Foundation
import HwpKitCore

/// 페이지 레이어의 `.drawImageReference` 명령을 실제 `CGImage`로 해석하는 공급자.
///
/// `HwpImageStore`(문서의 BinData 바이트) → `HwpImageAdapter`(디코딩) →
/// `HwpImageCache`(LRU + 동시 디코드 병합) 경로를 잇고, 디코딩이 끝나면
/// `onImageResolved`로 레이어 redraw를 요청한다.
///
/// 공급자는 문서마다 새로 만든다 — binItemId는 문서-로컬 키이므로
/// 캐시를 문서 간에 공유하면 다른 문서의 이미지가 재사용된다.
public final class HwpPageImageProvider: @unchecked Sendable {
    private let store: HwpImageStore
    private let cache: HwpImageCache
    private let adapter = HwpImageAdapter()
    private let lock = NSLock()
    /// draw 경로용 동기 스냅샷 ((binItemId, style) 변형별). NSCache라 메모리
    /// 압박 시 자동으로 비워지고, 비워진 항목은 requestImage가 다시 채운다.
    private let resolvedImages = NSCache<NSString, CGImage>()
    private var failedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    private var imageResolvedHandler: (@Sendable (UInt32) -> Void)?

    /// (binItemId, style) 변형의 결정론적 캐시 키
    private static func variantKey(_ binItemId: UInt32, _ style: HwpImageRenderStyle?) -> String {
        guard let style else { return "\(binItemId)" }
        return "\(binItemId)|\(style.cropLeft),\(style.cropTop),\(style.cropRight)," +
            "\(style.cropBottom)|\(style.brightness)|\(style.contrast)|\(style.effect.rawValue)"
    }

    /// 비동기 디코딩 완료 시 호출된다 (임의 스레드).
    public var onImageResolved: (@Sendable (UInt32) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return imageResolvedHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            imageResolvedHandler = newValue
        }
    }

    public init(store: HwpImageStore, cache: HwpImageCache) {
        self.store = store
        self.cache = cache
        resolvedImages.totalCostLimit = 64_000_000
    }

    /// 이미 디코딩된 이미지를 동기 반환한다 (draw 경로용).
    public func cachedImage(for key: UInt32, style: HwpImageRenderStyle? = nil) -> CGImage? {
        resolvedImages.object(forKey: Self.variantKey(key, style) as NSString)
    }

    /// 디코딩에 실패했던 키인지 여부 (placeholder 렌더 판단용).
    public func didFail(for key: UInt32, style: HwpImageRenderStyle? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedKeys.contains(Self.variantKey(key, style))
    }

    /// 비동기 디코딩 + 스타일 적용을 트리거한다. 이미 완료/진행 중이면 무시한다.
    public func requestImage(for key: UInt32, style: HwpImageRenderStyle? = nil) {
        guard cachedImage(for: key, style: style) == nil else { return }
        let variant = Self.variantKey(key, style)
        lock.lock()
        let alreadyHandled = failedKeys.contains(variant) || inFlightKeys.contains(variant)
        if !alreadyHandled {
            inFlightKeys.insert(variant)
        }
        lock.unlock()
        guard !alreadyHandled else { return }

        let store = store
        let cache = cache
        let adapter = adapter
        Task { [weak self] in
            // 원본 디코드는 binItemId 단위로 공유 캐시하고,
            // 스타일 변형은 변형 키로 이 provider에만 저장한다.
            let decoded = await cache.fetch(key) {
                guard let data = store.data(forBinItemId: key) else { return nil }
                let binaryData = CoreHwpBinaryDataShim.binaryData(
                    named: store.extensionName(forBinItemId: key),
                    data: data
                )
                switch adapter.decode(binaryData: binaryData) {
                case let .success(decoded):
                    return decoded.image
                case .failure:
                    return nil
                }
            }
            let styled = decoded.map { HwpImageStyleRenderer.apply(style, to: $0) }
            // crop-only 변형은 CGImage.cropping이 원본 backing을 공유·고정하므로
            // 캐시 비용을 원본 크기 기준으로 계상한다.
            let pinnedPixels = max(
                (styled?.width ?? 0) * (styled?.height ?? 0),
                (decoded?.width ?? 0) * (decoded?.height ?? 0)
            )
            self?.finishRequest(
                key: key,
                variant: variant,
                image: styled,
                cost: pinnedPixels * 4
            )
        }
    }

    private func finishRequest(key: UInt32, variant: String, image: CGImage?, cost: Int) {
        lock.lock()
        inFlightKeys.remove(variant)
        if let image {
            resolvedImages.setObject(image, forKey: variant as NSString, cost: cost)
        } else {
            failedKeys.insert(variant)
        }
        let handler = imageResolvedHandler
        lock.unlock()
        handler?(key)
    }

    /// PlatformImage(NSImage/UIImage) 편의 접근자 — 앱 레벨 소비용.
    public func platformImage(for key: UInt32) -> PlatformImage? {
        guard let image = cachedImage(for: key) else { return nil }
        return PlatformImage(hwpCgImage: image)
    }
}

/// HwpImageAdapter가 `CoreHwp.HwpBinaryData`를 받으므로 스토어 바이트를 감싸준다.
private enum CoreHwpBinaryDataShim {
    static func binaryData(named extensionName: String?, data: Data) -> CoreHwp.HwpBinaryData {
        CoreHwp.HwpBinaryData(
            name: "BIN0000.\(extensionName ?? "bin")",
            data: data
        )
    }
}
