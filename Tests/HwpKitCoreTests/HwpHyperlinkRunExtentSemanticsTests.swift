import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// run 진행 폭 범위의 **의미** — 자소 묶음의 소속, 자간, 단방향 줄의 종전 산식 대조,
    /// paint list ≡ 히트.
    final class HwpHyperlinkRunExtentSemanticsTests: HwpBidiHyperlinkRegionTestCase {
        /// **자소 묶음이 링크 경계에 걸치면 첫 글자의 링크다** — CT는 첫가끝 자모·ZWJ 이모지
        /// 열·아랍 lam-alef를 속성 경계를 넘어 한 run으로 내고 그 run의 속성(그려지는 링크)은
        /// 첫 글자 것이다. 포함 판정이면 그 run이 양쪽에서 버려져 클릭 구멍이 난다.
        func testClusterStraddlingSpanBoundaryBelongsToItsFirstCharacter() {
            let font = kCTFontAttributeName as NSAttributedString.Key
            let clusters: [(text: String, cut: Int)] = [
                ("\u{1112}\u{1161}\u{11AB}", 1),
                ("x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}y", 4),
                ("\u{0644}\u{0627}", 1),
            ]
            for (text, cut) in clusters {
                let string = NSMutableAttributedString(string: text, attributes: [font: Self.font])
                string.addAttribute(
                    HwpAttributedStringKey.hyperlink, value: "https://first.example",
                    range: NSRange(location: 0, length: cut)
                )
                string.addAttribute(
                    HwpAttributedStringKey.hyperlink, value: "https://second.example",
                    range: NSRange(location: cut, length: string.length - cut)
                )
                let regions = regions(string)
                let runs = inkedRuns(string)
                // 정말 걸치는 run이 있다 — 첫 글자 링크의 run이 경계 너머까지 든다.
                let straddles = runs.contains {
                    $0.url == "https://first.example" && $0.text.utf16.count > cut
                }
                expect(straddles).to(beTrue(), description: text)
                for run in runs {
                    expect(self.hit(regions, run.point))
                        .to(equal(run.url), description: "\(text) \"\(run.text)\"")
                }
                // 구멍이 없다 — 줄 상자 폭 전체가 어느 링크든 덮는다.
                let box = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: Self.origin, lineWidth: Self.width
                ).first?.selectionRect ?? .null
                let covered = regions.map(\.rect).reduce(CGFloat(0)) { $0 + $1.width }
                expect(Double(covered))
                    .to(beCloseTo(Double(box.width), within: 0.001), description: text)
            }
        }

        /// **논리 끝이 결합 부호인 RTL run의 rect는 기저 글리프로 잰다** (PR 리뷰) — RTL run의
        /// 첫 글리프는 논리 마지막 글자의 부호라 GPOS 오프셋만큼 기저와 다른 자리에 있다(Times
        /// New Roman 홀람은 기저 왼쪽 1.59pt, GeezaPro 샤다+파타는 오른쪽 3.71pt). 첫 글리프로
        /// 잡으면 링크 rect가 줄 상자 밖으로 나가거나 이웃 링크 글자를 덮는다. 오른쪽 정렬된
        /// 순수 RTL 줄에서 앞 스팬은 줄 상자 오른쪽 끝에 닿고 뒤 스팬과 정확히 잇닿아야 한다.
        func testRTLRunEndingWithCombiningMarkIsMeasuredFromItsBaseGlyph() {
            struct Case {
                let name: String
                let font: CTFont
                let first: String
                let second: String
            }
            let times = CTFontCreateWithName("Times New Roman" as CFString, 10, nil)
            let cases = [
                Case(name: "times holam", font: times,
                     first: "\u{05E9}\u{05B9}", second: " \u{05E2}\u{05DD}"),
                Case(name: "times qamats", font: times,
                     first: "\u{05E9}\u{05B8}", second: " \u{05E2}\u{05DD}"),
                Case(name: "arabic shadda fatha", font: Self.font,
                     first: "\u{0634}\u{0651}\u{064E}", second: " \u{0639}\u{0644}"),
                Case(name: "arabic dammatan", font: Self.font,
                     first: "\u{0645}\u{064F}\u{062D}\u{064E}\u{0645}\u{0651}\u{064E}"
                         + "\u{062F}\u{064C}",
                     second: " \u{0639}\u{0644}\u{064A}"),
            ]
            for testCase in cases {
                let name = testCase.name
                let string = joined([
                    span(testCase.first, url: "https://a.example", font: testCase.font),
                    span(testCase.second, url: "https://b.example", font: testCase.font),
                ])
                let regions = regions(string)
                let box = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: Self.origin, lineWidth: Self.width
                ).first?.selectionRect ?? .null
                let first = regions.filter { $0.url == "https://a.example" }.map(\.rect)
                let second = regions.filter { $0.url == "https://b.example" }.map(\.rect)
                expect(first.count).to(equal(1), description: name)
                expect(second.count).to(equal(1), description: name)
                guard let firstRect = first.first, let secondRect = second.first else { continue }
                expect(Double(firstRect.maxX))
                    .to(beCloseTo(Double(box.maxX), within: 0.001), description: name)
                expect(Double(secondRect.maxX))
                    .to(beCloseTo(Double(firstRect.minX), within: 0.001), description: name)
                expect(firstRect.intersects(secondRect)).to(beFalse(), description: name)
            }
        }

        /// **글리프 없는 문자는 앞 run에 흡수돼도 링크를 잃지 않는다** (PR 리뷰) — CT는
        /// U+200B·RLM(U+200F)·결합 부호를 속성이 달라도 앞 run에 합쳐 run이 스팬 경계를 넘는다.
        /// 포함 판정이면 그 run의 링크가 통째로 사라졌다. 종전 산식과 rect 수·범위가 같아야 한다.
        func testGlyphlessCharacterAbsorbedIntoPreviousRunKeepsBothLinks() {
            struct Case {
                let name: String
                let text: String
                /// 앞 링크 길이(UTF-16)와, 링크 없는 사이 문자 수.
                let first: Int
                let gap: Int
            }
            let font = kCTFontAttributeName as NSAttributedString.Key
            let cases = [
                Case(name: "zwsp of second", text: "AAA\u{200B}BBB", first: 3, gap: 0),
                Case(name: "rlm unlinked", text: "AAA\u{200F}BBB", first: 3, gap: 1),
                Case(name: "hangul rlm", text: "가나\u{200F}다라", first: 2, gap: 1),
                Case(name: "combining mark of second", text: "ab\u{0301}c", first: 2, gap: 0),
            ]
            for testCase in cases {
                let string = NSMutableAttributedString(
                    string: testCase.text, attributes: [font: Self.font]
                )
                string.addAttribute(
                    HwpAttributedStringKey.hyperlink, value: "https://first.example",
                    range: NSRange(location: 0, length: testCase.first)
                )
                let secondStart = testCase.first + testCase.gap
                string.addAttribute(
                    HwpAttributedStringKey.hyperlink, value: "https://second.example",
                    range: NSRange(location: secondStart, length: string.length - secondStart)
                )
                let regions = regions(string).map { ($0.rect, $0.url) }
                let legacy = legacySpanBoxes(string, lineWidth: Self.width)
                expect(regions.count).to(equal(legacy.count), description: testCase.name)
                expect(regions.count).to(equal(2), description: testCase.name)
                for (region, box) in zip(regions, legacy) {
                    expect(Double(region.0.minX))
                        .to(beCloseTo(Double(box.minX), within: 0.001), description: testCase.name)
                    expect(Double(region.0.maxX))
                        .to(beCloseTo(Double(box.maxX), within: 0.001), description: testCase.name)
                }
                expectEveryRunOpensItsOwnLink(string)
            }
        }

        /// 글자 위치로 옮겨진 링크 뒤에 다른 스팬의 폭 0 문자가 흡수돼도 **밴드는 남는다** —
        /// 밴드 소속도 줄 상자 구간과 같은 첫 글자 규칙이다.
        func testShiftedLinkKeepsItsBandWhenAGlyphlessCharacterOfAnotherSpanIsAbsorbed() {
            let string = joined([
                span("LINK", url: "https://first.example",
                     extra: [HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -3)]),
                span("\u{200B}X", url: "https://second.example"),
            ])
            let box = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            ).first?.selectionRect ?? .null
            let bands = regions(string).filter {
                $0.url == "https://first.example" && $0.rect.minY > box.minY + 0.001
            }
            expect(bands.count) == 1
            expect(Double((bands.first?.rect.maxY ?? 0) - box.maxY))
                .to(beCloseTo(3.0, within: 0.001))
        }

        /// **진행 폭이 음수인 run은 트랩 없이 정규화된 rect를 낸다** (PR 리뷰) — 좁은 글리프에
        /// 큰 음수 자간이 걸리면 run 폭이 음수라(Helvetica 10pt `í`(i + U+0301)에 kern −3 →
        /// −0.222pt, HWP 자간 −30%) 역전된 범위로 `ClosedRange`를 만들던 첫 형태는 프로세스를
        /// 종료했다. CT는 단일 글리프 `i`·`.`의 kern은 폭 0으로 클램프하므로(rect 없음, 종전
        /// `maxX > minX` 가드와 같다) 음수는 결합 부호가 붙은 run에서 난다 — 그 rect는 줄 상자
        /// (`selectionRect`, 역시 음수 폭)와 같은 진행 폭 정의의 절대 구간 [시작 + 폭, 시작]이다.
        func testNegativeRunWidthFromLargeNegativeKernDoesNotTrap() {
            let collapsed = tightlyKerned("i\u{0301}")
            let widths = runWidths(collapsed)
            // 정말 음수 폭 run이다 — 아니면 이 테스트가 아무것도 지키지 않는다.
            expect(widths.count) == 1
            expect(widths.first ?? 0).to(beLessThan(0))
            let rects = regions(collapsed).map(\.rect)
            expect(rects.count) == 1
            expect(Double(rects.first?.width ?? -1))
                .to(beCloseTo(-(widths.first ?? 0), within: 0.001))
            expect(Double(rects.first?.maxX ?? -1))
                .to(beCloseTo(Double(Self.origin.x), within: 0.001))

            // 단일 글리프는 CT가 kern을 폭 0으로 클램프한다 — rect가 없고 트랩도 없다.
            for text in ["i", "."] {
                let string = tightlyKerned(text)
                expect(self.runWidths(string).first ?? -1)
                    .to(beCloseTo(0, within: 0.001), description: text)
                expect(self.regions(string)).to(beEmpty(), description: text)
            }
        }

        /// **자간(kern)이 있는 줄의 rect는 줄 상자와 같은 진행 폭 정의다** — 링크가 줄 끝까지
        /// 닿으면 rect 끝 = `selectionRect` 끝(마지막 글자의 kern 포함)이고, 이웃 스팬은 정확히
        /// 잇닿는다. 종전 캐럿 산식은 경계에서 kern/2, 줄 끝에서 kern만큼 달랐다(음수 자간이면
        /// 줄 상자 밖으로 나갔다).
        func testKernedSpansMeetAtRunBoundariesAndEndAtTheLineBox() {
            let kernKey = kCTKernAttributeName as NSAttributedString.Key
            for kern in [2.0, -1.0] {
                let string = joined([
                    span("ab", url: "https://a.example", extra: [kernKey: NSNumber(value: kern)]),
                    span("cd", url: "https://b.example", extra: [kernKey: NSNumber(value: kern)]),
                ])
                let regions = regions(string)
                let first = regions.filter { $0.url == "https://a.example" }.map(\.rect)
                let second = regions.filter { $0.url == "https://b.example" }.map(\.rect)
                let box = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: Self.origin, lineWidth: Self.width
                ).first?.selectionRect ?? .null
                expect(first.count).to(equal(1), description: "kern \(kern)")
                expect(second.count).to(equal(1), description: "kern \(kern)")
                guard let firstRect = first.first, let secondRect = second.first else { continue }
                let label = "kern \(kern)"
                expect(Double(firstRect.maxX))
                    .to(beCloseTo(Double(secondRect.minX), within: 0.001), description: label)
                expect(Double(secondRect.maxX))
                    .to(beCloseTo(Double(box.maxX), within: 0.001), description: label)
                expect(Double(firstRect.minX))
                    .to(beCloseTo(Double(box.minX), within: 0.001), description: label)
            }
        }

        /// **단방향 줄의 rect는 종전 그대로다** — 스팬 양끝 오프셋(min/max)의 상자와 줄마다
        /// 하나씩 0.001pt 안에서 같다. 단일·다중 스팬, 글꼴 폴백, 꼬리 공백, 장평, 줄 넘김.
        func testUnidirectionalSpansKeepTheLegacySpanBox() {
            var condensedMatrix = CGAffineTransform(scaleX: 0.5, y: 1)
            let condensed = CTFontCreateCopyWithAttributes(Self.font, 0, &condensedMatrix, nil)
            struct Case {
                let name: String
                let string: NSAttributedString
                let lineWidth: CGFloat
            }
            let cases = [
                Case(name: "single", string: span("LINK", url: "u"), lineWidth: 200),
                Case(name: "multi", string: joined([
                    span("AAAA ", url: "a"), span("plain "), span("BBBB", url: "b"), span(" "),
                    span("CCCC", url: "c"),
                ]), lineWidth: 300),
                Case(name: "fallback", string: joined([
                    span("홈페이지 바로가기 link", url: "k"), span(" tail"),
                ]), lineWidth: 300),
                Case(name: "trailing ws", string: joined([
                    span("LINK   ", url: "u"), span("x"),
                ]), lineWidth: 200),
                Case(name: "condensed", string: joined([
                    span(String(repeating: "A", count: 20)),
                    span("LINK", url: "c", font: condensed),
                ]), lineWidth: 300),
                Case(name: "wrapped", string: joined([
                    span("AAAAAAAAAA ", url: "a"), span("BBBBBBBBBB BBBB", url: "b"),
                ]), lineWidth: 80),
            ]
            for testCase in cases {
                let name = testCase.name
                let regions = regions(testCase.string, lineWidth: testCase.lineWidth).map(\.rect)
                let legacy = legacySpanBoxes(testCase.string, lineWidth: testCase.lineWidth)
                expect(regions.count).to(equal(legacy.count), description: name)
                for (rect, box) in zip(regions, legacy) {
                    expect(Double(rect.minX))
                        .to(beCloseTo(Double(box.minX), within: 0.001), description: name)
                    expect(Double(rect.maxX))
                        .to(beCloseTo(Double(box.maxX), within: 0.001), description: name)
                    expect(rect.minY).to(equal(box.minY), description: name)
                    expect(rect.height).to(equal(box.height), description: name)
                }
            }
        }

        /// 종전 산식 — 스팬 양끝 인덱스의 `CTLineGetOffsetForStringIndex`를 min/max로 정규화한
        /// 줄 상자 하나 (cc40b23). 단방향 줄에서는 옳은 값이라 회귀 기준으로 쓴다.
        func legacySpanBoxes(
            _ string: NSAttributedString, lineWidth: CGFloat
        ) -> [CGRect] {
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: lineWidth
            )
            var boxes: [CGRect] = []
            string.enumerateAttribute(
                HwpAttributedStringKey.hyperlink, in: NSRange(location: 0, length: string.length)
            ) { value, range, _ in
                guard value is String else { return }
                for drawn in lines {
                    let lower = max(range.location, drawn.stringRange.location)
                    let upper = min(
                        range.location + range.length,
                        drawn.stringRange.location + drawn.stringRange.length
                    )
                    guard upper > lower else { continue }
                    let ctStart = CTLineGetStringRange(drawn.line).location
                    let lowerX = CTLineGetOffsetForStringIndex(
                        drawn.line, ctStart + lower - drawn.stringRange.location, nil
                    )
                    let upperX = CTLineGetOffsetForStringIndex(
                        drawn.line, ctStart + upper - drawn.stringRange.location, nil
                    )
                    guard max(lowerX, upperX) > min(lowerX, upperX) else { continue }
                    boxes.append(CGRect(
                        x: drawn.baselineOrigin.x + min(lowerX, upperX),
                        y: drawn.baselineOrigin.y - drawn.ascent,
                        width: max(lowerX, upperX) - min(lowerX, upperX),
                        height: drawn.ascent + drawn.descent
                    ))
                }
            }
            return boxes
        }

        /// 방출 ≡ 히트: 페이지의 `.hyperlink` 명령과 `HwpHitTester`가 양방향 줄에서 같은 자리에
        /// 같은 URL을 낸다 — 이슈 표의 세 지점(ב·ג 구간, א, abc).
        func testPaintListAndHitTesterAgreeOnBidiLine() {
            let string = joined([
                span("abc \u{05D0}", url: "https://a.example"),
                span("\u{05D1}\u{05D2}", url: "https://b.example"),
            ])
            let frame = CGRect(x: 20, y: 100, width: 300, height: 20)
            let block = AnyHwpBlock(frame: frame, kind: .text, attributedString: string)
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )
            let commands = HwpPaintListBuilder().build(for: page).commands.compactMap { command
                -> (rect: CGRect, url: String)? in
                if case let .hyperlink(rect, url) = command {
                    return (rect: rect, url: url)
                }
                return nil
            }
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: frame.origin, lineWidth: frame.width
            )
            let midY = (lines.first?.baselineOrigin.y ?? 0)
                + ((lines.first?.descent ?? 0) - (lines.first?.ascent ?? 0)) / 2
            for run in inkedRuns(string) {
                // `inkedRuns`는 원점 (0, 100) 기준이라 블록 원점 x만 옮긴다.
                let point = CGPoint(x: run.point.x + frame.minX, y: midY)
                let hit = HwpHitTester().hit(page: page, point: point)
                var hitURL: String?
                if case let .hyperlink(url, _) = hit {
                    hitURL = url
                }
                expect(hitURL).to(equal(run.url), description: "hit \"\(run.text)\"")
                expect(self.hit(commands, point))
                    .to(equal(run.url), description: "paint \"\(run.text)\"")
            }
        }
    }

    private extension HwpHyperlinkRunExtentSemanticsTests {
        /// kern −3(10pt의 −30%)이 걸린 링크 하나.
        func tightlyKerned(_ text: String) -> NSAttributedString {
            joined([span(
                text, url: "https://a.example",
                extra: [kCTKernAttributeName as NSAttributedString.Key: NSNumber(value: -3)]
            )])
        }

        /// 첫 줄 run들의 타이포그래피 폭.
        func runWidths(_ string: NSAttributedString) -> [Double] {
            let line = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            ).first
            let runs = line.flatMap { CTLineGetGlyphRuns($0.line) as? [CTRun] } ?? []
            return runs.map {
                CTRunGetTypographicBounds($0, CFRange(location: 0, length: 0), nil, nil, nil)
            }
        }
    }
#endif
