import HwpKitCore
@testable import HwpKitNative
import Nimble
import QuartzCore
import XCTest

/// macOS/iOS 문서 뷰 공통 헬퍼 (플랫폼 중립 — 양쪽 테스트 번들에서 컴파일).
@MainActor
final class HwpDocumentViewSupportTests: XCTestCase {
    // MARK: - effectiveContentsScale

    func testEffectiveContentsScaleFollowsZoom() {
        let unzoomed = HwpDocumentViewSupport.effectiveContentsScale(base: 2, zoomScale: 1)
        let zoomed = HwpDocumentViewSupport.effectiveContentsScale(base: 2, zoomScale: 3)

        expect(unzoomed) == 2
        expect(zoomed) == 6
    }

    func testEffectiveContentsScaleKeepsBaseWhenZoomedOut() {
        // 축소 상태에서 해상도를 낮추지 않는다 (재확대 시 흐릿함 방지)
        let scale = HwpDocumentViewSupport.effectiveContentsScale(base: 2, zoomScale: 0.25)

        expect(scale) == 2
    }

    func testEffectiveContentsScaleCapsAtFourTimesBase() {
        let scale = HwpDocumentViewSupport.effectiveContentsScale(base: 2, zoomScale: 10)

        expect(scale) == 8
    }

    // MARK: - boundedContentsScale (래스터 백킹 안전 캡)

    func testBoundedContentsScaleKeepsNormalPageUnchanged() {
        // 레터 크기는 어떤 배율에서도 캡을 밑돌아 해상도가 그대로다.
        let letter = CGSize(width: 612, height: 792)
        expect(HwpDocumentViewSupport.boundedContentsScale(3, for: letter)) == 3
    }

    func testBoundedContentsScaleCapsHugeLayerBelowAxisLimit() {
        // 한 축이 81,920pt를 넘는 긴 메모 패널: 최소 배율(0.1)이 축 캡을 덮으면
        // 8192px를 넘는 백킹이 생긴다 — 캡이 이겨 축 픽셀이 8192 이하여야 한다 (P1).
        let tall = CGSize(width: 185, height: 480_000)
        let scale = HwpDocumentViewSupport.boundedContentsScale(2, for: tall)
        expect(scale * tall.height) <= 8192
        expect(scale * tall.width) <= 8192
    }

    // MARK: - isProgressiveUpdate (프로그레시브 스냅샷 판정)

    private func makeDocument(pageCount: Int, loadToken: UUID?) -> HwpDocument {
        let pages = (0 ..< pageCount).map { index in
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [],
                pageNumber: index + 1
            )
        }
        return HwpDocument(
            pages: pages,
            metadata: HwpDocumentMetadata(pageCount: pageCount, loadToken: loadToken),
            unsupportedElements: []
        )
    }

    func testSameTokenWithPageGrowthIsProgressive() {
        let token = UUID()
        let old = makeDocument(pageCount: 1, loadToken: token)
        let new = makeDocument(pageCount: 3, loadToken: token)

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)) == true
    }

    func testSameTokenWithEqualPageCountIsProgressive() {
        // 페이지 수 유지 (마지막 스냅샷 재통지)도 증분으로 취급
        let token = UUID()
        let old = makeDocument(pageCount: 2, loadToken: token)
        let new = makeDocument(pageCount: 2, loadToken: token)

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)) == true
    }

    func testDifferentTokenIsNotProgressive() {
        let old = makeDocument(pageCount: 1, loadToken: UUID())
        let new = makeDocument(pageCount: 3, loadToken: UUID())

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)) == false
    }

    func testNilTokenIsNotProgressive() {
        let old = makeDocument(pageCount: 1, loadToken: nil)
        let new = makeDocument(pageCount: 3, loadToken: nil)

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)) == false
    }

    func testPageShrinkIsNotProgressive() {
        let token = UUID()
        let old = makeDocument(pageCount: 3, loadToken: token)
        let new = makeDocument(pageCount: 1, loadToken: token)

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)) == false
    }

    func testNilDocumentIsNotProgressive() {
        let token = UUID()
        let document = makeDocument(pageCount: 1, loadToken: token)

        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: nil, to: document)) == false
        expect(HwpDocumentViewSupport.isProgressiveUpdate(from: document, to: nil)) == false
    }

    // MARK: - updateContentsScale (메모 패널 그룹 포함 — 양 플랫폼 통일)

    func testUpdateContentsScaleUpdatesEveryLayerGroup() {
        let pageLayer = HwpPageLayer()
        let panelLayer = HwpPageLayer()
        pageLayer.contentsScale = 2
        panelLayer.contentsScale = 2

        HwpDocumentViewSupport.updateContentsScale(
            of: [pageLayer], [panelLayer], scale: 4
        )

        expect(pageLayer.contentsScale) == 4
        expect(panelLayer.contentsScale) == 4
    }

    // MARK: - updateSelectionOverlays

    private let highlightFill = CGColor(red: 0, green: 0, blue: 1, alpha: 0.3)

    private func makePageLayer() -> HwpPageLayer {
        let layer = HwpPageLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 595, height: 842)
        return layer
    }

    func testSelectionOverlayAttachesToPageLayer() {
        let pageLayer = makePageLayer()
        var selectionLayers: [Int: CAShapeLayer] = [:]

        HwpDocumentViewSupport.updateSelectionOverlays(
            pageLayers: [0: pageLayer],
            selectionLayers: &selectionLayers,
            highlightRects: { _ in [CGRect(x: 10, y: 10, width: 100, height: 20)] },
            fillColor: highlightFill
        )

        let overlay = selectionLayers[0]
        expect(overlay).toNot(beNil())
        expect(overlay?.superlayer) === pageLayer
        expect(overlay?.frame) == pageLayer.bounds
        expect(overlay?.fillColor?.alpha) == 0.3
        expect(overlay?.path?.isEmpty) == false
    }

    func testSelectionOverlayIsReusedAcrossUpdates() {
        let pageLayer = makePageLayer()
        var selectionLayers: [Int: CAShapeLayer] = [:]
        let update = {
            HwpDocumentViewSupport.updateSelectionOverlays(
                pageLayers: [0: pageLayer],
                selectionLayers: &selectionLayers,
                highlightRects: { _ in [CGRect(x: 10, y: 10, width: 100, height: 20)] },
                fillColor: self.highlightFill
            )
        }

        update()
        let first = selectionLayers[0]
        update()

        expect(selectionLayers[0]) === first
        expect(pageLayer.sublayers?.count) == 1
    }

    func testEmptyRectsRemoveOverlay() {
        let pageLayer = makePageLayer()
        var selectionLayers: [Int: CAShapeLayer] = [:]
        HwpDocumentViewSupport.updateSelectionOverlays(
            pageLayers: [0: pageLayer],
            selectionLayers: &selectionLayers,
            highlightRects: { _ in [CGRect(x: 10, y: 10, width: 100, height: 20)] },
            fillColor: highlightFill
        )
        let overlay = selectionLayers[0]

        HwpDocumentViewSupport.updateSelectionOverlays(
            pageLayers: [0: pageLayer],
            selectionLayers: &selectionLayers,
            highlightRects: { _ in [] },
            fillColor: highlightFill
        )

        expect(selectionLayers[0]).to(beNil())
        expect(overlay?.superlayer).to(beNil())
    }

    func testOffscreenPageOverlayIsCleaned() {
        // 가상화로 페이지 레이어가 사라지면 그 페이지의 오버레이도 청소
        let pageLayer = makePageLayer()
        var selectionLayers: [Int: CAShapeLayer] = [:]
        HwpDocumentViewSupport.updateSelectionOverlays(
            pageLayers: [3: pageLayer],
            selectionLayers: &selectionLayers,
            highlightRects: { _ in [CGRect(x: 10, y: 10, width: 100, height: 20)] },
            fillColor: highlightFill
        )
        let overlay = selectionLayers[3]

        HwpDocumentViewSupport.updateSelectionOverlays(
            pageLayers: [:],
            selectionLayers: &selectionLayers,
            highlightRects: { _ in [] },
            fillColor: highlightFill
        )

        expect(selectionLayers).to(beEmpty())
        expect(overlay?.superlayer).to(beNil())
    }
}
