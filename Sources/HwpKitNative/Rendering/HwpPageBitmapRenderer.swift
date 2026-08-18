import CoreGraphics
import Foundation
import HwpKitCore

public enum HwpPageBitmapRenderError: Error, Sendable {
    case pageOutOfRange(index: Int, pageCount: Int)
    case invalidPixelSize(width: Int, height: Int)
    case invalidSourceRect(CGRect)
    case contextCreationFailed
    case imageCreationFailed
    case unresolvedImages(variants: Set<String>)
}

extension HwpPageBitmapRenderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .pageOutOfRange(index, pageCount):
            "Page \(Self.oneBased(index)) is outside the document (\(pageCount) page(s))"
        case let .invalidPixelSize(width, height):
            """
            Bitmap size must be within \
            1...\(HwpPageBitmapRenderer.maximumPixelDimension) (got \(width)×\(height))
            """
        case let .invalidSourceRect(rect):
            "Source rect must have a positive size (got \(rect.width)×\(rect.height))"
        case .contextCreationFailed:
            "Could not create a bitmap context"
        case .imageCreationFailed:
            "Could not read the rendered bitmap back as an image"
        case let .unresolvedImages(variants):
            "\(variants.count) image variant(s) stayed unresolved after predecoding"
        }
    }

    /// 1-기반 쪽 번호 표시는 **클램프가 산술보다 먼저**다. 쪽 인덱스는 공개
    /// 인자라 `Int.max`가 들어올 수 있는데, 그 값은 범위 밖으로 안전하게 분류돼
    /// 이 오류가 되고 나서 `index + 1`에서 트랩한다 — 타입 있는 오류를 주기로 한
    /// 계약이 그 오류를 **표시하는 순간** 프로세스를 죽인다.
    private static func oneBased(_ index: Int) -> Int {
        index < .max ? index + 1 : .max
    }
}

extension HwpPageBitmapRenderError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// 프리디코드 뒤에도 확정되지 않은 이미지 변형이 남았을 때의 정책.
///
/// 프리디코드는 바이트 예산으로 축출된 변형을 미해결로 남긴다. 뷰는 다음
/// 재드로우가 되살리지만 화면 없는 경로에는 그 루프가 없으므로, 호출자마다
/// 답이 갈린다 — 그래서 정책이 인자다.
public enum HwpUnresolvedImagePolicy: Sendable {
    /// 그대로 그린다 (회색 로딩 사각형이 남는다). 축소판·미리보기처럼 결과가
    /// **보조 표시**인 경로용 — 그림 하나 때문에 쪽 전체를 잃는 것이 더 나쁘다.
    case drawPlaceholder
    /// 오류로 끝낸다. 산출물이 기준선이 되거나(픽스처 하네스) 사용자가 보관하는
    /// 파일이 되는(PDF) 경로용 — 회색 사각형이 정답으로 굳으면 안 된다.
    case fail
}

/// `HwpPage`를 뷰와 **같은 draw 경로**로 비트맵 `CGImage`에 그린다.
///
/// `HwpPageLayer.draw(in:)`가 뷰 계층 없이 임의 `CGContext`에 그리는 순수
/// 오프스크린 렌더러라 가능하다 — 즉 화면·PDF와 같은 paint list, 같은 조판이다.
/// PDF 내보내기(`HwpPDFRenderer`)와는 `draw(page:in:provider:)` 한 자리를
/// 공유한다: 종이 배경과 레이어 구성이 두 곳에 갈라져 있으면 한쪽만 바뀐다.
///
/// 이미지 확정 규약은 PDF 루프를 그대로 따른다 —
/// `retainOnlyImages` → `predecodeImageReferences` → `unsettledImageVariants`.
/// 미확정 처리만 `HwpUnresolvedImagePolicy`로 갈린다.
public enum HwpPageBitmapRenderer {
    /// 이미지 예산 기본값. **변형 예산과 원본 캐시 예산 둘 다**에 같은 값을
    /// 준다 — 둘은 독립 회계라 한쪽만 낮추면 상한이 두 배가 된다
    /// (`HwpPDFRenderer`가 같은 이유로 둘을 함께 설정한다).
    public static let defaultImageByteLimit = HwpPageImageProvider.defaultResolvedByteLimit

    /// 출력 비트맵의 축별 상한 (px).
    ///
    /// **픽셀 수를 문서가 정하기 때문에** 필요하다: `HwpPageGeometry`는 페이지
    /// 치수를 200인치(14,400pt)로 **상한만** 막고 하한은 `> 0`이라 1 HWPUNIT =
    /// 0.01pt 폭이 그대로 통과한다. 종횡비 상한이 1,440,000이라 208px 축소판
    /// 하나가 299,520,000행 ≈ 249GB를 요구한다. 캐시 예산은 이것을 못 막는다 —
    /// 할당이 먼저이고 `HwpThumbnailCache`는 방금 넣은 항목이 예산을 넘어도
    /// 의도적으로 남긴다. 화면 뷰는 페이지를 자연 크기로 그려 무사하고, 폭을
    /// 끌어올리는 축소판·PrvImage 대조에서만 이 증폭이 생긴다.
    ///
    /// 값은 실사용의 한참 위다 — 렌더 골든 850px, 픽셀 해시 1x(A4 595px),
    /// fidelity 724px, 샘플 축소판 ~200px.
    public static let maximumPixelDimension = 16384

    /// 페이지 종횡비를 유지하는 픽셀 높이 — 상한에서 **클램프**한다.
    ///
    /// 거부가 아니라 클램프인 이유는 이것이 호스트가 셀 자리를 미리 잡는 **크기
    /// 헬퍼**라서다: 실패하면 그 쪽이 목록에서 통째로 사라진다
    /// (`HwpOutlineItem`의 수준 클램프와 같은 기준). 그리는 쪽(`rasterize`)은
    /// 반대로 **거부**한다 — 거기서 조용히 줄이면 호출자가 요청하지 않은 크기의
    /// 비트맵이 나간다.
    public static func pixelHeight(for page: HwpPage, pixelWidth: Int) -> Int {
        let width = clampedDimension(CGFloat(pixelWidth))
        guard page.size.width > 0, page.size.height > 0 else { return width }
        return clampedDimension((CGFloat(width) * page.size.height / page.size.width).rounded())
    }

    /// `Int(_:)` 변환은 범위 밖 값에서 **트랩**하므로 클램프가 변환보다 먼저다.
    /// 조작 문서의 종횡비와 `Int.max` 픽셀 폭이 둘 다 이 경로로 온다.
    private static func clampedDimension(_ value: CGFloat) -> Int {
        guard value.isFinite, value >= 1 else { return 1 }
        guard value < CGFloat(maximumPixelDimension) else { return maximumPixelDimension }
        return Int(value)
    }

    /// 페이지 하나를 비트맵으로 렌더한다. 공급자와 캐시를 **이 호출 안에서만**
    /// 만들고 끝에 놓으므로 문서 간 오염이 없다 (캐시 키가 `binItemId` 하나라
    /// 캐시를 문서 간에 공유하면 다른 문서의 비트맵이 히트한다).
    ///
    /// 여러 쪽을 훑는 호출자는 이 API를 반복하지 말 것 — 쪽마다 디코드를 처음부터
    /// 다시 한다. `HwpPageThumbnailRenderer`가 공급자를 재사용하면서 쪽 경계마다
    /// 이전 쪽 래스터를 버리는 순회 규율을 갖고 있다.
    ///
    /// - Parameters:
    ///   - sourceRect: 캔버스를 채울 페이지 영역 (top-down 페이지 좌표).
    ///     `nil`이면 페이지 전체다 — 그때 CTM은 **순수 스케일**이라 기존 렌더와
    ///     비트 단위로 같다.
    public static func render(
        page: HwpPage,
        imageStore: HwpImageStore,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceRect: CGRect? = nil,
        unresolvedImages policy: HwpUnresolvedImagePolicy = .drawPlaceholder,
        imageByteLimit: Int = defaultImageByteLimit
    ) async throws -> CGImage {
        let provider = makeProvider(for: imageStore, imageByteLimit: imageByteLimit)
        defer { provider?.cancelOutstanding() }
        if let provider {
            try await resolveImages(in: page, provider: provider, policy: policy)
        }
        return try rasterize(
            page: page,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourceRect: sourceRect,
            provider: provider
        )
    }

    /// 문서 전용 공급자 + 전용 캐시. 두 예산을 **함께** 준다 — 캐시 기본값을
    /// 그대로 두면 변형 예산과 독립으로 쌓여 상한이 두 배가 된다.
    static func makeProvider(
        for imageStore: HwpImageStore,
        imageByteLimit: Int
    ) -> HwpPageImageProvider? {
        guard !imageStore.isEmpty else { return nil }
        let provider = HwpPageImageProvider(
            store: imageStore, cache: HwpImageCache(maxBytes: imageByteLimit)
        )
        provider.resolvedByteLimit = imageByteLimit
        return provider
    }

    /// 이 쪽의 이미지를 확정까지 디코딩한다 — PDF 루프와 **같은 순서**다.
    ///
    /// `setPinnedImages`가 아니라 `retainOnlyImages`인 것이 요점이다: 고정 교체만
    /// 하면 그것이 부르는 축출이 예산 초과 시에만 돌아 이전 쪽 래스터가 예산
    /// 한계까지 잔류한다 (**unpin은 해제가 아니다**). 축소판은 정의상 쪽 순회다.
    static func resolveImages(
        in page: HwpPage,
        provider: HwpPageImageProvider,
        policy: HwpUnresolvedImagePolicy
    ) async throws {
        provider.retainOnlyImages(HwpPageImageProvider.imageVariantKeys(in: page.paintList))
        await provider.predecodeImageReferences(in: page.paintList)
        try Task.checkCancellation()
        guard policy == .fail else { return }
        let unsettled = provider.unsettledImageVariants(in: page.paintList)
        guard unsettled.isEmpty else {
            throw HwpPageBitmapRenderError.unresolvedImages(variants: unsettled)
        }
    }

    /// 확정된 공급자를 받아 동기 래스터화만 한다 (이미지 대기는 호출부 몫).
    static func rasterize(
        page: HwpPage,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceRect: CGRect?,
        provider: HwpPageImageProvider?
    ) throws -> CGImage {
        guard pixelWidth >= 1, pixelWidth <= maximumPixelDimension,
              pixelHeight >= 1, pixelHeight <= maximumPixelDimension
        else {
            throw HwpPageBitmapRenderError.invalidPixelSize(
                width: pixelWidth, height: pixelHeight
            )
        }
        let source = sourceRect ?? CGRect(origin: .zero, size: page.size)
        guard source.width > 0, source.height > 0 else {
            throw HwpPageBitmapRenderError.invalidSourceRect(source)
        }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HwpPageBitmapRenderError.contextCreationFailed
        }
        // 캔버스 전체를 먼저 흰 종이로 깐다. `draw`가 페이지 사각형을 다시 깔지만
        // 그것만으로는 부족하다 — `sourceRect`가 종이 밖으로 나가면 그 여백이
        // 투명(=0)으로 남아, 알파를 무시하고 읽는 소비자에게 검정이 된다.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        applySourceTransform(
            to: context,
            page: page,
            source: source,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        draw(page: page, in: context, provider: provider)
        guard let image = context.makeImage() else {
            throw HwpPageBitmapRenderError.imageCreationFailed
        }
        return image
    }

    /// 흰 종이 + 레이어 구성 + draw — 비트맵 캔버스와 PDF 페이지 컨텍스트가
    /// 공유하는 **유일한 그리기 몸통**이다. 두 곳에 갈라 두면 배경·flip·레이어
    /// 필드 대입 중 하나가 한쪽에서만 바뀐다.
    ///
    /// PDF 페이지는 기본이 투명이라 배경을 뷰어·프린터가 정하게 두면 종이 은유가
    /// 깨진다 — 화면의 페이지 레이어 배경과 같은 흰 종이를 깐다.
    static func draw(page: HwpPage, in context: CGContext, provider: HwpPageImageProvider?) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: page.size))
        context.restoreGState()

        let layer = HwpPageLayer()
        layer.bounds = CGRect(origin: .zero, size: page.size)
        layer.pageHeight = page.size.height
        layer.imageProvider = provider
        layer.paintList = page.paintList
        layer.draw(in: context)
    }

    /// `source`(top-down 페이지 좌표)가 캔버스를 채우도록 CTM을 잡는다.
    ///
    /// 이 변환은 `HwpPageLayer.draw`가 자기 bounds 높이로 CTM을 뒤집기 **전에**
    /// 걸리므로, 아래 이동량은 그 flip 뒤의 좌표계(y-up 페이지) 기준이다.
    /// 스케일 뒤에 이동을 부르는 순서인 것이 중요하다 — CGContext는 나중에 부른
    /// 변환이 좌표에 먼저 적용되므로 이동이 **페이지 단위**로 해석되고, 그래서
    /// 페이지 전체(`source == 페이지`)일 때 이동량이 부동소수 오차 없이 정확히
    /// (0, 0)이 된다. 장치 단위로 이동하면 `pageH × (pxH / pageH) ≠ pxH`라
    /// 1e-13pt짜리 이동이 남아 픽셀 해시 기준선이 흔들린다.
    private static func applySourceTransform(
        to context: CGContext,
        page: HwpPage,
        source: CGRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        context.scaleBy(
            x: CGFloat(pixelWidth) / source.width,
            y: CGFloat(pixelHeight) / source.height
        )
        context.translateBy(x: -source.minX, y: source.maxY - page.size.height)
    }
}
