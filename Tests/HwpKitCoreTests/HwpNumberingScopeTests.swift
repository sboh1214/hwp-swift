@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 컨테이너 안 문단의 번호 조회 열쇠 (#158) — 컨테이너 레이아웃이 셀·개체 요소·
    /// 리스트 단위로 복원한 자식 서수가 번호 생성기가 쓴 평면 서수
    /// (`HwpPaginator.childParagraphSequence(of:)`)와 같은지를 컨테이너 종류마다 잠근다.
    /// 어긋나면 라벨이 옆 문단의 번호를 받거나 사라진다.
    final class HwpNumberingScopeTests: XCTestCase {
        private static func paragraph(_ text: String, shape: UInt16 = 11) throws -> HwpParagraph {
            try HwpSynthetic.styledParagraph(text, paraShapeId: shape)
        }

        private static func list(_ paragraphs: [HwpParagraph]) -> CoreHwp.HwpListControlList {
            CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: paragraphs
            )
        }

        private static func text(_ paragraph: HwpParagraph) -> String {
            String(decoding: HwpOutlineCollector.titleUnits(of: paragraph), as: UTF16.self)
        }

        private static let hostPath = HwpParagraphPath(sectionIndex: 0, paragraphIndex: 3)

        /// 빈 셀·문단 없는 요소·여러 리스트를 섞은 컨테이너 넷 — 표(셀 문단 수 2·0·1·3),
        /// 개체(요소 2개, 첫 요소는 리스트 2개), 각주(문단 2), 머리말(문단 1).
        private static func controls() throws -> [CoreHwp.HwpCtrlId] {
            let table = HwpSynthetic.table(
                cellWidth: 10000, rowHeights: [1000, 1000],
                cellParagraphs: [
                    [[try paragraph("a"), try paragraph("b")], []],
                    [
                        [try paragraph("c")],
                        [try paragraph("d"), try paragraph("e"), try paragraph("f")],
                    ],
                ]
            )
            var object = try HwpSynthetic.inlineTextboxObject(width: 5000, height: 2000, text: "g")
            object.shapeComponentArray[0].textBoxListArray = [
                list([try paragraph("g")]), list([try paragraph("h"), try paragraph("i")]),
            ]
            var second = object.shapeComponentArray[0]
            second.textBoxListArray = [list([try paragraph("j")])]
            object.shapeComponentArray.append(second)
            return [
                .table(table),
                .genShapeObject(object),
                try XCTUnwrap(HwpSynthetic.noteControl(
                    .footnote, paragraphs: [try paragraph("k"), try paragraph("l")]
                )),
                try XCTUnwrap(HwpSynthetic.noteControl(.header, paragraphs: [try paragraph("m")])),
            ]
        }

        /// 컨테이너 레이아웃이 걷는 순서(셀 → 문단, 요소 → 리스트 → 문단, 리스트 → 문단)로
        /// 복원한 경로가 평면 순회의 서수와 문단 하나하나 대응한다.
        func testDerivedPathsMatchTheFlatChildSequenceForEveryContainer() throws {
            let scope = HwpNumberingScope(numbering: .empty, path: Self.hostPath)
            for (controlIndex, control) in try Self.controls().enumerated() {
                let container = scope.container(controlIndex: controlIndex)
                let flat = HwpPaginator.childParagraphs(of: control).map(\.0)
                var derived: [(path: HwpParagraphPath, text: String)] = []
                switch control {
                case let .table(table):
                    let cells = container.tableCells(of: table)
                    for (cellIndex, cell) in table.cellArray.enumerated() {
                        for (paragraphIndex, paragraph) in cell.paragraphArray.enumerated() {
                            let scope = cells.paragraph(
                                cellIndex: cellIndex, paragraphIndex: paragraphIndex
                            )
                            derived.append((scope.path, Self.text(paragraph)))
                        }
                    }
                case let .genShapeObject(object):
                    let components = object.shapeComponentArray
                    for (componentIndex, component) in components.enumerated() {
                        var childIndex = HwpNumberingScope.textboxChildOffset(
                            components: components, componentIndex: componentIndex
                        )
                        for list in component.textBoxListArray {
                            for paragraph in list.paragraphArray {
                                derived.append((
                                    container.paragraph(childIndex: childIndex).path,
                                    Self.text(paragraph)
                                ))
                                childIndex += 1
                            }
                        }
                    }
                case let .footnote(list), let .header(list):
                    let paragraphs = list.listArray.flatMap(\.paragraphArray)
                    for (childIndex, paragraph) in paragraphs.enumerated() {
                        derived.append((
                            container.paragraph(childIndex: childIndex).path, Self.text(paragraph)
                        ))
                    }
                default:
                    fail("예상하지 못한 컨트롤 \(control)")
                }
                let expected = flat.indices.map {
                    Self.hostPath.appending(controlIndex: controlIndex, childIndex: $0)
                }
                expect(derived.map(\.path)).to(
                    equal(expected), description: "control \(controlIndex)"
                )
                expect(derived.map(\.text)).to(
                    equal(flat.map(Self.text)), description: "control \(controlIndex)"
                )
            }
        }

        /// 표의 셀 접두 합과 개체 요소 접두 합 — 빈 셀·문단 없는 요소는 서수를 차지하지
        /// 않고, 첫 항목의 접두는 0이다.
        func testPrefixOffsetsSkipEmptyContainers() throws {
            let controls = try Self.controls()
            guard case let .table(table) = controls[0],
                  case let .genShapeObject(object) = controls[1]
            else { return fail("합성 컨트롤 순서") }
            expect(HwpNumberingScope.tableCellOffsets(of: table)) == [0, 2, 2, 3]
            let components = object.shapeComponentArray
            expect(HwpNumberingScope.textboxChildOffset(
                components: components, componentIndex: 0
            )) == 0
            expect(HwpNumberingScope.textboxChildOffset(
                components: components, componentIndex: 1
            )) == 3
            expect(HwpNumberingScope.tableCellOffsets(of: HwpSynthetic.table(
                cellWidth: 1000, rowHeights: [], cellParagraphs: []
            ))) == []
            // 범위 밖 셀 서수는 접두 0으로 접는다 — 잘못된 셀이 트랩을 만들지 않는다.
            let cells = HwpNumberingScope(numbering: .empty, path: Self.hostPath)
                .container(controlIndex: 0).tableCells(of: table)
            expect(cells.paragraph(cellIndex: 9, paragraphIndex: 1).path)
                == Self.hostPath.appending(controlIndex: 0, childIndex: 1)
        }

        /// 열쇠는 생성된 표를 그대로 읽는다 — 셀·글상자·각주 문단이 문서 순서로 받은
        /// 번호가 경로 조회로 나오고, 없는 문단은 nil이다.
        func testScopesReadTheGeneratedNumbers() throws {
            var host = try Self.paragraph("2 (표·글상자를 품음)")
            let table = HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [2000],
                cellParagraphs: [[
                    [try Self.paragraph("3 셀"), try Self.paragraph("본문", shape: 9)],
                    [try Self.paragraph("4 셀")],
                ]]
            )
            var textbox = try HwpSynthetic.inlineTextboxObject(width: 5000, height: 2000, text: "x")
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("5 글상자"), try Self.paragraph("개요 1", shape: 1),
            ]
            host.ctrlHeaderArray = [.table(table), .genShapeObject(textbox)]
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("1"), host, try Self.paragraph("6")],
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            let hostScope = HwpNumberingScope(
                numbering: numbering, path: HwpParagraphPath(sectionIndex: 0, paragraphIndex: 2)
            )
            expect(hostScope.number?.text) == "2."
            let cells = hostScope.container(controlIndex: 0).tableCells(of: table)
            expect(cells.paragraph(cellIndex: 0, paragraphIndex: 0).number?.text) == "3."
            expect(cells.paragraph(cellIndex: 0, paragraphIndex: 1).number).to(beNil())
            expect(cells.paragraph(cellIndex: 1, paragraphIndex: 0).number?.text) == "4."
            let box = hostScope.container(controlIndex: 1)
            expect(box.number(childIndex: 0)?.text) == "5."
            expect(box.number(childIndex: 1)?.kind) == HwpParagraphNumber.Kind.outline
            expect(box.number(childIndex: 2)).to(beNil())
            // 표에 없는 경로는 nil — 열쇠는 표를 바꾸지 않는다.
            expect(hostScope.container(controlIndex: 7).number(childIndex: 0)).to(beNil())
        }
    }
#endif
