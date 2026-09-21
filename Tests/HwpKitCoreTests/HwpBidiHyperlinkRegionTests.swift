import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// **양방향 줄의 링크 스팬은 화면에서 잇닿은 구간마다 rect를 낸다** (#201).
    ///
    /// 종전에는 스팬 양끝의 `CTLineGetOffsetForStringIndex`를 min/max로 정규화한 상자
    /// 하나였다 — 논리 순서와 화면 순서가 다른 줄에서는 그 상자가 다른 링크의 글자를 덮고
    /// 자기 글자를 빠뜨린다 (실측 `abc אבג`에 `abc א`·`בג` 두 링크, Helvetica 10pt: 앞 스팬
    /// 상자 0…28.804가 뒤 스팬 글자 18.901…28.804를 덮고, 앞 스팬 자기 글자 א 28.804…35.254는
    /// 어느 영역에도 없다). 방향 경계 인덱스의 오프셋이 반대쪽 run의 가장자리를 가리키는
    /// 탓이라 스팬 하나로 전체를 걸어도 히브리 글자 셋이 통째로 빠졌다.
    ///
    /// 오라클은 **run의 잉크**다 — `CTRunGetImageBounds`는 시각 좌표라 논리 순서와 무관하고,
    /// 그 run의 링크 속성이 곧 그 자리를 눌렀을 때 열려야 하는 URL이다.
    class HwpBidiHyperlinkRegionTestCase: XCTestCase {
        static let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        static let origin = CGPoint(x: 0, y: 100)
        static let width: CGFloat = 300

        /// 링크 속성과 잉크 중심을 가진 run — 그 자리의 탭이 열어야 하는 URL.
        struct InkedRun {
            let url: String?
            let text: String
            let point: CGPoint
        }

        func span(
            _ text: String, url: String? = nil, font: CTFont = HwpBidiHyperlinkRegionTestCase.font,
            extra: [NSAttributedString.Key: Any] = [:]
        ) -> NSAttributedString {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ]
            if let url {
                attributes[HwpAttributedStringKey.hyperlink] = url
            }
            for (key, value) in extra {
                attributes[key] = value
            }
            return NSAttributedString(string: text, attributes: attributes)
        }

        func joined(_ spans: [NSAttributedString]) -> NSAttributedString {
            let string = NSMutableAttributedString()
            spans.forEach { string.append($0) }
            return string
        }

        func regions(
            _ string: NSAttributedString, lineWidth: CGFloat = width
        ) -> [(rect: CGRect, url: String)] {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: Self.origin, lineWidth: lineWidth
            )
        }

        /// 히트 규칙 그대로 — `regions.first { contains }` (`HwpHitTester`).
        func hit(_ regions: [(rect: CGRect, url: String)], _ point: CGPoint) -> String? {
            regions.first { $0.rect.contains(point) }?.url
        }

        /// 그려진 줄마다 잉크 있는 run의 (링크, 잉크 중심). 잉크 중심의 y는 줄 상자 가운데다.
        func inkedRuns(
            _ string: NSAttributedString, lineWidth: CGFloat = width
        ) -> [InkedRun] {
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: lineWidth
            )
            var result: [InkedRun] = []
            for drawn in lines {
                guard let runs = CTLineGetGlyphRuns(drawn.line) as? [CTRun] else { continue }
                let midY = drawn.baselineOrigin.y + (drawn.descent - drawn.ascent) / 2
                for run in runs {
                    let ink = CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0))
                    guard !ink.isNull, ink.width > 0 else { continue }
                    let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                    // 재조판된 줄은 0-기준 부분 복사본이라 단위 문자열 인덱스로 되돌린다.
                    let range = CTRunGetStringRange(run)
                    let ctRange = CTLineGetStringRange(drawn.line)
                    let unitLocation =
                        drawn.stringRange.location + (range.location - ctRange.location)
                    result.append(InkedRun(
                        url: attributes?[HwpAttributedStringKey.hyperlink] as? String,
                        text: (string.string as NSString).substring(
                            with: NSRange(location: unitLocation, length: range.length)
                        ),
                        point: CGPoint(x: drawn.baselineOrigin.x + ink.midX, y: midY)
                    ))
                }
            }
            return result
        }

        /// 모든 run의 잉크 중심이 자기 URL로 열린다 — 링크 없는 run은 어느 영역에도 안 든다.
        func expectEveryRunOpensItsOwnLink(
            _ string: NSAttributedString, lineWidth: CGFloat = width,
            file: FileString = #file, line: UInt = #line
        ) {
            let regions = regions(string, lineWidth: lineWidth)
            let runs = inkedRuns(string, lineWidth: lineWidth)
            // 링크 run이 하나도 안 잡히면(속성 브리징 실패) 아래 루프가 공허해진다.
            expect(file: file, line: line, runs.contains { $0.url != nil }) == true
            for run in runs {
                let opened = expect(file: file, line: line, self.hit(regions, run.point))
                if let url = run.url {
                    opened.to(equal(url), description: "run \"\(run.text)\" at \(run.point)")
                } else {
                    opened.to(beNil(), description: "run \"\(run.text)\" at \(run.point)")
                }
            }
        }
    }

    /// 양방향 줄 — 이슈의 재현 문자열과 그 변주. 오라클은 run의 잉크다 (기반 클래스 주석).
    final class HwpBidiHyperlinkRegionTests: HwpBidiHyperlinkRegionTestCase {
        /// `abc א`(A) + `בג`(B): 이슈의 재현 문자열. A는 화면에서 떨어진 두 구간이라 rect
        /// 둘, B는 그 사이 하나 — 어느 글자를 눌러도 자기 URL이다.
        func testEachRunOnBidiLineOpensItsOwnLink() {
            let string = joined([
                span("abc \u{05D0}", url: "https://a.example"),
                span("\u{05D1}\u{05D2}", url: "https://b.example"),
            ])
            expectEveryRunOpensItsOwnLink(string)

            let regions = regions(string)
            let first = regions.filter { $0.url == "https://a.example" }.map(\.rect)
            let second = regions.filter { $0.url == "https://b.example" }.map(\.rect)
            expect(first.count) == 2
            expect(second.count) == 1
            // 회귀하면 단언 실패로 끝나야지 첨자 트랩으로 번들을 죽이면 안 된다.
            guard first.count == 2, second.count == 1 else { return }
            // A의 두 구간 사이에 B가 끼어 있다 — 셋이 서로 겹치지 않고 잇닿는다.
            let ordered = (first + second).sorted { $0.minX < $1.minX }
            expect(ordered.map(\.minX)) == [first[0].minX, second[0].minX, first[1].minX]
            expect(Double(ordered[0].maxX)).to(beCloseTo(Double(ordered[1].minX), within: 0.001))
            expect(Double(ordered[1].maxX)).to(beCloseTo(Double(ordered[2].minX), within: 0.001))
        }

        /// 스팬 하나가 양방향 줄 전체를 걸면 rect는 하나고 **히브리 글자도 든다** — 종전에는
        /// 스팬 끝 인덱스의 오프셋이 방향 경계에서 왼쪽 값을 줘 `abc ` 폭에서 끝났다.
        func testSingleSpanOverBidiLineCoversEveryGlyph() {
            let string = span("abc \u{05D0}\u{05D1}\u{05D2}", url: "https://all.example")
            expectEveryRunOpensItsOwnLink(string)

            let rects = regions(string).map(\.rect)
            let line = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            ).first
            expect(rects.count) == 1
            expect(Double(rects.first?.width ?? 0))
                .to(beCloseTo(Double(line?.selectionRect.width ?? -1), within: 0.001))
        }

        /// 아랍 문자는 이어 쓰기(shaping)로 run이 갈리고 두 스팬이 서로 끼어든다 —
        /// `x مر`(P)·`حبا y`(Q)는 화면에서 P·Q·P·Q 네 구간이다.
        func testShapedArabicRunsOpenTheirOwnLinks() {
            let string = joined([
                span("x \u{0645}\u{0631}", url: "https://p.example"),
                span("\u{062D}\u{0628}\u{0627} y", url: "https://q.example"),
            ])
            expectEveryRunOpensItsOwnLink(string)

            let regions = regions(string)
            expect(regions.filter { $0.url == "https://p.example" }.count) == 2
            expect(regions.filter { $0.url == "https://q.example" }.count) == 2
        }

        /// 순수 RTL 줄의 두 스팬은 각각 rect 하나이고 서로 잇닿는다 — 앞 스팬이 오른쪽이다.
        func testPureRTLSpansStayOneRectEach() {
            let string = joined([
                span("\u{05E9}\u{05DC}\u{05D5}\u{05DD}", url: "https://a.example"),
                span(" \u{05E2}\u{05D5}\u{05DC}\u{05DD}", url: "https://b.example"),
            ])
            expectEveryRunOpensItsOwnLink(string)

            let regions = regions(string)
            let first = regions.filter { $0.url == "https://a.example" }.map(\.rect)
            let second = regions.filter { $0.url == "https://b.example" }.map(\.rect)
            expect(first.count) == 1
            expect(second.count) == 1
            guard let firstRect = first.first, let secondRect = second.first else { return }
            expect(Double(secondRect.maxX)).to(beCloseTo(Double(firstRect.minX), within: 0.001))
        }

        /// 링크 없는 run이 끼어도 그 자리는 어느 링크도 아니다 — 양방향 줄에서 링크 밖
        /// 히브리 낱말이 앞뒤 링크 상자에 덮이지 않는다.
        func testUnlinkedRunBetweenBidiLinksOpensNothing() {
            let string = joined([
                span("abc \u{05D0}", url: "https://a.example"),
                span("\u{05D1}\u{05D2} "),
                span("\u{05D3}\u{05D4}", url: "https://b.example"),
                span(" xyz"),
            ])
            expectEveryRunOpensItsOwnLink(string)
        }

        /// 양쪽 정렬로 재조판된 줄(0-기준 부분 복사본)에서도 run 범위를 스팬에 바르게 댄다 —
        /// 둘째 줄이 재조판본이고 그 줄에서 A가 두 구간으로 갈린다 (종전 산식은 줄마다 rect
        /// 하나뿐이라 여기서 실패한다).
        func testJustifiedRetypesetLineSplitsBidiSpan() {
            let paragraph = kCTParagraphStyleAttributeName as NSAttributedString.Key
            let style = Self.justifiedStyle()
            let string = joined([
                span("aaaa bbbb cccc ", extra: [paragraph: style]),
                span("abc \u{05D0}", url: "https://a.example", extra: [paragraph: style]),
                span("\u{05D1}\u{05D2}", url: "https://b.example", extra: [paragraph: style]),
                span(" ghi jkl mno pqr stu vwx", url: "https://c.example",
                     extra: [paragraph: style]),
            ])
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: 80
            )
            // 둘째 줄이 정말 재조판본(0-기준 CTLine)이고 양방향 줄이다 — 아니면 이 테스트가
            // 아무것도 지키지 않는다.
            expect(lines.count) == 3
            guard lines.count == 3 else { return }
            let second = lines[1]
            expect(CTLineGetStringRange(second.line).location) == 0
            expect(second.stringRange.location).to(beGreaterThan(0))
            let regions = regions(string, lineWidth: 80)
            let onSecond = regions.filter {
                abs($0.rect.minY - (second.baselineOrigin.y - second.ascent)) < 0.001
            }
            expect(onSecond.filter { $0.url == "https://a.example" }.count) == 2
            expect(onSecond.filter { $0.url == "https://b.example" }.count) == 1
            expectEveryRunOpensItsOwnLink(string, lineWidth: 80)
        }

        static func justifiedStyle() -> CTParagraphStyle {
            var alignment = CTTextAlignment.justified
            return withUnsafeMutablePointer(to: &alignment) { pointer in
                CTParagraphStyleCreate([CTParagraphStyleSetting(
                    spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer
                )], 1)
            }
        }
    }
#endif
