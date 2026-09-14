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

        /// **옮겨진 run의 칠 영역은 그 run의 가로 범위만 갖는다** (#197 리뷰 2차).
        ///
        /// 줄 전체 폭에 최대 오프셋을 걸면 안 옮겨진 run 아래의 **빈 띠까지 claim**해,
        /// 그 자리의 탭이 뒤 층의 보이는 링크를 막는다 (claim은 정밀 커버리지여야
        /// 한다는 R54). 'A'만 10pt 내리면 'B…' 아래 띠는 칠한 것이 아니다.
        func testLoweredRunClaimsOnlyItsOwnColumnRange() {
            let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
            let mixed = NSMutableAttributedString(string: "A", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -10),
            ])
            mixed.append(NSAttributedString(string: "BBBBBBBBBB", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ]))
            let regions = HwpDrawnTextLayout.textLineRegions(
                attributedString: mixed, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            )
            let box = try? XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: mixed, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first?.selectionRect)
            let lowered = CGPoint(x: (box?.maxX ?? 0) - 2, y: (box?.maxY ?? 0) + 5)
            let inA = CGPoint(x: (box?.minX ?? 0) + 1, y: (box?.maxY ?? 0) + 5)

            // 줄 상자 자체는 그대로 있고, 내려간 띠는 'A'의 가로 범위에만 있다.
            expect(regions.contains { $0.contains(inA) }) == true
            expect(regions.contains { $0.contains(lowered) }) == false
            expect(regions.contains { $0 == box }) == true
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
            let loweredBand = loweredLine?.paintedRects.last?.maxY ?? 0
            expect(Double(loweredBand - (loweredSelection?.maxY ?? 0)))
                .to(beCloseTo(3.0, within: 0.0001))

            let claim = HwpDrawnTextLayout.textLineRegions(
                attributedString: lowered, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            )
            // 줄 상자는 그대로 남고 내려간 밴드가 **따로** 온다 (정밀 커버리지).
            expect(claim.contains { $0 == plainSelection }) == true
            expect(Double((claim.map(\.maxY).max() ?? 0) - (plainSelection?.maxY ?? 0)))
                .to(beCloseTo(3.0, within: 0.0001))
        }
    }

    /// 넓힌 자격 영역에서 **블록 링크 폴백이 위치를 확인해야** 한다 (#197 리뷰 2차).
    ///
    /// `hitEligibleFrame`의 `.text`가 세로로도 넓어지면서(글자 위치가 옮긴 글리프를 덮기
    /// 위해) 이웃 블록의 자격 띠가 서로 겹친다. `blockLevelURL`이 위치를 안 보고 URL을
    /// 돌려주면 **위쪽 글자 위의 탭이 아래쪽 블록의 링크를 연다** — 방출된 적 없는 URL이
    /// 열리는 R63의 `.text` 축이다.
    final class HwpTextBlockLinkFallbackTests: XCTestCase {
        private func linkBlock(url: String, y: CGFloat) -> AnyHwpBlock {
            AnyHwpBlock(
                frame: CGRect(x: 0, y: y, width: 100, height: 10),
                kind: .text,
                attributedString: NSAttributedString(string: "LINK", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName("Helvetica" as CFString, 10, nil),
                ]),
                hyperlinkURL: url
            )
        }

        private func url(of hit: HwpHitResult?) -> String? {
            if case let .hyperlink(url, _) = hit {
                return url
            }
            return nil
        }

        private func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks,
                pageNumber: 1
            )
        }

        /// 위쪽 글자 위(y=107)의 탭은 **위쪽** URL이다 — 아래쪽 블록의 자격 띠가 거기까지
        /// 닿아도 그 자리에 아래쪽 글자는 칠해지지 않았다.
        func testTapOnUpperGlyphDoesNotOpenLowerBlockLink() {
            let upper = linkBlock(url: "https://upper.example", y: 100)
            let lower = linkBlock(url: "https://lower.example", y: 116)

            for blocks in [[upper, lower], [lower, upper]] {
                let hit = HwpHitTester().hit(page: page(blocks), point: CGPoint(x: 5, y: 107))
                expect(self.url(of: hit)) == "https://upper.example"
            }
        }

        /// 프레임 안은 종전대로 — 조판 없이 통과한다.
        func testTapInsideFrameStillOpensItsOwnLink() {
            let block = linkBlock(url: "https://inside.example", y: 100)
            let hit = HwpHitTester().hit(page: page([block]), point: CGPoint(x: 5, y: 105))

            expect(self.url(of: hit)) == "https://inside.example"
        }

        /// 어느 블록의 글자도 칠해지지 않은 띠에서는 폴백하지 않는다.
        func testTapOnEmptyBandOpensNoLink() {
            let block = linkBlock(url: "https://only.example", y: 100)
            // 글자 폭(≈22pt) 오른쪽, 프레임 아래 — 자격 영역 안이지만 칠은 없다.
            let hit = HwpHitTester().hit(page: page([block]), point: CGPoint(x: 80, y: 114))

            expect(self.url(of: hit)).to(beNil())
        }
    }
#endif
