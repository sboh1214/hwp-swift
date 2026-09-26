import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 다음 블록의 **프레임 위 글자 claim**이 앞 블록의 링크 줄 띠를 가져가지 않는다 (#233 리뷰,
    /// `HwpHitTester.textClaim`).
    ///
    /// 문단은 문단마다 블록이고 뒤 블록이 먼저 히트되므로, 다음 문단의 첫 줄 잉크가 자기 프레임
    /// 위로 솟는 몫(글꼴 ascent − 0.85 × 기본 크기 — R53의 텍스트 축)이 앞 줄 띠의 아래쪽을
    /// claim했다. 방출된 링크 rect는 거기까지인데 히트는 `.text`라 "방출 ≡ 히트"가 깨졌고, 다음
    /// 줄이 40pt면 밑줄 위 탭까지 안 열렸다 (함초롬바탕 10pt 2.2pt, 40pt 8.8pt).
    ///
    /// 오라클은 한글 12.30 편집 화면이다 (2026-09-26, 155%): 10pt 160% 링크 줄 바로 아래 줄을
    /// 상대 크기 200%·150%로 키워 그 글리프가 자기 줄 상자 위로 솟아 링크 밑줄까지 덮어도, 그
    /// 획 위를 누르면 링크 줄이 다음 줄 상자 상단까지 열렸다(상자 바닥 +5.9·+6.06pt, 대조 줄
    /// +6.0) — 한글은 줄 띠로 판정하고 다음 줄 잉크를 보지 않는다.
    final class HwpHyperlinkClickBandClaimTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private static let url = "https://example.com/above"
        private static let percent160 = HwpLineSpacingRule(kind: .percent, value: 160)

        /// 10pt 160% 한 줄 — 프레임 16pt(줄 상자 10 + 줄 간격 몫 6)가 곧 클릭 띠다.
        private static func linkLine(
            url: String? = HwpHyperlinkClickBandClaimTests.url
        ) -> NSAttributedString {
            var attributes = Fixtures.attributes(size: 10)
            if let url {
                attributes[HwpAttributedStringKey.hyperlink] = url
                attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            }
            return Fixtures.applying(
                percent160, to: NSAttributedString(string: "LINK LINK LINK", attributes: attributes)
            )
        }

        /// 기본 크기 10pt에 글꼴만 키운 줄 — 상대 크기처럼 줄 상자는 10pt라 잉크가 위로 솟는다.
        private static func tallLine(
            fontSize: CGFloat = 17, fontName: String = "Helvetica"
        ) -> NSAttributedString {
            Fixtures.applying(percent160, to: NSAttributedString(
                string: "HHHHHHHH",
                attributes: Fixtures.attributes(size: fontSize, baseSize: 10, fontName: fontName)
            ))
        }

        private static func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks, pageNumber: 1
            )
        }

        private static let linkFrame = CGRect(x: 0, y: 100, width: 400, height: 16)
        private static let nextFrame = CGRect(x: 0, y: 116, width: 400, height: 16)

        private static func bodyPair(
            link: NSAttributedString, next: NSAttributedString
        ) -> HwpPage {
            page([
                AnyHwpBlock(frame: linkFrame, kind: .text, attributedString: link),
                AnyHwpBlock(frame: nextFrame, kind: .text, attributedString: next),
            ])
        }

        /// 다음 문단의 큰 글자 잉크가 앞 줄 띠(…116)로 솟아도 그 자리는 앞 줄 링크다. 앞 줄에 링크가
        /// 없으면 종전대로 다음 문단이 claim한다 — 양보는 링크에만 한다.
        func testTallInkOfTheNextParagraphDoesNotTakeTheLinkBand() {
            let next = Self.tallLine()
            let ink = HwpDrawnTextLayout.textLineRegions(
                attributedString: next, origin: Self.nextFrame.origin, lineWidth: 400
            ).first ?? .null
            // 17pt ascent가 0.85 × 10을 넘어 줄 상자가 프레임 위로 나간다 (Helvetica 17: 4.0pt).
            expect(Double(ink.minY)).to(beLessThan(113))
            let tester = HwpHitTester()
            let linked = Self.bodyPair(link: Self.linkLine(), next: next)
            let unlinked = Self.bodyPair(link: Self.linkLine(url: nil), next: next)
            for y: CGFloat in [113.0, 114.5, 115.9] {
                let point = CGPoint(x: 5, y: y)
                expect(tester.textPaints(next, in: Self.nextFrame, at: point)) == true
                expect(tester.hit(page: linked, point: point))
                    == .hyperlink(url: Self.url, blockIndex: 0)
                expect(tester.hit(page: unlinked, point: point))
                    == .text(blockIndex: 1, characterIndex: nil)
            }
            // 다음 문단 프레임 안은 그 문단 몫이다.
            expect(tester.hit(page: linked, point: CGPoint(x: 5, y: 116.5)))
                == .text(blockIndex: 1, characterIndex: nil)
        }

        /// 글꼴 ascent가 0.85em을 넘는 **보통 크기** 글꼴도 같다 — 결정론 조판의 Menlo 10pt(ascent
        /// 9.28)는 0.78pt, 함초롬바탕 10pt(10.7)는 2.2pt 띠가 매 문단 경계에 생겼다.
        func testAscentAboveTheBoxOfAnOrdinaryNextParagraphDoesNotTakeTheLinkBand() {
            let next = Self.tallLine(fontSize: 10, fontName: "Menlo")
            let point = CGPoint(x: 5, y: 115.5)
            let tester = HwpHitTester()
            expect(tester.textPaints(next, in: Self.nextFrame, at: point)) == true
            let page = Self.bodyPair(link: Self.linkLine(), next: next)
            expect(tester.hit(page: page, point: point)) == .hyperlink(url: Self.url, blockIndex: 0)
        }

        /// 각주는 문단마다 블록이라 같은 각주의 뒤 문단이 앞 문단 링크 띠를 가져갔다 (`.occluded`
        /// → `.footnote`). 글자뿐인 claim은 본문과 같이 양보하고, 개체가 칠한 자리는 그대로 claim한다.
        func testNextFootnoteParagraphInkDoesNotTakeTheLinkBand() {
            func laidOut(_ string: NSAttributedString) -> HwpLaidOutParagraph {
                HwpLaidOutParagraph(
                    attributedString: string,
                    frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 300, height: 16), paragraphId: 1
                )
            }
            let separator = CGRect(x: 50, y: 690, width: 100, height: 1)
            let first = HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 700, width: 300, height: 16),
                paragraphs: [laidOut(Self.linkLine())], number: 1,
                separatorLine: separator, isNoteEnd: false
            )
            func second(shapes: [HwpCellShape] = []) -> HwpFootnoteBlock {
                HwpFootnoteBlock(
                    frame: CGRect(x: 50, y: 716, width: 300, height: 10),
                    paragraphs: [laidOut(Self.tallLine())], number: 1,
                    separatorLine: separator, shapes: shapes
                )
            }
            func page(_ second: HwpFootnoteBlock) -> HwpPage {
                Self.page([
                    AnyHwpBlock(frame: first.frame, kind: .footnote, payload: .footnote(first)),
                    AnyHwpBlock(frame: second.frame, kind: .footnote, payload: .footnote(second)),
                ])
            }
            let point = CGPoint(x: 55, y: 714.5)
            let tester = HwpHitTester()
            expect(tester.hit(page: page(second()), point: point))
                == .hyperlink(url: Self.url, blockIndex: 0)
            // 뒤 문단의 채운 도형이 프레임 위로 넘쳐 그 자리를 덮으면 도형 쪽이다 (R42 #2).
            let shapeRect = CGRect(x: 0, y: -4, width: 20, height: 8)
            let filled = HwpCellShape(
                rect: shapeRect,
                geometry: HwpShapeGeometry(
                    path: CGPath(rect: shapeRect, transform: nil),
                    fillColor: CGColor(gray: 0.5, alpha: 1), strokeColor: nil, strokeWidth: 0
                ),
                controlInstanceId: 1
            )
            expect(tester.hit(page: page(second(shapes: [filled])), point: point))
                == .footnote(blockIndex: 1, number: 1)
        }
    }
#endif
