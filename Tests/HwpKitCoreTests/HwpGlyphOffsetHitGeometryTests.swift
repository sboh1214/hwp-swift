import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글자 위치(표 33)로 옮겨진 글리프와 **기하 질의**의 관계 (#197 리뷰).
    ///
    /// 조판 문자열이 `kCTBaselineOffset`을 싣지 않게 된 뒤(그래야 한글처럼 줄 상자가
    /// 안 커진다) 글리프는 `hwp.glyphBaselineOffset`으로 실제로 움직인다. 그러면 줄
    /// 상자만 보는 기하 질의는 **그려진 글자를 놓친다** — 실측: Helvetica 10pt 링크에
    /// 글자 위치 30이면 잉크 하단 3.000pt가 줄 상자 밖이라 하단 클릭이 `.text`로
    /// 떨어지고, 위치 100에서는 겹침이 0%가 된다.
    ///
    /// 반대로 **선택 하이라이트는 따라가면 안 된다** — 한글도 안 따라간다
    /// (2026-09-14 실측: `CharShape` 픽스처의 '글자위치 30' 줄만 선택하면 하이라이트
    /// 상단이 이웃 줄들과 같은 격자(81px 간격)에 있고 글리프만 그 안에서 7px 내려간다).
    final class HwpGlyphOffsetHitGeometryTests: XCTestCase {
        private static let url = "https://example.com"

        /// 글자 위치가 실린 링크 문자열. `offset`은 렌더러 규약(양수 = 위)이다.
        private func linked(offset: Double?) -> NSAttributedString {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, 10, nil),
                HwpAttributedStringKey.hyperlink: Self.url,
            ]
            if let offset {
                attributes[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(value: offset)
            }
            return NSAttributedString(string: "LINK", attributes: attributes)
        }

        private func region(offset: Double?) -> CGRect {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: linked(offset: offset),
                origin: CGPoint(x: 0, y: 100),
                lineWidth: 200
            ).first?.rect ?? .null
        }

        /// **아래로 옮긴 글리프만큼 링크 영역이 아래로 넓어진다** — 위는 그대로다
        /// (평행이동이 아니라 합집합이라, 같은 줄의 오프셋 없는 글자도 계속 덮는다).
        func testDownwardGlyphOffsetGrowsHyperlinkRegionDownward() {
            let plain = region(offset: nil)
            let lowered = region(offset: -3)

            expect(plain.isNull) == false
            expect(Double(lowered.minY)).to(beCloseTo(Double(plain.minY), within: 0.0001))
            expect(Double(lowered.maxY - plain.maxY)).to(beCloseTo(3.0, within: 0.0001))
        }

        /// 위로 옮기면 반대쪽이 넓어진다.
        func testUpwardGlyphOffsetGrowsHyperlinkRegionUpward() {
            let plain = region(offset: nil)
            let raised = region(offset: 3)

            expect(Double(plain.minY - raised.minY)).to(beCloseTo(3.0, within: 0.0001))
            expect(Double(raised.maxY)).to(beCloseTo(Double(plain.maxY), within: 0.0001))
        }

        /// 한 줄에 오프셋이 다른 run이 섞이면 **양쪽 다** 덮는다 — 밴드를 통째로 옮기면
        /// 오프셋 없는 run의 잉크가 오히려 밖으로 나간다.
        func testMixedOffsetsWidenBothEdges() {
            let mixed = NSMutableAttributedString()
            let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
            for (text, offset) in [("UP", 4.0), ("MID", 0.0), ("DOWN", -2.0)] {
                var attributes: [NSAttributedString.Key: Any] = [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    HwpAttributedStringKey.hyperlink: Self.url,
                ]
                if offset != 0 {
                    attributes[HwpAttributedStringKey.glyphBaselineOffset] =
                        NSNumber(value: offset)
                }
                mixed.append(NSAttributedString(string: text, attributes: attributes))
            }
            let rect = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: mixed, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first?.rect ?? .null
            let plain = region(offset: nil)

            expect(Double(plain.minY - rect.minY)).to(beCloseTo(4.0, within: 0.0001))
            expect(Double(rect.maxY - plain.maxY)).to(beCloseTo(2.0, within: 0.0001))
        }

        /// **선택 하이라이트는 그대로다** (한글 실측) — 옮겨진 잉크를 덮는 것은
        /// `paintedRect` 쪽이고, `textLineRegions`(claim)가 그것을 쓴다.
        func testSelectionRectStaysOnTheLineBoxWhilePaintedRectFollowsInk() {
            let lowered = linked(offset: -3)
            let plainLine = HwpDrawnTextLayout.lines(
                attributedString: linked(offset: nil),
                origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first
            let loweredLine = HwpDrawnTextLayout.lines(
                attributedString: lowered, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first
            let plainSelection = try? XCTUnwrap(plainLine?.selectionRect)
            let loweredSelection = try? XCTUnwrap(loweredLine?.selectionRect)

            expect(loweredSelection) == plainSelection
            expect(Double((loweredLine?.paintedRect.maxY ?? 0) - (loweredSelection?.maxY ?? 0)))
                .to(beCloseTo(3.0, within: 0.0001))

            let claim = HwpDrawnTextLayout.textLineRegions(
                attributedString: lowered, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first
            expect(Double((claim?.maxY ?? 0) - (plainSelection?.maxY ?? 0)))
                .to(beCloseTo(3.0, within: 0.0001))
        }
    }
#endif
