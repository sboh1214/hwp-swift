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

        /// 비대칭 바깥 여백 — 왼쪽 정렬은 표를 왼쪽 여백만큼 들이고, 오른쪽 정렬은 상자(표 + 좌우
        /// 여백)의 오른쪽이 문단 오른쪽이라 표 오른쪽이 오른쪽 여백만큼 안이다. 대칭 여백 + 가운데
        /// 정렬은 여백을 무시해도 같은 자리라 이 규칙을 가리지 못한다 (#254 리뷰).
        func testFlowFootnoteTableAsymmetricMarginsFollowTheAlignment() throws {
            func rects(
                _ alignment: CoreHwp.HwpCommonCtrlRelativeAlignment,
                margins: [CoreHwp.HWPUNIT16]
            ) throws -> (table: CGRect, paragraph: CGRect) {
                var note = try cachedNote()
                let table = HwpSynthetic.table(
                    cellWidth: 10000, rowHeights: [2000],
                    cellParagraphs: [[[try HwpSynthetic.textParagraph("가")]]]
                )
                note.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                    table, treatAsChar: false, textWrap: .topAndBottom, margins: margins,
                    horizontalAlignment: alignment
                ))]
                let block = try firstBlock(of: note)
                return try (
                    XCTUnwrap(block.nestedTables.first).rect, XCTUnwrap(block.paragraphs.first).rect
                )
            }
            let left = try rects(.topOrLeft, margins: [1000, 0, 0, 0])
            expect(left.table.minX).to(beCloseTo(left.paragraph.minX + 10, within: 1e-6))
            let right = try rects(.bottomOrRight, margins: [1000, 2000, 0, 0])
            expect(right.table.maxX).to(beCloseTo(right.paragraph.maxX - 20, within: 1e-6))
        }

        /// 각주 안 글자처럼 취급 표는 줄 앵커가 바깥 상자의 원점이라 왼쪽 여백을 **한 번만** 들인다 —
        /// 수집기가 바깥 상자 정렬을 덧대면 여백이 두 번 들어간다 (#254 리뷰). 한글 기본 표는 바깥
        /// 여백 1mm라 실문서에서 바로 드러나는 자리다.
        func testInlineFootnoteTableAppliesItsLeftMarginOnce() throws {
            func minX(margins: [CoreHwp.HWPUNIT16]) throws -> CGFloat {
                var note = try HwpSynthetic.cachedInlineControlParagraph(
                    segments: [(location: 0, height: 1600)]
                )
                let table = HwpSynthetic.table(
                    cellWidth: 10000, rowHeights: [1500],
                    cellParagraphs: [[[try HwpSynthetic.textParagraph("가")]]]
                )
                note.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                    table, treatAsChar: true, margins: margins
                ))]
                return try XCTUnwrap(firstBlock(of: note).nestedTables.first).rect.minX
            }
            let withMargin = try minX(margins: [1000, 0, 0, 0])
            let withoutMargin = try minX(margins: [0, 0, 0, 0])
            expect(withMargin - withoutMargin).to(beCloseTo(10, within: 1e-6))
        }

        /// 바깥 상자 정렬은 흐름을 차지하는 표의 규칙이다 — 글 뒤로·글 앞으로 표는 본문 경로
        /// (`anchoredObjectFrame`)처럼 각주에서도 바깥 여백을 보지 않는다 (#254 리뷰, 한글 미실측).
        func testOverlayFootnoteTableIgnoresOuterMarginsLikeTheBodyPath() throws {
            var note = try cachedNote()
            let table = HwpSynthetic.table(
                cellWidth: 10000, rowHeights: [2000],
                cellParagraphs: [[[try HwpSynthetic.textParagraph("가")]]]
            )
            note.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                table, treatAsChar: false, textWrap: .behindText, margins: [1000, 1000, 0, 0]
            ))]

            let block = try firstBlock(of: note)
            let nested = try XCTUnwrap(block.nestedTables.first)
            let paragraph = try XCTUnwrap(block.paragraphs.first).rect
            expect(nested.rect.minX).to(beCloseTo(paragraph.minX, within: 1e-6))
        }
    }
#endif
