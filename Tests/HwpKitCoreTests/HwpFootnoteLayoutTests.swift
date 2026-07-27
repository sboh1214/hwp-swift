import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpFootnoteLayoutTests: XCTestCase {
    private var geometry: HwpPageGeometry!
    private var index: HwpIndex!
    private var layout: HwpFootnoteLayout!

    override func setUp() {
        super.setUp()
        // A4 page: 595×842 pt, 72 pt margins → contentFrame = (72, 72, 451, 698)
        geometry = HwpPageGeometry(
            pageSize: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
            contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
            headerFrame: nil,
            footerFrame: nil,
            columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
        )
        index = HwpIndex(from: CoreHwp.HwpFile())
        layout = HwpFootnoteLayout(fontResolver: HwpFontResolver.testDeterministic)
    }

    func testEmptyFootnotesReturnsEmptyArray() {
        let result = layout.layout(footnotes: [], onPage: geometry, index: index)
        expect(result) == []
    }

    func testSingleBlankFootnoteReturnsOneBlock() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        expect(result.count) == 1
    }

    func testSingleBlockHasNonEmptySeparatorLine() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        expect(block.separatorLine.width) > 0
        expect(block.separatorLine.height) > 0
    }

    func testSeparatorWidthWithoutShapeIsOneThirdOfContentWidth() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        let expected = geometry.contentFrame.width / 3
        expect(block.separatorLine.width).to(beCloseTo(expected, within: 0.01))
    }

    func testBlockNumberComesFromInput() {
        let result = layout.layout(footnotes: [input(number: 7)], onPage: geometry, index: index)
        expect(result.first?.number) == 7
    }

    func testMultipleFootnotesKeepInputNumbers() {
        let footnotes = [input(number: 1), input(number: 2), input(number: 3)]
        let result = layout.layout(footnotes: footnotes, onPage: geometry, index: index)
        expect(result.count) == 3
        for (idx, block) in result.enumerated() {
            expect(block.number) == idx + 1
        }
    }

    func testBlocksStackBelowSeparator() {
        let footnotes = [input(number: 1), input(number: 2)]
        let result = layout.layout(footnotes: footnotes, onPage: geometry, index: index)
        guard result.count == 2 else {
            fail("Expected two blocks")
            return
        }
        expect(result[0].frame.minY) >= result[0].separatorLine.maxY
        expect(result[1].frame.minY) >= result[0].frame.maxY
    }

    func testBlockFrameIsWithinReservedArea() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        // 각주 영역은 최대 콘텐츠 높이의 절반까지만 확보된다.
        let reservedTop = geometry.contentFrame.maxY - geometry.contentFrame.height / 2
        expect(block.frame.minY) >= reservedTop
        expect(block.frame.maxY) <= geometry.contentFrame.maxY + 1
    }

    func testPlaceReturnsOverflowWhenNotesExceedHalfPage() throws {
        // 콘텐츠 절반(349pt)을 넘도록 긴 각주 여러 개를 만든다.
        let longText = String(repeating: "각주 본문이 길어서 여러 줄로 감싸진다. ", count: 40)
        let footnotes = try (1 ... 4).map { number in
            HwpFootnoteLayout.Input(
                paragraph: try HwpSynthetic.textParagraph("\(number)) \(longText)"),
                number: number
            )
        }

        let placement = layout.place(footnotes: footnotes, onPage: geometry, index: index)

        expect(placement.blocks.count) >= 1
        expect(placement.overflow.count) >= 1
        expect(placement.blocks.count + placement.overflow.count) == footnotes.count
        // 이월은 입력 순서의 꼬리 구간이어야 한다.
        expect(placement.overflow.map(\.number))
            == Array((placement.blocks.count + 1) ... footnotes.count)
        // 배치된 블록은 콘텐츠 아래 경계를 넘지 않는다.
        for block in placement.blocks {
            expect(block.frame.maxY) <= geometry.contentFrame.maxY + 0.5
        }
    }

    func testPlaceAlwaysPlacesFirstNoteForProgress() throws {
        let hugeText = String(repeating: "한 각주가 페이지 절반보다 크다. ", count: 400)
        let footnotes = [HwpFootnoteLayout.Input(
            paragraph: try HwpSynthetic.textParagraph(hugeText),
            number: 1
        )]

        let placement = layout.place(footnotes: footnotes, onPage: geometry, index: index)

        expect(placement.blocks.count) == 1
        expect(placement.overflow).to(beEmpty())
    }

    func testPlaceWithoutOverflowMatchesLayout() {
        let footnotes = [input(number: 1), input(number: 2)]
        let placement = layout.place(footnotes: footnotes, onPage: geometry, index: index)
        let blocks = layout.layout(footnotes: footnotes, onPage: geometry, index: index)
        expect(placement.overflow).to(beEmpty())
        expect(placement.blocks) == blocks
    }

    private func input(number: Int) -> HwpFootnoteLayout.Input {
        HwpFootnoteLayout.Input(paragraph: CoreHwp.HwpParagraph(), number: number)
    }

    /// 라인 캐시가 있는 각주는 CT 재측정 대신 한글이 계산한 높이를 쓴다
    /// (헌법주석 실측: 한자 다수 각주가 CT에서 2줄로 부풀던 회귀 가드).
    func testFootnoteHeightPrefersLineSegCache() throws {
        // 캐시: 1줄 h 900 + sp 600 (lineSegParagraph 헬퍼 고정값) → 15pt
        let paragraph = try HwpSynthetic.lineSegParagraph(
            "각주 본문 텍스트",
            segments: [(location: 0, height: 900)]
        )
        let result = layout.layout(
            footnotes: [HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)],
            onPage: geometry,
            index: index
        )
        expect(result.count) == 1
        expect(result.first?.frame.height).to(beCloseTo(15, within: 0.1))
    }

    /// 같은 각주 컨트롤 (같은 번호)의 이어지는 문단은 간격 없이 붙는다
    /// (헌법주석 실측: 문단 캐시 loc 연속 — 내부 간격 0).
    func testSameNumberFootnoteParagraphsStackWithoutGap() throws {
        let first = try HwpSynthetic.lineSegParagraph(
            "항목 1", segments: [(location: 0, height: 1000)]
        )
        let second = try HwpSynthetic.lineSegParagraph(
            "항목 2", segments: [(location: 0, height: 1000)]
        )
        let blocks = layout.layout(
            footnotes: [
                HwpFootnoteLayout.Input(paragraph: first, number: 1),
                HwpFootnoteLayout.Input(paragraph: second, number: 1),
            ],
            onPage: geometry,
            index: index
        )
        expect(blocks.count) == 2
        guard blocks.count == 2 else { return }
        expect(blocks[1].frame.minY).to(beCloseTo(blocks[0].frame.maxY, within: 0.01))
    }
}
