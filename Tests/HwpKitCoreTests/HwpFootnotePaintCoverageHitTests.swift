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
        /// 안쪽에 테두리 띠 넷을 그리므로 그 선 위의 탭은 표가 가져가야 하고,
        /// 칸 **안**(투명)만 아래 블록 몫이다.
        func testUnfilledNestedTableBorderClaimsButInteriorFallsThrough() {
            let page = Self.pageWithUnfilledNestedTable(wrappedByLink: false)
            // 셀 위쪽 테두리 띠 (1pt) — 각주가 claim한다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 600.5)))
                == .footnote(blockIndex: 1, number: 1)
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
        }

        /// 블록(100pt)을 넘어 300pt까지 뻗은 **안 채운** 중첩 표 + 그 아래 링크 블록.
        private static func pageWithUnfilledNestedTable(wrappedByLink: Bool) -> HwpPage {
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
        }
    }
#endif
