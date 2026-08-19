import CoreGraphics
import Foundation
import HwpKitCore
import QuartzCore

/// macOS(`HwpDocumentNSView`)·iOS(`HwpDocumentUIView`) 문서 뷰가 공유하는
/// 플랫폼 중립 헬퍼. CALayer·CGFloat만 다루므로 #if 없이 양쪽에서 컴파일된다
/// (macOS 빌드에 포함되어 swift test가 커버).
///
/// 프로토콜 + extension 대신 명시적 입력을 받는 정적 함수로 둔다 —
/// 뷰의 `public private(set)` 저장 프로퍼티 접근 제어와 충돌하지 않고,
/// 입출력이 드러나 단독 테스트가 쉽다.
@MainActor
enum HwpDocumentViewSupport {
    // MARK: - 문서 갱신 판정

    /// 프로그레시브 스냅샷 (같은 loadToken + 페이지 증가) 여부.
    /// true면 뷰는 기존 레이어·스크롤 위치를 유지하고 크기·가시 범위만 늘린다.
    /// 뷰가 죽을 때 검색 세션을 뗀다.
    ///
    /// SwiftUI 를 거치지 않는 직접 사용 경로에는 `dismantleNSView`/
    /// `dismantleUIView` 가 없어 여기서만 끊을 수 있다 — 안 끊으면 호스트가
    /// 붙든 컨트롤러가 이 뷰의 선택 컨트롤러를, 그것이 다시 문서 전체를 잡는다.
    ///
    /// `deinit` 은 nonisolated 이고 dealloc 이 메인에서 돈다는 보장이 없어
    /// `@MainActor` 인 `detach()` 를 그 자리에서 부를 수 없다. 두 컨트롤러 모두
    /// `@MainActor` 라 Sendable 이므로 참조만 넘겨 홉을 태운다. 떼는 대상은
    /// **자기 것뿐**이다 — 그 사이 다른 뷰가 세션을 가져갔으면 건드리지 않는다.
    nonisolated static func detachSearchSessionOnTeardown(
        _ controller: HwpSearchController?,
        from selection: HwpSelectionController
    ) {
        guard let controller else { return }
        Task { @MainActor in
            guard controller.isAttached(to: selection) else { return }
            controller.detach()
            removeSearchHooks(from: controller)
        }
    }

    /// 이 뷰가 설치한 검색 훅을 뗀다.
    ///
    /// 호출부는 `isAttached(to:)` 로 **자기 세션**임을 먼저 확인한다 — 다른 뷰가
    /// 이미 재배선했으면 그 훅을 지우면 안 되는데 클로저는 동일성 비교가 안 되므로
    /// 그 가드가 유일한 판별이다. 안 지우면 뗀 컨트롤러가 옛 뷰의 클로저를 들고
    /// 있다가, 재사용될 때 옛 뷰를 다시 칠하고 `retainedPageRange` 로 **새
    /// 지오메트리를 옛 가시 범위로 축출**한다 (#75 리뷰 13차).
    @MainActor
    static func removeSearchHooks(from controller: HwpSearchController) {
        controller.onMatchesChanged = nil
        controller.onCurrentMatchChanged = nil
        controller.retainedPageRange = nil
    }

    nonisolated static func isProgressiveUpdate(
        from old: HwpDocument?,
        to new: HwpDocument?
    ) -> Bool {
        guard let old, let new,
              let token = new.metadata.loadToken,
              old.metadata.loadToken == token,
              new.pages.count >= old.pages.count
        else { return false }
        return true
    }

    // MARK: - contentsScale (Retina 선명도)

    /// Retina 해상도 + 줌 배율에 맞춘 레이어 래스터 해상도.
    /// 축소 (zoom < 1)는 base 유지, 확대는 base × 4 상한.
    nonisolated static func effectiveContentsScale(
        base: CGFloat,
        zoomScale: CGFloat
    ) -> CGFloat {
        min(base * max(1, zoomScale), base * 4)
    }

    /// 레이어 한 축의 래스터 픽셀 상한 (Metal 최대 텍스처 = 백킹 스토어 안전선).
    private static let maximumRasterPixelsPerAxis: CGFloat = 8192

    /// 레이어 하나의 총 래스터 픽셀 상한 (RGBA 64MB). 축별 상한만으로는
    /// 14400pt 페이지가 8192² = 256MB 백킹을 받아 가상화 5장이면 1GB를
    /// 넘겨 iOS가 종료된다 — 면적 총량으로 제한한다 (#3).
    private static let maximumRasterPixels: CGFloat = 16_000_000

    /// 페이지 크기 × scale이 백킹 스토어 상한을 넘으면 scale을 낮춘다 (#7).
    /// 거대 페이지 (미신뢰 치수·큰 줌)가 수 GiB RGBA 백킹을 요구하는 것을 막는다.
    /// 실제 페이지(≤ 레터/A4)는 어떤 줌에서도 상한을 밑돌아 해상도 불변.
    nonisolated static func boundedContentsScale(_ scale: CGFloat, for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return scale }
        let axisCap = min(
            maximumRasterPixelsPerAxis / size.width,
            maximumRasterPixelsPerAxis / size.height
        )
        // 총 면적 = (w·s)(h·s) = w·h·s² ≤ maximumRasterPixels → s ≤ √(max/(w·h))
        let areaCap = (maximumRasterPixels / (size.width * size.height)).squareRoot()
        // 최소 배율(0.1)은 원하는 scale에만 적용하고, 안전 캡(axisCap/areaCap)은
        // 항상 이기게 한다 — 거대 레이어(예: 긴 메모 패널, axisCap<0.1)에서 바닥이
        // 캡을 덮어 8192px 축 한계를 넘는 백킹이 생기던 것을 막는다 (P1).
        return min(max(0.1, scale), axisCap, areaCap)
    }

    /// 배율이 달라진 레이어만 재래스터한다. 메모 패널 레이어 그룹도 함께
    /// 넘겨 페이지와 같은 해상도를 유지한다 (양 플랫폼 공통).
    static func updateContentsScale(
        of layerGroups: [HwpPageLayer]...,
        scale: CGFloat
    ) {
        for layers in layerGroups {
            for layer in layers {
                let bounded = boundedContentsScale(scale, for: layer.bounds.size)
                guard layer.contentsScale != bounded else { continue }
                layer.contentsScale = bounded
                layer.setNeedsDisplay()
            }
        }
    }

    // MARK: - fit 배율 (#78)

    /// 스크롤 캔버스를 뷰포트에 맞추는 배율 — 퇴화 입력이면 nil이다.
    ///
    /// **퇴화 입력을 여기서 직접 거른다.** 하류의 비-finite 게이트가 이 경우를
    /// 잡아 주지 않기 때문이다: `HwpZoomControls.sanitized`는 0을 finite로 보아
    /// 1.0 폴백을 태우지 않고 하한 0.25로 클램프하므로, 폭 0 뷰포트가 사용자에게는
    /// "안내 없는 25% 축소"로 보인다. NaN을 내보내도 마찬가지다 — iOS는 직전 값을
    /// 유지하고 macOS는 클램프를 통과시킨 뒤 조용히 no-op이라, 두 플랫폼 모두
    /// "버튼이 안 먹는" 증상만 남고 원인은 어디에도 남지 않는다. nil은 호출부가
    /// "아직 맞출 수 없다"를 구분해 예약할 수 있게 하는 신호이기도 하다.
    /// 선례는 `HwpPageBitmapRenderer.pixelHeight`의 `page.size` 양수 가드다.
    ///
    /// `range`를 **인자로 받는** 이유: 배율 한계 `0.25...5.0`은 이미 프로덕션 세
    /// 곳(`HwpZoomControls` 기본 range·`NSScrollView` magnification·`UIScrollView`
    /// zoomScale)에 사본이 있다. 여기서 또 적으면 넷이 되어 향후 범위 변경이 조용히
    /// 갈리므로, 호출부가 자기 스크롤 뷰의 실제 한계를 넘긴다.
    ///
    /// - Parameters:
    ///   - content: 스크롤 캔버스 크기 (문서 좌표계). 폭은 문서 전체 최대 행 폭이고
    ///     높이는 맞출 대상 행의 높이다 — 둘 다 메모 패널을 포함한다.
    ///   - viewport: 배율과 무관한 뷰포트 크기 (macOS `NSScrollView.contentSize`
    ///     = 클립 뷰 frame, iOS 는 문서 뷰 본체의 `bounds`).
    nonisolated static func fitZoomScale(
        content: CGSize,
        viewport: CGSize,
        fit: HwpZoomFit,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        guard isUsableExtent(content.width), isUsableExtent(viewport.width) else { return nil }
        var scale = viewport.width / content.width
        if fit == .page {
            guard isUsableExtent(content.height), isUsableExtent(viewport.height) else {
                return nil
            }
            scale = min(scale, viewport.height / content.height)
        }
        // 유한한 두 양수의 나눗셈도 언더플로로 0이 될 수 있다 (거대 캔버스).
        guard isUsableExtent(scale) else { return nil }
        return min(max(scale, range.lowerBound), range.upperBound)
    }

    private nonisolated static func isUsableExtent(_ value: CGFloat) -> Bool {
        value.isFinite && value > 0
    }

    // MARK: - 페이지 레이어 chrome

    /// 페이지 종이 배경 + 그림자 + 래스터 해상도 (양 플랫폼 동일 스펙).
    static func decoratePageLayer(_ layer: HwpPageLayer, contentsScale: CGFloat) {
        layer.backgroundColor = PlatformColor.white.cgColor
        layer.shadowColor = PlatformColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.contentsScale = boundedContentsScale(contentsScale, for: layer.bounds.size)
    }

    /// 페이지에 메모 패널이 있으면 오른쪽 바깥에 투명 레이어로 만든다.
    static func makeMemoPanelLayer(
        document: HwpDocument?,
        pageIndex: Int,
        pageFrame: CGRect,
        contentsScale: CGFloat
    ) -> HwpPageLayer? {
        guard let panel = document?.pages[safe: pageIndex]?.memoPanel else { return nil }
        let panelLayer = HwpPageLayer()
        // 풍선 스택이 페이지보다 길면 레이어를 콘텐츠 높이로 키워 클립을 막는다 (#8).
        let panelHeight = max(pageFrame.height, panel.contentHeight)
        panelLayer.frame = CGRect(
            x: pageFrame.maxX,
            y: pageFrame.minY,
            width: panel.width,
            height: panelHeight
        )
        panelLayer.pageHeight = panelHeight
        panelLayer.backgroundColor = nil
        panelLayer.contentsScale = boundedContentsScale(contentsScale, for: panelLayer.bounds.size)
        panelLayer.paintList = panel.paintList
        return panelLayer
    }

    // MARK: - 이미지 공급자

    /// 문서별 새 캐시 + 공급자를 만든다 — binItemId는 문서-로컬 키이므로
    /// 캐시를 문서 간에 공유하면 다른 문서의 이미지가 재사용된다.
    /// 디코딩 완료 시 main queue에서 `currentLayers()`가 돌려준 레이어 중
    /// 해당 이미지를 참조하는 것만 다시 그린다.
    /// 이미지 없는 문서는 nil — 호출부는 공급자만 비우고 캐시는 유지한다.
    /// 주어진 페이지 범위가 참조하는 이미지 binItemId 집합 — provider의 가시
    /// 작업셋 pin 갱신용 (#2). 이 이미지는 캐시 예산 초과여도 축출되지 않아
    /// 4장+ 이미지 페이지의 축출→재요청 사이클을 막는다.
    /// 주어진 페이지 범위가 참조하는 이미지 변형 키 집합 — provider의 가시 작업셋
    /// pin 갱신용 (#1). binItemId가 아니라 (crop/effect) 변형 단위라, 같은 ID의
    /// 옛 변형이 계속 pin되지 않는다.
    nonisolated static func imageReferences(
        in document: HwpDocument?,
        pageRange: Range<Int>
    ) -> Set<String> {
        guard let document else { return [] }
        var variants: Set<String> = []
        for index in pageRange where document.pages.indices.contains(index) {
            variants.formUnion(
                HwpPageImageProvider.imageVariantKeys(in: document.pages[index].paintList)
            )
        }
        return variants
    }

    static func makeImageProvider(
        document: HwpDocument?,
        onLayersNeedingDisplay currentLayers: @escaping @MainActor () -> [HwpPageLayer]
    ) -> (cache: HwpImageCache, provider: HwpPageImageProvider)? {
        guard let document, !document.imageStore.isEmpty else { return nil }
        let cache = HwpImageCache()
        let provider = HwpPageImageProvider(store: document.imageStore, cache: cache)
        provider.onImageResolved = { key in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for layer in currentLayers() where layer.containsImageReference(key) {
                        layer.setNeedsDisplay()
                    }
                }
            }
        }
        // 만석 드롭 요청을 재시도시키려 전체 가시 레이어를 재드로우한다 — 유일
        // 이미지가 드롭돼 키별 재드로우를 못 받던 레이어도 복구된다 (R42 #1).
        provider.onDeferredCapacityAvailable = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    currentLayers().forEach { $0.setNeedsDisplay() }
                }
            }
        }
        return (cache, provider)
    }

    // MARK: - 미지원 요소 알림

    static func notifyUnsupportedElements(
        in document: HwpDocument?,
        to callback: ((HwpUnsupportedElement) -> Void)?
    ) {
        document?.unsupportedElements.forEach { callback?($0) }
    }

    // MARK: - 선택 하이라이트 오버레이

    /// 하이라이트를 페이지 레이어의 sublayer로 부착해 조상 flip 기하를
    /// 상속한다 (top-down rect 직접 대입, 자체 flip 금지). 빈 페이지와
    /// 화면 밖 페이지의 오버레이는 청소한다.
    static func updateSelectionOverlays(
        pageLayers: [Int: HwpPageLayer],
        selectionLayers: inout [Int: CAShapeLayer],
        highlightRects: (Int) -> [CGRect],
        fillColor: CGColor
    ) {
        updateHighlightOverlays(
            pageLayers: pageLayers,
            overlayLayers: &selectionLayers,
            highlightRects: highlightRects,
            fillColor: fillColor,
            zPosition: HwpOverlayZ.selection
        )
    }

    /// 하이라이트 오버레이 갱신의 일반형 — 선택(#5)과 검색(#75)이 공유한다.
    ///
    /// `zPosition`이 인자인 이유: 부착은 `addSublayer` 한 줄뿐이고 이미 붙어
    /// 있으면 다시 붙이지 않으므로, 명시하지 않으면 **첫 부착 순서가 그대로
    /// z-순서로 고착된다**. 가상화로 축출→재실체화한 페이지만 순서가 다시
    /// 정해져 같은 화면에서 페이지마다 겹침 색이 뒤바뀐다.
    ///
    /// `fillColor`를 **매 호출** 갱신하는 이유: 문서를 교체해도 딕셔너리가
    /// 비워지지 않아 오버레이가 재사용되는데, 생성 분기에서만 색을 대입하면
    /// 재사용된 오버레이가 옛 색을 그대로 들고 다시 붙는다. 색이 공개
    /// 설정(`HwpSearchHighlightStyle`)이 된 이상 이 경로가 실제로 밟힌다.
    static func updateHighlightOverlays(
        pageLayers: [Int: HwpPageLayer],
        overlayLayers: inout [Int: CAShapeLayer],
        highlightRects: (Int) -> [CGRect],
        fillColor: CGColor,
        zPosition: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (pageIndex, pageLayer) in pageLayers {
            let rects = highlightRects(pageIndex)
            if rects.isEmpty {
                overlayLayers[pageIndex]?.removeFromSuperlayer()
                overlayLayers[pageIndex] = nil
                continue
            }
            let overlay = overlayLayers[pageIndex] ?? {
                let layer = CAShapeLayer()
                overlayLayers[pageIndex] = layer
                return layer
            }()
            overlay.fillColor = fillColor
            overlay.zPosition = zPosition
            // 오버레이는 벡터 path라 페이지 레이어와 같은 배율로 래스터해야
            // Retina·확대에서 가장자리가 뭉개지지 않는다.
            overlay.contentsScale = pageLayer.contentsScale
            if overlay.superlayer !== pageLayer {
                overlay.removeFromSuperlayer()
                pageLayer.addSublayer(overlay)
            }
            overlay.frame = pageLayer.bounds
            let path = CGMutablePath()
            for rect in rects {
                path.addRect(rect)
            }
            overlay.path = path
        }
        // 화면 밖으로 나간 페이지의 오버레이 정리
        for (pageIndex, overlay) in overlayLayers where pageLayers[pageIndex] == nil {
            overlay.removeFromSuperlayer()
            overlayLayers[pageIndex] = nil
        }
        CATransaction.commit()
    }
}

/// 페이지 레이어 sublayer의 겹침 순서.
///
/// 선택이 가장 위인 이유: 사용자가 직접 드래그해 만든 것이라 검색이 칠한
/// 자동 하이라이트에 가려지면 안 된다.
enum HwpOverlayZ {
    static let searchMatch: CGFloat = 10
    static let currentSearchMatch: CGFloat = 20
    static let selection: CGFloat = 30
}

/// 인덱스가 범위 밖이면 nil — iOS 뷰의 로컬 재정의를 모듈 공용으로 승격.
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
