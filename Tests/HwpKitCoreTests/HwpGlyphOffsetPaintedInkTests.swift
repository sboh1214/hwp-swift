import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 옮겨진 밴드의 가로 범위는 **잉크**다 — 진행 폭이 아니다 (#200 리뷰).
    ///
    /// `CTRunGetTypographicBounds`는 공백·탭의 진행 폭을 세지만 `CTRunDraw`는 거기 아무것도
    /// 찍지 않는다. 밴드가 그 폭을 덮으면 세로로 옮겨진 **빈 띠**가 링크로 눌리고, 전경
    /// 글자가 뒤 층의 보이는 링크를 거짓으로 가린다 (R54 정밀 claim 위반). 줄 상자
    /// (`selectionRect`)가 꼬리 공백을 빼는 것과도 어긋났다.
    final class HwpGlyphOffsetBandInkTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        private static let origin = CGPoint(x: 0, y: 100)

        private func attributes(
            font: CTFont = HwpGlyphOffsetBandInkTests.font, offset: Double?
        ) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ]
            if let offset {
                attributes[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(value: offset)
            }
            return attributes
        }

        private func line(_ string: NSAttributedString) -> HwpDrawnLine? {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: 200
            ).first
        }

        /// 줄 상자 뒤에 붙는 밴드들 (`paintedRects.dropFirst()`).
        private func bands(_ string: NSAttributedString) -> [CGRect] {
            Array(line(string)?.paintedRects.dropFirst() ?? [])
        }

        /// **꼬리 공백은 밴드에 안 든다** — 줄 상자가 빼는 것과 같은 자리에서 끝난다.
        func testTrailingWhitespaceDoesNotExtendTheBand() {
            let padded = NSAttributedString(string: "LINK   ", attributes: attributes(offset: -3))
            let bare = NSAttributedString(string: "LINK", attributes: attributes(offset: -3))
            let box = line(padded)?.selectionRect ?? .null
            let paddedBands = bands(padded)
            let bareBands = bands(bare)

            expect(paddedBands.count) == 1
            // 진행 폭 기반이면 꼬리 공백 3자(≈8.3pt)만큼 줄 상자 오른쪽 밖까지 갔다.
            expect(Double(paddedBands[0].maxX))
                .to(beLessThanOrEqualTo(Double(box.maxX) + 0.001))
            // 공백이 있든 없든 같은 잉크 — 밴드가 같다.
            expect(paddedBands) == bareBands
        }

        /// **공백뿐인 run은 밴드가 없다** — 줄 상자 폭이 0인데 밴드만 8pt였다.
        func testWhitespaceOnlyRunHasNoBand() {
            let blank = NSAttributedString(string: "   ", attributes: attributes(offset: -3))

            expect(self.bands(blank)).to(beEmpty())
            expect(Double(self.line(blank)?.selectionRect.width ?? -1))
                .to(beCloseTo(0, within: 0.001))
        }

        /// **run 끝의 탭 진행 폭은 밴드에 안 든다** — 탭은 글자 모양 속성(글자 위치 포함)으로
        /// 방출되므로 파싱 문서에서 닿는 경우다. `A\t`만 옮기면 밴드는 A의 잉크로 끝난다.
        func testTabAdvanceAtRunEndIsExcluded() {
            let string = NSMutableAttributedString(
                string: "A\t", attributes: attributes(offset: -3)
            )
            string.append(NSAttributedString(string: "B", attributes: attributes(offset: nil)))
            let bands = bands(string)
            let bare = self.bands(
                NSAttributedString(string: "A", attributes: attributes(offset: -3))
            )

            expect(bands.count) == 1
            expect(bands) == bare
            // B는 탭 스톱 뒤(≈28pt)에 있다 — 밴드가 그 앞에서 끝나야 탭 띠를 안 덮는다.
            let bStart = line(string).map { CTLineGetOffsetForStringIndex($0.line, 2, nil) } ?? 0
            expect(Double(bands[0].maxX)).to(beLessThan(Double(bStart) - 10))
        }

        /// **장평(글꼴 매트릭스)이 밴드에 반영된다** — `CTRunGetPositions`는 매트릭스 적용 전
        /// 좌표라, 그것으로 낸 밴드는 장평 50% run에서 잉크의 두 배였다. 줄 상자와 같은
        /// 자리에서 끝나야 한다.
        func testCondensedFontBandFollowsScaledInk() {
            var matrix = CGAffineTransform(scaleX: 0.5, y: 1)
            let condensed = CTFontCreateCopyWithAttributes(Self.font, 0, &matrix, nil)
            let string = NSAttributedString(
                string: "LINK", attributes: attributes(font: condensed, offset: -3)
            )
            let box = line(string)?.selectionRect ?? .null
            let full = line(
                NSAttributedString(string: "LINK", attributes: attributes(offset: -3))
            )?.selectionRect ?? .null
            let bands = bands(string)

            expect(bands.count) == 1
            // 정말 장평이 걸렸는지 — 줄 상자가 원래의 절반이다.
            expect(Double(box.width)).to(beCloseTo(Double(full.width) / 2, within: 0.01))
            expect(Double(bands[0].maxX)).to(beLessThanOrEqualTo(Double(box.maxX) + 0.001))
            expect(Double(bands[0].maxX)).to(beGreaterThan(Double(box.maxX) - 1))
        }

        /// 줄 **중간**의 장평 run — 매트릭스 적용 전 좌표로 낸 밴드는 실제 x의 두 배 자리
        /// (엉뚱한 열 위)에 섰다. 밴드는 그 run의 글자 범위 안에 있어야 한다.
        func testCondensedRunMidLineBandStaysOnItsOwnColumns() {
            var matrix = CGAffineTransform(scaleX: 0.5, y: 1)
            let condensed = CTFontCreateCopyWithAttributes(Self.font, 0, &matrix, nil)
            let string = NSMutableAttributedString(
                string: String(repeating: "A", count: 20), attributes: attributes(offset: nil)
            )
            string.append(NSAttributedString(
                string: "LINK", attributes: attributes(font: condensed, offset: -3)
            ))
            let drawn = line(string)
            let bands = bands(string)
            let start = drawn.map { CTLineGetOffsetForStringIndex($0.line, 20, nil) } ?? 0
            let end = drawn.map { CTLineGetOffsetForStringIndex($0.line, 24, nil) } ?? 0

            expect(bands.count) == 1
            expect(Double(bands[0].minX)).to(beGreaterThanOrEqualTo(Double(start) - 0.5))
            expect(Double(bands[0].maxX)).to(beLessThanOrEqualTo(Double(end) + 0.5))
            expect(Double(bands[0].width)).to(beGreaterThan(Double(end - start) / 2))
        }

        /// run **안쪽** 공백은 하나의 밴드에 남는다 — 줄 상자(선택 하이라이트)도 안쪽
        /// 공백을 덮는 것과 같은 기준이라, 옮겨진 링크의 낱말 사이가 히트 불가가 되지 않는다.
        func testInteriorSpaceStaysInsideOneBand() {
            let string = NSAttributedString(string: "A B", attributes: attributes(offset: -3))
            let bands = bands(string)
            let spaceX = line(string).map { CTLineGetOffsetForStringIndex($0.line, 1, nil) } ?? 0

            expect(bands.count) == 1
            expect(bands[0].contains(CGPoint(x: spaceX + 1, y: bands[0].midY))) == true
        }

        /// **run 경계의 낱말 사이도 덮는다** — 한글(폴백 글꼴)과 라틴이 섞이면 공백이 제 run이
        /// 되거나 라틴 run에 붙는다. 어느 쪽이든 옮겨진 링크의 낱말 사이가 히트 불가가 되면
        /// 안 된다 (`홈페이지 바로가기`처럼 한국어 문서의 일반형).
        func testWordGapAcrossRunBoundaryIsBridged() {
            let mixed = NSAttributedString(
                string: "한글 link", attributes: attributes(offset: -3)
            )
            let bands = bands(mixed)
            let spaceX = line(mixed).map { CTLineGetOffsetForStringIndex($0.line, 2, nil) } ?? 0
            let runCount = line(mixed).map { CFArrayGetCount(CTLineGetGlyphRuns($0.line)) } ?? 0

            // 정말 run이 갈렸는지 — 아니면 이 테스트가 아무것도 지키지 않는다.
            expect(runCount).to(beGreaterThan(1))
            expect(bands.count) == 1
            expect(bands[0].contains(CGPoint(x: spaceX + 1, y: bands[0].midY))) == true
        }

        /// 공백만 따로 run이 되어도(글꼴이 다른 두 낱말 사이) 다리가 놓인다 — 다만 그 공백이
        /// **옮겨지지 않았으면**(오프셋 0) 묶지 않는다: 거기엔 옮겨진 잉크가 없다.
        func testWhitespaceOnlyRunBridgesOnlyWhenShifted() {
            let bold = CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil)
            let shifted = NSMutableAttributedString(
                string: "click", attributes: attributes(font: bold, offset: -3)
            )
            shifted.append(NSAttributedString(string: " ", attributes: attributes(offset: -3)))
            shifted.append(NSAttributedString(string: "here", attributes: attributes(offset: -3)))
            let spaceX = line(shifted).map { CTLineGetOffsetForStringIndex($0.line, 5, nil) } ?? 0
            let bridged = bands(shifted)
            expect(bridged.count) == 1
            expect(bridged[0].contains(CGPoint(x: spaceX + 1, y: bridged[0].midY))) == true

            let unshiftedSpace = NSMutableAttributedString(
                string: "click", attributes: attributes(font: bold, offset: -3)
            )
            unshiftedSpace.append(
                NSAttributedString(string: " ", attributes: attributes(offset: nil))
            )
            unshiftedSpace.append(
                NSAttributedString(string: "here", attributes: attributes(offset: -3))
            )
            let split = bands(unshiftedSpace)
            expect(split.count) == 2
            expect(split.contains { $0.contains(CGPoint(x: spaceX + 1, y: $0.midY)) }) == false
        }

        /// 링크가 다른 run은 잇닿아도 묶지 않는다 — 한 밴드가 두 스팬에 걸치면 어느 쪽 링크도
        /// 그 밴드를 못 가져가거나(포함 실패) 남의 잉크를 가져간다.
        func testAdjacentRunsWithDifferentLinksStaySeparate() {
            var first = attributes(offset: -3)
            first[HwpAttributedStringKey.hyperlink] = "https://a.example"
            var second = attributes(offset: -3)
            second[HwpAttributedStringKey.hyperlink] = "https://b.example"
            let string = NSMutableAttributedString(string: "AB", attributes: first)
            string.append(NSAttributedString(string: "CD", attributes: second))
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: Self.origin, lineWidth: 200
            )

            expect(self.bands(string).count) == 2
            expect(regions.filter { $0.url == "https://a.example" }.count) == 2
            expect(regions.filter { $0.url == "https://b.example" }.count) == 2
        }

        /// **순수 RTL 줄** — 꼬리 공백이 시각적으로 왼쪽에 놓여 줄 상자 밖으로 나간다. 진행 폭
        /// 밴드는 거기(줄 상자 왼쪽 밖)에 빈 밴드를 하나 더 냈다. 잉크 밴드는 줄 상자 안이다.
        func testRTLTrailingWhitespaceLeavesNoBandOutsideTheLineBox() {
            let rtl = NSAttributedString(
                string: "\u{05D0}\u{05D1}\u{05D2} ", attributes: attributes(offset: -3)
            )
            let box = line(rtl)?.selectionRect ?? .null
            let bands = bands(rtl)

            expect(bands.count) == 1
            expect(Double(bands[0].minX)).to(beGreaterThanOrEqualTo(Double(box.minX) - 0.5))
            expect(Double(bands[0].maxX)).to(beLessThanOrEqualTo(Double(box.maxX) + 0.5))
        }
    }

    /// 자격 영역은 옮겨진 글리프의 **최대 |오프셋|**만큼도 넓다 (#200 리뷰).
    ///
    /// `textBounds`의 세로 여유가 줄 높이뿐이면, 오프셋이 그보다 큰 글리프 — 첨자(0.67배
    /// 글꼴·+0.33em)와 글자 위치(±1.0×크기)가 누적되는 글자 모양, 또는 공개 키로 실린 큰
    /// 값 — 위의 탭이 rect 판정에 닿기도 전에 블록 단계에서 기각된다 (R56 "자격 ⊇ 칠"
    /// 위반). 실측: Helvetica 10pt·줄 높이 10에서 오프셋 12부터 `hit`이 nil이었다.
    final class HwpLargeGlyphOffsetEligibilityTests: XCTestCase {
        private static let url = "https://example.com"
        private static let frame = CGRect(x: 0, y: 100, width: 100, height: 10)

        private func linked(fontSize: CGFloat = 10, offset: Double) -> NSAttributedString {
            NSAttributedString(string: "LINK", attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                HwpAttributedStringKey.hyperlink: Self.url,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: offset),
            ])
        }

        private func page(_ block: AnyHwpBlock) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block], pageNumber: 1
            )
        }

        /// 옮겨진 밴드의 **바깥 끝** 1pt 안쪽 — 위로 옮겼으면 상단, 아래로면 하단.
        ///
        /// 밴드가 정말 있고 그 지점이 프레임 **밖**임을 단언한다 — 밴드가 사라지면 `.last`가
        /// 줄 상자로 떨어져 프레임 안 탭이 되고, 그러면 자격이 어떻든 통과해 버린다.
        private func farEdgeTap(of attributed: NSAttributedString, offset: Double) -> CGPoint {
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: attributed, origin: Self.frame.origin, lineWidth: Self.frame.width
            )
            expect(regions.count).to(equal(2), description: "offset \(offset): 밴드가 없다")
            let band = regions.last?.rect ?? .null
            let tap = CGPoint(x: band.minX + 2, y: offset > 0 ? band.minY + 1 : band.maxY - 1)
            expect(Self.frame.contains(tap)).to(beFalse(), description: "offset \(offset): \(tap)")
            return tap
        }

        private func url(of hit: HwpHitResult?) -> String? {
            if case let .hyperlink(url, _) = hit {
                return url
            }
            return nil
        }

        /// 줄 높이(10)를 넘는 오프셋도 양방향 모두 눌린다.
        func testOffsetBeyondLineHeightStaysHittable() {
            for offset in [12.0, 20.0, -12.0, -20.0] {
                let attributed = linked(offset: offset)
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: .text, attributedString: attributed
                )
                let hit = HwpHitTester().hit(
                    page: page(block), point: farEdgeTap(of: attributed, offset: offset)
                )

                expect(self.url(of: hit)).to(equal(Self.url), description: "offset \(offset)")
            }
        }

        /// 첨자 크기 글꼴(6.7pt)에 첨자 올림 + 글자 위치 100이 누적된 13.3pt — 파싱 문서에서
        /// 닿는 조합이다 (`applySuperscript`는 기존 오프셋에 더한다).
        func testSuperscriptSizedFontWithStackedOffsetStaysHittable() {
            let attributed = linked(fontSize: 6.7, offset: 13.3)
            let block = AnyHwpBlock(
                frame: Self.frame, kind: .text, attributedString: attributed
            )
            let hit = HwpHitTester().hit(
                page: page(block), point: farEdgeTap(of: attributed, offset: 13.3)
            )

            expect(self.url(of: hit)) == Self.url
        }

        /// 구조적 불변식 — 어떤 오프셋이든 자격 영역이 칠 영역(`textLineRegions`)을 품는다.
        func testEligibilityContainsEveryPaintedRect() {
            for offset in stride(from: -40.0, through: 40.0, by: 4.0) where offset != 0 {
                let attributed = linked(offset: offset)
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: .text, attributedString: attributed
                )
                let eligible = HwpHitTester().hitEligibleFrame(for: block)
                let painted = HwpDrawnTextLayout.textLineRegions(
                    attributedString: attributed, origin: Self.frame.origin,
                    lineWidth: Self.frame.width
                )

                // 밴드가 실제로 프레임 밖에 있어야 이 단언이 무언가를 지킨다.
                expect(painted.count).to(equal(2), description: "offset \(offset)")
                expect(painted.allSatisfy { Self.frame.contains($0) })
                    .to(beFalse(), description: "offset \(offset): 밴드가 프레임 안이다")
                expect(painted.allSatisfy { eligible.contains($0) })
                    .to(beTrue(), description: "offset \(offset): \(eligible) ⊉ \(painted)")
            }
        }

        /// 옮겨진 run의 잉크는 진행 폭 밖으로 넘칠 수 있다(기울임 근사·이탤릭 `f`) — 링크가
        /// 자연 폭 프레임을 꽉 채우면 그 오버행이 rect 폭 × 6% 밖이라 방출된 링크 rect가
        /// 블록 단계에서 기각됐다. 자격은 옮겨진 run이 있을 때 가로도 글꼴 지표로 넓힌다.
        func testInkOverhangOfShiftedRunStaysEligible() {
            var matrix = CGAffineTransform.identity
            matrix.c += 0.22
            let slanted = CTFontCreateCopyWithAttributes(
                CTFontCreateWithName("Helvetica" as CFString, 10, nil), 0, &matrix, nil
            )
            let attributed = NSAttributedString(string: "fff", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: slanted,
                HwpAttributedStringKey.hyperlink: Self.url,
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -3),
            ])
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(attributed), nil, nil, nil
            ))
            let frame = CGRect(x: 100, y: 100, width: natural, height: 12)
            let block = AnyHwpBlock(frame: frame, kind: .text, attributedString: attributed)
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: attributed, origin: frame.origin, lineWidth: frame.width
            ).map(\.rect)
            let band = regions.last ?? .null
            let eligible = HwpHitTester().hitEligibleFrame(for: block)

            // 정말 넘치는지 — 밴드 오른쪽 끝이 슬라이트 오버플로 허용치 밖이다.
            expect(regions.count) == 2
            expect(Double(band.maxX)).to(beGreaterThan(Double(frame.maxX + frame.width * 0.06)))
            expect(regions.allSatisfy { eligible.contains($0) }) == true
            let tap = CGPoint(x: band.maxX - 0.2, y: band.maxY - 1)
            expect(self.url(of: HwpHitTester().hit(page: self.page(block), point: tap))) == Self.url
        }

        /// 세로로 넓히는 몫은 **최대 |오프셋|**만큼이고, 가로는 오프셋 크기와 무관하게 글꼴 줄
        /// 높이(잉크 오버행 상한)까지다 — 오프셋 없는 문단의 자격은 그대로다.
        func testEligibilityGrowsByTheOffsetVerticallyAndByTheLineHeightHorizontally() {
            let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
            let lineHeight = Double(
                CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            )
            let plain = NSAttributedString(string: "LINK", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ])
            let plainFrame = HwpHitTester().hitEligibleFrame(
                for: AnyHwpBlock(frame: Self.frame, kind: .text, attributedString: plain)
            )
            // 오프셋 없는 문단: 가로는 폭의 6%, 세로는 줄 높이 (종전 그대로).
            expect(Double(Self.frame.minX - plainFrame.minX)).to(beCloseTo(6, within: 0.001))
            expect(Double(Self.frame.minY - plainFrame.minY))
                .to(beCloseTo(lineHeight, within: 0.001))

            for offset in [-7.0, 20.0] {
                let shifted = HwpHitTester().hitEligibleFrame(
                    for: AnyHwpBlock(
                        frame: Self.frame, kind: .text, attributedString: linked(offset: offset)
                    )
                )
                expect(Double(plainFrame.minY - shifted.minY))
                    .to(beCloseTo(abs(offset), within: 0.001), description: "offset \(offset)")
                expect(Double(shifted.maxY - plainFrame.maxY))
                    .to(beCloseTo(abs(offset), within: 0.001), description: "offset \(offset)")
                expect(Double(Self.frame.minX - shifted.minX))
                    .to(beCloseTo(lineHeight, within: 0.001), description: "offset \(offset)")
                expect(Double(shifted.maxX - Self.frame.maxX))
                    .to(beCloseTo(lineHeight, within: 0.001), description: "offset \(offset)")
            }
        }
    }
#endif
