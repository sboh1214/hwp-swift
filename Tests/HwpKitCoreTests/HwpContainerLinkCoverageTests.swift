import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 자격·층 라우팅의 남은 구멍 (R64)

    /// 방출이 내는 자리를 자격이 못 덮거나(미터 팁·중첩 표 여백), 층 인식 조회를
    /// 각주만 타는(덮인 스팬) 세 구멍을 잠근다.
    extension HwpContainerBlockLinkHitTests {
        /// stroke는 폭의 절반만 밖으로 나가지 않는다 — miter 조인의 팁은 `miterLimit`
        /// 까지 뻗는다. 판정(`strokePaints`)은 그 stroke 경로를 보므로, 자격이
        /// bbox + 폭/2 면 **보이는 팁 위**의 탭이 기각돼 아래 본문 링크가 열린다.
        func testFootnoteShapeMiterTipClaimsTap() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 꼭짓점 (0,50) 에서 벌어진 각 16° — miter 비율 1/sin(8°) ≈ 7.2 < 10 이라
            // 팁이 살아 있고, 폭 8pt 기준 (8/2)/sin(8°) ≈ 28.7pt 뻗는다
            let spike = CGMutablePath()
            spike.move(to: CGPoint(x: 200, y: 21.9))
            spike.addLine(to: CGPoint(x: 0, y: 50))
            spike.addLine(to: CGPoint(x: 200, y: 78.1))
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: CGRect(x: 0, y: 0, width: 200, height: 100),
                    geometry: HwpShapeGeometry(
                        path: spike,
                        fillColor: nil,
                        strokeColor: black.cgColor,
                        strokeWidth: 8
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 21
                )]
            )
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 0, y: 590, width: 400, height: 120),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let pages = page([beneath, AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )])

            // 꼭짓점에서 10pt 더 나간 팁 위 (bbox + 폭/2 로는 못 닿는 자리)
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 40, y: 650)))
                == .footnote(blockIndex: 1, number: 1)
            // 팁보다 더 먼 자리 — 아무것도 안 칠했으므로 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 15, y: 650)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 중첩 표의 감싼 링크는 **표 rect 전체**로 방출된다 (R60) — walker가 셀만
        /// 주므로 자격이 셀 union이면 표 rect와 첫 셀 사이 여백 띠가 빠진다.
        func testNestedTableSpacingBandIsEligible() {
            let blockFrame = CGRect(x: 50, y: 100, width: 200, height: 50)
            // 중첩 표는 셀을 20pt 안쪽에 두고 블록 아래로 80pt 넘친다
            let innerCell = cell(CGRect(x: 20, y: 20, width: 60, height: 60))
            let nested = HwpNestedTableFrame(
                rect: CGRect(x: 0, y: 30, width: 100, height: 100),
                table: HwpTableFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                    rows: [HwpTableRowFrame(
                        rowFrame: innerCell.cellFrame, cells: [innerCell]
                    )],
                    borderColor: black, borderWidth: 1
                ),
                controlInstanceId: 91
            ).withWrapperURL("https://example.com/nested")
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 0, y: 100, width: 400, height: 200),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let table = tableBlock(
                frame: blockFrame,
                cell: cell(
                    CGRect(x: 0, y: 0, width: 200, height: 50), nestedTables: [nested]
                )
            )
            let pages = page([beneath, table])

            // 셀 **아래쪽** 여백 띠 — 자격은 bounding box라 셀 union으로는 못 닿는
            // 유일한 자리다 (좌우 여백은 부모 셀 bbox에 이미 든다)
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 100, y: 220)))
                == .hyperlink(url: "https://example.com/nested", blockIndex: 1)
            // 표 rect 밖 — 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 100, y: 240)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        // MARK: - R64: 컨테이너도 층 인식 경로

        /// 필드 스팬(%hlk)도 층 순서를 따라야 한다 — 각주에서 고친 그 규약(R42 #1)이
        /// 표·글상자에는 빠져 있었다. walkText 스캔은 페인트 **정순**이라 덮인 셀 문단의
        /// 스팬을 먼저 잡아, 위에 놓인 글상자의 링크가 진다.
        func testTableSpanLinksResolveTopmostFirst() {
            let blockFrame = CGRect(x: 50, y: 100, width: 400, height: 40)
            let overlay = HwpCellTextbox(
                rect: CGRect(x: 0, y: 0, width: 40, height: 40),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 40, height: 40),
                    paragraphs: [spanParagraph(
                        "덮는링크", url: "https://example.com/overlay",
                        rect: CGRect(x: 0, y: 0, width: 40, height: 40), paragraphId: 2
                    )],
                    borderColor: nil, borderWidth: 0, fillColor: nil
                ),
                paintsBehindText: false,
                zOrder: 0, sourceOrder: 0,
                controlInstanceId: 5
            )
            let block = tableBlock(
                frame: blockFrame,
                cell: cell(
                    CGRect(x: 0, y: 0, width: 400, height: 40),
                    paragraphs: [spanParagraph(
                        "덮인링크텍스트", url: "https://example.com/covered",
                        rect: CGRect(x: 0, y: 0, width: 400, height: 40), paragraphId: 1
                    )],
                    textboxes: [overlay]
                )
            )
            let pages = page([block])

            // 겹친 자리 — 위에 그린 글상자의 링크가 이긴다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 56, y: 106)))
                == .hyperlink(url: "https://example.com/overlay", blockIndex: 0)
            // 글상자 밖이지만 셀 글자 위 — 덮이지 않은 스팬이 그대로 열린다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 110, y: 106)))
                == .hyperlink(url: "https://example.com/covered", blockIndex: 0)
        }

        // MARK: - R65: 세로 자격은 폰트 메트릭

        /// 캐시 문단 높이가 CT 줄보다 짧으면 글자가 rect **아래**로 그려진다.
        /// 세로 여유를 문단 **폭**에 비례시키면 (좁은 셀은 2.4pt뿐) 그 글자가 자격
        /// 밖이라, 전경 글자가 claim에 실패하고 뒤 층의 링크가 이긴다.
        func testUndersizedCachedParagraphStillClaimsRenderedGlyphs() {
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
            // 12pt 글자를 담은 문단인데 캐시 높이는 4pt — 폭도 40pt라 폭 비례
            // 여유는 2.4pt뿐이다 (실제 줄은 ~14pt)
            let foreground = NSMutableAttributedString(string: "가나다")
            foreground.addAttribute(
                .font, value: CTFontCreateWithName("Menlo" as CFString, 12, nil),
                range: NSRange(location: 0, length: foreground.length)
            )
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: foreground,
                    frame: HwpParagraphFrame(totalHeight: 4, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 40, height: 4),
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
            let pages = page([AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )])

            // 캐시 rect 아래지만 **그려진 글자 위** — 각주가 claim한다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 56, y: 610)))
                == .footnote(blockIndex: 0, number: 1)
            // 줄 상자보다 훨씬 아래 — 글자가 없으므로 뒤 글상자의 링크가 열린다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 56, y: 640)))
                == .hyperlink(url: "https://example.com/behind", blockIndex: 0)
        }

        /// 폰트를 고정해 글리프 rect가 기기에 따라 달라지지 않게 한 스팬 문단
        private func spanParagraph(
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
    }
#endif
