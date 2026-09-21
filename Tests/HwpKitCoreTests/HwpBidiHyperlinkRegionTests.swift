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
    final class HwpBidiHyperlinkRegionTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        private static let origin = CGPoint(x: 0, y: 100)
        private static let width: CGFloat = 300

        /// 링크 속성과 잉크 중심을 가진 run — 그 자리의 탭이 열어야 하는 URL.
        private struct InkedRun {
            let url: String?
            let text: String
            let point: CGPoint
        }

        private func span(
            _ text: String, url: String? = nil, font: CTFont = HwpBidiHyperlinkRegionTests.font,
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

        private func joined(_ spans: [NSAttributedString]) -> NSAttributedString {
            let string = NSMutableAttributedString()
            spans.forEach { string.append($0) }
            return string
        }

        private func regions(
            _ string: NSAttributedString, lineWidth: CGFloat = width
        ) -> [(rect: CGRect, url: String)] {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: Self.origin, lineWidth: lineWidth
            )
        }

        /// 히트 규칙 그대로 — `regions.first { contains }` (`HwpHitTester`).
        private func hit(_ regions: [(rect: CGRect, url: String)], _ point: CGPoint) -> String? {
            regions.first { $0.rect.contains(point) }?.url
        }

        /// 그려진 줄마다 잉크 있는 run의 (링크, 잉크 중심). 잉크 중심의 y는 줄 상자 가운데다.
        private func inkedRuns(
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
        private func expectEveryRunOpensItsOwnLink(
            _ string: NSAttributedString, lineWidth: CGFloat = width,
            file: FileString = #file, line: UInt = #line
        ) {
            let regions = regions(string, lineWidth: lineWidth)
            let runs = inkedRuns(string, lineWidth: lineWidth)
            expect(file: file, line: line, runs.isEmpty) == false
            for run in runs {
                let opened = expect(file: file, line: line, self.hit(regions, run.point))
                if let url = run.url {
                    opened.to(equal(url), description: "run \"\(run.text)\" at \(run.point)")
                } else {
                    opened.to(beNil(), description: "run \"\(run.text)\" at \(run.point)")
                }
            }
        }

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
            expect(Double(second[0].maxX)).to(beCloseTo(Double(first[0].minX), within: 0.001))
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
        /// 여러 줄에 걸친 양방향 문단의 모든 run이 자기 URL로 열린다.
        func testJustifiedMultiLineBidiParagraphMapsRunsToSpans() {
            var alignment = CTTextAlignment.justified
            let style = withUnsafeMutablePointer(to: &alignment) { pointer in
                CTParagraphStyleCreate([CTParagraphStyleSetting(
                    spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer
                )], 1)
            }
            let paragraph = kCTParagraphStyleAttributeName as NSAttributedString.Key
            let string = joined([
                span("abc abc abc \u{05D0}\u{05D1}\u{05D2} \u{05D3}\u{05D4}\u{05D5} def ",
                     url: "https://a.example", extra: [paragraph: style]),
                span("\u{05D6}\u{05D7} ghi", url: "https://b.example", extra: [paragraph: style]),
                span(" \u{05D8}\u{05D9} end end", url: "https://c.example",
                     extra: [paragraph: style]),
            ])
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: 90
            )
            // 정말 여러 줄이고, 앞 줄은 재조판본(0-기준 CTLine)이다 — 아니면 이 테스트가
            // 아무것도 지키지 않는다.
            expect(lines.count).to(beGreaterThan(1))
            expect(lines.dropLast().contains {
                CTLineGetStringRange($0.line).location == 0 && $0.stringRange.location > 0
            }) == true
            expectEveryRunOpensItsOwnLink(string, lineWidth: 90)
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
        private func legacySpanBoxes(
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

    /// 스팬에 속한 run 범위를 잇닿은 구간으로 합치는 규칙 (`visualSegments`).
    final class HwpHyperlinkVisualSegmentTests: XCTestCase {
        private typealias Extent = HwpDrawnTextLayout.RunExtent

        /// 화면 순서 [A][B][A]: 스팬 A는 구간 둘, 스팬 B는 그 사이 하나.
        func testSplitsAroundAForeignRun() {
            let extents = [
                Extent(range: CFRange(location: 0, length: 4), minX: 0, maxX: 18.9),
                Extent(range: CFRange(location: 5, length: 2), minX: 18.9, maxX: 28.8),
                Extent(range: CFRange(location: 4, length: 1), minX: 28.8, maxX: 35.3),
            ]
            let first = HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 5)
            )
            let second = HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 5, length: 2)
            )

            expect(first) == [0 ... 18.9, 28.8 ... 35.3]
            expect(second) == [18.9 ... 28.8]
        }

        /// 잇닿은 run은 하나로 합치고 (경계 오차 0.001 안), 폭 0 run은 버리며, 스팬에 걸친
        /// run(포함이 아닌 교집합)은 가져가지 않는다.
        func testJoinsAdjacentRunsDropsEmptyOnesAndSkipsStraddlers() {
            let extents = [
                Extent(range: CFRange(location: 0, length: 2), minX: 0, maxX: 10),
                Extent(range: CFRange(location: 2, length: 1), minX: 10.0005, maxX: 10.0005),
                Extent(range: CFRange(location: 3, length: 2), minX: 10.0005, maxX: 20),
                Extent(range: CFRange(location: 5, length: 3), minX: 20, maxX: 30),
            ]
            let segments = HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 6)
            )

            expect(segments) == [0 ... 20]
            expect(HwpDrawnTextLayout.visualSegments(
                of: [extents[1]], in: CFRange(location: 0, length: 6)
            )).to(beEmpty())
        }

        /// 화면 순서가 흐트러진 입력도 x로 정렬해 합친다 — 결과는 순서와 무관하다.
        func testOrderIndependent() {
            let extents = [
                Extent(range: CFRange(location: 2, length: 2), minX: 20, maxX: 30),
                Extent(range: CFRange(location: 0, length: 2), minX: 10, maxX: 20),
            ]
            expect(HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 4)
            )) == [10 ... 30]
        }
    }
#endif
