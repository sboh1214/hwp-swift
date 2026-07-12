import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 점→위치 스냅, 범위→하이라이트 rect, 범위→텍스트 직렬화 테스트.
final class HwpSelectionGeometryTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func textBlock(
        _ text: String,
        frame: CGRect,
        role: HwpBlockRole = .body
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            role: role
        )
    }

    private func makeDocument(pages: [[AnyHwpBlock]]) -> HwpDocument {
        HwpDocument(
            pages: pages.enumerated().map { index, blocks in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: blocks,
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pages.count),
            unsupportedElements: []
        )
    }

    func testUnitsExcludePageChrome() {
        let document = makeDocument(pages: [[
            textBlock("body", frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
            textBlock(
                "- 1 -",
                frame: CGRect(x: 50, y: 800, width: 200, height: 20),
                role: .pageChrome
            ),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let units = geometry.units(forPage: 0)

        expect(units.count) == 1
        expect(units[0].attributedString.string) == "body"
    }

    func testPositionSnapsInsideLine() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let start = geometry.position(nearest: CGPoint(x: 50, y: 108), pageIndex: 0)
        let beyondEnd = geometry.position(nearest: CGPoint(x: 590, y: 108), pageIndex: 0)

        expect(start?.characterOffset) == 0
        expect(beyondEnd?.characterOffset) == 11
    }

    func testPositionSnapsFromEmptySpace() {
        let document = makeDocument(pages: [[
            textBlock("above", frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
            textBlock("below", frame: CGRect(x: 50, y: 300, width: 200, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        // 본문 아래 빈 공간 → 마지막 단위로 스냅
        let below = geometry.position(nearest: CGPoint(x: 60, y: 700), pageIndex: 0)

        expect(below?.blockIndex) == 1
    }

    func testHighlightRectsForPartialLine() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        let selection = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ),
            focus: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 5
            )
        )

        let rects = geometry.highlightRects(pageIndex: 0, selection: selection)

        expect(rects.count) == 1
        expect(rects[0].minX).to(beCloseTo(50, within: 0.5))
        // "Hello"의 폭은 "Hello world" 전체 폭보다 좁아야 한다
        let fullWidth = (NSAttributedString(
            string: "Hello world",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        ).size()).width
        expect(rects[0].width) < fullWidth
        expect(rects[0].width) > 10
    }

    func testPlainTextJoinsUnitsAcrossPages() {
        let document = makeDocument(pages: [
            [textBlock("first page", frame: CGRect(x: 50, y: 100, width: 200, height: 20))],
            [textBlock("second page", frame: CGRect(x: 50, y: 100, width: 200, height: 20))],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        let selection = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 6
            ),
            focus: HwpTextPosition(
                pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 6
            )
        )

        expect(geometry.plainText(for: selection)) == "page\nsecond"
    }

    func testPlainTextStripsControlMarkers() {
        expect(HwpSelectionGeometry.strippingControlMarkers("a\u{FFFC}b")) == "ab"
    }

    func testWordRangeAtPosition() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let word = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 7
        ))

        expect(word?.range.start.characterOffset) == 6
        expect(word?.range.end.characterOffset) == 11
    }
}
