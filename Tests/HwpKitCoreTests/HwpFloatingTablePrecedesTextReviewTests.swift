import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글줄 앞 자리 차지 표(#190)가 **측정 앞**에 놓여야 지켜지는 정합 — PR 리뷰가 잡은
    /// 세 계열: 표 셀 각주와 본문 각주의 번호, 표가 단을 넘긴 뒤 글줄이 놓이는 단의 폭,
    /// 나누지 않는 표(`pageBreakMode == .none`)의 바깥 여백. 빌더는
    /// `FloatingTablePrecedesTextSupport`(`HwpFloatingTablePrecedesTextTests`와 공용)다.
    final class HwpFloatingTablePrecedesTextReviewTests: XCTestCase {
        private typealias Support = FloatingTablePrecedesTextSupport

        private static func note(_ text: String) -> CoreHwp.HwpParagraph {
            HwpSynthetic.noteParagraph(
                text, autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
        }

        private static func footnote(_ text: String) -> CoreHwp.HwpCtrlId {
            .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [note(text)]))
        }

        private static func noteTexts(on page: HwpPage?) -> [String] {
            (page?.blocks ?? []).filter { $0.kind == .footnote }
                .compactMap { $0.attributedString?.string }
        }

        private static func bodyText(on page: HwpPage?) -> String {
            (page?.blocks ?? []).filter { $0.kind != .footnote }
                .compactMap { $0.attributedString?.string }.joined()
        }

        // MARK: 각주 번호

        /// 글줄 앞에 놓인 표의 셀 각주가 번호를 **먼저** 가져가고, 본문의 각주 참조 마커는
        /// 그 뒤 카운터로 구워져 각주 영역의 번호와 같다 — 표를 측정 뒤에 놓으면 참조는
        /// 1)로 그려지고 그 각주는 2)로 실린다 (PR 리뷰).
        func testCellFootnoteOfThePrecedingTableNumbersBeforeTheBodyReference() async throws {
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [Self.footnote(" 셀 각주")]
            var host = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 11)]
                + "본문".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 17)]
            host.paraText = paraText
            host.paraLineSeg.paraLineSegInternalArray = []
            host.ctrlHeaderArray = [
                .table(HwpSynthetic.placed(
                    HwpSynthetic.table(
                        cellWidth: 20000, rowHeights: [3000], cellParagraphs: [[[cell]]]
                    ),
                    treatAsChar: false, margins: [283, 283, 283, 283]
                )),
                Self.footnote(" 본문 각주"),
            ]
            let paginator = Support.paginator(bodyParagraphs: [host, try Support.flow("뒤 문단")])
            let page = try await paginator.page(at: 0)

            let notes = Self.noteTexts(on: page)
            expect(notes.map { String($0.prefix(2)) }).to(equal(["1)", "2)"]))
            expect(notes.first).to(contain("셀 각주"))
            expect(notes.last).to(contain("본문 각주"))
            // 본문 참조는 각주 영역의 번호와 같은 2)다.
            expect(Self.bodyText(on: page)).to(contain("2)"))
            expect(Self.bodyText(on: page)).toNot(contain("1)"))
        }

        // MARK: 단 폭

        /// 표가 좁은 첫 단을 넘겨 넓은 둘째 단에서 끝나면 글줄은 **둘째 단 폭**으로 잰다 —
        /// 진입 단 폭으로 잰 줄을 그대로 쓰면 넓은 단에서 줄이 두 개로 남아 상자가 두 배가
        /// 된다 (PR 리뷰). 비등폭 단은 `Column` 픽스처와 같은 10339/20682·간격 1747이다
        /// (134.16pt / 268.37pt).
        func testParagraphLineIsMeasuredAtTheColumnWhereTheTableEnds() async throws {
            var host = Support.paragraphWithInlineControl(suffix: String(repeating: "가", count: 20))
            host.ctrlHeaderArray = try Support.host(rowCount: 7).ctrlHeaderArray
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
                ],
                bodyParagraphs: [host, try Support.flow("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .table, .table, .text, .text]))
            guard blocks.count == 5 else { return }
            let first = blocks[1], second = blocks[2], line = blocks[3]
            // 본문 200.8pt: 템플릿 16 + 위 여백 2.83 → 5행(150)까지, 6행째는 아래 여백까지
            // 넣으면 201.66 > 200.8이라 둘째 단으로.
            expect(first.rowCount).to(equal(5))
            expect(second.rowCount).to(equal(2))
            expect(second.frame.minX).to(beCloseTo(241.87, within: 0.01))
            // 글줄은 둘째 단(268.37pt)에서 20자가 한 줄이다 — 첫 단(134.16pt)이면 두 줄.
            expect(line.frame.minX).to(beCloseTo(241.87, within: 0.01))
            expect(line.frame.width).to(beCloseTo(268.37, within: 0.01))
            expect(line.frame.height).to(beCloseTo(16, within: 0.01))
            expect(line.frame.minY).to(beCloseTo(second.frame.maxY + 2.83, within: 0.01))
        }

        // MARK: 나누지 않는 표

        /// 쪽 경계 나눔이 없는 표(표 76 bits 0-1 == 0)도 위·아래 바깥 여백을 적합 판정에
        /// 넣어 통째로 다음 쪽으로 가고, 그 쪽에서 위 여백 뒤에 놓이며 글줄은 아래 여백
        /// 뒤를 따른다.
        func testUnsplittableTableCountsItsMarginsAndMovesWhole() async throws {
            // 본문 205.8pt: 템플릿 + 앞 문단 여섯(112) → 남은 93.8. 표 90은 들어가지만
            // 여백 5.66을 더한 95.66은 안 들어간다 (여백을 안 세면 이 쪽에 남는다).
            let paginator = Support.paginator(pageHeight: 30500, bodyParagraphs: try (0 ..< 6).map {
                try Support.flow("앞 문단 \($0)")
            } + [try Support.host(rowCount: 3, pageBreakProperty: 0), try Support.flow("뒤 문단")])
            let first = try await Support.blocks(of: paginator)
            let second = try await Support.blocks(of: paginator, page: 1)
            expect(first.map(\.kind)).to(equal(Array(repeating: .text, count: 7)))
            expect(second.map(\.kind)).to(equal([.table, .text, .text]))
            guard second.count == 3 else { return }
            expect(second[0].rowCount).to(equal(3))
            // 합성 구역은 머리말 여백이 0이라 본문 상단 = 첫 쪽 템플릿 문단의 top(56.68)이다.
            expect(second[0].frame.minY).to(beCloseTo(first[0].frame.minY + 2.83, within: 0.01))
            expect(second[0].frame.height).to(beCloseTo(90, within: 0.01))
            expect(second[1].frame.minY).to(beCloseTo(second[0].frame.maxY + 2.83, within: 0.01))
        }

        /// 글줄이 표 뒤에서 쪽에 안 들어가 문단을 다음 쪽에서 다시 처리해도 표는 다시 놓이지
        /// 않고, 진단이 보고하는 표의 쪽은 첫 조각이 **실제로 놓인** 쪽이다 (PR 리뷰 — 조각을
        /// 내기 전에 쪽을 넘기면 놓기 전 값은 한 쪽 이르다).
        func testTablePageIsTheOneItsFirstSegmentLandedOn() async throws {
            // 본문 205.8pt: 템플릿 + 앞 문단 열하나(192) → 남은 13.8. 첫 행 30이 안 들어가
            // 표는 통째로 2쪽 상단으로 가고, 글줄이 그 뒤를 따른다.
            var host = try Support.host(rowCount: 1)
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [Self.footnote(" 셀 각주")]
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [3000], cellParagraphs: [[[cell]]]
                ),
                treatAsChar: false, margins: [283, 283, 283, 283]
            ))]
            let fillers = try (0 ..< 11).map { try Support.flow("앞 문단 \($0)") }
            let paginator = Support.paginator(pageHeight: 30500, bodyParagraphs: fillers + [host])
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            let firstBody = try XCTUnwrap(first).blocks.filter { $0.role == .body }
            let secondBody = try XCTUnwrap(second).blocks.filter { $0.role == .body }
            expect(firstBody.filter { $0.kind == .table }).to(beEmpty())
            expect(secondBody.filter { $0.kind != .footnote }.map(\.kind))
                .to(equal([.table, .text]))
            // 셀 각주는 표가 놓인 2쪽에 실린다.
            expect(Self.noteTexts(on: first)).to(beEmpty())
            expect(Self.noteTexts(on: second).first).to(contain("셀 각주"))
        }
    }
#endif
