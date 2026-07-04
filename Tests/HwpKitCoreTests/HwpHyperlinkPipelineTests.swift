import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpHyperlinkPipelineTests: XCTestCase {
    private func makeHyperlinkBlock(url: String, frame: CGRect) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(string: "linked"),
            hyperlinkURL: url
        )
    }

    private func makePage(with blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: blocks,
            pageNumber: 1
        )
    }

    func testHitTesterReturnsHyperlinkForBlockWithURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let block = makeHyperlinkBlock(url: "https://example.com", frame: frame)
        let page = makePage(with: [block])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 25))

        expect {
            if case let .hyperlink(url, blockIndex) = hit {
                return url == "https://example.com" && blockIndex == 0
            }
            return false
        } == true
    }

    func testHitTesterReturnsTextWhenBlockHasNoURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let plain = AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(string: "plain")
        )
        let page = makePage(with: [plain])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 25))

        expect {
            if case .text = hit { return true }
            return false
        } == true
    }

    func testPaintListBuilderEmitsHyperlinkCommandForBlockWithURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let block = makeHyperlinkBlock(url: "https://example.com", frame: frame)
        let page = makePage(with: [block])

        let paintList = HwpPaintListBuilder()
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile()))

        let hyperlinkCommand = paintList.commands.first { command in
            if case .hyperlink = command { return true }
            return false
        }
        expect(hyperlinkCommand).notTo(beNil())

        if case let .hyperlink(rect, url) = hyperlinkCommand {
            expect(rect) == frame
            expect(url) == "https://example.com"
        }
    }

    func testPaintListBuilderOmitsHyperlinkCommandWhenNoURL() {
        let plain = AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 100, height: 30),
            kind: .text,
            attributedString: NSAttributedString(string: "plain")
        )
        let page = makePage(with: [plain])

        let paintList = HwpPaintListBuilder()
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile()))

        let hasHyperlink = paintList.commands.contains { command in
            if case .hyperlink = command { return true }
            return false
        }
        expect(hasHyperlink) == false
    }
}
