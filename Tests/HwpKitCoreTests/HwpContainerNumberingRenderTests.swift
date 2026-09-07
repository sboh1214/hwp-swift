import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 컨테이너(표 셀·글상자·각주·미주·머리말/꼬리말) 안 문단의 문단 번호·개요 번호
    /// 라벨 렌더 (#158) — 합성 입력으로 조판기 통합을 잠근다. 라벨 전치 자체
    /// (`appendNumberingHeading`)는 #154의 스위트가, 경로 복원은
    /// `HwpNumberingScopeTests`가, 실물은 `HwpKitTests`의 `numbering-sequence` 쌍이 본다.
    final class HwpContainerNumberingRenderTests: XCTestCase {
        private static func paragraph(_ text: String, shape: UInt16 = 11) throws -> HwpParagraph {
            try HwpSynthetic.styledParagraph(text, paraShapeId: shape)
        }

        private static func index(
            definition: CoreHwp.HwpNumbering = HwpSynthetic.numberingDefinition()
        ) -> HwpIndex {
            HwpSynthetic.numberingIndex(numberings: [0: definition])
        }

        private static func isLabelled(_ text: NSAttributedString) -> Bool {
            text.length > 0 && text.attribute(
                HwpAttributedStringKey.numberingLabel, at: 0, effectiveRange: nil
            ) != nil
        }

        /// 쪽의 텍스트 단위(본문·컨테이너 안 문단, `chrome`이면 머리말/꼬리말)를 렌더
        /// 순서로 걷어 라벨 표식이 붙은 문자열만 모은다.
        private static func labelled(in page: HwpPage, chrome: Bool = false) -> [String] {
            var texts: [String] = []
            for block in page.blocks where (block.role == .pageChrome) == chrome {
                HwpBlockContentWalker.walkText(block: block) { attributed, _, _ in
                    if isLabelled(attributed) {
                        texts.append(attributed.string)
                    }
                }
            }
            return texts
        }

        private static func labelled(
            in paginator: HwpPaginator, chrome: Bool = false
        ) async throws -> [String] {
            var texts: [String] = []
            let pageCount = await paginator.totalPages()
            for pageIndex in 0 ..< pageCount {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                texts += labelled(in: page, chrome: chrome)
            }
            return texts
        }

        /// 번호 문단 머리 진단 — "개요 번호 문단 머리"·"번호 매기기 문단 머리" 둘 다.
        private static func numberingHints(_ paginator: HwpPaginator) async -> [String] {
            await paginator.unsupportedElements().map(\.hint).filter { $0.contains("문단 머리") }
        }

        // MARK: - 표 셀

        /// 표 셀 문단은 품은 문단 뒤·표 뒤 문단 앞의 번호를 받아 셀 조판 문자열에 라벨을
        /// 전치하고, 라벨을 그린 문단은 진단에 남지 않는다. 선택·복사 단위에도 실린다.
        func testTableCellParagraphsGetLabelsInDocumentOrder() async throws {
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [3000],
                cellParagraphs: [[
                    [try Self.paragraph("셀 하나"), try Self.paragraph("본문", shape: 9)],
                    [try Self.paragraph("셀 둘")],
                ]]
            ))]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try Self.paragraph("첫째"), host, try Self.paragraph("뒤")],
                index: Self.index()
            )

            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            expect(Self.labelled(in: page)) == [
                "1. 첫째", "2. 표를 품은 문단", "3. 셀 하나", "4. 셀 둘", "5. 뒤",
            ]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
            let units = HwpSelectableText.units(in: page).map(\.attributedString.string)
            expect(units).to(contain("3. 셀 하나", "4. 셀 둘"))
            expect(units).to(contain("본문"))
        }

        /// 셀 문단이 품은 중첩 표와 글상자의 문단도 한 겹 더 내려간 경로로 번호를 받는다
        /// — 컨테이너 수집기(`HwpParagraphObjectCollector`)와 중첩 표 재귀 양쪽.
        func testNestedTableAndTextboxInsideACellGetLabels() async throws {
            var cellParagraph = try Self.paragraph("셀")
            var textbox = try HwpSynthetic.inlineTextboxObject(
                width: 12000, height: 2000, text: "x"
            )
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("셀 글상자"),
            ]
            // 둘째 요소 — 셀 안 개체는 수집기가 요소를 하나씩 넘기므로 앞 요소의 문단 수
            // (`childOffset`)를 더해야 둘째 요소 문단이 제 번호를 받는다.
            var second = textbox.shapeComponentArray[0]
            second.textBoxListArray[0].paragraphArray = [try Self.paragraph("셀 글상자 둘")]
            textbox.shapeComponentArray.append(second)
            cellParagraph.ctrlHeaderArray = [
                .table(HwpSynthetic.table(
                    cellWidth: 10000, rowHeights: [2000],
                    cellParagraphs: [[[try Self.paragraph("중첩 셀")]]]
                )),
                .genShapeObject(textbox),
            ]
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [8000], cellParagraphs: [[[cellParagraph]]]
            ))]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: Self.index()
            )

            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            // 렌더 순서는 셀 문단 → 셀 개체 → 중첩 표라 문서 순서(중첩 표가 글상자보다
            // 앞)와 다르다 — 번호는 문서 순서로 매겨졌는지만 본다.
            expect(Set(Self.labelled(in: page))) == [
                "1. 표를 품은 문단", "2. 셀", "3. 중첩 셀", "4. 셀 글상자", "5. 셀 글상자 둘",
            ]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
        }

        /// 표가 쪽을 넘어 셀 문단이 잘리면 라벨은 첫 조각에만 있고 이어지는 조각은
        /// 본문만 잇는다 (`HwpTableSplitter`의 `continuationFragment`).
        func testCellParagraphSlicedAcrossPagesKeepsOneLabel() async throws {
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 40000, rowHeights: [2000],
                cellParagraphs: [[[
                    try Self.paragraph(String(repeating: "가나다라마바사 ", count: 200)),
                ]]]
            ))]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host, try Self.paragraph("표 뒤")],
                index: Self.index(), pageHeight: 20000
            )

            let pageCount = await paginator.totalPages()
            expect(pageCount) >= 2
            var fragments: [(page: Int, labelled: Bool, prefix: String)] = []
            for pageIndex in 0 ..< pageCount {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.kind == .table {
                    HwpBlockContentWalker.walkText(block: block) { attributed, _, _ in
                        guard attributed.string.contains("가나다라마바사") else { return }
                        fragments.append((
                            pageIndex, Self.isLabelled(attributed),
                            String(attributed.string.prefix(3))
                        ))
                    }
                }
            }
            expect(fragments.count) >= 2
            expect(fragments.map(\.labelled)) == [true] + Array(
                repeating: false, count: fragments.count - 1
            )
            expect(fragments.first?.prefix) == "2. "
            // 이어지는 조각은 줄 경계에서 잘린 본문으로 시작한다 — 라벨도 거리 빈칸도 없다.
            expect(fragments.dropFirst().map(\.prefix)).to(allPass {
                !$0.hasPrefix("2.") && !$0.hasPrefix(" ")
            })
            expect(Set(fragments.map(\.page)).count) >= 2
            let all = try await Self.labelled(in: paginator)
            expect(all.last) == "3. 표 뒤"
        }

        // MARK: - 글상자·각주·미주

        /// 흐름에 놓인 글상자의 문단은 개체 요소 → 리스트 → 문단 서수로 번호를 받는다.
        /// 개요 문단은 자기 카운터(구역 정의의 정의)를 쓴다.
        func testFlowTextboxParagraphsGetLabels() async throws {
            var host = try Self.paragraph("글상자를 품은 문단")
            host.paraText?.charArray += [HwpChar(type: .extended, value: 11)]
            var textbox = try HwpSynthetic.inlineTextboxObject(
                width: 20000, height: 4000, text: "x"
            )
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("글상자 하나"), try Self.paragraph("개요", shape: 1),
            ]
            host.ctrlHeaderArray = [.genShapeObject(textbox)]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host, try Self.paragraph("뒤")], index: Self.index()
            )

            let labelled = try await Self.labelled(in: paginator)
            expect(labelled) == [
                "1. 글상자를 품은 문단\u{FFFC}", "2. 글상자 하나", "1. 개요", "3. 뒤",
            ]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
        }

        /// 각주·미주 문단은 자동 번호(`1)`) 앞에 문단 번호 라벨을 받는다 — 각주는 쪽
        /// 하단 블록, 미주는 문서 끝 흐름 블록에 실린다.
        func testFootnoteAndEndnoteParagraphsGetLabels() async throws {
            func note(_ text: String, kind: UInt32) throws -> HwpParagraph {
                var paragraph = HwpSynthetic.noteParagraph(
                    text,
                    autoNumber: HwpSynthetic.autoNumberControl(kind: kind, decorationTail: ")")
                )
                paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: 11, paraStyleId: 0
                )
                return paragraph
            }
            var host = try Self.paragraph("각주를 품은 문단")
            host.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .footnote, paragraphs: [try note(" 각주 본문", kind: 1)]
            ))]
            var endHost = try Self.paragraph("미주를 품은 문단")
            endHost.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .endnote, paragraphs: [try note(" 미주 본문", kind: 2)]
            ))]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host, endHost], index: Self.index()
            )

            let labelled = try await Self.labelled(in: paginator)
            // 쪽 안 블록 순서는 본문 → 각주 영역 → 미주 흐름이다.
            expect(labelled) == [
                "1. 각주를 품은 문단", "3. 미주를 품은 문단", "2. 1) 각주 본문", "4. 1) 미주 본문",
            ]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
        }

        // MARK: - 머리말·꼬리말

        /// 머리말·꼬리말 문단은 등록 시점의 번호로 쪽마다 같은 라벨을 받고(밴드 캐시
        /// 포함), 접근성 크롬 낭독에도 라벨이 실린다. 본문 선택 단위에는 종전대로 없다.
        func testHeaderAndFooterParagraphsGetLabelsOnEveryPage() async throws {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 20000, outlineNumberingId: 1)),
                    try XCTUnwrap(HwpSynthetic.noteControl(
                        .header, paragraphs: [try Self.paragraph("머리말")]
                    )),
                    try XCTUnwrap(HwpSynthetic.noteControl(
                        .footer, paragraphs: [try Self.paragraph("꼬리말")]
                    )),
                ],
                bodyParagraphs: [
                    try Self.paragraph("첫째"),
                    try Self.paragraph(String(repeating: "가나다라마바사 ", count: 200), shape: 9),
                    try Self.paragraph("둘째"),
                ]
            )
            let paginator = HwpPaginator(
                sections: [section], index: Self.index(), fontResolver: .testDeterministic
            )

            let pageCount = await paginator.totalPages()
            expect(pageCount) >= 2
            for pageIndex in 0 ..< pageCount {
                let loaded = try await paginator.page(at: pageIndex)
                let page = try XCTUnwrap(loaded)
                expect(Self.labelled(in: page, chrome: true)).to(
                    equal(["1. 머리말", "2. 꼬리말"]), description: "page \(pageIndex)"
                )
                let units = HwpSelectableText.units(in: page)
                expect(units.map(\.attributedString.string)).notTo(contain("1. 머리말"))
                let chrome = HwpAccessibilityContent.pageUnits(page: page, bodyUnits: units)
                    .filter { $0.kind == .pageChrome }.map(\.label)
                expect(chrome) == ["1. 머리말", "2. 꼬리말"]
            }
            let labelled = try await Self.labelled(in: paginator)
            expect(labelled) == ["3. 첫째", "4. 둘째"]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
        }

        /// 배치가 거부한 셀(격자 밖 주소로 빈 칸을 못 찾은 셀)은 그려지지 않지만 그
        /// 문단은 `cellArray` 서수를 차지한다 — 뒤 셀의 번호 경로는 받아들인 셀의 서수가
        /// 아니라 `cellArray` 서수로 풀어야 한다.
        func testRejectedCellsStillCountTowardCellOrdinals() async throws {
            var table = HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [3000],
                cellParagraphs: [[[try Self.paragraph("a")]]]
            )
            // 1×1 격자 밖 주소 → 빈 칸이 없어 거부된다. 그 뒤 (0,0) 셀은 겹쳐도 받아들인다.
            table.cellArray.append(HwpSynthetic.tableCell(
                row: 9, column: 9, width: 20000, height: 3000, paragraphs: [try Self.paragraph("x")]
            ))
            table.cellArray.append(HwpSynthetic.tableCell(
                row: 0, column: 0, width: 20000, height: 3000, paragraphs: [try Self.paragraph("b")]
            ))
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [.table(table)]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: Self.index()
            )

            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            expect(Set(Self.labelled(in: page))) == ["1. 표를 품은 문단", "2. a", "4. b"]
            let numbering = paginator.paragraphNumbering
            expect(numbering.entries.map(\.number.text)) == ["1.", "2.", "3.", "4."]
        }

        /// 표 셀 안 각주와 각주 안 표 — 셀 각주는 표 세그먼트 배치가 셀 서수로 걷고
        /// (`collectTableCellFootnotes(numbering:)`), 각주 안 표는 각주 전용 수집기의 표
        /// 분기(`collectsTables`)가 한 겹 더 내려간다.
        func testFootnotesInsideCellsAndTablesInsideFootnotesGetLabels() async throws {
            func note(_ text: String) throws -> HwpParagraph {
                var paragraph = HwpSynthetic.noteParagraph(
                    text, autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )
                paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: 11, paraStyleId: 0
                )
                return paragraph
            }
            var cellParagraph = try Self.paragraph("셀")
            cellParagraph.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .footnote, paragraphs: [try note(" 셀 각주")]
            ))]
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [3000], cellParagraphs: [[[cellParagraph]]]
            ))]
            var noteWithTable = try note(" 표를 품은 각주")
            noteWithTable.ctrlHeaderArray?.append(.table(HwpSynthetic.placed(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [3000],
                cellParagraphs: [[[try Self.paragraph("각주 셀")]]]
            ))))
            var noteHost = try Self.paragraph("각주를 품은 문단")
            noteHost.ctrlHeaderArray = [try XCTUnwrap(HwpSynthetic.noteControl(
                .footnote, paragraphs: [noteWithTable]
            ))]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host, noteHost], index: Self.index()
            )

            // 각주 자동 번호는 문서 순서 카운터라 둘째 각주가 `2)`다.
            let labelled = try await Self.labelled(in: paginator)
            expect(Set(labelled)) == [
                "1. 표를 품은 문단", "2. 셀", "3. 1) 셀 각주",
                "4. 각주를 품은 문단", "5. 2) 표를 품은 각주", "6. 각주 셀",
            ]
            let hints = await Self.numberingHints(paginator)
            expect(hints).to(beEmpty())
        }

        /// 값이 같은 머리말 컨트롤이 다른 자리에서 다른 번호를 받는다 — 등록 시점의 번호를
        /// 밴드가 들고, 밴드 블록 캐시 키(`BandBlocksKey.numbers`)가 번호를 가른다. 키에서
        /// 번호가 빠지면 뒤 머리말이 앞 머리말의 캐시 블록(옛 라벨)을 되돌려 받는다.
        func testIdenticalHeaderControlsKeepTheirOwnNumbers() async throws {
            let header = try XCTUnwrap(HwpSynthetic.noteControl(
                .header, paragraphs: [try Self.paragraph("머리말")]
            ))
            var host = try Self.paragraph("호스트")
            host.ctrlHeaderArray = [header]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 20000, outlineNumberingId: 1)),
                    header,
                ],
                bodyParagraphs: [
                    try Self.paragraph("첫째"),
                    try Self.paragraph(String(repeating: "가나다라마바사 ", count: 200), shape: 9),
                    host,
                    try Self.paragraph("끝"),
                ]
            )
            let paginator = HwpPaginator(
                sections: [section], index: Self.index(), fontResolver: .testDeterministic
            )

            let pageCount = await paginator.totalPages()
            expect(pageCount) >= 2
            let first = try await paginator.page(at: 0)
            let last = try await paginator.page(at: pageCount - 1)
            expect(Self.labelled(in: try XCTUnwrap(first), chrome: true)) == ["1. 머리말"]
            expect(Self.labelled(in: try XCTUnwrap(last), chrome: true)) == ["4. 머리말"]
            let body = try await Self.labelled(in: paginator)
            expect(body) == ["2. 첫째", "3. 호스트", "5. 끝"]
        }

        /// 라벨이 각주의 줄 수를 바꿀 때 예약(`measuredFootnoteHeight`)이 배치(`measureNote`)와
        /// 같은 라벨로 같은 높이를 재고, 높이 캐시는 위치 경로로 갈린다 — 같은 문단 값이
        /// 다른 자리에서 다른(더 긴) 라벨을 받으면 재사용하지 않는다.
        func testFootnoteReservationMatchesPlacementWhenTheLabelWraps() {
            let index = Self.index()
            let note = HwpSynthetic.noteParagraph(
                " abc", autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let short = HwpParagraphPath(sectionIndex: 0, paragraphIndex: 1)
                .appending(controlIndex: 0, childIndex: 0)
            let long = HwpParagraphPath(sectionIndex: 0, paragraphIndex: 2)
                .appending(controlIndex: 0, childIndex: 0)
            let numbering = HwpParagraphNumbering(
                numbers: [
                    short: HwpParagraphNumber(
                        kind: .numbering, definitionIndex: 0, numbers: [1], text: "1."
                    ),
                    long: HwpParagraphNumber(
                        kind: .numbering, definitionIndex: 0, numbers: [2], text: "2.2.2.2.2."
                    ),
                ],
                paths: [short, long], isTruncated: false
            )
            var coordinator = HwpFootnoteCoordinator(index: index, fontResolver: .testDeterministic)
            // Menlo 10pt 한 자 6pt: "1) abc"(36pt)는 한 줄, "1. 1) abc"(54pt)는 두 줄이다.
            let environment = HwpFootnoteCoordinator.Environment(contentWidth: 45, footnoteShape: nil)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)

            let unlabelled = coordinator.measuredFootnoteHeight(
                of: note, number: 0, environment: environment
            )
            let reserved = coordinator.measuredFootnoteHeight(
                of: note, number: 0, environment: environment,
                numbering: HwpNumberingScope(numbering: numbering, path: short)
            )
            let placed = layout.measureNote(
                note, number: 0, width: 45, index: index, footnoteShape: nil, sizeResolver: nil,
                numbering: HwpNumberingScope(numbering: numbering, path: short)
            )
            expect(reserved) == placed.textRectHeight
            expect(placed.frame.lines.count) == 2
            expect(reserved) > unlabelled
            // 같은 문단 값, 다른 경로(더 긴 라벨) — 캐시를 재사용하면 두 줄 높이가 돌아온다.
            let longer = coordinator.measuredFootnoteHeight(
                of: note, number: 0, environment: environment,
                numbering: HwpNumberingScope(numbering: numbering, path: long)
            )
            expect(longer) > reserved
            expect(longer) == layout.measureNote(
                note, number: 0, width: 45, index: index, footnoteShape: nil, sizeResolver: nil,
                numbering: HwpNumberingScope(numbering: numbering, path: long)
            ).textRectHeight
        }

        // MARK: - 진단

        /// 컨테이너 안 문단도 번호를 만들지 못한 이유별로 보고된다 — 셀의 댕글링 정의
        /// 참조, 글상자의 참조 없는 개요, 각주의 형식 슬롯 없는 수준. 정의에 닿은 셀
        /// 문단은 라벨을 받아 보고되지 않는다.
        func testUnnumberedContainerParagraphsAreReportedByCause() async throws {
            var cellParagraph = try Self.paragraph("셀 개요", shape: 1)
            var textbox = try HwpSynthetic.inlineTextboxObject(width: 12000, height: 2000, text: "x")
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.paragraph("댕글링", shape: 21),
            ]
            cellParagraph.ctrlHeaderArray = [.genShapeObject(textbox)]
            var note = HwpSynthetic.noteParagraph(
                " 8수준", autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            note.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 18, paraStyleId: 0)
            var host = try Self.paragraph("표를 품은 문단")
            host.ctrlHeaderArray = [
                .table(HwpSynthetic.table(
                    cellWidth: 30000, rowHeights: [3000],
                    cellParagraphs: [[[cellParagraph, try Self.paragraph("정상 셀")]]]
                )),
                try XCTUnwrap(HwpSynthetic.noteControl(.footnote, paragraphs: [note])),
            ]
            // 구역 정의의 개요 참조 0 → 개요 문단은 "(번호 정의 참조 없음)".
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: Self.index(), outlineNumberingId: 0
            )

            _ = await paginator.totalPages()
            let elements = await paginator.unsupportedElements()
                .filter { $0.hint.contains("문단 머리") }
            expect(elements.map(\.hint).sorted()) == [
                "개요 번호 문단 머리 (번호 정의 참조 없음)",
                "번호 매기기 문단 머리 (8수준 형식 없음)",
                "번호 매기기 문단 머리 (없는 번호 정의 2 참조)",
            ]
            expect(elements.map(\.page)) == [1, 1, 1]
            let labelled = try await Self.labelled(in: paginator)
            expect(labelled) == ["1. 표를 품은 문단", "2. 정상 셀"]
        }
    }
#endif
