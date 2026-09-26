import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 프레임 밖에 그려진 전경 글자는 **링크가 없어도 그 블록이 claim한다** (R53의 텍스트 축,
    /// #200 리뷰 2차).
    ///
    /// 자격 영역은 글자 위치로 옮겨진 글리프까지 넓어졌는데, 프레임 밖 경로가 링크만 확인하고
    /// 없으면 아래 블록으로 내려가면 **보이는 전경 글자 위의 탭이 그 밑에 숨은 링크를 연다**.
    /// 프레임 안에서 같은 글자가 `.text`가 되는 것과 답이 같아야 한다. 판정은 `textPaints`
    /// (줄 상자·옮겨진 밴드)라 자격 영역의 빈 띠는 종전대로 아래 블록 몫이다.
    final class HwpOutOfFrameTextClaimTests: XCTestCase {
        private static let url = "https://behind.example"
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)

        /// 링크 없는 전경 문단 — 글리프를 10pt 내려 프레임(y 100…110) 아래로 보낸다.
        private func foreground(kind: HwpBlockKind = .text) -> AnyHwpBlock {
            AnyHwpBlock(
                frame: CGRect(x: 0, y: 100, width: 100, height: 10), kind: kind,
                attributedString: NSAttributedString(string: "AAAA", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                    HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -10),
                ])
            )
        }

        /// 그 아래 링크 블록 — 프레임(y 112…122)이 내려간 글리프의 **잉크**(≈111…119)를 품는다.
        private let behind = AnyHwpBlock(
            frame: CGRect(x: 0, y: 112, width: 100, height: 10), kind: .text,
            attributedString: NSAttributedString(string: "LINK", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ]),
            hyperlinkURL: url
        )

        private func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks, pageNumber: 1
            )
        }

        /// 내려간 글리프의 **잉크 한가운데** — 전경 프레임 밖, 뒤 블록 프레임 안이다. 밴드의
        /// descent 띠(잉크 없음)가 아니라 실제로 보이는 글자 위를 누른다.
        private func tapOnShiftedGlyph(of block: AnyHwpBlock, bandCount: Int = 1) -> CGPoint {
            let attributed = block.attributedString ?? NSAttributedString()
            let regions = HwpDrawnTextLayout.textLineRegions(
                attributedString: attributed, origin: block.frame.origin,
                lineWidth: block.frame.width
            )
            // 줄 상자 하나 + 옮겨진 run마다 밴드 하나 — 첫 밴드(시각 순서 맨 왼쪽 run) 위를 누른다.
            expect(regions.count) == 1 + bandCount
            let band = regions.count > 1 ? regions[1] : .null
            // 밴드 = 줄 상자(ascent+descent)를 옮긴 것 — 대문자 잉크는 베이스라인 위 ~0.7em.
            let tap = CGPoint(x: band.minX + 2, y: band.maxY - CTFontGetDescent(Self.font) - 3.5)
            expect(block.frame.contains(tap)) == false
            expect(self.behind.frame.contains(tap)) == true
            return tap
        }

        /// 어느 순서로 그려졌든 **위에 그려진** 전경 글자가 이긴다 — 뒤 링크는 열리지 않는다.
        func testTapOnShiftedForegroundGlyphDoesNotOpenTheLinkBehind() {
            let front = foreground()
            let tap = tapOnShiftedGlyph(of: front)

            // 논리 순서가 곧 페인트 순서 — 뒤에 오는 블록이 위에 그려진다.
            expect(HwpHitTester().hit(page: self.page([self.behind, front]), point: tap))
                == .text(blockIndex: 1, characterIndex: nil)
            // 링크 블록이 위에 그려졌으면 그 링크가 이긴다 (종전 동작).
            if case let .hyperlink(url, index)? = HwpHitTester().hit(
                page: page([front, behind]), point: tap
            ) {
                expect(url) == Self.url
                expect(index) == 1
            } else {
                fail("링크 블록이 위에 있으면 링크가 열려야 한다")
            }
        }

        /// 자격 영역의 **빈 띠**(글자 오른쪽)는 종전대로 아래 블록 몫이다.
        func testTapOnEmptyEligibilityBandStillReachesTheLinkBehind() {
            let front = foreground()
            let tap = tapOnShiftedGlyph(of: front)
            let empty = CGPoint(x: 80, y: tap.y)
            expect(HwpHitTester().hitEligibleFrame(for: front).contains(empty)) == true

            if case let .hyperlink(url, _)? = HwpHitTester().hit(
                page: page([behind, front]), point: empty
            ) {
                expect(url) == Self.url
            } else {
                fail("빈 띠에서는 뒤 링크가 열려야 한다")
            }
        }

        /// 링크 스팬이 있는 문단의 **링크 아닌** 글자도 같다 — 스팬 경로(`hasFieldSpans`)가
        /// nil을 돌려준 뒤에도 칠 확인으로 claim한다.
        func testUnlinkedGlyphOfALinkBearingParagraphClaimsTheTap() {
            let mixed = NSMutableAttributedString(string: "AAAA", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -10),
            ])
            mixed.append(NSAttributedString(string: "LINK", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -10),
                HwpAttributedStringKey.hyperlink: "https://front.example",
            ]))
            let front = AnyHwpBlock(
                frame: CGRect(x: 0, y: 100, width: 100, height: 10), kind: .text,
                attributedString: mixed
            )
            // 링크 속성 경계에서 run이 갈려 밴드가 둘이다 — 첫 밴드가 링크 아닌 `AAAA`.
            let tap = tapOnShiftedGlyph(of: front, bandCount: 2)

            expect(HwpHitTester().hit(page: self.page([self.behind, front]), point: tap))
                == .text(blockIndex: 1, characterIndex: nil)
        }

        /// slight-overflow 한 줄이 **가로로** 넘친 글자도 claim한다 — 오른쪽에 붙은 링크 블록의
        /// 프레임 안에 그 잉크가 놓여도 위에 그려진 글자가 이긴다.
        func testSlightOverflowGlyphBesideTheFrameClaimsTheTap() {
            let plain = NSAttributedString(string: "OVERFLOWING", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
            ])
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(plain), nil, nil, nil
            ))
            // 자연 폭의 97% — 허용 초과(6%) 안에서 오른쪽으로 3% 넘친다.
            let frame = CGRect(x: 0, y: 100, width: floor(natural * 0.97), height: 12)
            let front = AnyHwpBlock(frame: frame, kind: .text, attributedString: plain)
            let side = AnyHwpBlock(
                frame: CGRect(x: frame.maxX, y: 100, width: 100, height: 12), kind: .text,
                attributedString: NSAttributedString(string: "LINK", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                ]),
                hyperlinkURL: Self.url
            )
            let tap = CGPoint(x: frame.maxX + 0.5, y: 106)
            expect(HwpDrawnTextLayout.textLineRegions(
                attributedString: plain, origin: frame.origin, lineWidth: frame.width
            ).contains { $0.contains(tap) }) == true

            expect(HwpHitTester().hit(page: self.page([side, front]), point: tap))
                == .text(blockIndex: 1, characterIndex: nil)
        }

        /// 조판 없는 게이트(`mayPaintOutsideFrame`) — 프레임 밖에 글자를 그릴 수 없는 곳에서는
        /// framesetting을 타지 않는다: 오프셋 없는 여러 줄 문단은 위·아래·옆 어디서도, 위 첨자만
        /// 있는 문단은 위 첨자 높이 안에서만. 세 지점 모두 실제로 칠이 없음을 먼저 단언한다.
        func testLayoutFreeGateNarrowsToWhereGlyphsCanBePainted() throws {
            let long = NSAttributedString(
                string: String(repeating: "여러 줄 본문 ", count: 12), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                    HwpAttributedStringKey.baseFontSize: NSNumber(value: 10),
                ]
            )
            // 프레임 높이는 실제 줄 상자 합 — 짧게 잡으면 아래 지점이 4번째 줄 상자 위가 된다.
            let boxes = HwpDrawnTextLayout.textLineRegions(
                attributedString: long, origin: CGPoint(x: 0, y: 100), lineWidth: 100
            )
            let bottom = try XCTUnwrap(boxes.map(\.maxY).max())
            let frame = CGRect(x: 0, y: 100, width: 100, height: ceil(bottom) - 100)
            expect(boxes.count).to(beGreaterThan(1))
            let above = CGPoint(x: 10, y: 97)
            let below = CGPoint(x: 10, y: frame.maxY + 2)
            let beside = CGPoint(x: 102, y: 110)
            for point in [above, below, beside] {
                expect(HwpHitTester().textPaints(long, in: frame, at: point))
                    .to(beFalse(), description: "\(point)")
                expect(HwpHitTester.mayPaintOutsideFrame(long, frame: frame, at: point))
                    .to(beFalse(), description: "\(point)")
            }

            let superscripted = NSMutableAttributedString(attributedString: long)
            // 위 첨자 올림 0.44 × 10pt = 4.4 — 위로 4.4pt 띠(y ≥ 95.6)까지만 연다.
            superscripted.addAttribute(
                HwpAttributedStringKey.glyphBaselineOffset, value: NSNumber(value: 4.4),
                range: NSRange(location: 0, length: 2)
            )
            expect(HwpHitTester.mayPaintOutsideFrame(superscripted, frame: frame, at: above))
                == true
            expect(HwpHitTester.mayPaintOutsideFrame(
                superscripted, frame: frame, at: CGPoint(x: 10, y: 95)
            )) == false
            expect(HwpHitTester.mayPaintOutsideFrame(superscripted, frame: frame, at: below))
                == false
        }

        /// 상대 크기가 큰 글꼴은 첫 줄 잉크가 프레임 **위**로 샌다 (baseline = 상단 + 0.85 × 기본
        /// 크기, 잉크는 그 위로 글꼴 ascent) — 링크 없이도 그 글자 위의 탭은 앞 문단이 아니라 이
        /// 문단이다. 게이트가 글꼴 지표로 그 띠를 연다. 단 앞 문단의 **링크**는 이긴다 (#233): 한글은
        /// 그 자리를 앞 줄의 클릭 띠로 보고 다음 줄 잉크를 보지 않는다(상대 크기 200%·150% 실측 —
        /// `HwpHitTester.textClaim`, `HwpHyperlinkClickBandClaimTests`). 종전 이 테스트는 반대를
        /// 단언했다.
        func testTallRelativeSizeGlyphAboveTheFrameClaimsTheTap() {
            let tall = NSAttributedString(string: "HHHH", attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, 17, nil),
                HwpAttributedStringKey.baseFontSize: NSNumber(value: 10),
            ])
            let front = AnyHwpBlock(
                frame: CGRect(x: 0, y: 116, width: 100, height: 16), kind: .text,
                attributedString: tall
            )
            let link = AnyHwpBlock(
                frame: CGRect(x: 0, y: 100, width: 100, height: 16), kind: .text,
                attributedString: NSAttributedString(string: "LINK", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                ]),
                hyperlinkURL: Self.url
            )
            // 첫 줄 상자 상단은 프레임 위 — 그 안의 잉크(대문자 상단) 위를 누른다.
            let box = HwpDrawnTextLayout.textLineRegions(
                attributedString: tall, origin: front.frame.origin, lineWidth: front.frame.width
            ).first ?? .null
            expect(Double(box.minY)).to(beLessThan(Double(front.frame.minY)))
            let tap = CGPoint(x: 3, y: front.frame.minY - 1)
            expect(link.frame.contains(tap)) == true
            expect(HwpHitTester().textPaints(tall, in: front.frame, at: tap)) == true

            let plain = AnyHwpBlock(
                frame: link.frame, kind: .text, attributedString: link.attributedString
            )
            expect(HwpHitTester().hit(page: self.page([plain, front]), point: tap))
                == .text(blockIndex: 1, characterIndex: nil)
            expect(HwpHitTester().hit(page: self.page([link, front]), point: tap))
                == .hyperlink(url: Self.url, blockIndex: 0)
        }

        /// 옮겨진 run의 기울임 오버행이 프레임 **옆**으로 나간 잉크 — 링크 없는 쌍둥이
        /// (`testInkOverhangOfShiftedRunStaysEligible`은 링크가 게이트 앞에서 먼저 이긴다).
        func testShiftedSlantedOverhangBesideTheFrameClaimsTheTap() {
            var matrix = CGAffineTransform.identity
            matrix.c += 0.22
            let slanted = CTFontCreateCopyWithAttributes(Self.font, 0, &matrix, nil)
            let plain = NSAttributedString(string: "fff", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: slanted,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -3),
            ])
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(plain), nil, nil, nil
            ))
            let frame = CGRect(x: 100, y: 100, width: natural, height: 12)
            let front = AnyHwpBlock(frame: frame, kind: .text, attributedString: plain)
            let side = AnyHwpBlock(
                frame: CGRect(x: frame.maxX, y: 100, width: 100, height: 12), kind: .text,
                attributedString: NSAttributedString(string: "LINK", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                ]),
                hyperlinkURL: Self.url
            )
            let band = HwpDrawnTextLayout.textLineRegions(
                attributedString: plain, origin: frame.origin, lineWidth: frame.width
            ).last ?? .null
            let tap = CGPoint(x: band.maxX - 0.2, y: frame.minY + 8)
            // 정말 프레임 옆 밖·밴드 안·옆 블록 프레임 안이다.
            expect(Double(band.maxX)).to(beGreaterThan(Double(frame.maxX)))
            expect(band.contains(tap)) == true
            expect(side.frame.contains(tap)) == true

            expect(HwpHitTester().hit(page: self.page([side, front]), point: tap))
                == .text(blockIndex: 1, characterIndex: nil)
        }

        /// payload 없는 조각 종류도 같은 술어로 claim한다 — 프레임 안과 같은 종류별 답이다.
        func testPayloadlessFragmentKindsClaimWithTheirOwnHit() {
            for (kind, expected) in [
                (HwpBlockKind.table, HwpHitResult.table(blockIndex: 1, row: 0, col: 0)),
                (.textbox, .shape(blockIndex: 1)),
                (.footnote, .footnote(blockIndex: 1, number: 0)),
            ] {
                let front = foreground(kind: kind)
                let tap = tapOnShiftedGlyph(of: front)
                expect(HwpHitTester().hit(page: self.page([self.behind, front]), point: tap))
                    .to(equal(expected), description: "\(kind)")
            }
        }
    }
#endif
