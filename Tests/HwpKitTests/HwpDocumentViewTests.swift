@testable import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import SwiftUI
import XCTest

#if os(macOS)
    import AppKit
#endif

final class HwpDocumentViewTests: XCTestCase {
    @MainActor
    func testDocumentViewBodyCompiles() {
        let view = HwpDocumentView(document: HwpDocument.empty)

        expect(String(describing: type(of: view.body))).toNot(beEmpty())
    }

    /// Int.min 페이지 바인딩(상태 복원)은 뺄셈을 먼저 하면 오버플로 트랩 —
    /// 클램프가 먼저여야 하고, 정상 값 산식은 종전과 동일해야 한다 (R57 #1).
    func testScrollPageIndexClampsBeforeSubtracting() {
        expect(hwpScrollPageIndex(fromOneBased: Int.min)) == 0
        expect(hwpScrollPageIndex(fromOneBased: -1)) == 0
        expect(hwpScrollPageIndex(fromOneBased: 0)) == 0
        expect(hwpScrollPageIndex(fromOneBased: 1)) == 0
        expect(hwpScrollPageIndex(fromOneBased: 7)) == 6
        expect(hwpScrollPageIndex(fromOneBased: Int.max)) == Int.max - 1
    }

    /// NaN/±inf 바인딩은 톨러런스 비교(NaN 비교 전부 false)에 앞서 writeback
    /// 대상이어야 정규화·핀치 echo가 복구할 수 있다 (R58 #1).
    func testZoomWritebackPredicatesRecoverNonFiniteBindings() {
        expect(hwpZoomNeedsWriteback(current: .nan, native: 1.0)) == true
        expect(hwpZoomNeedsWriteback(current: .infinity, native: 1.0)) == true
        expect(hwpZoomNeedsWriteback(current: 1.0, native: 1.0005)) == false
        expect(hwpZoomNeedsWriteback(current: 1.0, native: 1.5)) == true

        expect(hwpZoomBindingUnchanged(.nan, .nan)) == true
        expect(hwpZoomBindingUnchanged(.infinity, .infinity)) == true
        expect(hwpZoomBindingUnchanged(1.0, 1.0005)) == true
        expect(hwpZoomBindingUnchanged(1.0, 2.0)) == false
        expect(hwpZoomBindingUnchanged(.nan, 1.0)) == false
    }

    /// NaN 바인딩 상태에서 finite 핀치 업데이트는 버려지지 않고 바인딩을
    /// 복구해야 한다 (R58 #1).
    @MainActor
    func testZoomChangeRecoversNaNBinding() {
        var zoom = CGFloat.nan
        let coordinator = HwpDocumentCoordinator(
            zoomScale: Binding(get: { zoom }, set: { zoom = $0 }),
            currentPage: nil,
            onHyperlinkTapped: nil,
            onUnsupportedElement: nil
        )

        coordinator.handleZoomChanged(1.5)

        expect(zoom) == 1.5
    }

    @MainActor
    func testCoordinatorDocumentGenerationTracksNilTokenReplacement() {
        // nil loadToken(직접 구성) 문서 교체도 세대가 증가해 stale 지연 작업을
        // 구분하고, 같은 문서 재등록은 멱등이어야 한다 (#4).
        let coordinator = HwpDocumentCoordinator(
            zoomScale: nil,
            currentPage: nil,
            onHyperlinkTapped: nil,
            onUnsupportedElement: nil
        )
        func makeDocument(pageCount: Int) -> HwpDocument {
            HwpDocument(
                pages: (0 ..< pageCount).map { index in
                    HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [],
                        pageNumber: index + 1
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: pageCount),
                unsupportedElements: []
            )
        }
        let documentA = makeDocument(pageCount: 2)
        let documentB = makeDocument(pageCount: 10)

        let generationA = coordinator.registerDocument(documentA)
        expect(coordinator.registerDocument(documentA)) == generationA
        let generationB = coordinator.registerDocument(documentB)
        expect(generationB) != generationA
    }

    @MainActor
    func testPageChangeWritebackSuppressedWhileApplyingBinding() {
        var currentPage = 50
        let coordinator = HwpDocumentCoordinator(
            zoomScale: nil,
            currentPage: Binding(get: { currentPage }, set: { currentPage = $0 }),
            onHyperlinkTapped: nil,
            onUnsupportedElement: nil
        )
        // 첫 프로그레시브 스냅샷(page 0)의 echo는 적용 구간이라 무시 — 요청
        // 페이지(50)가 유지돼 이후 스냅샷에서 유실되지 않는다 (P2).
        coordinator.applyingBinding {
            coordinator.handlePageChanged(0)
        }
        expect(currentPage) == 50
        // 구간 밖 실제 스크롤은 바인딩에 반영한다.
        coordinator.handlePageChanged(24)
        expect(currentPage) == 25
    }

    /// 줌 echo도 페이지와 동일하게 적용 구간에서 억제된다 — 범위 밖 값의
    /// 네이티브 클램프 재보고가 update 중 바인딩을 쓰지 않는다 (R38 #3).
    func testZoomWritebackSuppressedWhileApplyingBinding() {
        var zoom: CGFloat = 9.0
        let coordinator = HwpDocumentCoordinator(
            zoomScale: Binding(get: { zoom }, set: { zoom = $0 }),
            currentPage: nil,
            onHyperlinkTapped: nil,
            onUnsupportedElement: nil
        )
        coordinator.applyingBinding {
            coordinator.handleZoomChanged(5.0)
        }
        expect(zoom) == 9.0
        coordinator.handleZoomChanged(2.0)
        expect(zoom) == 2.0
    }

    #if os(macOS)
        @MainActor
        func testOutOfRangePageBindingNormalizedForCompleteDocument() {
            // 최종 문서(isComplete)에 없는 페이지 요청(3쪽 문서에 100)은 클램프
            // 값으로 바인딩이 되돌아온다 — 억제된 echo 탓에 무효 바인딩이 남지
            // 않게 한다 (#6). 프로그레시브 중간 스냅샷은 정규화하지 않는다.
            var currentPage = 100
            let pages = (0 ..< 3).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [],
                    pageNumber: index + 1
                )
            }
            let document = HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: 3, loadToken: UUID()),
                unsupportedElements: []
            )
            let view = HwpDocumentView(
                document: document,
                currentPage: Binding(get: { currentPage }, set: { currentPage = $0 })
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            hostingView.layoutSubtreeIfNeeded()

            // 정규화는 state-during-update를 피해 업데이트 밖에서 반영된다 —
            // 메인 런루프를 돌려 지연 쓰기를 기다린다 (P2).
            expect(currentPage).toEventually(equal(3), timeout: .seconds(2))
        }

        /// fit 명령의 왕복 계약 (#78): 호스트가 값을 넣으면 (1) 뷰가 배율을
        /// 맞추고 (2) 그 배율이 `zoomScale` 바인딩으로 돌아오며 (3) 명령
        /// 바인딩은 idle(nil)로 되돌아간다.
        ///
        /// 이 경로가 **지연 적용**까지 함께 증명한다 — `makeNSView` 는 frame 0
        /// 에서 배선되므로 그 시점에는 뷰포트가 없고, 뷰가 예약해 뒀다가 첫
        /// 실측 `layout()` 에서 맞춘다. 세 단언 모두 업데이트 밖에서 반영되므로
        /// 메인 런루프를 돌려 기다린다 (페이지 정규화 테스트와 같은 형태).
        @MainActor
        func testFitZoomCommandAppliesAndReturnsToIdle() {
            var zoomScale = CGFloat(1.0)
            var fitZoom: HwpZoomFit? = .width
            let pages = (0 ..< 3).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [],
                    pageNumber: index + 1
                )
            }
            let document = HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: 3, loadToken: UUID()),
                unsupportedElements: []
            )
            let view = HwpDocumentView(
                document: document,
                zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
                fitZoom: Binding(get: { fitZoom }, set: { fitZoom = $0 })
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            hostingView.layoutSubtreeIfNeeded()

            guard let nativeView = hostingView.firstSubview(of: HwpDocumentNSView.self) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }

            expect(fitZoom).toEventually(beNil(), timeout: .seconds(2))
            expect(nativeView.zoomScale).toEventuallyNot(beCloseTo(1.0), timeout: .seconds(2))
            expect(zoomScale).toEventually(
                beCloseTo(nativeView.zoomScale, within: 0.001), timeout: .seconds(2)
            )
            // 320pt 창에 595pt 캔버스 — 폭 맞춤은 축소여야 한다.
            expect(nativeView.zoomScale) < 1.0
        }

        private func makeFitProbeDocument(pageHeight: CGFloat) -> HwpDocument {
            HwpDocument(
                pages: (0 ..< 3).map { index in
                    HwpPage(
                        size: CGSize(width: 595, height: pageHeight),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [],
                        pageNumber: index + 1
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: 3, loadToken: UUID()),
                unsupportedElements: []
            )
        }

        /// fit 명령의 세대 소유권 정책 (#107 리뷰).
        ///
        /// 네 갈래를 한자리에서 고정한다 — 새 명령은 적용, **같은 값이 세대를 넘으면**
        /// 옛 문서를 향한 것이라 거부, 값이 다르면 새 요청이라 적용, nil 을 관측하면
        /// 기록을 지워 다음 요청이 다시 살아난다. 셋째가 없으면 "모든 교체를 거부"하는
        /// 순진한 구현도 통과해 "새 문서를 열자마자 맞춤"이 조용히 죽는다.
        @MainActor
        func testFitCommandOwnershipFollowsDocumentGeneration() {
            let coordinator = HwpDocumentCoordinator(
                zoomScale: nil, currentPage: nil,
                onHyperlinkTapped: nil, onUnsupportedElement: nil
            )
            let first = makeFitProbeDocument(pageHeight: 842)
            let second = makeFitProbeDocument(pageHeight: 2000)
            let third = makeFitProbeDocument(pageHeight: 1200)

            _ = coordinator.registerDocument(first)
            expect(coordinator.fitToApply(.page)) == HwpZoomFit.page

            _ = coordinator.registerDocument(second)
            expect(coordinator.fitToApply(.page)).to(beNil())
            expect(coordinator.fitToApply(.width)) == HwpZoomFit.width

            expect(coordinator.fitToApply(nil)).to(beNil())
            _ = coordinator.registerDocument(third)
            expect(coordinator.fitToApply(.width)) == HwpZoomFit.width
        }

        /// 옛 문서를 향한 fit 명령이 교체본의 배율을 정하지 않는다 (#107 리뷰).
        ///
        /// 소비 Task 가 돌기 전에 문서가 바뀌면 `configure` 가 같은 non-nil 바인딩을
        /// 다시 보는데, 세대 비교가 명령을 **지우는** 쪽에만 있어 A 의 `.page` 가 B 에
        /// 적용됐다 (실측: 배율이 B 의 쪽 맞춤 0.3 으로, `.page` 라 스크롤도 B 의 쪽
        /// 머리로). 네이티브 뷰가 예약을 교체에서 버리는 가드를 래퍼가 명령을 다시
        /// 건네 우회하던 것이다. 명령이 결국 비워지는 것은 그대로여야 한다.
        @MainActor
        func testStaleFitCommandDoesNotSetTheReplacementScale() {
            var zoomScale = CGFloat(1.0)
            var fitZoom: HwpZoomFit? = .page
            let zoom = Binding(get: { zoomScale }, set: { zoomScale = $0 })
            let fit = Binding(get: { fitZoom }, set: { fitZoom = $0 })

            let hostingView = NSHostingView(
                rootView: HwpDocumentView(
                    document: makeFitProbeDocument(pageHeight: 842),
                    zoomScale: zoom,
                    fitZoom: fit
                )
            )
            hostingView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            hostingView.layoutSubtreeIfNeeded()
            guard let nativeView = hostingView.firstSubview(of: HwpDocumentNSView.self) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }
            expect(nativeView.zoomScale) < 1.0

            hostingView.rootView = HwpDocumentView(
                document: makeFitProbeDocument(pageHeight: 2000),
                zoomScale: zoom,
                fitZoom: fit
            )
            hostingView.layoutSubtreeIfNeeded()

            // 800x600 뷰포트 / 595x2000 쪽 → B 의 쪽 맞춤은 min(800/595, 600/2000) = 0.3
            expect(nativeView.zoomScale).toNot(beCloseTo(0.3, within: 0.0001))
            expect(fitZoom).toEventually(beNil(), timeout: .seconds(2))
        }

        @MainActor
        func testBindingsPropagateThroughNativeWrapper() {
            var zoomScale = CGFloat(1.75)
            var currentPage = 0
            let view = HwpDocumentView(
                document: HwpDocument.empty,
                zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
                currentPage: Binding(get: { currentPage }, set: { currentPage = $0 })
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            hostingView.layoutSubtreeIfNeeded()

            guard let nativeView = hostingView.firstSubview(of: HwpDocumentNSView.self) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }

            expect(nativeView.zoomScale).to(beCloseTo(1.75))

            nativeView.updateVisiblePages(range: 2 ..< 3)

            expect(currentPage) == 3
        }
    #endif
}

#if os(macOS)
    private extension NSView {
        func firstSubview<T: NSView>(of type: T.Type) -> T? {
            if let match = self as? T {
                return match
            }

            for subview in subviews {
                if let match = subview.firstSubview(of: type) {
                    return match
                }
            }

            return nil
        }
    }
#endif
