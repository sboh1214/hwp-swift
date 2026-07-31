import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 개체를 감싼 %hlk (R49/R50)

    extension HwpFootnoteObjectLayoutTests {
        /// `%hlk`가 감싼 인라인 개체는 **자기 링크로 눌린다** (R49). run builder가
        /// 필드 범위를 U+FFFC run까지 포함해 닫으므로 개체의 링크는 개체 페이로드가
        /// 아니라 **부모 문단의 스팬**에 산다 — 층을 먼저 보는 규약(R42 #1) 그대로면
        /// 개체가 자기 링크를 가린다. 링크 없는 같은 개체는 여전히 아래를 가려야
        /// 하므로(R42 #2) 양쪽을 함께 태운다.
        func testHyperlinkWrappingFootnoteObjectStaysTappable() throws {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let objectRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            func footnote(wrappedByLink: Bool) -> HwpFootnoteBlock {
                let attributed = NSMutableAttributedString(string: "\u{FFFC}")
                let full = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
                )
                // run builder가 U+FFFC run에 다는 것과 같은 controlIndex —
                // 이것이 링크와 개체를 잇는 열쇠다 (R50 #1).
                attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
                if wrappedByLink {
                    attributed.addAttribute(
                        HwpAttributedStringKey.hyperlink,
                        value: "https://example.com/wrapped", range: full
                    )
                }
                return HwpFootnoteBlock(
                    frame: blockFrame,
                    paragraphs: [HwpLaidOutParagraph(
                        attributedString: attributed,
                        frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                        rect: CGRect(x: 0, y: 0, width: 400, height: 40),
                        paragraphId: 1,
                        hyperlinkURL: wrappedByLink ? "https://example.com/wrapped" : nil
                    )],
                    number: 1,
                    separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                    images: [HwpCellImage(
                        rect: objectRect,
                        binItemId: 3,
                        style: nil,
                        paintsBehindText: false,
                        zOrder: 0, sourceOrder: 0,
                        controlInstanceId: 40,
                        controlIndex: 0
                    )]
                )
            }

            // 스팬이 감싼 개체 — 개체 자리를 눌러도 그 링크가 나온다
            let linkRegions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: try XCTUnwrap(footnote(wrappedByLink: true).paragraphs.first)
                    .attributedString,
                origin: .zero,
                lineWidth: 400
            )
            let glyph = try XCTUnwrap(linkRegions.first, "U+FFFC run에 링크 스팬이 없다").rect
            let inGlyph = CGPoint(
                x: blockFrame.minX + glyph.midX, y: blockFrame.minY + glyph.midY
            )
            expect(HwpHitTester().hit(page: Self.page(footnote(wrappedByLink: true)), point: inGlyph))
                == .hyperlink(url: "https://example.com/wrapped", blockIndex: 0)
            // 링크 없는 같은 개체는 그대로 불투명하게 가린다
            expect(HwpHitTester().hit(
                page: Self.page(footnote(wrappedByLink: false)), point: inGlyph
            )) == .footnote(blockIndex: 0, number: 1)
        }

        /// 개체가 **다른** 링크 텍스트를 덮었을 뿐이면 구제하지 않는다 (R50 #1).
        /// 구제를 지점 포함만으로 하면 덮인 링크가 열려 가림 규약(R42 #2)이 깨진다 —
        /// 링크가 붙은 run의 `controlIndex`가 그 층의 것과 같을 때만 구제한다.
        func testOpaqueObjectCoveringUnrelatedSpanLinkStaysOccluded() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let attributed = NSMutableAttributedString(string: "덮인 링크 텍스트")
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
            )
            // 개체(controlIndex 7)와 **무관한** 텍스트 스팬 링크
            attributed.addAttribute(
                HwpAttributedStringKey.hyperlink,
                value: "https://example.com/covered-span", range: full
            )
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: attributed,
                    frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                images: [HwpCellImage(
                    rect: CGRect(x: 0, y: 0, width: 200, height: 40),
                    binItemId: 3,
                    style: nil,
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 41,
                    controlIndex: 7
                )]
            )

            // 그림이 링크 글리프를 덮은 자리 — 그림의 링크가 아니므로 가린다
            expect(HwpHitTester().hit(
                page: Self.page(footnote), point: CGPoint(x: 55, y: 605)
            )) == .footnote(blockIndex: 0, number: 1)
        }

        /// `%hlk`가 **채운 셀을 가진 표**를 감싸면 그 링크가 열린다 (R50 #2) —
        /// `tableHit`의 `.occluded`를 감싼 스팬 확인 **전에** 반환하면 각주 히트로
        /// 떨어진다.
        func testHyperlinkWrappingFilledNestedTableStaysTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            let attributed = NSMutableAttributedString(string: "\u{FFFC}")
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
            )
            attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 3, range: full)
            attributed.addAttribute(
                HwpAttributedStringKey.hyperlink,
                value: "https://example.com/wrapped-table", range: full
            )
            let footnote = HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 600, width: 400, height: 40),
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: attributed,
                    frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: cellRect,
                    table: HwpTableFrame(
                        outerFrame: cellRect,
                        rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [HwpTableCellFrame(
                            cellFrame: cellRect,
                            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                            paragraphs: [],
                            borders: .uniform(width: 0.5, color: black),
                            // 채운 셀 — 링크가 없으면 가린다 (R43 #5)
                            fillColor: HwpRGBColor(red: 200, green: 200, blue: 200)
                        )])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 42,
                    controlIndex: 3
                )]
            )

            expect(HwpHitTester().hit(
                page: Self.page(footnote), point: CGPoint(x: 100, y: 620)
            )) == .hyperlink(url: "https://example.com/wrapped-table", blockIndex: 0)
        }
    }
#endif
