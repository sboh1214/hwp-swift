import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 안 넓은 표 (#254) — `HwpFootnoteObjectLayoutTests`의 각주 조판 입력(`cachedNote`·
    /// `firstBlock`)을 그대로 쓴다.
    extension HwpFootnoteObjectLayoutTests {
        /// 각주 안 자리 차지 표도 문단 폭보다 넓으면 줄이지 않고, 바깥 상자(표 + 좌우 바깥 여백)를
        /// 문단 rect에 정렬한 뒤 왼쪽 여백만큼 들인다 — 페이지 경로(`HwpPaginator.flowTableOriginX`)와
        /// 같은 규칙이다 (#254, 한글: 각주 안 450pt 자리 차지 표 문단 가운데 72.72 — 본문 425.2pt).
        func testFlowFootnoteTableKeepsAuthoredWidthAndAlignsItsOuterBox() throws {
            var note = try cachedNote()
            let cell = [
                [try HwpSynthetic.textParagraph("좌")], [try HwpSynthetic.textParagraph("우")],
            ]
            let wide = HwpSynthetic.table(
                cellWidth: 25000, rowHeights: [2000], cellParagraphs: [cell]
            )
            note.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                wide, treatAsChar: false, textWrap: .topAndBottom, margins: [1000, 1000, 0, 0],
                horizontalAlignment: .center
            ))]

            let block = try firstBlock(of: note)
            let nested = try XCTUnwrap(block.nestedTables.first)
            let paragraph = try XCTUnwrap(block.paragraphs.first).rect
            // 저작 500pt가 문단 폭 451pt로 줄지 않고, 상자 520pt가 문단 가운데 + 왼쪽 여백 10pt
            expect(nested.rect.width).to(beCloseTo(500, within: 1e-6))
            expect(nested.rect.minX)
                .to(beCloseTo(paragraph.minX + (paragraph.width - 520) / 2 + 10, within: 1e-6))
        }
    }
#endif
