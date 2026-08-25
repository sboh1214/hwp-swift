#if os(iOS)
    import CoreGraphics
    import CoreText
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import UIKit
    import UniformTypeIdentifiers
    import XCTest

    /// iOS 선택 — 하이라이트 오버레이와 **끝점 핸들**(#84).
    ///
    /// macOS의 `HwpDocumentNSViewSelectionTests`와 대칭이다. 그전까지 iOS
    /// 선택을 겨냥한 테스트는 `testAutoscrollStepZonesAndClamp` 하나뿐이었다.
    ///
    /// 오버레이·핸들 단언은 "보이는가"를 증명하지 못한다 (`HwpKitNative/
    /// AGENTS.md`의 사고 기록) — 시뮬레이터 육안 확인과 **함께** 읽어야 한다.
    @MainActor
    final class HwpDocumentUIViewSelectionTests: XCTestCase {
        private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private func makeDocument(
            pageHeight: CGFloat = 842,
            pageCount: Int = 1
        ) -> HwpDocument {
            let pages = (0 ..< pageCount).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: pageHeight),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [AnyHwpBlock(
                        frame: CGRect(x: 50, y: 100, width: 300, height: 20),
                        kind: .text,
                        attributedString: NSAttributedString(
                            string: "Hello world",
                            attributes: [
                                kCTFontAttributeName as NSAttributedString.Key: font,
                            ]
                        )
                    )],
                    pageNumber: index + 1
                )
            }
            return HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: pageCount),
                unsupportedElements: []
            )
        }

        private func makeView(
            pageHeight: CGFloat = 842,
            pageCount: Int = 1
        ) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 800)
            )
            view.document = makeDocument(pageHeight: pageHeight, pageCount: pageCount)
            view.layoutIfNeeded()
            return view
        }

        private func select(_ view: HwpDocumentUIView, from start: Int, to end: Int) {
            view.selectionController.begin(at: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: start
            ))
            view.selectionController.extend(to: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: end
            ))
        }

        // MARK: - 하이라이트 오버레이 (macOS 스위트와 대칭)

        func testSelectionAttachesOverlayToPageLayer() {
            let view = makeView()

            select(view, from: 0, to: 5)

            let overlay = view.selectionLayers[0]
            expect(overlay).toNot(beNil())
            expect(overlay?.superlayer) === view.pageLayers[0]
            expect(overlay?.path?.isEmpty) == false
        }

        func testClearRemovesOverlayAndHandles() throws {
            let view = makeView()
            select(view, from: 0, to: 5)

            view.selectionController.clear()

            expect(view.selectionLayers[0]).to(beNil())
            expect(try XCTUnwrap(view.selectionInteraction.startHandle).alpha) == 0
            expect(try XCTUnwrap(view.selectionInteraction.endHandle).alpha) == 0
        }

        func testCopyAndSelectAllActionsFollowSelectionState() {
            let view = makeView()

            expect(view.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil))
                == false
            expect(view.canPerformAction(
                #selector(UIResponder.selectAll(_:)), withSender: nil
            )) == true

            view.selectAll(nil)

            expect(view.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil))
                == true
            expect(view.selectionController.selectedText()) == "Hello world"
        }

        func testCopyWritesPlainAndRTFRepresentationsToPasteboard() throws {
            // 한 항목에 평문·RTF 두 표현형을 싣는다 (#118). 주입 지점은 macOS
            // `HwpDocumentNSView.pasteboard`의 iOS 짝이다.
            let view = makeView()
            let pasteboard = try XCTUnwrap(UIPasteboard(
                name: UIPasteboard.Name(rawValue: UUID().uuidString), create: true
            ))
            view.pasteboard = pasteboard
            view.selectAll(nil)

            view.copy(nil)

            expect(pasteboard.string) == "Hello world"
            let data = try XCTUnwrap(
                pasteboard.data(forPasteboardType: UTType.rtf.identifier)
            )
            let parsed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            expect(parsed.string) == "Hello world"
        }

        // MARK: - 핸들 계층 (제스처 경합을 계층 배치로 푼 계약)

        /// 핸들이 `contentView` 계층에 있으면 (1) 줌 transform을 물려받고
        /// (2) 탭 핸들러의 `hasSelection → clear()` 분기가 먼저 성립해 핸들을
        /// 톡 치는 순간 선택이 통째로 사라진다. 스크롤 뷰의 **형제**여야 한다.
        func testHandlesLiveOutsideTheZoomedScrollViewSubtree() throws {
            let view = makeView()
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let end = try XCTUnwrap(view.selectionInteraction.endHandle)

            expect(start.superview) === view
            expect(end.superview) === view
            expect(start.isDescendant(of: view.scrollView)) == false
            expect(end.isDescendant(of: view.contentView)) == false
            expect(start.edge) == .start
            expect(end.edge) == .end
        }

        /// 스크롤 뷰보다 **뒤에** 붙어야 히트 테스트가 핸들을 먼저 본다.
        func testHandleWinsHitTestingOverTheScrollView() throws {
            let view = makeView()
            select(view, from: 0, to: 5)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)

            let onKnob = CGPoint(x: start.frame.midX, y: start.frame.minY + 2)
            expect(view.hitTest(onKnob, with: nil)) === start

            // 그리는 영역 밖이어도 그랩 여유 안이면 잡힌다 (손가락 굵기)
            let nearMiss = CGPoint(
                x: start.frame.midX,
                y: start.frame.minY - HwpSelectionHandleGeometry.grabMargin + 1
            )
            expect(view.hitTest(nearMiss, with: nil)) === start

            // 여유 밖은 스크롤 뷰로 내려간다 — 여기까지 삼키면 본문 탭이 죽는다
            let clearOfHandle = CGPoint(
                x: start.frame.midX,
                y: start.frame.minY - HwpSelectionHandleGeometry.grabMargin - 4
            )
            expect(view.hitTest(clearOfHandle, with: nil)) !== start
        }

        /// 선택이 없으면 핸들은 잡히지도 않는다 (`alpha == 0`은 히트 테스트 제외).
        func testHiddenHandlesDoNotSwallowTouches() throws {
            let view = makeView()
            select(view, from: 0, to: 5)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let onKnob = CGPoint(x: start.frame.midX, y: start.frame.minY + 2)

            view.selectionController.clear()

            expect(view.hitTest(onKnob, with: nil)) !== start
        }

        /// 두 끝점이 가까우면 (1x의 한 글자·0.25x의 짧은 선택) 끝 핸들의 그랩
        /// 영역이 시작 그립을 **통째로** 덮는다. UIKit `hitTest`는 subview
        /// 역순이라 나중에 붙은 끝 핸들이 늘 이겨, 순서에 맡기면 그 배율에서
        /// 시작 끝점을 잡을 길이 사라진다 (#84 리뷰).
        func testOverlappingHandlesRouteEachTouchToItsOwnKnob() throws {
            let view = makeView()
            select(view, from: 0, to: 1)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let end = try XCTUnwrap(view.selectionInteraction.endHandle)
            let startKnob = HwpSelectionHandleGeometry.knobCenter(
                handleFrame: start.frame, edge: .start
            )
            let endKnob = HwpSelectionHandleGeometry.knobCenter(
                handleFrame: end.frame, edge: .end
            )

            // 겹침이 실제로 일어나는 상황임을 먼저 고정한다 — 두 그랩 영역이
            // 안 겹치면 아래 단언이 순서 문제를 재지 못하고 공허하게 통과한다
            expect(HwpSelectionHandleGeometry.isWithinGrabArea(
                end.convert(startKnob, from: view), bounds: end.bounds
            )) == true

            expect(view.hitTest(startKnob, with: nil)) === start
            expect(view.hitTest(endKnob, with: nil)) === end
        }

        // MARK: - 핸들 배치

        func testHandlesSitOnTheSelectionEndpoints() throws {
            let view = makeView()

            select(view, from: 0, to: 5)

            let carets = view.selectionController.selectionCarets()
            expect(carets.count) == 2
            for caret in carets {
                let handle = try XCTUnwrap(
                    caret.edge == .start
                        ? view.selectionInteraction.startHandle
                        : view.selectionInteraction.endHandle
                )
                expect(handle.alpha) == 1
                let pageFrame = view.selectionPageFrame(at: caret.pageIndex)
                let expected = view.contentView.convert(
                    caret.rect.offsetBy(dx: pageFrame.minX, dy: pageFrame.minY), to: view
                )
                let center = HwpSelectionHandleGeometry.caretCenter(
                    handleFrame: handle.frame, edge: caret.edge
                )
                expect(center.x).to(beCloseTo(expected.midX, within: 0.01))
                expect(center.y).to(beCloseTo(expected.midY, within: 0.01))
            }
        }

        /// 핸들은 줌 대상 밖에 살아 배율을 물려받지 않는다 — 0.25x에서 점이
        /// 되거나 5x에서 거대해지면 안 된다. 캐럿 바만 글자를 따라 길어진다.
        func testHandleSizeIsInvariantUnderZoom() throws {
            let view = makeView()
            select(view, from: 0, to: 5)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let unzoomed = start.frame

            view.zoomScale = 3
            // 프로그램적 줌은 보이던 중심을 유지하려 오프셋을 옮긴다 — 그대로
            // 두면 캐럿이 뷰포트 밖으로 나가 핸들이 숨고(프레임은 그 자리에
            // 멈춘다) 아래 단언이 배율이 아니라 그 사실을 재게 된다.
            view.scrollView.contentOffset = .zero
            view.scrollViewDidScroll(view.scrollView)

            expect(start.alpha) == 1
            expect(start.frame.width) == unzoomed.width
            expect(start.frame.width) == HwpSelectionHandleGeometry.knobDiameter
            // 캐럿(=글자) 높이만 배율을 탄다
            let caretHeight = { (frame: CGRect) in
                frame.height - HwpSelectionHandleGeometry.knobDiameter
            }
            expect(caretHeight(start.frame)).to(
                beCloseTo(caretHeight(unzoomed) * 3, within: 0.5)
            )
        }

        /// 가시 페이지 범위가 **그대로**인 스크롤에서도 핸들은 따라와야 한다.
        /// `scrollViewDidScroll`의 `range != activeVisibleRange` 가드가 그런
        /// 스크롤을 조기 반환하므로, 핸들 갱신은 그 가드 **앞**에 있어야 한다.
        func testHandlesFollowScrollingWithinTheSameVisibleRange() throws {
            let view = makeView(pageHeight: 2000)
            select(view, from: 0, to: 5)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let before = start.frame
            let rangeBefore = view.activeVisibleRange

            // 캐럿이 뷰포트 안에 남는 만큼만 민다 — 밖으로 내보내면 핸들이
            // 숨어서(그리고 프레임이 그 자리에 멈춰서) 추적이 아니라 숨김을
            // 재게 된다. 그쪽은 아래 테스트가 따로 본다.
            view.scrollView.contentOffset = CGPoint(x: 0, y: 60)
            view.scrollViewDidScroll(view.scrollView)

            // 가드가 걸리는 상황임을 먼저 고정한다
            expect(view.activeVisibleRange) == rangeBefore
            expect(start.alpha) == 1
            expect(start.frame.minY).to(beCloseTo(before.minY - 60, within: 0.5))
        }

        /// 뷰포트 밖으로 나간 끝점의 핸들은 가장자리로 클램프하지 않고 숨긴다 —
        /// 클램프하면 손가락이 엉뚱한 자리의 핸들을 잡아 선택이 튄다.
        func testHandleHidesWhenItsEndpointScrollsOffScreen() throws {
            let view = makeView(pageHeight: 2000)
            select(view, from: 0, to: 5)
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            expect(start.alpha) == 1

            view.scrollView.contentOffset = CGPoint(x: 0, y: 900)
            view.scrollViewDidScroll(view.scrollView)

            expect(start.alpha) == 0

            view.scrollView.contentOffset = .zero
            view.scrollViewDidScroll(view.scrollView)

            expect(start.alpha) == 1
        }

        /// 크로스 페이지 선택은 두 핸들이 서로 다른 페이지에 선다.
        func testHandlesSpanPagesForACrossPageSelection() throws {
            let view = makeView(pageCount: 2)
            view.selectionController.begin(at: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 3
            ))
            view.selectionController.extend(to: HwpTextPosition(
                pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 4
            ))

            let carets = view.selectionController.selectionCarets()
            expect(carets.map(\.pageIndex)) == [0, 1]
            let start = try XCTUnwrap(view.selectionInteraction.startHandle)
            let end = try XCTUnwrap(view.selectionInteraction.endHandle)
            expect(start.alpha) == 1
            // 두 번째 페이지 끝점은 뷰포트(800pt) 밖이라 숨는다
            expect(end.alpha) == 0
        }

        // MARK: - 마무리 처리

        /// 핸들을 반대 핸들 위에 정확히 겹치면 범위가 비는데, 선택 객체만 남으면
        /// `hasSelection`이 false인 채로 오버레이 갱신만 계속 돈다 (macOS
        /// `mouseUp`과 같은 정리).
        func testCollapsedSelectionIsCleared() {
            let view = makeView()
            select(view, from: 4, to: 4)

            expect(view.selectionController.selection).toNot(beNil())
            expect(view.clearCollapsedSelection()) == true
            expect(view.selectionController.selection).to(beNil())
            // 지울 게 없으면 false — 확장 선택을 건드리지 않는다
            select(view, from: 0, to: 5)
            expect(view.clearCollapsedSelection()) == false
            expect(view.selectionController.hasSelection) == true
        }

        /// 오토스크롤 상태를 값 타입으로 접은 뒤에도 링크 수명 규약은 그대로다
        /// (`CADisplayLink`는 target을 보유하므로 반드시 해제된다).
        func testAutoscrollLinkLifecycleSurvivesTheStateFold() {
            let view = makeView()

            view.selectionInteraction.autoscrollViewportPoint = CGPoint(x: 100, y: 4)
            view.updateSelectionAutoscroll()

            expect(view.selectionInteraction.autoscrollLink).toNot(beNil())

            view.stopSelectionAutoscroll()

            expect(view.selectionInteraction.autoscrollLink).to(beNil())
            expect(view.selectionInteraction.autoscrollViewportPoint).to(beNil())
        }
    }
#endif
