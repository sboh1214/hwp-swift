import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글상자의 **목록 끝** (#233) — 글상자 문단 배열의 마지막 문단은 마지막 줄 띠가 줄 상자에서
    /// 끝나고, 앞 문단은 줄 간격 몫까지다 (한글: 글상자·표 셀·각주의 마지막 줄 아래는 링크가 안
    /// 열린다). 목록 끝은 호출 자리마다 따로 실리므로(방출: 최상위 글상자·셀 글상자·각주 글상자
    /// 순회, 히트: 글상자 블록·셀 글상자의 `containerHit`) 자리마다 방출 ≡ 히트를 함께 잠근다.
    /// 배열 끝의 길이 0 문단은 방문하지 않지만 목록 끝 판정에는 든다 — 그 앞 문단은 끝이 아니다.
    final class HwpHyperlinkClickBandTextboxTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private static let firstURL = "https://first.example"
        private static let lastURL = "https://last.example"
        private static let percent160 = HwpLineSpacingRule(kind: .percent, value: 160)
        private static let black = HwpRGBColor(red: 0, green: 0, blue: 0)

        /// 10pt 160% 한 줄 문단 — 로컬 y에서 줄 상자 10, 줄 간격 몫 6.
        private static func paragraph(
            _ url: String?, y: CGFloat, id: UInt32
        ) -> HwpLaidOutParagraph {
            var attributes = Fixtures.attributes(size: 10)
            if let url {
                attributes[HwpAttributedStringKey.hyperlink] = url
                attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            }
            let text = url == nil ? "" : "LINK"
            return HwpLaidOutParagraph(
                attributedString: Fixtures.applying(
                    percent160, to: NSAttributedString(string: text, attributes: attributes)
                ),
                frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                rect: CGRect(x: 0, y: y, width: 200, height: 16), paragraphId: id
            )
        }

        private static func textbox(_ paragraphs: [HwpLaidOutParagraph]) -> HwpTextboxFrame {
            HwpTextboxFrame(
                outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
                paragraphs: paragraphs, borderColor: nil, borderWidth: 0, fillColor: nil
            )
        }

        private static let twoLinks = [
            paragraph(firstURL, y: 0, id: 1), paragraph(lastURL, y: 16, id: 2),
        ]

        private static func page(_ block: AnyHwpBlock) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block], pageNumber: 1
            )
        }

        /// 방출된 링크 rect의 하단 — URL별.
        private static func emittedBottoms(_ page: HwpPage) -> [String: [Double]] {
            var bottoms: [String: [Double]] = [:]
            for command in HwpPaintListBuilder().build(for: page).commands {
                if case let .hyperlink(rect, url) = command {
                    bottoms[url, default: []].append(Double(rect.maxY))
                }
            }
            return bottoms
        }

        private static func url(_ result: HwpHitResult?) -> String? {
            if case let .hyperlink(url, _) = result {
                return url
            }
            return nil
        }

        /// 두 문단이 페이지 y `top`에서 시작할 때: 앞 문단 띠 top…top+16, 마지막 문단 top+16…top+26.
        private static func expectListEnd(_ page: HwpPage, top: CGFloat, x: CGFloat) {
            let tester = HwpHitTester()
            // 앞 문단: 밑줄(상자 바닥 +0.2)과 줄 간격 몫 끝까지 열린다.
            expect(url(tester.hit(page: page, point: CGPoint(x: x, y: top + 10.2)))) == firstURL
            expect(url(tester.hit(page: page, point: CGPoint(x: x, y: top + 15.9)))) == firstURL
            // 마지막 문단: 줄 상자 안은 열리고 밑줄은 아니다.
            expect(url(tester.hit(page: page, point: CGPoint(x: x, y: top + 25.9)))) == lastURL
            expect(url(tester.hit(page: page, point: CGPoint(x: x, y: top + 26.2)))).to(beNil())
            let bottoms = emittedBottoms(page)
            expect(bottoms[firstURL]).to(beCloseTo([Double(top) + 16], within: 0.001))
            expect(bottoms[lastURL]).to(beCloseTo([Double(top) + 26], within: 0.001))
        }

        /// 최상위 글상자 블록 — 방출은 `walkListedText`의 `.textbox` 갈래, 히트는 글상자 블록의
        /// `containerHit`이다.
        func testTopLevelTextboxLastParagraphIsTheListEnd() {
            let frame = CGRect(x: 50, y: 100, width: 200, height: 80)
            let block = AnyHwpBlock(
                frame: frame, kind: .textbox, payload: .textbox(Self.textbox(Self.twoLinks))
            )
            Self.expectListEnd(Self.page(block), top: 100, x: 55)
        }

        /// 표 셀 안 글상자 — 방출은 셀 글상자 순회, 히트는 셀 층의 글상자 `containerHit`이다.
        func testCellTextboxLastParagraphIsTheListEnd() {
            let cellFrame = CGRect(x: 0, y: 0, width: 300, height: 120)
            let cell = HwpTableCellFrame(
                cellFrame: cellFrame, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [], borders: HwpBorderSet.uniform(width: 0.5, color: Self.black),
                fillColor: nil,
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 20, y: 10, width: 200, height: 80),
                    textbox: Self.textbox(Self.twoLinks), controlInstanceId: 7
                )]
            )
            let table = HwpTableFrame(
                outerFrame: cellFrame,
                rows: [HwpTableRowFrame(rowFrame: cellFrame, cells: [cell])],
                borderColor: Self.black, borderWidth: 0.5
            )
            let block = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 300, height: 120), kind: .table,
                payload: .table(table)
            )
            Self.expectListEnd(Self.page(block), top: 110, x: 75)
        }

        /// 각주 안 글상자 — 방출은 각주 순회의 글상자 갈래, 히트는 각주 층의 글상자 `containerHit`이다.
        func testFootnoteTextboxLastParagraphIsTheListEnd() {
            let footnote = HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 600, width: 300, height: 100),
                paragraphs: [], number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 100, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 20, y: 10, width: 200, height: 80),
                    textbox: Self.textbox(Self.twoLinks), controlInstanceId: 8
                )]
            )
            let block = AnyHwpBlock(
                frame: footnote.frame, kind: .footnote, payload: .footnote(footnote)
            )
            Self.expectListEnd(Self.page(block), top: 610, x: 75)
        }

        /// 배열 끝이 길이 0 문단이면 그 앞 링크 문단은 목록 끝이 아니다 — 띠가 줄 간격 몫까지다
        /// (한글도 그 빈 문단 줄이 뒤따른다). 방출과 히트가 같다.
        func testTrailingEmptyParagraphKeepsTheLineSpacingShare() {
            let paragraphs = [
                Self.paragraph(Self.firstURL, y: 0, id: 1), Self.paragraph(nil, y: 16, id: 2),
            ]
            let block = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 200, height: 80), kind: .textbox,
                payload: .textbox(Self.textbox(paragraphs))
            )
            let page = Self.page(block)
            let tester = HwpHitTester()
            expect(Self.url(tester.hit(page: page, point: CGPoint(x: 55, y: 115.9))))
                == Self.firstURL
            expect(Self.emittedBottoms(page)[Self.firstURL])
                .to(beCloseTo([116], within: 0.001))
        }
    }
#endif
