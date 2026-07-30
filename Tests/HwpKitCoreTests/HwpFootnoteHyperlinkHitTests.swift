import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

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

        /// 겹치는 개체는 **위에 그려진 것**이 히트를 이긴다 (R41 #1). 페인트는
        /// 글 뒤로 개체 → 문단 텍스트 → 글 앞으로 개체 순이므로 히트는 그 역순
        /// 이어야 한다 — 저장 순서로 훑으면 덮여 안 보이는 URL이 열린다.
        func testOverlappingFootnoteObjectHitFollowsReversePaintOrder() {
            for paintsBehindText in [false, true] {
                let expected = paintsBehindText
                    ? "https://example.com/covered"
                    : "https://example.com/overlay"
                let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
                let footnote = HwpFootnoteBlock(
                    frame: blockFrame,
                    paragraphs: [HwpLaidOutParagraph(
                        attributedString: NSAttributedString(string: "덮인 각주 텍스트"),
                        frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                        rect: CGRect(x: 0, y: 0, width: 400, height: 40),
                        paragraphId: 1,
                        hyperlinkURL: "https://example.com/covered"
                    )],
                    number: 1,
                    separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                    textboxes: [HwpCellTextbox(
                        rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                        textbox: HwpTextboxFrame(
                            outerFrame: CGRect(x: 0, y: 0, width: 100, height: 20),
                            paragraphs: [HwpLaidOutParagraph(
                                attributedString: NSAttributedString(string: "덮는 글상자"),
                                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                                rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                                paragraphId: 2,
                                hyperlinkURL: "https://example.com/overlay"
                            )],
                            borderColor: nil, borderWidth: 0, fillColor: nil
                        ),
                        paintsBehindText: paintsBehindText,
                        zOrder: 0,
                        sourceOrder: 0,
                        controlInstanceId: 5
                    )]
                )
                let page = HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [AnyHwpBlock(
                        frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                    )],
                    pageNumber: 1
                )

                // 글상자와 문단이 겹치는 지점 (블록-로컬 10, 10)
                expect(HwpHitTester().hit(page: page, point: CGPoint(x: 60, y: 610)))
                    == .hyperlink(url: expected, blockIndex: 0)
                // 글상자 밖 문단 영역은 어느 배치든 문단 링크
                expect(HwpHitTester().hit(page: page, point: CGPoint(x: 300, y: 610)))
                    == .hyperlink(url: "https://example.com/covered", blockIndex: 0)
            }
        }

        /// 자손이 자기 컨테이너를 넘어 그려지면 그 띠도 눌려야 한다 (R41 #2) —
        /// 픽스처의 셀(500pt)은 자기 표 rect(100pt)보다 넓다. 페인트는
        /// 클립 없이 그리므로, 자격 영역이나 포함 판정이 최상위 rect에서 멈추면
        /// 보이는 링크가 조회 전에 기각된다.
        func testFootnoteDescendantOverflowHyperlinkIsTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 500, height: 30)
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(string: "표 밖으로 넘친 셀"),
                    frame: HwpParagraphFrame(totalHeight: 30, lines: []),
                    rect: cellRect,
                    paragraphId: 1,
                    hyperlinkURL: "https://example.com/descendant"
                )],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil
            )
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 80)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: CGRect(x: 0, y: 0, width: 100, height: 30),
                    table: HwpTableFrame(
                        outerFrame: CGRect(x: 0, y: 0, width: 100, height: 30),
                        rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 9
                )]
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                )],
                pageNumber: 1
            )

            // 블록 frame(maxX 450)·표 rect(로컬 100) 둘 다 밖이지만 셀은 그려진 자리
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 510, y: 610)))
                == .hyperlink(url: "https://example.com/descendant", blockIndex: 0)
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

    // MARK: - 겹친 층의 스팬·가림 (R42)

    extension HwpFootnoteObjectLayoutTests {
        /// 필드 스팬(%hlk)도 층 순서를 따라야 한다 (R42 #1). 스팬 경로는 문서가
        /// 말하는 **주 경로**인데(“하이퍼링크 방출은 스팬 우선”), 블록 전체를 훑는
        /// walkText 스캔이 페인트 **정순**이라 덮인 문단 스팬을 먼저 잡았다.
        func testOverlappingFootnoteSpanLinksResolveTopmostFirst() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.spanParagraph(
                    "덮인링크텍스트", url: "https://example.com/covered",
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40), paragraphId: 1
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 0, y: 0, width: 200, height: 40),
                    textbox: HwpTextboxFrame(
                        outerFrame: CGRect(x: 0, y: 0, width: 200, height: 40),
                        paragraphs: [Self.spanParagraph(
                            "덮는링크텍스트", url: "https://example.com/overlay",
                            rect: CGRect(x: 0, y: 0, width: 200, height: 40), paragraphId: 2
                        )],
                        borderColor: nil, borderWidth: 0, fillColor: nil
                    ),
                    paintsBehindText: false,
                    zOrder: 0,
                    sourceOrder: 0,
                    controlInstanceId: 5
                )]
            )

            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 56, y: 606)))
                == .hyperlink(url: "https://example.com/overlay", blockIndex: 0)
        }

        /// 링크 없는 **불투명** 전경 개체는 아래 링크를 가린다 (R42 #2) — 보이는
        /// 개체를 눌렀는데 숨은 링크가 열리면 안 된다. 반대로 **채우기 없는** 도형은
        /// 가리지 않는다: 이 리포는 오버레이가 겹치는 것을 설계로 두므로
        /// (`앵커 규칙`), 속 빈 장식 도형까지 막으면 그 아래 링크가 통째로 죽는다.
        func testFilledForegroundObjectOccludesFootnoteLinkButHollowOneDoesNot() {
            let filled = HwpRGBColor(red: 255, green: 0, blue: 0).cgColor
            for fillColor in [filled, nil] as [CGColor?] {
                let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
                let footnote = HwpFootnoteBlock(
                    frame: blockFrame,
                    paragraphs: [HwpLaidOutParagraph(
                        attributedString: NSAttributedString(string: "가려진 각주 링크"),
                        frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                        rect: CGRect(x: 0, y: 0, width: 400, height: 40),
                        paragraphId: 1,
                        hyperlinkURL: "https://example.com/under"
                    )],
                    number: 1,
                    separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                    shapes: [HwpCellShape(
                        rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                        geometry: HwpShapeGeometry(
                            path: CGPath(
                                rect: CGRect(x: 0, y: 0, width: 100, height: 40), transform: nil
                            ),
                            fillColor: fillColor, strokeColor: nil, strokeWidth: 0
                        ),
                        paintsBehindText: false,
                        zOrder: 0,
                        sourceOrder: 0,
                        controlInstanceId: 6
                    )]
                )
                let hit = HwpHitTester().hit(
                    page: Self.page(footnote), point: CGPoint(x: 60, y: 610)
                )

                if fillColor == nil {
                    expect(hit) == .hyperlink(url: "https://example.com/under", blockIndex: 0)
                } else {
                    expect(hit) == .footnote(blockIndex: 0, number: 1)
                }
                // 도형 밖은 어느 경우든 아래 링크가 열린다
                expect(HwpHitTester().hit(
                    page: Self.page(footnote), point: CGPoint(x: 300, y: 610)
                )) == .hyperlink(url: "https://example.com/under", blockIndex: 0)
            }
        }

        /// 폰트를 고정해 글리프 rect가 기기에 따라 달라지지 않게 한 스팬 문단.
        private static func spanParagraph(
            _ text: String, url: String, rect: CGRect, paragraphId: UInt32
        ) -> HwpLaidOutParagraph {
            let attributed = NSMutableAttributedString(string: text)
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
            )
            attributed.addAttribute(HwpAttributedStringKey.hyperlink, value: url, range: full)
            return HwpLaidOutParagraph(
                attributedString: attributed,
                frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
                rect: rect,
                paragraphId: paragraphId,
                hyperlinkURL: url
            )
        }

        private static func page(_ footnote: HwpFootnoteBlock) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: footnote.frame, kind: .footnote, payload: .footnote(footnote)
                )],
                pageNumber: 1
            )
        }
    }
#endif
