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

    /// 배율이 달라진 레이어만 재래스터한다. 메모 패널 레이어 그룹도 함께
    /// 넘겨 페이지와 같은 해상도를 유지한다 (양 플랫폼 공통).
    static func updateContentsScale(
        of layerGroups: [HwpPageLayer]...,
        scale: CGFloat
    ) {
        for layers in layerGroups {
            for layer in layers where layer.contentsScale != scale {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
            }
        }
    }

    // MARK: - 페이지 레이어 chrome

    /// 페이지 종이 배경 + 그림자 + 래스터 해상도 (양 플랫폼 동일 스펙).
    static func decoratePageLayer(_ layer: HwpPageLayer, contentsScale: CGFloat) {
        layer.backgroundColor = PlatformColor.white.cgColor
        layer.shadowColor = PlatformColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.contentsScale = contentsScale
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
        panelLayer.frame = CGRect(
            x: pageFrame.maxX,
            y: pageFrame.minY,
            width: panel.width,
            height: pageFrame.height
        )
        panelLayer.pageHeight = pageFrame.height
        panelLayer.backgroundColor = nil
        panelLayer.contentsScale = contentsScale
        panelLayer.paintList = panel.paintList
        return panelLayer
    }

    // MARK: - 이미지 공급자

    /// 문서별 새 캐시 + 공급자를 만든다 — binItemId는 문서-로컬 키이므로
    /// 캐시를 문서 간에 공유하면 다른 문서의 이미지가 재사용된다.
    /// 디코딩 완료 시 main queue에서 `currentLayers()`가 돌려준 레이어 중
    /// 해당 이미지를 참조하는 것만 다시 그린다.
    /// 이미지 없는 문서는 nil — 호출부는 공급자만 비우고 캐시는 유지한다.
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (pageIndex, pageLayer) in pageLayers {
            let rects = highlightRects(pageIndex)
            if rects.isEmpty {
                selectionLayers[pageIndex]?.removeFromSuperlayer()
                selectionLayers[pageIndex] = nil
                continue
            }
            let overlay = selectionLayers[pageIndex] ?? {
                let layer = CAShapeLayer()
                layer.fillColor = fillColor
                selectionLayers[pageIndex] = layer
                return layer
            }()
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
        for (pageIndex, overlay) in selectionLayers where pageLayers[pageIndex] == nil {
            overlay.removeFromSuperlayer()
            selectionLayers[pageIndex] = nil
        }
        CATransaction.commit()
    }
}

/// 인덱스가 범위 밖이면 nil — iOS 뷰의 로컬 재정의를 모듈 공용으로 승격.
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
