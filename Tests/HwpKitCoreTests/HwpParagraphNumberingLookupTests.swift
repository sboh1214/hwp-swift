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

        /// 머리말·꼬리말 안 문단도 컨테이너다 — 구역 첫 문단의 머리말 컨트롤 안 번호
        /// 문단이 본문 목록의 번호 하나를 소비한다(한글.app 실측 전 — 쪽마다 반복되는
        /// 크롬이라 본문 카운터를 잇는 것이 맞는지는 미실측 항목이다).
        func testHeaderParagraphsShareTheBodyCounter() throws {
            var host = try Self.paragraph("2 (머리말을 품음)", shape: 11)
            host.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .header, paragraphs: [try Self.paragraph("1 머리말", shape: 11)]
            ))]
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("1", shape: 11), host, try Self.paragraph("4", shape: 11)],
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            expect(numbering.entries.map(\.number.text)) == ["1.", "2.", "3.", "4."]
            expect(numbering.paths.map(\.description)) == ["s0/p1", "s0/p2", "s0/p2/c0/n0", "s0/p3"]
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
            expect(first.isTruncated) == false
            expect(HwpParagraphNumbering.empty.count) == 0
            expect(HwpParagraphNumbering.empty.isTruncated) == false
            expect(HwpParagraphNumbering.empty.number(at: Self.top(0))).to(beNil())
        }

        // MARK: - 상한

        /// 라벨은 만드는 도중 `textUnitCeiling`에서 멈춘다 — 형식 문자열은 WORD 길이만큼
        /// 길 수 있어 지시자를 수만 번 적은 정의 하나로 문단마다 수 MB 라벨이 생기고,
        /// 시작 번호를 접는 것만으로는(로마 대문자 65,535 = 70자) 막히지 않는다.
        func testLabelsStopAtTheUnitCeilingWhileBeingBuilt() throws {
            let repeated = String(repeating: "^1", count: 3000)
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("긴 라벨", shape: 11), try Self.paragraph("둘째", shape: 11)],
                numberings: [0: HwpSynthetic.numberingDefinition(
                    formats: [repeated, "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"],
                    numberFormats: [2], startingIndex: 1,
                    startingIndexArray: [UInt32.max, 1, 1, 1, 1, 1, 1]
                )]
            )
            let ceiling = HwpParagraphNumber.textUnitCeiling
            let labels = numbering.entries.map(\.number.text)
            expect(labels.map(\.utf16.count)) == [ceiling, ceiling]
            // 온전한 라벨의 접두다 — 로마 숫자 조각이 그대로 이어진다.
            let roman = HwpNumberFormat.string(for: 65535, shape: 2)
            expect(labels[0].hasPrefix(roman + roman)) == true
            expect(numbering.entries.map(\.number.number)) == [65535, 65536]
        }

        /// 천장은 유니코드 스칼라 경계에서 끊는다 — 대리 쌍이 쪼개져 U+FFFD가 생기지
        /// 않고 결과는 언제나 원문의 접두다.
        func testLabelCeilingDoesNotSplitSurrogatePairs() throws {
            let ceiling = HwpParagraphNumber.textUnitCeiling
            // 2단위 이모지만으로 천장을 하나 넘기면 마지막 이모지는 통째로 빠진다.
            let emoji = String(repeating: "😀", count: ceiling / 2 + 1)
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("이모지", shape: 11)],
                numberings: [0: HwpSynthetic.numberingDefinition(
                    formats: [emoji + "^1", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"]
                )]
            )
            let label = try XCTUnwrap(numbering.entries.first?.number.text)
            expect(label.utf16.count) == ceiling
            expect(label.unicodeScalars.contains("\u{FFFD}")) == false
            expect(label.unicodeScalars.allSatisfy { $0 == "😀" }) == true
            expect(emoji.hasPrefix(label)) == true
            // 천장 안에 드는 라벨은 손대지 않는다 — 실물의 가장 긴 형식도 여기 든다.
            let short = HwpSynthetic.generateNumbering(
                [try Self.paragraph("짧은", shape: 11)],
                numberings: [0: HwpSynthetic.numberingDefinition(formats: ["제^1장 ^n.", "^2."])]
            )
            expect(short.entries.first?.number.text) == "제1장 1."
        }

        /// 문서 전체 항목 상한 — 걸리면 뒤쪽 번호 문단은 버리고 `isTruncated`로 알리며
        /// 순회도 멈춘다. 상한 안이면 플래그가 서지 않는다.
        func testDocumentEntryLimitDropsTrailingParagraphsAndFlagsIt() throws {
            let paragraphs = try (1 ... 5).map { try Self.paragraph("\($0)", shape: 11) }
            let section = HwpSynthetic.numberingSection(paragraphs: paragraphs)
            let index = HwpSynthetic.numberingIndex(
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            let truncated = HwpParagraphNumbering.generate(
                sections: [section], index: index, maximumEntries: 3
            )
            expect(truncated.isTruncated) == true
            expect(truncated.entries.map(\.number.text)) == ["1.", "2.", "3."]
            expect(truncated.number(at: Self.top(4))).to(beNil())

            let exact = HwpParagraphNumbering.generate(
                sections: [section], index: index, maximumEntries: 5
            )
            expect(exact.isTruncated) == false
            expect(exact.count) == 5
            expect(HwpParagraphNumbering.maximumDocumentEntries) == 20000
        }

        /// 걷는 문단 수에도 상한이 있다 — 항목 상한은 번호 문단에서만 줄어들어 번호
        /// 없는 문단이 수백만 개면 순회 자체가 문서를 여는 시간을 삼킨다. 상한 뒤의
        /// 번호 문단은 버리고 `isTruncated`로 알린다.
        func testVisitedParagraphLimitStopsTheWalkAndFlagsIt() throws {
            var paragraphs = try (1 ... 6).map { try Self.paragraph("본문 \($0)", shape: 9) }
            paragraphs.append(try Self.paragraph("상한 뒤 번호", shape: 11))
            let section = HwpSynthetic.numberingSection(paragraphs: paragraphs)
            let index = HwpSynthetic.numberingIndex(
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            // 구역 첫 문단(구역 정의)까지 8문단 — 상한 4는 번호 문단 앞에서 멈춘다.
            let truncated = HwpParagraphNumbering.generate(
                sections: [section], index: index,
                maximumEntries: HwpParagraphNumbering.maximumDocumentEntries,
                maximumVisitedParagraphs: 4
            )
            expect(truncated.isTruncated) == true
            expect(truncated.count) == 0

            let whole = HwpParagraphNumbering.generate(
                sections: [section], index: index,
                maximumEntries: HwpParagraphNumbering.maximumDocumentEntries,
                maximumVisitedParagraphs: 8
            )
            expect(whole.isTruncated) == false
            expect(whole.entries.map(\.number.text)) == ["1."]
            expect(HwpParagraphNumbering.maximumVisitedParagraphs) == 500_000
        }

        /// 감싼 Task가 취소되면 걷다 만다 — 순회는 `HwpPaginator.init`의 동기 경로라
        /// 조판의 취소 관찰 밖이고, 취소된 로드의 표는 조판기와 함께 버려진다.
        func testCancelledTaskStopsTheWalk() async throws {
            let paragraphs = try (1 ... 3).map { try Self.paragraph("\($0)", shape: 11) }
            let section = HwpSynthetic.numberingSection(paragraphs: paragraphs)
            let index = HwpSynthetic.numberingIndex(
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            let task = Task {
                // 취소가 먼저 관찰되도록 취소 가능한 대기 뒤에 생성한다.
                try? await Task.sleep(for: .seconds(10))
                return HwpParagraphNumbering.generate(sections: [section], index: index)
            }
            task.cancel()
            let cancelled = await task.value
            expect(cancelled.isTruncated) == true
            expect(cancelled.count) == 0
            // 취소되지 않은 Task에서는 전부 센다.
            let whole = await Task { HwpParagraphNumbering.generate(sections: [section], index: index) }.value
            expect(whole.isTruncated) == false
            expect(whole.count) == 3
        }

        /// 컨테이너 자식은 게으른 원본(`childParagraphSequence`)과 배열
        /// (`childParagraphs`)이 같은 순서·같은 종류다 — 순회는 게으른 쪽을 써 상한·
        /// 취소에서 멈추면 그 뒤 문단을 꺼내지 않는다.
        func testLazyChildSequenceMatchesTheArrayTraversal() throws {
            let table = HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [2000, 2000],
                cellParagraphs: [
                    [[try Self.paragraph("a", shape: 11), try Self.paragraph("b", shape: 9)],
                     [try Self.paragraph("c", shape: 11)]],
                    [[try Self.paragraph("d", shape: 11)], []],
                ]
            )
            var textbox = try HwpSynthetic.inlineTextboxObject(width: 5000, height: 2000, text: "x")
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("e", shape: 11), try Self.paragraph("f", shape: 1),
            ]
            let note = try XCTUnwrap(HwpSynthetic.noteControl(
                .footnote, paragraphs: [try Self.paragraph("g", shape: 11)]
            ))
            for control in [CoreHwp.HwpCtrlId.table(table), .genShapeObject(textbox), note] {
                let lazy = Array(HwpPaginator.childParagraphSequence(of: control))
                let eager = HwpPaginator.childParagraphs(of: control)
                expect(lazy.map(\.0)) == eager.map(\.0)
                expect(lazy.map(\.1)) == eager.map(\.1)
            }
            expect(Array(HwpPaginator.childParagraphSequence(of: HwpSynthetic.bookmarkControl("b")))
                .isEmpty) == true

            // 상한이 셀 하나에서 걸리면 그 뒤 셀 문단은 세지 않는다.
            var host = try Self.paragraph("표", shape: 9)
            host.ctrlHeaderArray = [.table(table)]
            let numbering = HwpParagraphNumbering.generate(
                sections: [HwpSynthetic.numberingSection(paragraphs: [host])],
                index: HwpSynthetic.numberingIndex(
                    numberings: [0: HwpSynthetic.numberingDefinition()]
                ),
                maximumEntries: HwpParagraphNumbering.maximumDocumentEntries,
                maximumVisitedParagraphs: 3
            )
            expect(numbering.isTruncated) == true
            expect(numbering.entries.map(\.number.text)) == ["1."]
        }
    }
#endif
