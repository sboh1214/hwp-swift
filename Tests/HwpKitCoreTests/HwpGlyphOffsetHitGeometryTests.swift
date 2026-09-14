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

        private func regions(offset: Double?) -> [CGRect] {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: linked(offset: offset),
                origin: CGPoint(x: 0, y: 100),
                lineWidth: 200
            ).map(\.rect)
        }

        /// 줄 상자 rect는 **언제나 그대로** 나온다 — 옮긴 몫은 따로 붙는 rect다.
        private func box(offset: Double?) -> CGRect {
            regions(offset: offset).first ?? .null
        }

        /// **아래로 옮긴 글리프만큼 링크 영역이 아래로 넓어진다** — 줄 상자는 그대로고
        /// 내려간 밴드가 따로 온다.
        func testDownwardGlyphOffsetGrowsHyperlinkRegionDownward() {
            let plain = box(offset: nil)
            let lowered = regions(offset: -3)

            expect(plain.isNull) == false
            expect(lowered.first) == plain
            expect(Double((lowered.map(\.maxY).max() ?? 0) - plain.maxY))
                .to(beCloseTo(3.0, within: 0.0001))
            expect(Double(lowered.map(\.minY).min() ?? 0))
                .to(beCloseTo(Double(plain.minY), within: 0.0001))
        }

        /// 위로 옮기면 반대쪽이 넓어진다.
        func testUpwardGlyphOffsetGrowsHyperlinkRegionUpward() {
            let plain = box(offset: nil)
            let raised = regions(offset: 3)

            expect(Double(plain.minY - (raised.map(\.minY).min() ?? 0)))
                .to(beCloseTo(3.0, within: 0.0001))
            expect(Double(raised.map(\.maxY).max() ?? 0))
                .to(beCloseTo(Double(plain.maxY), within: 0.0001))
        }

        /// 한 줄에 오프셋이 다른 run이 섞이면 **양쪽 다** 덮되, 각 밴드는 **자기 run의
        /// 가로 범위**만 갖는다 (#197 리뷰 3차).
        func testMixedOffsetsSplitPerRun() {
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
            let rects = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: mixed, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).map(\.rect)
            let plain = box(offset: nil)

            // 줄 상자 + 위로 4pt 밴드 + 아래로 2pt 밴드.
            expect(rects.count) == 3
            expect(Double(plain.minY - (rects.map(\.minY).min() ?? 0)))
                .to(beCloseTo(4.0, within: 0.0001))
            expect(Double((rects.map(\.maxY).max() ?? 0) - plain.maxY))
                .to(beCloseTo(2.0, within: 0.0001))
            // 옮긴 두 밴드는 줄 상자보다 **좁다** — 'MID'가 든 가로 범위를 안 가져간다.
            let lineBox = rects[0]
            for band in rects.dropFirst() {
                expect(Double(band.width)).to(beLessThan(Double(lineBox.width)))
            }
        }

        /// **링크 영역도 안 옮겨진 run 위의 빈 자리를 가져가지 않는다** (#197 리뷰 3차).
        ///
        /// 같은 URL의 'ABBBBBBBBBB'에서 A만 10pt 올리면, 종전에는 스팬 전체 폭에 최대
        /// 오프셋이 걸려 B **위**의 빈 자리까지 이 링크가 가져갔다 — 뒤에 있는 링크가
        /// 그 자리에서 졌다.
        func testRaisedRunLinkAreaKeepsItsOwnColumnRange() {
            let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
            let string = NSMutableAttributedString(string: "A", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                HwpAttributedStringKey.hyperlink: Self.url,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: 10),
            ])
            string.append(NSAttributedString(string: "BBBBBBBBBB", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                HwpAttributedStringKey.hyperlink: Self.url,
            ]))
            let rects = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).map(\.rect)
            // 기준점은 **오프셋 없는 같은 문자열**의 줄 상자에서 낸다 — 결과에서 끌어오면
            // 구현이 rect를 부풀렸을 때 기준까지 함께 밀려 비교가 무의미해진다.
            let plainString = NSAttributedString(string: "ABBBBBBBBBB", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                HwpAttributedStringKey.hyperlink: Self.url,
            ])
            let lineBox = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: plainString, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            ).first?.rect ?? .null
            let aboveA = CGPoint(x: lineBox.minX + 1, y: lineBox.minY - 5)
            let aboveB = CGPoint(x: lineBox.maxX - 2, y: lineBox.minY - 5)

            expect(rects.contains { $0.contains(aboveA) }) == true
            expect(rects.contains { $0.contains(aboveB) }) == false
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

    /// 줄별 밴드를 **한 번만 걷어 나눠 쓰는** 캐시가 제자리에 붙는지 (#197 리뷰 후속).
    ///
    /// `hyperlinkRegions`는 링크 스팬마다 문단의 모든 줄을 돈다 — 밴드를 (스팬 × 줄)마다
    /// 다시 걷으면 `CTRunGetAttributes` 브리징 값을 그만큼 치른다 (실측: 40스팬 ~13줄
    /// 1.16 → 0.74ms, 120스팬 ~40줄 4.02 → 2.91ms). 줄 캐시 옆에 같이 두되 **색인이
    /// 어긋나면 다른 줄의 오프셋이 이 줄에 붙어** 방출된 적 없는 자리가 링크가 된다.
    final class HwpGlyphOffsetBandCacheTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)

        /// 좁은 폭에서 두 줄로 갈리는, 링크가 서로 다른 두 스팬. 둘째만 옮긴다.
        private func twoLines(offset: Double) -> NSAttributedString {
            let string = NSMutableAttributedString(string: "AAAAAAAAAA ", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.hyperlink: "https://first.example",
            ])
            string.append(NSAttributedString(string: "BBBBBBBBBB", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.hyperlink: "https://second.example",
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: offset),
            ]))
            return string
        }

        private func regions(_ string: NSAttributedString) -> [(rect: CGRect, url: String)] {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: 80
            )
        }

        /// 밴드는 **옮겨진 run이 있는 줄에만** 붙는다 — 앞 줄 링크는 줄 상자 하나뿐이다.
        func testBandLandsOnItsOwnLineOnly() {
            let regions = regions(twoLines(offset: 6))
            let first = regions.filter { $0.url == "https://first.example" }.map(\.rect)
            let second = regions.filter { $0.url == "https://second.example" }.map(\.rect)

            expect(first.count) == 1
            expect(second.count) == 2
            // 두 스팬이 실제로 다른 줄에 있다 (아니면 이 테스트가 아무것도 안 지킨다).
            expect(Double(second[0].minY)).to(beGreaterThan(Double(first[0].minY)))
            // 옮긴 몫은 둘째 줄 상자 위 6pt고, 첫 줄은 그대로다.
            expect(Double(second[0].minY - second[1].minY)).to(beCloseTo(6.0, within: 0.0001))
            expect(regions.contains { $0.rect.minY < first[0].minY }) == false
        }

        /// 오프셋 0은 **속성이 없는 것과 같다** — 건너뛰기 판정(`carriesGlyphOffset`)과
        /// 밴드 수집이 같은 술어를 써야 한 쪽만 0을 옮겨진 run으로 세지 않는다.
        func testZeroOffsetMatchesNoAttribute() {
            let zeroed = regions(twoLines(offset: 0)).map(\.rect)
            let plain = NSMutableAttributedString(string: "AAAAAAAAAA ", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.hyperlink: "https://first.example",
            ])
            plain.append(NSAttributedString(string: "BBBBBBBBBB", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: Self.font,
                HwpAttributedStringKey.hyperlink: "https://second.example",
            ]))

            expect(zeroed) == regions(plain).map(\.rect)
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
