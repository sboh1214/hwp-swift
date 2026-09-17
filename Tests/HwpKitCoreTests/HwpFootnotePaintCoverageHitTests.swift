import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 칠 커버리지 (R54) — claim은 정밀 커버리지, 자격 영역은 상위집합

    extension HwpFootnoteObjectLayoutTests {
        /// 전경 글자가 **글 뒤로** 개체보다 먼저 claim한다 (R54). 링크 없는 문단은
        /// 아무 히트도 내지 않아 뒤 층의 숨은 링크가 열렸다 — 페인트 역순 규약이
        /// 깨진다. 줄 사이 여백처럼 **안 칠한** 자리는 그대로 뒤 층으로 내려간다.
        func testForegroundTextClaimsBeforeBehindTextLink() {
            let blockFrame = CGRect(x: 50, y: 600, width: 300, height: 60)
            let behindBox = HwpTextboxFrame(
                outerFrame: CGRect(x: 0, y: 0, width: 300, height: 60),
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(string: "뒤 링크"),
                    frame: HwpParagraphFrame(totalHeight: 60, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 300, height: 60),
                    paragraphId: 2,
                    hyperlinkURL: "https://example.com/behind"
                )],
                borderColor: nil, borderWidth: 0, fillColor: nil
            )
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                // 전경 문단은 위쪽 20pt 띠에만 글자를 그린다
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(
                        string: String(repeating: "앞글자", count: 6)
                    ),
                    frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 300, height: 20),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 0, y: 0, width: 300, height: 60),
                    textbox: behindBox,
                    paintsBehindText: true,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 23
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

            // 전경 글자 위 — 뒤 링크가 열리면 안 된다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 60, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            // 글자가 없는 아래 띠 — 뒤 글상자의 링크가 열린다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 60, y: 650)))
                == .hyperlink(url: "https://example.com/behind", blockIndex: 0)
        }

        /// 넘침 띠의 **투명한** 자리는 각주가 claim하지 않는다 (R54). 자격 영역은
        /// bounding box라 속 빈 도형의 안쪽까지 들어오지만 거기엔 아무것도 안
        /// 칠했으므로, 아래 블록의 **보이는** 링크가 열려야 한다. 반대로 테두리
        /// 선 위는 칠해진 자리라 각주가 가져간다.
        func testTransparentOverflowDoesNotClaimButPaintedBorderDoes() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 속 빈 사각형이 블록(100pt)을 넘어 300pt까지 — 테두리만 그린다
            let shapeRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: shapeRect,
                    geometry: HwpShapeGeometry(
                        path: CGPath(rect: shapeRect, transform: nil),
                        fillColor: nil,
                        strokeColor: HwpRGBColor(red: 0, green: 0, blue: 0).cgColor,
                        strokeWidth: 1
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 21
                )]
            )
            let underBlock = AnyHwpBlock(
                frame: CGRect(x: 50, y: 600, width: 400, height: 40),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [underBlock, AnyHwpBlock(
                    frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                )],
                pageNumber: 1
            )

            // 도형 안쪽 (칠하지 않은 자리) — 아래 본문 링크가 열린다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 620)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
            // 위 테두리 선 위 (1pt 굵기) — 각주가 claim한다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 600.2)))
                == .footnote(blockIndex: 1, number: 1)
        }

        /// **안 채운 표도 칸막이는 칠한다** (R55). 페인터(`borderCommands`)가 셀
        /// 모서리에 중심을 둔 테두리 띠 넷을 그리므로 그 선 위의 탭은 표가 가져가야 하고,
        /// 칸 **안**(투명)만 아래 블록 몫이다.
        func testUnfilledNestedTableBorderClaimsButInteriorFallsThrough() {
            let page = Self.pageWithUnfilledNestedTable(wrappedByLink: false)
            // 셀 위쪽 테두리 띠 (1pt, 모서리 600 양쪽 0.5) — 각주가 claim한다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 600.2)))
                == .footnote(blockIndex: 1, number: 1)
            // 모서리 **바깥** 절반(599.5~600)도 칠한 자리다 — 자격 영역이 각주 프레임(600~)
            // 에서 멈추면 게이트에서 기각돼 아래 링크가 열린다 (R54 `자격 ⊇ 칠`, #191 리뷰).
            // 아래 블록이 그 자리까지 올라와 있어도 각주가 먼저다
            let raised = Self.pageWithUnfilledNestedTable(wrappedByLink: false, underBlockTop: 590)
            expect(HwpHitTester().hit(page: raised, point: CGPoint(x: 250, y: 599.7)))
                == .footnote(blockIndex: 1, number: 1)
            // 띠 밖(599.5 위)은 각주가 칠하지 않았다 — 자격은 칠한 곳까지만 넓어져 아래 링크
            expect(HwpHitTester().hit(page: raised, point: CGPoint(x: 250, y: 599.3)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
            // 칸 안 — 아무것도 안 칠했으니 아래 본문 링크가 열린다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 620)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 안 채운 표를 감싼 `%hlk`도 테두리 선 위에서 열린다 (R55). `tableHit`이
        /// 칸막이를 `.miss`로 보면 `layerHit`의 구제에 닿지 못해 컨테이너 히트로
        /// 떨어졌다 — 도형 stroke(R54)와 같은 축이다.
        func testWrapperLinkOpensOnUnfilledNestedTableBorder() {
            let page = Self.pageWithUnfilledNestedTable(wrappedByLink: true)
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 600.5)))
                == .hyperlink(url: "https://example.com/wrapped-unfilled", blockIndex: 1)
            // 칸 **안**(투명)도 감싼 링크의 영역이다 — 방출이 표 rect 전체로 내므로
            // 히트도 같아야 한다 (R60). 링크 없는 같은 표는 위 테스트대로 통과한다.
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 620)))
                == .hyperlink(url: "https://example.com/wrapped-unfilled", blockIndex: 1)
        }

        /// 자격 영역은 문단 rect가 아니라 **렌더가 닿을 수 있는 상위집합**이어야
        /// 한다 (R56). 캐시 높이가 대체 폰트 CT 줄보다 짧으면 글자가 rect 아래로
        /// 그려지는데, rect로 자르면 그 글자 위의 탭이 `containerHit`에 닿기도
        /// 전에 기각돼 아래 블록 링크가 열린다.
        func testTextPaintedBelowShortParagraphRectStillClaims() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            let text = NSMutableAttributedString(string: String(repeating: "각주", count: 12))
            text.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil),
                range: NSRange(location: 0, length: text.length)
            )
            // 문단 rect 높이는 5pt뿐 — CT 줄(≈14pt)이 그 아래로 넘쳐 그려진다
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: text,
                    frame: HwpParagraphFrame(totalHeight: 5, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 300, height: 5),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1)
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(
                        frame: CGRect(x: 50, y: 600, width: 400, height: 40),
                        kind: .text,
                        attributedString: NSAttributedString(string: "본문 링크"),
                        hyperlinkURL: "https://example.com/beneath"
                    ),
                    AnyHwpBlock(
                        frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                    ),
                ],
                pageNumber: 1
            )

            // 문단 rect 아래(605 밖)지만 글자가 그려진 자리 — 각주가 claim한다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 608)))
                == .footnote(blockIndex: 1, number: 1)
        }

        /// 테두리 stroke의 **바깥쪽 절반**도 칠이다 (R61). CG는 경로 중앙에 그어
        /// (`ctx.stroke(rect)`) 폭의 절반이 rect 밖에 놓이는데, 커버리지가 rect만
        /// 보면 보이는 선 위의 탭이 아래 블록 링크로 샌다.
        func testImageBorderStrokeOutsideRectIsPainted() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 그림이 블록(100pt)을 넘어 300pt까지 — 폭 2pt 테두리는 349~351에 그려진다
            let imageRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                images: [HwpCellImage(
                    rect: imageRect,
                    binItemId: 3,
                    style: nil,
                    borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
                    borderWidth: 2,
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 70
                )]
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(
                        frame: CGRect(x: 50, y: 600, width: 400, height: 40),
                        kind: .text,
                        attributedString: NSAttributedString(string: "본문 링크"),
                        hyperlinkURL: "https://example.com/beneath"
                    ),
                    AnyHwpBlock(
                        frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                    ),
                ],
                pageNumber: 1
            )

            // 그림 rect 오른쪽 끝(350)의 **바깥쪽** 0.5pt — 선이 보이는 자리다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 350.5, y: 620)))
                == .footnote(blockIndex: 1, number: 1)
        }

        /// 이중선의 **둘째 줄**도 칠이다 (R56). 페인터(`HwpBorderSet.edges`)는 셀 모서리에
        /// 중심을 둔 폭 띠 안에 가는 선 둘을 그린다 (#191) — 모서리 **밖**의 첫 줄 위의 탭도
        /// 이 셀을 가리키고, 두 줄 사이도 띠라 칠이며, 띠 밖은 아니다.
        func testDoubleBorderSecondStripeIsPainted() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [],
                borders: HwpBorderSet(
                    top: 3, bottom: 0, left: 0, right: 0,
                    topColor: black, bottomColor: black, leftColor: black, rightColor: black,
                    topShape: .doubleLine
                ),
                fillColor: nil
            )

            // 폭 3 → 띠 −1.5~1.5: 첫 줄 −1.5~−0.75, 둘째 줄 0.75~1.5
            expect(cell.paints(CGPoint(x: 50, y: -1.2))).to(beTrue())
            expect(cell.paints(CGPoint(x: 50, y: 1.2))).to(beTrue())
            expect(cell.paints(CGPoint(x: 50, y: 0))).to(beTrue())
            expect(cell.paints(CGPoint(x: 50, y: 2.5))).to(beFalse())
        }

        /// 블록(100pt)을 넘어 300pt까지 뻗은 **안 채운** 중첩 표 + 그 아래 링크 블록.
        private static func pageWithUnfilledNestedTable(
            wrappedByLink: Bool, underBlockTop: CGFloat = 600
        ) -> HwpPage {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            let tableRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let attributed = NSMutableAttributedString(string: "\u{FFFC}")
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
            )
            attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
            if wrappedByLink {
                attributed.addAttribute(
                    HwpAttributedStringKey.hyperlink,
                    value: "https://example.com/wrapped-unfilled", range: full
                )
            }
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: attributed,
                    frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: tableRect,
                    table: HwpTableFrame(
                        outerFrame: tableRect,
                        rows: [HwpTableRowFrame(rowFrame: tableRect, cells: [HwpTableCellFrame(
                            cellFrame: tableRect,
                            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                            paragraphs: [],
                            borders: .uniform(width: 1, color: black),
                            fillColor: nil
                        )])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 31,
                    controlIndex: 0,
                    paragraphId: 1
                )]
            )
            return HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(
                        frame: CGRect(
                            x: 50, y: underBlockTop, width: 400, height: 640 - underBlockTop
                        ),
                        kind: .text,
                        attributedString: NSAttributedString(string: "본문 링크"),
                        hyperlinkURL: "https://example.com/beneath"
                    ),
                    AnyHwpBlock(
                        frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
                    ),
                ],
                pageNumber: 1
            )
        }

        /// 최상위 표 블록도 프레임 밖 테두리 바깥 절반을 claim한다 (#191 리뷰) — 각주 갈래의
        /// `.occluded`와 같은 축이라, 위 문단의 링크 위에 놓인 표의 위 변 바깥 절반을 눌러도
        /// 링크가 열리지 않고 그 셀이 잡힌다. 띠 밖은 여전히 링크다.
        func testTopLevelTableClaimsTheOuterHalfOfItsBorder() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let cell = HwpTableCellFrame(
                cellFrame: cellRect, row: 2, column: 3, rowSpan: 1, columnSpan: 1,
                paragraphs: [], borders: .uniform(width: 2, color: black), fillColor: nil
            )
            let table = HwpTableFrame(
                outerFrame: cellRect,
                rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                borderColor: black, borderWidth: 1
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(
                        frame: CGRect(x: 50, y: 500, width: 400, height: 100),
                        kind: .text,
                        attributedString: NSAttributedString(string: "본문 링크"),
                        hyperlinkURL: "https://example.com/above"
                    ),
                    AnyHwpBlock(
                        frame: CGRect(x: 50, y: 600, width: 300, height: 40),
                        kind: .table, payload: .table(table)
                    ),
                ],
                pageNumber: 1
            )
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 200, y: 599.5)))
                == .table(blockIndex: 1, row: 2, col: 3)
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 200, y: 598.5)))
                == .hyperlink(url: "https://example.com/above", blockIndex: 0)
        }
    }
#endif
