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
                        controlIndex: 0,
                        // 이 개체를 낸 문단 — 서수는 문단마다 0부터라 쌍이어야
                        // 감싼 링크와 이어진다 (R51 #1)
                        paragraphId: 1
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

        /// 감싼 링크 구제는 **가림**이 아니라 **칠**을 본다 (R54). 속 빈 도형은
        /// 아래를 가리지 않아 `occludes`가 거짓이지만, 그 테두리 선 위의 탭은
        /// 그 개체를 가리키므로 감싼 `%hlk`가 열려야 한다. 링크가 없으면 같은
        /// 자리가 각주 히트로 남는다 (칠해진 자리이므로 claim은 한다).
        func testWrapperLinkOpensOnHollowShapeBorder() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let shapeRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            func footnote(wrappedByLink: Bool) -> HwpFootnoteBlock {
                let attributed = NSMutableAttributedString(string: "\u{FFFC}")
                let full = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
                )
                attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
                if wrappedByLink {
                    attributed.addAttribute(
                        HwpAttributedStringKey.hyperlink,
                        value: "https://example.com/hollow", range: full
                    )
                }
                return HwpFootnoteBlock(
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
                    shapes: [HwpCellShape(
                        rect: shapeRect,
                        geometry: HwpShapeGeometry(
                            path: CGPath(rect: shapeRect, transform: nil),
                            fillColor: nil,
                            strokeColor: HwpRGBColor(red: 0, green: 0, blue: 0).cgColor,
                            strokeWidth: 1
                        ),
                        paintsBehindText: false,
                        zOrder: 0, sourceOrder: 0,
                        controlInstanceId: 22,
                        controlIndex: 0,
                        paragraphId: 1
                    )]
                )
            }

            // 도형 오른쪽 테두리 — U+FFFC 글리프(문단 왼쪽 끝)에서 멀어 스팬
            // 히트가 아니라 감싼 링크 구제만이 답을 낼 수 있는 자리다
            let onBorder = CGPoint(x: 149.8, y: 620)
            expect(HwpHitTester().hit(page: Self.page(footnote(wrappedByLink: true)), point: onBorder))
                == .hyperlink(url: "https://example.com/hollow", blockIndex: 0)
            expect(HwpHitTester().hit(
                page: Self.page(footnote(wrappedByLink: false)), point: onBorder
            )) == .footnote(blockIndex: 0, number: 1)

            // 도형 **안쪽** (칠하지 않은 자리) — 감싼 링크는 개체 rect 전체의
            // 것이므로 방출(전체 rect)과 같은 답이어야 한다 (R60). U+FFFC 글리프
            // (문단 왼쪽 끝)에서 멀어 스팬 히트로는 나올 수 없는 자리다.
            expect(HwpHitTester().hit(
                page: Self.page(footnote(wrappedByLink: true)), point: CGPoint(x: 100, y: 620)
            )) == .hyperlink(url: "https://example.com/hollow", blockIndex: 0)
        }

        /// 각주도 **블록-레벨 하이퍼링크 폴백**을 지킨다 (R59). 방출은 컨테이너
        /// 링크가 하나도 없으면 `block.hyperlinkURL`을 frame 전체로 내므로, 히트가
        /// 층 조회만 보고 끝내면 밑줄은 그려지는데 탭이 안 먹는다.
        func testFootnoteBlockLevelHyperlinkStaysTappable() {
            let page = Self.pageWithFootnote(
                paragraphURL: nil, blockURL: "https://example.com/block-level"
            )
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 100, y: 620)))
                == .hyperlink(url: "https://example.com/block-level", blockIndex: 0)
        }

        /// 폴백은 **층 조회가 실패했을 때만** 쓴다 — 각주 문단이 자기 링크를
        /// 가지면 그것이 이긴다 (R42 #1의 순서를 그대로 지킨다).
        func testFootnoteInnerLinkWinsOverBlockLevelFallback() {
            let page = Self.pageWithFootnote(
                paragraphURL: "https://example.com/inner",
                blockURL: "https://example.com/block-level"
            )
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 100, y: 610)))
                == .hyperlink(url: "https://example.com/inner", blockIndex: 0)
        }

        /// 안쪽 링크가 있으면 블록 URL로 **폴백하지 않는다** (R61). 방출은 컨테이너
        /// 링크를 하나라도 내면 프레임 전체 블록 링크를 내지 않으므로, 안쪽 링크가
        /// 안 걸리는 자리에서 폴백하면 **paint list에 없는 URL**이 열린다.
        func testFootnoteBlockFallbackIsSuppressedWhenInnerLinkExists() {
            let page = Self.pageWithFootnote(
                paragraphURL: "https://example.com/inner",
                blockURL: "https://example.com/block-level"
            )
            // 문단 rect(위 20pt) **아래** — 안쪽 링크가 claim하지 않는 자리
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 100, y: 635)))
                == .footnote(blockIndex: 0, number: 1)
        }

        /// 문단-레벨 링크(선택)와 블록-레벨 링크를 가진 각주 한 장.
        private static func pageWithFootnote(
            paragraphURL: String?, blockURL: String
        ) -> HwpPage {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(string: "각주 본문"),
                    frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 400, height: 20),
                    paragraphId: 1,
                    hyperlinkURL: paragraphURL
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1)
            )
            return HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: blockFrame,
                    kind: .footnote,
                    hyperlinkURL: blockURL,
                    payload: .footnote(footnote)
                )],
                pageNumber: 1
            )
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
                    controlIndex: 3,
                    paragraphId: 1
                )]
            )

            expect(HwpHitTester().hit(
                page: Self.page(footnote), point: CGPoint(x: 100, y: 620)
            )) == .hyperlink(url: "https://example.com/wrapped-table", blockIndex: 0)
        }

        /// 기하 복사 헬퍼가 감싼 링크 열쇠를 **보존**한다 (R51 #2). 세로 정렬이
        /// 개체를 옮기거나(`verticallyAligned`) 표 분할이 클립·이동하면 이 헬퍼를
        /// 지난다. 기본값으로 떨어진 열쇠는 U+FFFC run과 매칭되지 않아 감싼
        /// 링크가 가림으로 죽는다.
        func testGeometryCopyHelpersPreserveWrapperKey() throws {
            let image = HwpCellImage(
                rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                binItemId: 1, style: nil,
                paintsBehindText: false, zOrder: 0, sourceOrder: 0,
                controlInstanceId: 9, controlIndex: 4, paragraphId: 7
            )
            let shape = HwpCellShape(
                rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                geometry: HwpShapeGeometry(
                    path: CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil),
                    fillColor: nil, strokeColor: nil, strokeWidth: 0
                ),
                paintsBehindText: false, zOrder: 0, sourceOrder: 0,
                controlInstanceId: 9, controlIndex: 4, paragraphId: 7
            )
            let textbox = HwpCellTextbox(
                rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                    paragraphs: [], borderColor: nil, borderWidth: 0, fillColor: nil
                ),
                paintsBehindText: false, zOrder: 0, sourceOrder: 0,
                controlInstanceId: 9, controlIndex: 4, paragraphId: 7
            )
            let nested = HwpNestedTableFrame(
                rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                table: HwpTableFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                    rows: [], borderColor: HwpRGBColor(red: 0, green: 0, blue: 0), borderWidth: 0
                ),
                controlInstanceId: 9, controlIndex: 4, paragraphId: 7
            )
            let moved = CGRect(x: 5, y: 5, width: 10, height: 10)
            // 헬퍼만이 아니라 그것을 쓰는 셀 이동 경로까지 태운다 (R52)
            let movedInCell = try XCTUnwrap(HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 0, width: 20, height: 20),
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [],
                borders: .uniform(width: 0, color: HwpRGBColor(red: 0, green: 0, blue: 0)),
                fillColor: nil,
                nestedTables: [nested]
            ).offsetBy(deltaY: 5).nestedTables.first)

            for key in [
                (image.withRect(moved).controlIndex, image.withRect(moved).paragraphId),
                (image.withClip(moved).controlIndex, image.withClip(moved).paragraphId),
                (shape.withRect(moved).controlIndex, shape.withRect(moved).paragraphId),
                (textbox.withRect(moved).controlIndex, textbox.withRect(moved).paragraphId),
                (nested.withRect(moved).controlIndex, nested.withRect(moved).paragraphId),
                (
                    nested.withTable(nested.table).controlIndex,
                    nested.withTable(nested.table).paragraphId
                ),
                (movedInCell.controlIndex, movedInCell.paragraphId),
            ] {
                expect(key.0) == 4
                expect(key.1) == 7
            }
        }

        /// 서수는 **문단마다 0부터** 다시 시작하므로 (`ctrlHeaderArray.enumerated()`)
        /// 여러 문단을 가진 글상자·셀에서는 서수만으로 유일하지 않다 (R51 #1).
        /// 앞 문단의 컨트롤 0에 감싼 링크가 있을 때 뒤 문단의 컨트롤 0을 누르면
        /// 앞 링크가 열리면 안 된다 — 열쇠는 (문단, 서수) 쌍이다.
        func testWrapperLookupDoesNotLeakAcrossParagraphs() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            func paragraph(id: UInt32, linked: Bool, rect: CGRect) -> HwpLaidOutParagraph {
                let attributed = NSMutableAttributedString(string: "\u{FFFC}")
                let full = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
                )
                attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
                if linked {
                    attributed.addAttribute(
                        HwpAttributedStringKey.hyperlink,
                        value: "https://example.com/first-paragraph", range: full
                    )
                }
                return HwpLaidOutParagraph(
                    attributedString: attributed,
                    frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
                    rect: rect,
                    paragraphId: id,
                    hyperlinkURL: nil
                )
            }
            // 셀에 문단 둘 — 앞(1)만 감싼 링크, 둘 다 컨트롤 서수 0
            let cellRect = CGRect(x: 0, y: 0, width: 200, height: 80)
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [
                    paragraph(id: 1, linked: true, rect: CGRect(x: 0, y: 0, width: 200, height: 40)),
                    paragraph(id: 2, linked: false, rect: CGRect(x: 0, y: 40, width: 200, height: 40)),
                ],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil,
                shapes: [HwpCellShape(
                    rect: CGRect(x: 0, y: 40, width: 200, height: 40),
                    geometry: HwpShapeGeometry(
                        path: CGPath(
                            rect: CGRect(x: 0, y: 0, width: 200, height: 40), transform: nil
                        ),
                        fillColor: HwpRGBColor(red: 255, green: 0, blue: 0).cgColor,
                        strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 50,
                    controlIndex: 0,
                    paragraphId: 2
                )]
            )
            let blockFrame = CGRect(x: 50, y: 600, width: 200, height: 80)
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: blockFrame,
                    kind: .table,
                    payload: .table(HwpTableFrame(
                        outerFrame: cellRect,
                        rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                        borderColor: black, borderWidth: 1
                    ))
                )],
                pageNumber: 1
            )

            // 뒤 문단(2)의 도형을 누르면 앞 문단(1)의 링크가 열리면 안 된다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 100, y: 660)))
                == .table(blockIndex: 0, row: 0, col: 0)
        }

        /// **셀 안** 중첩 표를 감싼 `%hlk`도 가림보다 먼저 살아난다 (R52). 셀 안
        /// 표는 셀 페인터 순서를 따르느라 층 경로(`layerHit`) 밖에 있어 그 구제를
        /// 못 받았다 — 채운 셀을 가진 중첩 표가 자기 링크를 가렸다.
        func testHyperlinkWrappingNestedTableInCellStaysTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 200, height: 80)
            let nestedRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            func cell(wrappedByLink: Bool) -> HwpTableCellFrame {
                let attributed = NSMutableAttributedString(string: "\u{FFFC}")
                let full = NSRange(location: 0, length: attributed.length)
                attributed.addAttribute(
                    .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil), range: full
                )
                attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 2, range: full)
                if wrappedByLink {
                    attributed.addAttribute(
                        HwpAttributedStringKey.hyperlink,
                        value: "https://example.com/wrapped-cell-table", range: full
                    )
                }
                return HwpTableCellFrame(
                    cellFrame: cellRect,
                    row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                    // 문단은 표 **아래** 절반에 둔다 — 스팬 글리프 rect로 눌리면
                    // 감싼 링크 구제가 아니라 평범한 스팬 히트를 재는 셈이 된다
                    paragraphs: [HwpLaidOutParagraph(
                        attributedString: attributed,
                        frame: HwpParagraphFrame(totalHeight: 40, lines: []),
                        rect: CGRect(x: 0, y: 40, width: 200, height: 40),
                        paragraphId: 11,
                        hyperlinkURL: nil
                    )],
                    borders: .uniform(width: 0.5, color: black),
                    fillColor: nil,
                    nestedTables: [HwpNestedTableFrame(
                        rect: nestedRect,
                        table: HwpTableFrame(
                            outerFrame: nestedRect,
                            rows: [HwpTableRowFrame(rowFrame: nestedRect, cells: [
                                HwpTableCellFrame(
                                    cellFrame: nestedRect,
                                    row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                                    paragraphs: [],
                                    borders: .uniform(width: 0.5, color: black),
                                    // 채운 셀 — 링크가 없으면 가린다 (R43 #5)
                                    fillColor: HwpRGBColor(red: 200, green: 200, blue: 200)
                                ),
                            ])],
                            borderColor: black, borderWidth: 1
                        ),
                        controlInstanceId: 60,
                        controlIndex: 2,
                        paragraphId: 11
                    )]
                )
            }
            func page(_ cell: HwpTableCellFrame) -> HwpPage {
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [AnyHwpBlock(
                        frame: CGRect(x: 50, y: 600, width: 200, height: 80),
                        kind: .table,
                        payload: .table(HwpTableFrame(
                            outerFrame: cellRect,
                            rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                            borderColor: black, borderWidth: 1
                        ))
                    )],
                    pageNumber: 1
                )
            }

            let inNestedFill = CGPoint(x: 100, y: 620)
            expect(HwpHitTester().hit(page: page(cell(wrappedByLink: true)), point: inNestedFill))
                == .hyperlink(url: "https://example.com/wrapped-cell-table", blockIndex: 0)
            // 링크 없는 같은 표는 그대로 가린다 (R42 #2)
            expect(HwpHitTester().hit(page: page(cell(wrappedByLink: false)), point: inNestedFill))
                == .table(blockIndex: 0, row: 0, col: 0)
        }
    }
#endif
