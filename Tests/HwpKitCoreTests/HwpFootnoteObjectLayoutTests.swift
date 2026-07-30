import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 각주/미주 문단에 앵커된 개체 (그림·도형·글상자·표)의 배치 (#94).
    ///
    /// 한글.app 실측 (헌법주석 `legacy-common-control-property`, 2026-07-30):
    /// - 459쪽 각주 38): 9.6×10.8pt 그림이 "씨"와 "의" 사이 **줄 안**에 저작 크기
    ///   그대로 그려지고, 각주는 3줄 그대로다 — 글자처럼 취급 슬롯이 이미 줄
    ///   높이를 정하므로 각주 높이가 변하지 않는다.
    /// - 883쪽 각주 29): 4×8/22셀 408×62.52pt 표가 각주 29의 둘째 문단으로
    ///   **각주 영역 안**에 그려지고 그 아래로 각주 30)이 이어진다. 표는 문단
    ///   들여쓰기에서 시작해 오른쪽 본문 경계를 넘어가며, 한글은 자르지 않는다.
    /// - 합성 실측: 각주 문단에 **떠 있는** 도형을 붙이면 구분선이 위로 밀려
    ///   각주 영역이 개체를 담는다 (「글 앞으로」·「자리 차지」 양쪽).
    ///
    /// 규약 요약: 각주는 표 셀·글상자와 같은 컨테이너다 — 개체는 블록 페이로드로
    /// 담고 (페이지 흐름으로 방출하면 각주 밖 본문 자리에 그려진다), 높이 하한은
    /// 글자처럼 취급이 **아닌** 개체에만 얹는다
    /// (`HwpParagraphObjectCollector.growsContainer` — 표 셀과 같은 술어).
    final class HwpFootnoteObjectLayoutTests: XCTestCase {
        private var geometry: HwpPageGeometry!
        private var index: HwpIndex!
        private var layout: HwpFootnoteLayout!

        override func setUp() {
            super.setUp()
            // A4 595×842pt, 72pt 여백 → contentFrame = (72, 72, 451, 698)
            geometry = HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
            )
            index = HwpIndex(from: CoreHwp.HwpFile())
            layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
        }

        // MARK: - 수집 (개체가 각주 블록 페이로드로 들어온다)

        /// 각주 문단의 글자처럼 취급 그림이 블록 페이로드로 들어오고, 줄 앵커
        /// 위치 (앞 텍스트 뒤)에 놓인다 — 헌법주석 459쪽 각주 38의 형상.
        func testInlinePictureInFootnoteBecomesBlockImageAtLineAnchor() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "각주 ", suffix: " 뒤")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlinePictureObject(
                width: 960, height: 1080, binItemId: 7, instanceId: 3
            ))]

            let block = try firstBlock(of: note)
            expect(block.images.count) == 1
            let image = try XCTUnwrap(block.images.first)
            expect(image.binItemId) == 7
            expect(image.controlInstanceId) == 3
            // 저작 크기 (960×1080 HWPUNIT = 9.6×10.8pt)를 그대로 쓴다 —
            // 한글도 자르거나 줄이지 않는다 (500% 확대 실측 높이 10.7pt).
            expect(image.rect.width).to(beCloseTo(9.6, within: 0.1))
            expect(image.rect.height).to(beCloseTo(10.8, within: 0.1))
            // 줄 앵커: 앞 텍스트("각주 ") 다음이라 문단 왼쪽이 아니다
            expect(image.rect.minX) > 1
            expectContained(objectsOf: block, in: block)
        }

        /// 각주 문단의 도형도 같은 경로로 담긴다.
        func testInlineShapeInFootnoteBecomesBlockShape() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlineShapeObject(
                width: 5000, height: 2000, instanceId: 5
            ))]

            let block = try firstBlock(of: note)
            expect(block.shapes.count) == 1
            let shape = try XCTUnwrap(block.shapes.first)
            expect(shape.controlInstanceId) == 5
            expect(shape.rect.width).to(beCloseTo(50, within: 0.5))
            expect(shape.rect.height).to(beCloseTo(20, within: 0.5))
            expectContained(objectsOf: block, in: block)
        }

        /// 각주 문단의 글상자는 안쪽 텍스트까지 함께 담긴다 — 이슈가 보고한
        /// "각주 안 글상자는 안쪽 텍스트까지 사라진다"의 회귀 가드.
        func testInlineTextboxInFootnoteKeepsItsInnerText() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = try [.genShapeObject(HwpSynthetic.inlineTextboxObject(
                width: 15000, height: 5000, text: "상자 속", instanceId: 11
            ))]

            let block = try firstBlock(of: note)
            expect(block.textboxes.count) == 1
            let textbox = try XCTUnwrap(block.textboxes.first)
            expect(textbox.controlInstanceId) == 11
            expect(textbox.textbox.paragraphs.map(\.attributedString.string)) == ["상자 속"]
            expectContained(objectsOf: block, in: block)
        }

        /// 각주 문단의 표가 블록 안 중첩 표로 담긴다 — 헌법주석 883쪽 각주 29의
        /// 형상 (4행 × 8열). 셀 텍스트까지 살아 있어야 한다.
        func testTableInFootnoteBecomesNestedTableWithCellText() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.table(HwpSynthetic.placed(twoByTwoTable()))]

            let block = try firstBlock(of: note)
            expect(block.nestedTables.count) == 1
            let nested = try XCTUnwrap(block.nestedTables.first)
            expect(nested.table.rows.count) == 2
            expect(nested.table.rows.flatMap(\.cells).count) == 4
            let cellText = nested.table.rows
                .flatMap(\.cells)
                .flatMap(\.paragraphs)
                .map(\.attributedString.string)
            expect(cellText) == ["r0c0", "r0c1", "r1c0", "r1c1"]
        }

        /// 미주 (흐름 배치, placeFlow)도 같은 수집을 한다 — 이슈의 "미주도 같은
        /// 경로라 동일하다".
        func testEndnoteFlowPlacementCollectsObjects() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlinePictureObject(
                width: 4000, height: 3000, binItemId: 2, instanceId: 4
            ))]

            let placement = layout.placeFlow(
                footnotes: [.init(paragraph: note, number: 1)],
                from: geometry.contentFrame.minY,
                in: geometry.contentFrame,
                index: index
            )
            let block = try XCTUnwrap(placement.blocks.first)
            expect(block.images.count) == 1
            expect(block.images.first?.binItemId) == 2
            expectContained(objectsOf: block, in: block)
        }

        // MARK: - 높이 (글자처럼 취급은 캐시 신뢰, 떠 있는 개체는 하한)

        /// 글자처럼 취급 개체는 라인 캐시가 담는 몫이라 각주 블록 높이를 바꾸지
        /// 않는다. 한글 실측 대응: 459쪽 각주 38은 그림이 있어도 3줄이고,
        /// 883쪽 각주 29 표 문단은 캐시 71.32pt 안에 들어간다. 얹으면 캐시를
        /// 신뢰하는 규약이 깨져 본문 절단이 한글과 어긋난다.
        func testInlineObjectKeepsCachedFootnoteBlockHeight() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlineShapeObject(
                width: 5000, height: 30000
            ))]

            let block = try firstBlock(of: note)
            expect(block.frame.height).to(beCloseTo(try cachedNoteHeight(), within: 0.5))
        }

        /// 떠 있는 개체는 라인 캐시에도 없어 각주 영역이 담지 못한다 — 한글.app
        /// 합성 실측 (2026-07-30): 각주 문단에 떠 있는 도형을 붙이면 구분선이
        /// 위로 밀려 각주 영역이 개체를 담는다. 담지 않으면 개체가 본문·꼬리말
        /// 위로 새어 나간다.
        func testFloatingObjectGrowsFootnoteBlockToContainIt() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 5000, height: 30000
            ))]

            let block = try firstBlock(of: note)
            expect(block.frame.height).to(beCloseTo(300, within: 0.5))
            expectContained(objectsOf: block, in: block)
        }

        /// 떠 있는 **표**도 같은 하한을 받는다 — 술어가 컨트롤 종류로 갈리면
        /// 표만 각주 밖으로 새어 나간다.
        func testFloatingTableGrowsFootnoteBlockToContainIt() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                twoByTwoTable(rowHeights: [10000, 10000]), treatAsChar: false
            ))]

            let block = try firstBlock(of: note)
            let nested = try XCTUnwrap(block.nestedTables.first)
            let baseline = try cachedNoteHeight()
            expect(block.frame.height) >= nested.rect.maxY - 0.5
            expect(block.frame.height) > baseline + 0.5
        }

        /// 쪽/종이 기준 개체는 하한에서 뺀다 — 그 저작 세로 오프셋은 페이지 상단
        /// 기준 절대 좌표인데 각주 블록 안에는 쪽 기하가 없어 `origin()`이 문단
        /// rect에 그대로 더하는 근사를 쓴다 (R32 #3). 근사를 하한으로 승격시키면
        /// 각주 스택 높이 오차가 본문 절단·페이지 수 오차로 번진다. 표 셀
        /// (#91 `testPageAnchoredFloatingObjectDoesNotGrowRow`)과 같은 경계다.
        func testPageAnchoredFloatingObjectDoesNotGrowFootnoteBlock() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 5000, height: 10000,
                verticalRelativeTo: .paper, verticalOffset: 60000
            ))]

            let block = try firstBlock(of: note)
            expect(block.frame.height).to(beCloseTo(try cachedNoteHeight(), within: 0.5))
            // 하한에서 빠질 뿐 렌더는 그대로 — 여기서 개체를 잃으면 소실 회귀다
            expect(block.shapes.count) == 1
        }

        /// 글 뒤로·글 앞으로는 겹치는 것이 설계라 하한을 얹지 않는다 (표 셀과
        /// 같은 술어 — `HwpParagraphObjectCollector.growsContainer`가 유일한
        /// 소유자다). 한글.app은 각주에서 「글 앞으로」에도 영역을 키우지만
        /// (2026-07-30 합성 실측), 그 술어를 각주만 다르게 두면 컨테이너별로
        /// 답이 갈린다 — 바꾸려면 표 셀과 함께 코퍼스 전체로 검증할 것.
        /// 빠지는 것은 **높이 하한뿐**이고 개체는 그대로 그려져야 한다.
        func testOverlayWrapModesDoNotGrowFootnoteBlockButStayRendered() throws {
            for wrap in [CoreHwp.HwpCommonCtrlTextWrap.behindText, .inFrontOfText] {
                var note = try cachedNote()
                note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                    width: 5000, height: 30000, textWrap: wrap
                ))]

                let block = try firstBlock(of: note)
                expect(block.frame.height).to(beCloseTo(try cachedNoteHeight(), within: 0.5))
                expect(block.shapes.count) == 1
                expect(block.shapes.first?.paintsBehindText) == (wrap == .behindText)
            }
        }

        /// 예약 (`HwpFootnoteCoordinator.measuredFootnoteHeight` — 본문 절단점을
        /// 정한다)과 배치 (블록 높이)는 **동형**이어야 한다. 예약이 작으면 각주
        /// 스택이 본문을 덮고, 크면 한글에 없는 페이지 절단이 생긴다.
        func testReservedHeightMatchesPlacedBlockHeightForFloatingObject() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 5000, height: 30000
            ))]

            let block = try firstBlock(of: note)
            var coordinator = HwpFootnoteCoordinator(
                index: index, fontResolver: .testDeterministic
            )
            let reserved = coordinator.measuredFootnoteHeight(
                of: note,
                number: 1,
                environment: .init(
                    contentWidth: geometry.contentFrame.width,
                    footnoteShape: nil
                )
            )
            expect(reserved).to(beCloseTo(block.frame.height, within: 0.5))
        }

        /// 떠 있는 개체가 블록을 키워도 **문단 rect는 문단 자신의 텍스트 높이**로
        /// 남는다 (R39 #2). 문단이 성장분까지 흡수하면 문단-레벨 링크 폴백
        /// (`HwpHitTester.spanAwareHyperlinkURL`)이 개체 아래 빈 영역까지 자기
        /// URL로 claim한다. 전 픽스처에서 두 높이가 같아 (떠 있는 각주 개체 0건)
        /// 되돌려도 렌더는 그대로라, 이 단언이 유일한 가드다.
        func testFloatingObjectGrowsBlockButNotParagraphRect() throws {
            var note = try cachedNote()
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 5000, height: 30000
            ))]

            let block = try firstBlock(of: note)
            let paragraphRect = try XCTUnwrap(block.paragraphs.first).rect
            expect(block.frame.height).to(beCloseTo(300, within: 0.5))
            expect(paragraphRect.height).to(beCloseTo(try cachedNoteHeight(), within: 0.5))
            expect(paragraphRect.height) < block.frame.height - 1
        }

        /// 상대 크기 개체가 든 각주는 줄 높이가 해석기 기하의 함수다 — 폭만 키에
        /// 넣으면 종이/쪽 높이·단 폭만 바뀐 재사용이 살아나 예약이 배치와 갈린다
        /// (R39 #1). 배치 (`HwpFootnoteLayout.measure`)는 캐시가 없어 항상 현재
        /// 기하로 재측정하므로 어긋나는 쪽은 언제나 예약이다.
        func testReservationIsNotReusedAcrossResolverGeometries() {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.paperRelativeInlineObject(
                widthPercent: 1000, heightPercent: 2000
            ))]
            let width = geometry.contentFrame.width
            var coordinator = HwpFootnoteCoordinator(
                index: index, fontResolver: .testDeterministic
            )
            func reserved(paperHeight: CGFloat) -> CGFloat {
                coordinator.measuredFootnoteHeight(
                    of: note,
                    number: 1,
                    environment: .init(
                        contentWidth: width,
                        footnoteShape: nil,
                        sizeResolver: HwpObjectSizeResolver(
                            paperSize: CGSize(width: 595, height: paperHeight),
                            contentSize: geometry.contentFrame.size,
                            columnWidth: width
                        )
                    )
                )
            }

            // 같은 문단·같은 번호·같은 폭이지만 종이 높이가 두 배 → 20% 개체도 두 배
            let a4 = reserved(paperHeight: 842)
            let tall = reserved(paperHeight: 1684)
            expect(tall) > a4 + 1
        }

        // MARK: - 흐름 방출 억제 (개체가 각주 밖 본문 자리에 그려지면 안 된다)

        /// 각주 안 개체는 각주 블록 페이로드로만 나오고 페이지 흐름 블록
        /// (image/shape/table/textbox)으로 다시 방출되지 않는다 — 방출하면 각주
        /// 영역 밖 본문 자리에 그려지고 흐름까지 밀어낸다.
        func testFootnoteObjectIsNotEmittedAsFlowBlock() async throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlinePictureObject(
                width: 20000, height: 5000, binItemId: 9, instanceId: 13
            ))]
            var host = try HwpSynthetic.textParagraph("본문 문단")
            host.ctrlHeaderArray = [
                try XCTUnwrap(HwpSynthetic.noteControl(.footnote, paragraphs: [note])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var pages: [HwpPage] = []
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                pages.append(page)
                pageIndex += 1
            }

            let blocks = pages.flatMap(\.blocks)
            expect(blocks.filter { $0.kind == .image }).to(beEmpty())
            expect(blocks.filter { $0.kind == .shape }).to(beEmpty())
            let footnoteBlocks = blocks.compactMap { block -> HwpFootnoteBlock? in
                guard case let .footnote(footnote) = block.payload else { return nil }
                return footnote
            }
            expect(footnoteBlocks.flatMap(\.images).map(\.binItemId)) == [9]
        }

        // MARK: - 헬퍼

        /// 라인 캐시가 있는 빈 각주 문단 — 높이 하한 테스트의 기준선.
        /// 캐시 높이(16pt)에 줄 간격(6pt)이 더해진 값이 문단 높이가 되므로,
        /// 기대치를 상수로 박지 않고 `cachedNoteHeight()`로 뽑아 쓴다.
        private func cachedNote() throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph("", segments: [(location: 0, height: 1600)])
        }

        /// 개체가 없는 `cachedNote()`의 각주 블록 높이 (하한 비교 기준선)
        private func cachedNoteHeight() throws -> CGFloat {
            try firstBlock(of: cachedNote()).frame.height
        }

        /// 문단 하나짜리 각주를 배치해 첫 블록을 돌려준다.
        private func firstBlock(
            of paragraph: CoreHwp.HwpParagraph,
            number: Int = 1
        ) throws -> HwpFootnoteBlock {
            let blocks = layout.layout(
                footnotes: [.init(paragraph: paragraph, number: number)],
                onPage: geometry,
                index: index
            )
            return try XCTUnwrap(blocks.first, "각주 블록이 없다")
        }

        /// 개체 rect가 블록 프레임 안에 들어오는지 (블록-로컬 좌표 기준).
        /// 이슈의 증상이 바로 "각주 영역이 자리는 예약하는데 안이 비어 있다"라,
        /// 담기기만 하고 블록 밖으로 새면 다시 잘못된 렌더다.
        private func expectContained(
            objectsOf block: HwpFootnoteBlock,
            in container: HwpFootnoteBlock,
            file: FileString = #file,
            line: UInt = #line
        ) {
            let bounds = CGRect(
                x: 0, y: 0,
                width: container.frame.width, height: container.frame.height
            )
            let rects = block.images.map(\.rect) + block.shapes.map(\.rect)
                + block.textboxes.map(\.rect) + block.nestedTables.map(\.rect)
            for rect in rects {
                expect(file: file, line: line, rect.minX) >= -0.5
                expect(file: file, line: line, rect.minY) >= -0.5
                expect(file: file, line: line, rect.maxY) <= bounds.maxY + 0.5
            }
        }

        /// 2행 2열 표 (셀마다 좌표 텍스트) — 각주 안 표의 최소 형상
        private func twoByTwoTable(
            rowHeights: [UInt32] = [2000, 2000]
        ) -> CoreHwp.HwpTable {
            let cells: [[[CoreHwp.HwpParagraph]]] = (0 ..< 2).map { row in
                (0 ..< 2).map { column in
                    [(try? HwpSynthetic.textParagraph("r\(row)c\(column)"))
                        ?? CoreHwp.HwpParagraph()]
                }
            }
            return HwpSynthetic.table(
                cellWidth: 10000,
                rowHeights: rowHeights,
                cellParagraphs: cells
            )
        }
    }

    // MARK: - 각주 안 개체·표의 하이퍼링크 (#94)

    extension HwpFootnoteObjectLayoutTests {
        /// 각주 안 글상자·표 문단의 링크도 히트된다 — 각주 블록 자체는 URL이 없어
        /// 예전에는 `.footnote` 히트로 떨어졌다 (셀 경로 R30 #3과 같은 규약).
        func testFootnoteInnerObjectHyperlinksAreTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let boxParagraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "글상자 링크"),
                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                rect: CGRect(x: 0, y: 0, width: 80, height: 20),
                paragraphId: 1,
                hyperlinkURL: "https://example.com/box"
            )
            let cellParagraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "셀 링크"),
                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                rect: CGRect(x: 0, y: 0, width: 80, height: 20),
                paragraphId: 2,
                hyperlinkURL: "https://example.com/cell"
            )
            let cell = HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 0, width: 100, height: 30),
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [cellParagraph],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil
            )
            let table = HwpTableFrame(
                outerFrame: CGRect(x: 0, y: 0, width: 100, height: 30),
                rows: [HwpTableRowFrame(
                    rowFrame: CGRect(x: 0, y: 0, width: 100, height: 30), cells: [cell]
                )],
                borderColor: black, borderWidth: 1
            )
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 80)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 200, y: 0, width: 80, height: 20),
                    textbox: HwpTextboxFrame(
                        outerFrame: CGRect(x: 0, y: 0, width: 80, height: 20),
                        paragraphs: [boxParagraph],
                        borderColor: nil, borderWidth: 0, fillColor: nil
                    ),
                    controlInstanceId: 7
                )],
                nestedTables: [HwpNestedTableFrame(
                    rect: CGRect(x: 0, y: 40, width: 100, height: 30),
                    table: table,
                    controlInstanceId: 8
                )]
            )
            let block = AnyHwpBlock(frame: blockFrame, kind: .footnote, payload: .footnote(footnote))
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )
            let tester = HwpHitTester()

            // 글상자 안 (블록-로컬 (210, 10) → 페이지 (260, 610))
            expect(tester.hit(page: page, point: CGPoint(x: 260, y: 610)))
                == .hyperlink(url: "https://example.com/box", blockIndex: 0)
            // 표 셀 안 (블록-로컬 (10, 50) → 페이지 (60, 650))
            expect(tester.hit(page: page, point: CGPoint(x: 60, y: 650)))
                == .hyperlink(url: "https://example.com/cell", blockIndex: 0)
            // 개체 밖은 각주 히트로 남는다
            expect(tester.hit(page: page, point: CGPoint(x: 400, y: 675)))
                == .footnote(blockIndex: 0, number: 1)
        }

        /// 각주 안 표는 블록 폭을 넘어 그려질 수 있다 — 한글도 자르지 않는다
        /// (헌법주석 883쪽 각주 29의 표는 오른쪽 본문 경계를 ~12.6pt 넘는다).
        /// 페인트가 클립 없이 그 띠를 그리므로 히트도 닿아야 한다 (R39 #3) —
        /// 안 닿으면 보이는 링크가 안 눌린다.
        func testFootnoteObjectHyperlinkOutsideBlockFrameIsTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 500, height: 30)
            let cellParagraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "넘친 셀 링크"),
                frame: HwpParagraphFrame(totalHeight: 30, lines: []),
                rect: cellRect,
                paragraphId: 1,
                hyperlinkURL: "https://example.com/overflow"
            )
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [cellParagraph],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil
            )
            // 블록 폭 400인데 표 폭은 500 — 오른쪽으로 100pt 넘어간다
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 80)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: cellRect,
                    table: HwpTableFrame(
                        outerFrame: cellRect,
                        rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 9
                )]
            )
            let block = AnyHwpBlock(frame: blockFrame, kind: .footnote, payload: .footnote(footnote))
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )

            // 블록 frame 밖 (x 510 > maxX 450) 이지만 표가 그려진 자리다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 510, y: 610)))
                == .hyperlink(url: "https://example.com/overflow", blockIndex: 0)
            // 아무것도 안 그려진 frame 밖은 종전대로 기각된다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 510, y: 670))).to(beNil())
        }

        /// 각주 문단-레벨 링크는 **문단 rect 안**에서만 히트된다 — 떠 있는 개체가
        /// 키운 아래 영역까지 삼키면 빈 자리·안쪽 개체가 바깥 URL을 연다 (R39 #2).
        /// 이 단언은 rect가 옳게 주어졌을 때의 히트 의미를 잠그고, 배치가 실제로
        /// 그 rect를 만드는지는 `testFloatingObjectGrowsBlockButNotParagraphRect`가
        /// 잠근다 — 둘이 함께여야 가드가 닫힌다.
        func testFootnoteParagraphLinkDoesNotClaimFloatingObjectArea() {
            let noteParagraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "각주 본문"),
                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                rect: CGRect(x: 0, y: 0, width: 400, height: 20),
                paragraphId: 1,
                hyperlinkURL: "https://example.com/note"
            )
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 120)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [noteParagraph],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: CGRect(x: 0, y: 40, width: 50, height: 60),
                    geometry: HwpShapeGeometry(
                        path: CGPath(rect: CGRect(x: 0, y: 0, width: 50, height: 60), transform: nil),
                        fillColor: nil, strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0,
                    sourceOrder: 0,
                    controlInstanceId: 4
                )]
            )
            let block = AnyHwpBlock(frame: blockFrame, kind: .footnote, payload: .footnote(footnote))
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )

            // 문단 안 (블록-로컬 y 10 < 20)
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 60, y: 610)))
                == .hyperlink(url: "https://example.com/note", blockIndex: 0)
            // 개체가 키운 아래 영역 (블록-로컬 y 100) — 각주 히트일 뿐 링크가 아니다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 60, y: 700)))
                == .footnote(blockIndex: 0, number: 1)
        }
    }
#endif
