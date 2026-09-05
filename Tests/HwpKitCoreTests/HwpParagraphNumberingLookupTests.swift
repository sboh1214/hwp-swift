@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 표의 **조회** (#153) — 컨테이너 안 문단의 위치 경로,
    /// 생성의 순수성(같은 문단을 몇 번 물어도 같은 번호), 조판기의 노출. 카운터
    /// 규칙 자체는 `HwpParagraphNumberingTests`가 본다.
    final class HwpParagraphNumberingLookupTests: XCTestCase {
        private static func paragraph(_ text: String, shape: UInt16) throws -> HwpParagraph {
            try HwpSynthetic.styledParagraph(text, paraShapeId: shape)
        }

        private static func top(_ paragraphIndex: Int) -> HwpParagraphPath {
            HwpParagraphPath(sectionIndex: 0, paragraphIndex: paragraphIndex)
        }

        /// 표 셀·글상자·각주 안 문단도 문서 순서(품은 문단 뒤)로 같은 카운터를 쓰고,
        /// 경로가 컨트롤 서수와 자식 문단 서수를 적는다.
        func testNestedParagraphsAreNumberedInDocumentOrderWithPaths() throws {
            var host = try Self.paragraph("2 (표·글상자를 품음)", shape: 11)
            host.paraText?.charArray += [HwpChar(type: .extended, value: 11)]
            let table = HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [2000],
                cellParagraphs: [[
                    [try Self.paragraph("3 셀", shape: 11), try Self.paragraph("본문", shape: 9)],
                    [try Self.paragraph("4 셀", shape: 11)],
                ]]
            )
            var textbox = try HwpSynthetic.inlineTextboxObject(width: 5000, height: 2000, text: "x")
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("5 글상자", shape: 11), try Self.paragraph("개요 1", shape: 1),
            ]
            host.ctrlHeaderArray = [.table(table), .genShapeObject(textbox)]
            var noteHost = try Self.paragraph("6 (각주를 품음)", shape: 11)
            noteHost.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .footnote, paragraphs: [try Self.paragraph("7 각주", shape: 11)]
            ))]

            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("1", shape: 11), host, noteHost, try Self.paragraph("8", shape: 11)],
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )

            expect(numbering.entries.map(\.number.text)) == [
                "1.", "2.", "3.", "4.", "5.", "1.", "6.", "7.", "8.",
            ]
            expect(numbering.paths.map(\.description)) == [
                "s0/p1", "s0/p2", "s0/p2/c0/n0", "s0/p2/c0/n2", "s0/p2/c1/n0", "s0/p2/c1/n1",
                "s0/p3", "s0/p3/c0/n0", "s0/p4",
            ]
            let cell = Self.top(2).appending(controlIndex: 0, childIndex: 2)
            expect(numbering.number(at: cell)?.text) == "4."
            expect(cell.isTopLevel) == false
            expect(cell.steps) == [HwpParagraphPath.Step(controlIndex: 0, childIndex: 2)]
            expect(numbering.number(at: Self.top(2).appending(controlIndex: 1, childIndex: 1))?.kind)
                == HwpParagraphNumber.Kind.outline
            expect(numbering.paths.filter(\.isTopLevel).count) == 4
        }

        /// 생성은 순수 함수다 — 같은 입력이면 같은 표이고, 같은 문단을 몇 번 물어도
        /// 같은 번호다 (조판이 문단을 재측정·재배치해도 카운터는 한 번만 는다).
        func testGenerationIsPureAndRepeatedLookupsAreStable() throws {
            let paragraphs = [
                try Self.paragraph("1", shape: 1), try Self.paragraph("가", shape: 2),
                try Self.paragraph("2", shape: 1),
            ]
            let definition = HwpSynthetic.numberingDefinition()
            let first = HwpSynthetic.generateNumbering(paragraphs, numberings: [0: definition])
            let second = HwpSynthetic.generateNumbering(paragraphs, numberings: [0: definition])
            expect(first) == second
            for _ in 0 ..< 3 {
                expect(first.number(at: Self.top(3))?.text) == "2."
                expect(first.number(for: HwpParagraphKey(sectionIndex: 0, paragraphIndex: 2))?.text)
                    == "1."
                expect(first[Self.top(1)]?.numbers) == [1]
            }
            expect(first.count) == 3
            expect(first.entries.map(\.path)) == first.paths
            expect(HwpParagraphNumbering.empty.count) == 0
            expect(HwpParagraphNumbering.empty.number(at: Self.top(0))).to(beNil())
        }

        /// 조판기는 init에서 같은 표를 만들어 둔다 — 조판 전에 물어도 전체다.
        func testPaginatorExposesTheSameTableBeforeAndAfterPagination() async throws {
            let definition = HwpSynthetic.numberingDefinition(numberFormats: [2, 8, 0, 8, 0, 8, 0])
            let paragraphs = [
                try Self.paragraph("I", shape: 1), try Self.paragraph("가", shape: 2),
                try Self.paragraph("1", shape: 11),
            ]
            let index = HwpSynthetic.numberingIndex(numberings: [0: definition])
            let paginator = HwpSynthetic.outlinePaginator(bodyParagraphs: paragraphs, index: index)
            let expected = HwpSynthetic.generateNumbering(paragraphs, numberings: [0: definition])

            let before = await paginator.paragraphNumbering()
            expect(before) == expected
            // 번호 매기기도 같은 정의(1수준 로마 대문자)를 쓰되 카운터는 따로다.
            expect(before.entries.map(\.number.text)) == ["I.", "가.", "I."]
            _ = await paginator.totalPages()
            let after = await paginator.paragraphNumbering()
            expect(after) == expected
            // 진단은 그대로 "(미렌더)"다 — 라벨은 아직 그리지 않는다 (#154).
            let hints = await paginator.unsupportedElements().map(\.hint)
            expect(hints) == [
                "개요 번호 문단 머리 (미렌더)", "개요 번호 문단 머리 (미렌더)",
                "번호 매기기 문단 머리 (미렌더)",
            ]
        }
    }
#endif
