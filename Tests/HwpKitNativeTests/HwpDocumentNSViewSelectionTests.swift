#if os(macOS)
    import AppKit
    import CoreText
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    /// macOS 드래그 선택 — 오버레이 부착과 복사 경로 테스트.
    @MainActor
    final class HwpDocumentNSViewSelectionTests: XCTestCase {
        private func makeDocument() -> HwpDocument {
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let block = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 300, height: 20),
                kind: .text,
                attributedString: NSAttributedString(
                    string: "Hello world",
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )
            return HwpDocument(
                pages: [page],
                metadata: HwpDocumentMetadata(pageCount: 1),
                unsupportedElements: []
            )
        }

        private func makeView() -> HwpDocumentNSView {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = makeDocument()
            return view
        }

        private func select(_ view: HwpDocumentNSView, from start: Int, to end: Int) {
            view.selectionController.begin(at: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: start
            ))
            view.selectionController.extend(to: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: end
            ))
        }

        func testSelectionAttachesOverlayToPageLayer() {
            let view = makeView()

            select(view, from: 0, to: 5)

            let overlay = view.selectionLayers[0]
            expect(overlay).toNot(beNil())
            expect(overlay?.superlayer) === view.pageLayers[0]
            expect(overlay?.path?.isEmpty) == false
        }

        func testClearRemovesOverlay() {
            let view = makeView()
            select(view, from: 0, to: 5)

            view.selectionController.clear()

            expect(view.selectionLayers[0]).to(beNil())
        }

        func testCopyWritesSelectedTextToPasteboard() {
            let view = makeView()
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: UUID().uuidString))
            view.pasteboard = pasteboard
            select(view, from: 0, to: 5)

            let copied = view.copySelectionToPasteboard()

            expect(copied) == true
            expect(pasteboard.string(forType: .string)) == "Hello"
        }

        func testCopyWithoutSelectionDoesNothing() {
            let view = makeView()
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: UUID().uuidString))
            view.pasteboard = pasteboard

            expect(view.copySelectionToPasteboard()) == false
        }

        func testPagePositionClampsToNearestPage() {
            let view = makeView()

            // 페이지 위 여백 (음수 y가 아닌 페이지 밖 gap 좌표도 항상 결과)
            let hit = view.pagePosition(nearest: CGPoint(x: 100, y: 5))

            expect(hit?.pageIndex) == 0
        }
    }
#endif
