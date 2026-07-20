import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpHyperlinkPipelineTests: XCTestCase {
    private func makeHyperlinkBlock(url: String, frame: CGRect) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(string: "linked"),
            hyperlinkURL: url
        )
    }

    private func makePage(with blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: blocks,
            pageNumber: 1
        )
    }

    /// 셀 안 글상자 문단의 하이퍼링크도 히트된다 — 글상자-로컬 좌표 변환 (R30 #3).
    func testCellTextboxHyperlinkIsTappable() {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let boxParagraph = HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: "링크"),
            frame: HwpParagraphFrame(totalHeight: 20, lines: []),
            rect: CGRect(x: 0, y: 0, width: 80, height: 20),
            paragraphId: 1,
            hyperlinkURL: "https://example.com"
        )
        let cell = HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: [],
            borders: HwpBorderSet.uniform(width: 0.5, color: black),
            fillColor: nil,
            textboxes: [HwpCellTextbox(
                rect: CGRect(x: 10, y: 10, width: 80, height: 20),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 80, height: 20),
                    paragraphs: [boxParagraph],
                    borderColor: nil, borderWidth: 0, fillColor: nil
                ),
                controlInstanceId: 1
            )]
        )
        let table = HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
            rows: [HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
                cells: [cell]
            )],
            borderColor: black, borderWidth: 1
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: 100, height: 50),
            kind: .table,
            payload: .table(table)
        )
        let page = makePage(with: [block])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 20, y: 20))

        expect {
            if case let .hyperlink(url, _) = hit {
                return url == "https://example.com"
            }
            return false
        } == true
    }

    /// 셀 글상자 문단에 필드 스팬이 있으면 링크 글리프 rect에서만 히트한다 —
    /// 앞쪽 평문 탭은 링크가 아니다 (R31 #1).
    func testCellTextboxLinkScopedToFieldSpan() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSMutableAttributedString(
            string: "before link after",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let linkRange = (attributed.string as NSString).range(of: "link")
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://example.com", range: linkRange
        )
        let boxParagraph = HwpLaidOutParagraph(
            attributedString: attributed,
            frame: HwpParagraphFrame(totalHeight: 20, lines: []),
            rect: CGRect(x: 0, y: 0, width: 200, height: 20),
            paragraphId: 1,
            hyperlinkURL: "https://example.com"
        )
        let block = cellTextboxBlock(with: boxParagraph)
        let page = makePage(with: [block])
        guard let region = HwpDrawnTextLayout.hyperlinkRegions(
            attributedString: attributed, origin: .zero, lineWidth: 200
        ).first else {
            fail("링크 스팬이 없다")
            return
        }

        // 글상자 원점 (10,10) + 스팬 rect 안 = URL
        let onLink = HwpHitTester().hit(
            page: page,
            point: CGPoint(x: 10 + region.rect.midX, y: 10 + region.rect.midY)
        )
        expect {
            if case let .hyperlink(url, _) = onLink {
                return url == "https://example.com"
            }
            return false
        } == true
        // 스팬 앞 평문 = 링크 아님 (표 히트로 떨어진다)
        let beforeLink = HwpHitTester().hit(page: page, point: CGPoint(x: 11, y: 20))
        expect {
            if case .hyperlink = beforeLink {
                return false
            }
            return true
        } == true
    }

    /// 다른 셀 문단에 필드 스팬이 있어도 (hasFieldSpans 게이트) 셀 글상자
    /// 링크는 도달 가능하다 — walkText 스팬 스캔이 글상자를 못 보는 우회 (R31 #1).
    func testCellTextboxLinkReachableUnderFieldSpanGate() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fieldAttributed = NSMutableAttributedString(
            string: "field",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        fieldAttributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://field.example",
            range: NSRange(location: 0, length: fieldAttributed.length)
        )
        let cellParagraph = HwpLaidOutParagraph(
            attributedString: fieldAttributed,
            frame: HwpParagraphFrame(totalHeight: 10, lines: []),
            rect: CGRect(x: 0, y: 35, width: 100, height: 10),
            paragraphId: 2,
            hyperlinkURL: nil
        )
        let boxParagraph = HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: "링크"),
            frame: HwpParagraphFrame(totalHeight: 20, lines: []),
            rect: CGRect(x: 0, y: 0, width: 80, height: 20),
            paragraphId: 1,
            hyperlinkURL: "https://box.example"
        )
        let block = cellTextboxBlock(with: boxParagraph, cellParagraphs: [cellParagraph])
        let page = makePage(with: [block])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 20, y: 20))

        expect {
            if case let .hyperlink(url, _) = hit {
                return url == "https://box.example"
            }
            return false
        } == true
    }

    func testHitTesterReturnsHyperlinkForBlockWithURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let block = makeHyperlinkBlock(url: "https://example.com", frame: frame)
        let page = makePage(with: [block])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 25))

        expect {
            if case let .hyperlink(url, blockIndex) = hit {
                return url == "https://example.com" && blockIndex == 0
            }
            return false
        } == true
    }

    func testHitTesterReturnsTextWhenBlockHasNoURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let plain = AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(string: "plain")
        )
        let page = makePage(with: [plain])

        let hit = HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 25))

        expect {
            if case .text = hit {
                return true
            }
            return false
        } == true
    }

    func testPaintListBuilderEmitsHyperlinkCommandForBlockWithURL() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)
        let block = makeHyperlinkBlock(url: "https://example.com", frame: frame)
        let page = makePage(with: [block])

        let paintList = HwpPaintListBuilder()
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile()))

        let hyperlinkCommand = paintList.commands.first { command in
            if case .hyperlink = command {
                return true
            }
            return false
        }
        expect(hyperlinkCommand).notTo(beNil())

        if case let .hyperlink(rect, url) = hyperlinkCommand {
            expect(rect) == frame
            expect(url) == "https://example.com"
        }
    }

    func testPaintListBuilderOmitsHyperlinkCommandWhenNoURL() {
        let plain = AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 100, height: 30),
            kind: .text,
            attributedString: NSAttributedString(string: "plain")
        )
        let page = makePage(with: [plain])

        let paintList = HwpPaintListBuilder()
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile()))

        let hasHyperlink = paintList.commands.contains { command in
            if case .hyperlink = command {
                return true
            }
            return false
        }
        expect(hasHyperlink) == false
    }

    func testDisplayURLStripsTrailingHwpFieldFlags() {
        // CCL·공공누리 실측: 트레일링 ;1;0;1 (HWP 필드 플래그) 제거
        expect(HwpHyperlinkURL.displayURL(
            "http://creativecommons.org/licenses/by/4.0/deed.ko;1;0;1"
        )) == "http://creativecommons.org/licenses/by/4.0/deed.ko"
        expect(HwpHyperlinkURL.displayURL(
            "http://www.kogl.or.kr/open/info/license_info/by.do;1;0;1"
        )) == "http://www.kogl.or.kr/open/info/license_info/by.do"
        // 플래그가 없으면 원문 그대로, URL 안의 비-플래그 세미콜론은 보존
        expect(HwpHyperlinkURL.displayURL("https://example.com")) == "https://example.com"
        expect(HwpHyperlinkURL.displayURL("http://x/a;b;1;0;1")) == "http://x/a;b"
    }

    func testHyperlinkScopedToFieldSpanNotWholeBlock() {
        // "before link after"에서 hyperlink 속성을 "link"에만 단 블록 —
        // 페인트/히트가 블록 전체가 아니라 "link" 글리프 rect로만 스코프해야 한다 (#2).
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSMutableAttributedString(
            string: "before link after",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let linkRange = (attributed.string as NSString).range(of: "link")
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://example.com", range: linkRange
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: 400, height: 20),
            kind: .text, attributedString: attributed
        )
        let page = makePage(with: [block])

        let paintList = HwpPaintListBuilder()
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile()))
        let linkRects: [CGRect] = paintList.commands.compactMap { command in
            if case let .hyperlink(rect, url) = command, url == "https://example.com" {
                return rect
            }
            return nil
        }
        expect(linkRects.count) == 1
        // "before " 뒤에서 시작하고 블록 전체 폭(400)이 아니다
        expect(linkRects[0].minX) > 0
        expect(linkRects[0].maxX) < 400

        // 히트: 링크 스팬 안 = URL, 앞쪽 평문("before") = 링크 아님
        let linkRect = linkRects[0]
        let onLink = HwpHitTester().hit(
            page: page, point: CGPoint(x: linkRect.midX, y: linkRect.midY)
        )
        expect {
            if case let .hyperlink(url, _) = onLink {
                return url == "https://example.com"
            }
            return false
        } == true
        let beforeLink = HwpHitTester().hit(page: page, point: CGPoint(x: 1, y: linkRect.midY))
        expect {
            if case .hyperlink = beforeLink {
                return false
            }
            return true
        } == true
    }

    func testOverflowSingleLineLinkEdgeIsTappable() {
        // slight-overflow 한 줄 링크(자연 폭이 frame 폭을 허용 배율 이내로 초과)는
        // frame 밖까지 그려진다 — frame 밖·잉크 안 지점의 탭이 링크로 히트해야
        // 한다 (#4).
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSMutableAttributedString(
            string: "linklinklink",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://example.com",
            range: NSRange(location: 0, length: attributed.length)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let frameWidth = naturalWidth / 1.03
        let block = AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: frameWidth, height: 20),
            kind: .text, attributedString: attributed
        )
        let page = makePage(with: [block])

        let outsideFrameInsideInk = CGPoint(x: (frameWidth + naturalWidth) / 2, y: 10)
        let hit = HwpHitTester().hit(page: page, point: outsideFrameInsideInk)

        expect {
            if case let .hyperlink(url, _) = hit {
                return url == "https://example.com"
            }
            return false
        } == true
    }

    func testHyperlinkRegionNormalizedForRTLText() {
        // RTL(히브리어) 링크 텍스트는 CT가 하위 논리 인덱스에 더 큰 x 오프셋을
        // 준다 — min/max 정규화가 없으면 region이 폐기돼 링크가 히트되지 않는다.
        // 정규화 후 양수 폭 region이 나와야 한다 (#1).
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSMutableAttributedString(
            string: "\u{05E9}\u{05DC}\u{05D5}\u{05DD}",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://example.com",
            range: NSRange(location: 0, length: attributed.length)
        )
        let regions = HwpDrawnTextLayout.hyperlinkRegions(
            attributedString: attributed, origin: .zero, lineWidth: 400
        )
        expect(regions.count) >= 1
        expect(regions.allSatisfy { $0.rect.width > 0 }) == true
    }
}

private extension HwpHyperlinkPipelineTests {
    /// (10,10)에 220×20 글상자를 담은 단일 셀 표 블록 (블록 원점 0,0)
    func cellTextboxBlock(
        with boxParagraph: HwpLaidOutParagraph,
        cellParagraphs: [HwpLaidOutParagraph] = []
    ) -> AnyHwpBlock {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cell = HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 300, height: 50),
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: cellParagraphs,
            borders: HwpBorderSet.uniform(width: 0.5, color: black),
            fillColor: nil,
            textboxes: [HwpCellTextbox(
                rect: CGRect(x: 10, y: 10, width: 220, height: 20),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 220, height: 20),
                    paragraphs: [boxParagraph],
                    borderColor: nil, borderWidth: 0, fillColor: nil
                ),
                controlInstanceId: 1
            )]
        )
        let table = HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 300, height: 50),
            rows: [HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 300, height: 50),
                cells: [cell]
            )],
            borderColor: black, borderWidth: 1
        )
        return AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: 300, height: 50),
            kind: .table,
            payload: .table(table)
        )
    }

    /// 셀 문단만 담은 200×50 단일 셀 표 블록 (블록 원점 0,0)
    func cellParagraphTableBlock(paragraphs: [HwpLaidOutParagraph]) -> AnyHwpBlock {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cell = HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 200, height: 50),
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: paragraphs,
            borders: HwpBorderSet.uniform(width: 0.5, color: black),
            fillColor: nil,
            textboxes: []
        )
        let table = HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 50),
            rows: [HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 200, height: 50),
                cells: [cell]
            )],
            borderColor: black, borderWidth: 1
        )
        return AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: 200, height: 50),
            kind: .table,
            payload: .table(table)
        )
    }
}

extension HwpHyperlinkPipelineTests {
    /// 같은 셀의 다른 문단이 필드 스팬을 가져도, 스팬 없는 문단의 폴백 링크는
    /// 문단 단위로 히트된다 — 블록 전체 게이트의 과차단 해소 (R38 #4). 스팬
    /// 문단의 글리프 밖 rect 폴백 금지(R31 계약)는 그대로다.
    func testFallbackParagraphLinkHitAlongsideSpanParagraph() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let spanAttributed = NSMutableAttributedString(
            string: "before link after",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let linkRange = (spanAttributed.string as NSString).range(of: "link")
        spanAttributed.addAttribute(
            HwpAttributedStringKey.hyperlink, value: "https://span.example", range: linkRange
        )
        let spanParagraph = HwpLaidOutParagraph(
            attributedString: spanAttributed,
            frame: HwpParagraphFrame(totalHeight: 20, lines: []),
            rect: CGRect(x: 0, y: 0, width: 200, height: 20),
            paragraphId: 1,
            hyperlinkURL: "https://span.example"
        )
        let fallbackParagraph = HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: "폴백 링크"),
            frame: HwpParagraphFrame(totalHeight: 20, lines: []),
            rect: CGRect(x: 0, y: 20, width: 200, height: 20),
            paragraphId: 2,
            hyperlinkURL: "https://fallback.example"
        )
        let page = makePage(with: [cellParagraphTableBlock(
            paragraphs: [spanParagraph, fallbackParagraph]
        )])

        let onFallback = HwpHitTester().hit(page: page, point: CGPoint(x: 30, y: 30))
        expect {
            if case let .hyperlink(url, _) = onFallback {
                return url == "https://fallback.example"
            }
            return false
        } == true

        let outsideSpanGlyph = HwpHitTester().hit(page: page, point: CGPoint(x: 195, y: 10))
        expect {
            if case .hyperlink = outsideSpanGlyph {
                return false
            }
            return true
        } == true
    }
}
