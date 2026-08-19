import HwpKitCore
@testable import HwpKitNative
import Nimble
import QuartzCore
import XCTest

/// 프로덕션 기본 배율 한계 — `fitZoomScale` 은 이 값을 **인자로** 받으므로
/// 테스트도 같은 자리에서 한 번만 적는다 (Nimble `expect` 가 autoclosure 라
/// 인스턴스 프로퍼티로 두면 호출마다 `self.` 가 붙는다).
private let zoomRange: ClosedRange<CGFloat> = 0.25 ... 5.0

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

    /// **비-Retina 호스트(base 1)도 지원 대상이다.** 창에 붙지 않은 뷰는
    /// `NSScreen` 으로 폴백하는데 GitHub macOS 러너가 1x 를 보고하므로, zoom 이
    /// 1 이면 갱신 결과도 1 이다 — "배율이 1 을 넘는다"를 전제한 뷰 테스트가
    /// 거기서 깨진다 (#99 첫 CI 의 실제 실패). zoom 을 주면 base 와 무관하게
    /// 1 을 넘으므로, 그것이 그 테스트들이 zoom 을 먼저 거는 근거다.
    func testEffectiveContentsScaleOnNonRetinaBase() {
        expect(HwpDocumentViewSupport.effectiveContentsScale(base: 1, zoomScale: 1)) == 1
        expect(HwpDocumentViewSupport.effectiveContentsScale(base: 1, zoomScale: 2)) == 2
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

    // MARK: - fitZoomScale (#78)

    /// 폭 맞춤은 캔버스 폭만 본다 — 캔버스 폭 × 배율 = 뷰포트 폭.
    func testFitWidthScalesCanvasToViewportWidth() {
        let scale = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: 1190, height: 842),
            viewport: CGSize(width: 595, height: 800),
            fit: .width,
            range: zoomRange
        )

        expect(scale) == 0.5
    }

    /// 쪽 맞춤은 두 축 중 **더 빡빡한** 쪽을 고른다. 같은 입력에서 폭 맞춤과
    /// 결과가 갈리는 것이 두 모드가 실제로 다르다는 증거다.
    func testFitPageTakesTheTighterAxis() {
        let content = CGSize(width: 595, height: 842)
        let viewport = CGSize(width: 595, height: 421)

        let page = HwpDocumentViewSupport.fitZoomScale(
            content: content, viewport: viewport, fit: .page, range: zoomRange
        )
        let width = HwpDocumentViewSupport.fitZoomScale(
            content: content, viewport: viewport, fit: .width, range: zoomRange
        )

        expect(page) == 0.5
        expect(width) == 1.0
    }

    func testFitPageTakesWidthWhenWidthIsTighter() {
        let scale = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: 1190, height: 842),
            viewport: CGSize(width: 595, height: 8420),
            fit: .page,
            range: zoomRange
        )

        expect(scale) == 0.5
    }

    /// 폭 맞춤은 높이를 **읽지 않는다** — 높이가 퇴화해도 결과가 나온다.
    /// 쪽 맞춤만 높이 가드를 탄다.
    func testFitWidthIgnoresDegenerateHeight() {
        let content = CGSize(width: 595, height: 0)
        let viewport = CGSize(width: 1190, height: 0)

        expect(
            HwpDocumentViewSupport.fitZoomScale(
                content: content, viewport: viewport, fit: .width, range: zoomRange
            )
        ) == 2.0
        expect(
            HwpDocumentViewSupport.fitZoomScale(
                content: content, viewport: viewport, fit: .page, range: zoomRange
            )
        ).to(beNil())
    }

    /// 배율 한계는 **인자로 받은 것**을 쓴다 — 0.25...5.0의 네 번째 사본을
    /// 만들지 않으려는 설계라, 호출부가 다른 범위를 주면 그 범위로 클램프된다.
    func testFitZoomClampsToGivenRange() {
        let tiny = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: 1, height: 1),
            viewport: CGSize(width: 800, height: 600),
            fit: .page,
            range: zoomRange
        )
        let huge = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: 100_000, height: 100_000),
            viewport: CGSize(width: 800, height: 600),
            fit: .page,
            range: zoomRange
        )
        let narrowRange = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: 1, height: 1),
            viewport: CGSize(width: 800, height: 600),
            fit: .page,
            range: 1.0 ... 2.0
        )

        expect(tiny) == 5.0
        expect(huge) == 0.25
        expect(narrowRange) == 2.0
    }

    /// 퇴화 입력은 **nil** 이다. 0을 그대로 흘리면 하류가 잡아 주지 않는다 —
    /// `HwpZoomControls.sanitized`는 0을 finite로 보아 1.0 폴백이 아니라
    /// 하한 0.25로 클램프하고, NaN은 macOS 배율 setter를 통과한 뒤 조용히
    /// no-op이 된다. 둘 다 사용자에게는 원인 없는 오작동으로 보인다.
    func testFitZoomRejectsDegenerateExtents() {
        let ok = CGSize(width: 595, height: 842)
        func scale(_ content: CGSize, _ viewport: CGSize, _ fit: HwpZoomFit) -> CGFloat? {
            HwpDocumentViewSupport.fitZoomScale(
                content: content, viewport: viewport, fit: fit, range: zoomRange
            )
        }

        for fit in HwpZoomFit.allCases {
            // 아직 실측되지 않은 뷰포트 (SwiftUI makeUIView / 창에 붙기 전)
            expect(scale(ok, .zero, fit)).to(beNil())
            // 문서가 없어 캔버스가 서지 않은 상태
            expect(scale(.zero, ok, fit)).to(beNil())
            // 조작 문서·상태 복원이 흘려 넣는 비-finite
            expect(scale(CGSize(width: CGFloat.nan, height: 842), ok, fit)).to(beNil())
            expect(scale(CGSize(width: CGFloat.infinity, height: 842), ok, fit)).to(beNil())
            expect(scale(ok, CGSize(width: -CGFloat.infinity, height: 600), fit)).to(beNil())
            // 음수 치수도 배율을 뒤집으므로 막는다
            expect(scale(CGSize(width: -595, height: 842), ok, fit)).to(beNil())
        }
        // 쪽 맞춤만 높이를 읽으므로 높이 퇴화는 그쪽에서만 nil 이고, 폭 맞춤은
        // 같은 입력에서 배율을 낸다 — 두 모드의 가드 범위가 다르다는 증거다.
        expect(scale(CGSize(width: 595, height: CGFloat.nan), ok, .page)).to(beNil())
        expect(scale(ok, CGSize(width: 800, height: 0), .page)).to(beNil())
        expect(scale(ok, CGSize(width: 800, height: -600), .page)).to(beNil())
        expect(scale(ok, CGSize(width: 800, height: -600), .width)).toNot(beNil())
    }

    /// 유한한 두 양수의 나눗셈도 **언더플로로 0** 이 될 수 있다. 0을 배율로
    /// 내보내면 클램프가 하한 0.25로 살려 내 "아무 안내 없는 축소"가 되므로
    /// 몫에도 같은 가드를 건다.
    func testFitZoomRejectsUnderflowedQuotient() {
        let scale = HwpDocumentViewSupport.fitZoomScale(
            content: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 842),
            viewport: CGSize(width: CGFloat.leastNonzeroMagnitude, height: 600),
            fit: .width,
            range: zoomRange
        )

        expect(scale).to(beNil())
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

    // MARK: - imageReferences (가시 작업셋 pin 갱신)

    private func makeImageDocument(keysByPage: [[UInt32]]) -> HwpDocument {
        let pages = keysByPage.enumerated().map { index, keys in
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [],
                pageNumber: index + 1,
                paintList: HwpPaintList(commands: keys.map { key in
                    .drawImageReference(
                        binItemId: key,
                        rect: CGRect(x: 0, y: 0, width: 10, height: 10)
                    )
                })
            )
        }
        return HwpDocument(
            pages: pages,
            metadata: HwpDocumentMetadata(pageCount: pages.count),
            unsupportedElements: []
        )
    }

    func testImageReferencesUnionsEveryPageInRange() {
        // 범위의 한 페이지만 pin하면 나머지 가시 페이지 이미지가 축출 대상이 된다
        let document = makeImageDocument(keysByPage: [[1], [2, 3], [4]])

        let variants = HwpDocumentViewSupport.imageReferences(in: document, pageRange: 0 ..< 3)

        expect(variants) == Set([1, 2, 3, 4].map { HwpPageImageProvider.variantKey($0, nil) })
    }

    func testImageReferencesSkipsOutOfBoundsPages() {
        // 가상화는 문서 끝을 넘긴 범위를 넘겨 온다 — 있는 페이지만 모은다
        let document = makeImageDocument(keysByPage: [[1], [2]])

        let variants = HwpDocumentViewSupport.imageReferences(in: document, pageRange: 1 ..< 9)

        expect(variants) == [HwpPageImageProvider.variantKey(2, nil)]
        expect(HwpDocumentViewSupport.imageReferences(in: nil, pageRange: 0 ..< 2)).to(beEmpty())
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
