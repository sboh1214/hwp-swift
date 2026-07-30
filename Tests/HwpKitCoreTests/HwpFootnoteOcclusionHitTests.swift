import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

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

        /// 채우기 없는 글상자도 **불투명**하다 (R43 #2) — `textboxCommands`가
        /// `fillColor`가 없으면 `.hwpWhite`로 칠하므로 "채우기 없음 = 투명"이 아니다.
        /// 보이는 흰 상자를 눌렀는데 아래 문단 링크가 열리면 안 된다.
        func testDefaultWhiteTextboxOccludesFootnoteLink() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.linkParagraph(
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                    textbox: HwpTextboxFrame(
                        outerFrame: CGRect(x: 0, y: 0, width: 100, height: 40),
                        paragraphs: [], borderColor: nil, borderWidth: 0, fillColor: nil
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 7
                )]
            )

            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 60, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 300, y: 610)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 채운 도형은 **경로 안쪽만** 가린다 (R43 #3) — `shapeCommands`가
        /// `geometry.path`만 칠하므로 바운딩 rect로 판정하면 타원의 투명한 모서리가
        /// 가림으로 잡혀 그 아래 보이는 링크가 안 눌린다.
        func testFilledEllipseOccludesOnlyInsideItsPath() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let ellipseRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.linkParagraph(
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: ellipseRect,
                    geometry: HwpShapeGeometry(
                        path: CGPath(ellipseIn: ellipseRect, transform: nil),
                        fillColor: HwpRGBColor(red: 255, green: 0, blue: 0).cgColor,
                        strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 8
                )]
            )

            // 타원 중심 (블록-로컬 50,20) 은 가린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 100, y: 620)))
                == .footnote(blockIndex: 0, number: 1)
            // 바운딩 박스 왼쪽 위 모서리 (2,2) 는 타원 밖이라 아래 링크가 눌린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 52, y: 602)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 글상자 **안** 전경 개체도 그 글상자 문단 뒤에 그려진다 (R43 #4) —
        /// `textboxCommands`가 글 뒤 자식 → 문단 → 글 앞 자식 순이므로, 안쪽
        /// 문단 링크를 덮은 자식이 있으면 그 링크가 열리면 안 된다.
        func testForegroundChildInsideFootnoteTextboxOccludesItsParagraphLink() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let boxRect = CGRect(x: 0, y: 0, width: 200, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: boxRect,
                    textbox: HwpTextboxFrame(
                        outerFrame: boxRect,
                        paragraphs: [Self.linkParagraph(rect: boxRect)],
                        borderColor: nil, borderWidth: 0, fillColor: nil,
                        shapes: [HwpCellShape(
                            rect: CGRect(x: 0, y: 0, width: 60, height: 40),
                            geometry: HwpShapeGeometry(
                                path: CGPath(
                                    rect: CGRect(x: 0, y: 0, width: 60, height: 40),
                                    transform: nil
                                ),
                                fillColor: HwpRGBColor(red: 0, green: 0, blue: 255).cgColor,
                                strokeColor: nil, strokeWidth: 0
                            ),
                            paintsBehindText: false,
                            zOrder: 0, sourceOrder: 0, controlInstanceId: 9
                        )]
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 10
                )]
            )

            // 자식 도형이 덮은 자리 (블록-로컬 10,10)
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 60, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            // 자식 밖 글상자 문단 (블록-로컬 100,10) 은 링크가 눌린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 150, y: 610)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 채운 셀도 아래를 가린다 (R43 #5) — 각주 안 표는 문단 **뒤에** 그려지므로
        /// 링크가 없다고 통과시키면 그 아래 문단 링크가 열린다.
        func testFilledFootnoteTableCellOccludesLowerParagraphLink() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [],
                borders: .uniform(width: 0.5, color: black),
                fillColor: HwpRGBColor(red: 200, green: 200, blue: 200)
            )
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.linkParagraph(
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: cellRect,
                    table: HwpTableFrame(
                        outerFrame: cellRect,
                        rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 11
                )]
            )

            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 60, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 300, y: 610)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 셀을 넘어 그려진 자손도 눌려야 한다 (R44 #2) — `tableHit`이 셀 프레임으로
        /// 미리 거르면 자격 영역은 그 자리를 인정하는데 조회가 막혀 보이는 링크가
        /// 죽는다. R41 #2에서 중첩 표 게이트를 걷어낼 때 셀 게이트가 남아 있었다.
        func testFootnoteTableCellDescendantOutsideCellFrameIsTappable() {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            // 셀 프레임은 100pt인데 그 안 문단은 500pt로 넘쳐 그려진다
            let cellFrame = CGRect(x: 0, y: 0, width: 100, height: 30)
            let cell = HwpTableCellFrame(
                cellFrame: cellFrame,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(string: "셀 밖으로 넘친 링크"),
                    frame: HwpParagraphFrame(totalHeight: 30, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 500, height: 30),
                    paragraphId: 1,
                    hyperlinkURL: "https://example.com/cell-overflow"
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
                    rect: cellFrame,
                    table: HwpTableFrame(
                        outerFrame: cellFrame,
                        rows: [HwpTableRowFrame(rowFrame: cellFrame, cells: [cell])],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 12
                )]
            )

            // 블록-로컬 (300,10) — 셀 프레임(100pt) 밖이지만 문단이 그려진 자리
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 350, y: 610)))
                == .hyperlink(url: "https://example.com/cell-overflow", blockIndex: 0)
        }

        /// 글상자 **밖에** 놓인 자식의 가림도 전파돼야 한다 (R44 #3) — 재귀가
        /// `.occluded`를 돌려주는데 `.found`만 받으면, 글상자 자신은 그 자리를
        /// 안 가리므로 아래 문단 링크가 열린다.
        func testOverflowingTextboxChildOcclusionPropagates() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let boxRect = CGRect(x: 0, y: 0, width: 50, height: 40)
            // 자식 도형이 글상자(50pt)를 넘어 200pt까지 채워 그려진다
            let childRect = CGRect(x: 0, y: 0, width: 200, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.linkParagraph(
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: boxRect,
                    textbox: HwpTextboxFrame(
                        outerFrame: boxRect,
                        paragraphs: [], borderColor: nil, borderWidth: 0, fillColor: nil,
                        shapes: [HwpCellShape(
                            rect: childRect,
                            geometry: HwpShapeGeometry(
                                path: CGPath(rect: childRect, transform: nil),
                                fillColor: HwpRGBColor(red: 0, green: 255, blue: 0).cgColor,
                                strokeColor: nil, strokeWidth: 0
                            ),
                            paintsBehindText: false,
                            zOrder: 0, sourceOrder: 0, controlInstanceId: 13
                        )]
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 14
                )]
            )

            // 블록-로컬 (150,10) — 글상자 rect 밖이지만 자식 도형이 덮은 자리
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 200, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            // 자식도 없는 자리는 아래 링크가 열린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 350, y: 610)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 잘려 나간 그림 부분은 가리지 않는다 (R45 #2) — `cellImageCommands`가
        /// `clipRect` 안만 그리므로, 저작 rect 전체를 불투명으로 보면 절단면 밖의
        /// 보이는 링크가 죽는다. 도형의 "경로만 칠한다"(R43 #3)와 같은 논리다.
        func testClippedImageOccludesOnlyItsVisiblePart() {
            let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
            let imageRect = CGRect(x: 0, y: 0, width: 200, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [Self.linkParagraph(
                    rect: CGRect(x: 0, y: 0, width: 400, height: 40)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                images: [HwpCellImage(
                    rect: imageRect,
                    binItemId: 3,
                    style: nil,
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    // 왼쪽 절반만 보인다 (표-로컬 — rect와 같은 좌표계)
                    clipRect: CGRect(x: 0, y: 0, width: 100, height: 40),
                    controlInstanceId: 15
                )]
            )

            // 보이는 절반 (블록-로컬 50,20) 은 가린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 100, y: 620)))
                == .footnote(blockIndex: 0, number: 1)
            // 잘려 나간 절반 (블록-로컬 150,20) 은 아래 링크가 눌린다
            expect(HwpHitTester().hit(page: Self.page(footnote), point: CGPoint(x: 200, y: 620)))
                == .hyperlink(url: "https://example.com/under", blockIndex: 0)
        }

        /// 가림은 **블록 경계를 넘어서도** 유지된다 (R45 #3). 각주 개체가 자기
        /// 블록 밖까지 덮으면, `.occluded`를 nil로 접어 아래 블록으로 내려가는
        /// 순간 그 밑에 깔린 본문 링크가 열린다.
        func testOcclusionOutsideBlockFrameDoesNotFallThroughToLowerBlock() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 도형이 블록(100pt)을 넘어 300pt까지 채워 그려진다
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
                        fillColor: HwpRGBColor(red: 255, green: 0, blue: 0).cgColor,
                        strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 16
                )]
            )
            // 각주 아래에 깔린 본문 링크 블록 (페인트 순서상 먼저 = 아래)
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

            // 블록 frame(maxX 150) 밖이지만 도형이 덮은 자리 — 아래 링크가 열리면 안 된다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 250, y: 620)))
                == .footnote(blockIndex: 1, number: 1)
            // 도형도 없는 자리는 아래 본문 링크가 열린다
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 400, y: 620)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 가림 테스트가 공유하는 링크 문단 (스팬 없이 문단-레벨 URL).
        private static func linkParagraph(rect: CGRect) -> HwpLaidOutParagraph {
            HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "가려질 링크 텍스트"),
                frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
                rect: rect,
                paragraphId: 1,
                hyperlinkURL: "https://example.com/under"
            )
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
