import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 링크 클릭 영역의 **세로 범위** (#233, `HwpDrawnTextLayout.ClickBand`) — 한글 편집 화면의
    /// 줄 클릭 띠: 줄 상자 상단부터 그 줄의 줄 간격 몫까지(다음 줄 상자 상단까지), 문단 사이
    /// 간격은 어느 줄의 것도 아니고, 목록(표 셀·글상자·각주)의 마지막 줄은 줄 상자에서 끝난다.
    ///
    /// 오라클은 한글 12.30.0(6446) macOS 편집 화면이다 (2026-09-26, 155%, 함초롬바탕 10pt 밑줄
    /// 링크를 한 줄씩 번갈아 왼쪽·오른쪽 칸에 둔 합성 HWPX를 칸마다 위→아래로 눌러 열린 URL을
    /// 읽었다, 경계 ±0.25pt). 베이스라인 기준 거리(아래가 +)로: 10pt 링크와 한 줄인 40pt 문단 끝
    /// 글자·40pt 책갈피 줄의 띠는 −34.0…+30.1(상자 바닥 +6.0에 40pt 몫 여분 24), 40pt 그림 줄은
    /// −34.0…+12.0(여분은 글자 상자 10pt 몫 6), 10pt 줄은 −8.5…+7.5. 입력은 Helvetica로 조판한다 —
    /// 한글 문서의 줄 상자는 글꼴 지표의 함수가 아니다 (`LineBoxFixtures`).
    ///
    /// 종전(CT 줄 지표)에는 40pt 문단 끝 글자·책갈피 줄의 띠가 10pt 글꼴의 ascent·descent에
    /// 머물러 상자 바닥에 붙는 밑줄(#226)과 글자·밑줄 사이 빈칸이 영역 밖이었고, 그림 줄은 위로만
    /// 커졌다 — 아래 세 가드가 모두 실패한다.
    final class HwpHyperlinkClickBandTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private static let url = "https://example.com/link"
        private static let origin = CGPoint(x: 0, y: 100)
        private static let width: CGFloat = 400
        private static let percent160 = HwpLineSpacingRule(kind: .percent, value: 160)

        private static func linkText(
            _ text: String = "LINK", url: String = HwpHyperlinkClickBandTests.url, size: CGFloat = 10
        ) -> NSAttributedString {
            var attributes = Fixtures.attributes(size: size)
            attributes[HwpAttributedStringKey.hyperlink] = url
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            return NSAttributedString(string: text, attributes: attributes)
        }

        private static func concat(_ parts: [NSAttributedString]) -> NSMutableAttributedString {
            let output = NSMutableAttributedString()
            parts.forEach(output.append)
            return output
        }

        /// 한 줄 문단 — 10pt 링크 뒤에 `tail`, 문자열 전체에 160% 줄 간격 (한글 기본값).
        private static func paragraph(
            tail: [NSAttributedString] = [], paragraphEnd: CGFloat? = nil
        ) -> NSAttributedString {
            let output = concat([linkText()] + tail)
            if let paragraphEnd {
                output.addAttribute(
                    HwpAttributedStringKey.paragraphEndBaseFontSize,
                    value: NSNumber(value: Double(paragraphEnd)),
                    range: NSRange(location: 0, length: output.length)
                )
            }
            return Fixtures.applying(percent160, to: output)
        }

        private static func regions(
            _ string: NSAttributedString, width: CGFloat = width
        ) -> [(rect: CGRect, url: String)] {
            HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: origin, lineWidth: width
            )
        }

        private static func hit(_ regions: [(rect: CGRect, url: String)], _ point: CGPoint) -> String? {
            regions.first { $0.rect.contains(point) }?.url
        }

        /// 그려지는 밑줄(글자 아래)의 중심 y — 렌더러와 같은 기준(`underlineReference`)과 기하.
        private static func underlineCenter(of drawn: HwpDrawnLine) -> CGFloat {
            let reference = HwpDrawnTextLayout.underlineReference(
                of: drawn.line, endsParagraph: drawn.endsParagraph
            )
            let line = HwpDecorationLineGeometry.underlineBelow(
                lineBoxHeight: reference.lineBoxHeight, thicknessFontSize: reference.textFontSize
            )
            return drawn.baselineOrigin.y - line.center
        }

        // MARK: 줄 상자가 링크 글자보다 높은 줄 (이슈 표본)

        private struct TallLine {
            let name: String
            let string: NSAttributedString
            /// 베이스라인에서 띠 하단까지 (한글 실측)
            let bandBottom: CGFloat
        }

        private static var tallLines: [TallLine] {
            [
                TallLine(name: "40pt 문단 끝 글자", string: paragraph(paragraphEnd: 40), bandBottom: 30),
                TallLine(name: "40pt 책갈피", string: paragraph(tail: [
                    Fixtures.objectMarker(height: 0, attributes: Fixtures.attributes(size: 40)),
                ]), bandBottom: 30),
                TallLine(name: "높이 40pt 그림", string: paragraph(tail: [
                    Fixtures.objectMarker(height: 40, attributes: Fixtures.attributes(size: 10)),
                ]), bandBottom: 12),
            ]
        }

        /// **밑줄과 글자·밑줄 사이 빈칸을 누르면 링크가 열린다** — 이슈의 세 표본. 띠는 40pt 줄
        /// 상자 상단(베이스라인 −34)부터 그 줄의 줄 간격 몫까지다.
        func testUnderlineAndGapBelowTheLinkTextOpenTheLink() {
            for tall in Self.tallLines {
                let name = tall.name
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: tall.string, origin: Self.origin, lineWidth: Self.width
                )
                expect(drawn.count).to(equal(1), description: name)
                guard let line = drawn.first else { continue }
                let regions = Self.regions(tall.string)
                expect(regions.count).to(equal(1), description: name)
                let x = regions.first?.rect.midX ?? 0
                let baseline = line.baselineOrigin.y
                // 밑줄은 40pt 상자 바닥(베이스라인 +6.0)에 위 가장자리를 둔다 (#226).
                let underline = Self.underlineCenter(of: line)
                expect(Double(underline - baseline)).to(beCloseTo(6.2, within: 0.05), description: name)
                expect(Self.hit(regions, CGPoint(x: x, y: underline))).to(equal(Self.url), description: name)
                // 글자(10pt, 잉크 바닥 ≈ +2.3)와 밑줄 사이 빈칸 — 한글 실측 +3.4·+3.8에서 열렸다.
                expect(Self.hit(regions, CGPoint(x: x, y: baseline + 4))).to(equal(Self.url), description: name)
                // 띠 경계: 위는 40pt 상자 상단, 아래는 줄 간격 몫 끝.
                let rect = regions.first?.rect ?? .null
                expect(Double(rect.minY - baseline)).to(beCloseTo(-34, within: 0.001), description: name)
                expect(Double(rect.maxY - baseline))
                    .to(beCloseTo(Double(tall.bandBottom), within: 0.001), description: name)
            }
        }

        /// 블록 히트로도 같다 — 띠는 블록 프레임(문단 높이 = 줄 전진량 합) 안이라 다음 블록의
        /// 프레임에 가려지지 않고, 다음 블록 첫 줄 상자부터는 그 블록 몫이다.
        func testHitTesterOpensTheLinkOnTheUnderlineAndStopsAtTheNextBlock() {
            let string = Self.paragraph(paragraphEnd: 40)
            // 40pt 상자 + 160% 여분 24 = 64 (한글 캐시: vertsize 4000·spacing 2400)
            let linkBlock = AnyHwpBlock(
                frame: CGRect(x: Self.origin.x, y: Self.origin.y, width: Self.width, height: 64),
                kind: .text, attributedString: string
            )
            let nextBlock = AnyHwpBlock(
                frame: CGRect(x: Self.origin.x, y: Self.origin.y + 64, width: Self.width, height: 16),
                kind: .text,
                attributedString: Fixtures.applying(Self.percent160, to: NSAttributedString(
                    string: "plain text", attributes: Fixtures.attributes(size: 10)
                ))
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [linkBlock, nextBlock], pageNumber: 1
            )
            let line = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            )[0]
            let x = Self.regions(string).first?.rect.midX ?? 0
            let tester = HwpHitTester()
            expect(tester.hit(page: page, point: CGPoint(x: x, y: Self.underlineCenter(of: line))))
                == .hyperlink(url: Self.url, blockIndex: 0)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: Self.origin.y + 63.5)))
                == .hyperlink(url: Self.url, blockIndex: 0)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: Self.origin.y + 64.5)))
                == .text(blockIndex: 1, characterIndex: nil)
        }

        // MARK: 줄과 줄 사이 · 문단 사이

        /// 줄과 줄의 경계는 **다음 줄 상자 상단**이다 — 앞 줄 띠가 줄 간격 몫까지 차지하고 뒤 줄
        /// 띠는 자기 상자 상단부터다 (한글: 10pt 160% 줄은 상자 바닥 +6.0, 한 줄 끝 앞뒤도 같다).
        func testLinesTileAtTheNextLineBoxTop() {
            let text = Fixtures.attributes(size: 10)
            let string = Fixtures.applying(Self.percent160, to: Self.concat([
                Self.linkText("FIRST", url: "https://first.example"),
                Fixtures.lineBreak(attributes: text),
                Self.linkText("SECOND", url: "https://second.example"),
            ]))
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            )
            expect(lines.count) == 2
            guard lines.count == 2 else { return }
            let regions = Self.regions(string)
            let secondTop = lines[1].baselineOrigin.y - 8.5
            // 첫 줄 상자 상단 100 + 전진량 16 = 둘째 줄 상자 상단
            expect(Double(secondTop)).to(beCloseTo(116, within: 0.001))
            let x = min(
                regions.first { $0.url == "https://first.example" }?.rect.midX ?? 0,
                regions.first { $0.url == "https://second.example" }?.rect.midX ?? 0
            )
            expect(Self.hit(regions, CGPoint(x: x, y: secondTop - 0.1))) == "https://first.example"
            expect(Self.hit(regions, CGPoint(x: x, y: secondTop + 0.1))) == "https://second.example"
            // 첫 줄 밑줄(상자 바닥 +0.2)은 첫 줄 몫
            expect(Self.hit(regions, CGPoint(x: x, y: Self.underlineCenter(of: lines[0]))))
                == "https://first.example"
        }

        /// **문단 사이 간격은 어느 링크도 아니다** — 결합 문자열의 두 문단 사이 24pt 띠(앞 문단
        /// 아래 간격)를 누르면 위·아래 링크 모두 안 열린다 (한글: 문단 아래·위 간격 24pt 띠 전체).
        func testParagraphSpacingBetweenParagraphsIsNotClickable() {
            let style = Fixtures.paragraphStyle(specs: [(.paragraphSpacing, 24)])
            let string = Fixtures.applying(Self.percent160, style: style, to: Self.concat([
                Self.linkText("FIRST", url: "https://first.example"),
                NSAttributedString(string: "\n", attributes: Fixtures.attributes(size: 10)),
                Self.linkText("SECOND", url: "https://second.example"),
            ]))
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            )
            expect(lines.count) == 2
            guard lines.count == 2 else { return }
            let regions = Self.regions(string)
            let x = regions.first?.rect.midX ?? 0
            let firstBandBottom = Self.origin.y + 16
            let secondTop = lines[1].baselineOrigin.y - 8.5
            // 두 줄 사이는 줄 간격 몫 6 + 문단 간격 24
            expect(Double(secondTop - Self.origin.y)).to(beCloseTo(40, within: 0.001))
            expect(Self.hit(regions, CGPoint(x: x, y: firstBandBottom - 0.1))) == "https://first.example"
            for y in stride(from: firstBandBottom + 0.1, to: secondTop, by: 4) {
                expect(Self.hit(regions, CGPoint(x: x, y: y))).to(beNil(), description: "y \(y)")
            }
            expect(Self.hit(regions, CGPoint(x: x, y: secondTop + 0.1))) == "https://second.example"
        }

        /// 띠는 줄 상자가 아니라 **줄 전진량**을 따른다 — 고정 8pt(상자 10pt)면 앞 줄 상자 아래
        /// 2pt는 다음 줄 몫이고(한글 실측), 100%면 경계가 상자 바닥이라 밑줄은 다음 줄 몫이다.
        func testBandFollowsTheLineAdvanceNotTheBox() {
            let cases: [(rule: HwpLineSpacingRule, advance: CGFloat)] = [
                (HwpLineSpacingRule(kind: .fixed, value: 8), 8),
                (HwpLineSpacingRule(kind: .percent, value: 100), 10),
            ]
            for (rule, advance) in cases {
                let name = "\(rule.kind) \(rule.value)"
                let text = Fixtures.attributes(size: 10)
                let string = Fixtures.applying(rule, to: Self.concat([
                    Self.linkText("FIRST", url: "https://first.example"),
                    Fixtures.lineBreak(attributes: text),
                    Self.linkText("SECOND", url: "https://second.example"),
                ]))
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: Self.origin, lineWidth: Self.width
                )
                let regions = Self.regions(string)
                let first = regions.first { $0.url == "https://first.example" }?.rect ?? .null
                expect(Double(first.height)).to(beCloseTo(Double(advance), within: 0.001), description: name)
                let x = first.midX
                let boundary = Self.origin.y + advance
                expect(Self.hit(regions, CGPoint(x: x, y: boundary - 0.1)))
                    .to(equal("https://first.example"), description: name)
                expect(Self.hit(regions, CGPoint(x: x, y: boundary + 0.1)))
                    .to(equal("https://second.example"), description: name)
                // 첫 줄 밑줄은 상자 바닥(+10) 아래라 다음 줄 몫이다.
                expect(Self.hit(regions, CGPoint(x: x, y: Self.underlineCenter(of: lines[0]))))
                    .to(equal("https://second.example"), description: name)
            }
        }

        // MARK: 목록 끝

        /// **목록의 마지막 줄은 줄 상자에서 끝난다** — 한글은 표 셀·글상자·각주의 마지막 줄
        /// 아래(밑줄 포함)를 눌러도 링크를 열지 않는다 (셀 높이 100pt로 아래가 비어 있어도).
        /// 목록 끝이 아니면 같은 줄이 줄 간격 몫까지 열린다.
        func testListEndStopsTheLastLineAtItsBox() {
            let string = Self.paragraph(paragraphEnd: 40)
            let listed = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: string, origin: Self.origin, lineWidth: Self.width,
                endsList: true
            )
            let open = Self.regions(string)
            let baseline = Self.origin.y + 34
            expect(listed.count) == 1
            expect(Double((listed.first?.rect.maxY ?? 0) - baseline)).to(beCloseTo(6, within: 0.001))
            expect(Double((open.first?.rect.maxY ?? 0) - baseline)).to(beCloseTo(30, within: 0.001))
            // 목록 끝이 아닌 앞 줄은 그대로 줄 간격 몫까지다.
            let text = Fixtures.attributes(size: 10)
            let twoLines = Fixtures.applying(Self.percent160, to: Self.concat([
                Self.linkText("FIRST", url: "https://first.example"),
                Fixtures.lineBreak(attributes: text),
                Self.linkText("SECOND", url: "https://second.example"),
            ]))
            let rects = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: twoLines, origin: Self.origin, lineWidth: Self.width,
                endsList: true
            ).map(\.rect)
            expect(rects.map { Double($0.height) }) == [16, 10]
        }

        /// 표 셀의 마지막 문단은 목록 끝이다 — 셀 안 앞 문단의 밑줄은 열리고 마지막 문단의 밑줄은
        /// 안 열린다. 방출(`.hyperlink` 명령)도 같은 rect다 (방출 ≡ 히트).
        func testTableCellLastParagraphIsTheListEnd() {
            let first = Self.paragraph()
            let last = Fixtures.applying(Self.percent160, to: Self.linkText(url: "https://last.example"))
            let paragraphs = [
                HwpLaidOutParagraph(
                    attributedString: first, frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                    rect: CGRect(x: 10, y: 10, width: 300, height: 16), paragraphId: 1
                ),
                HwpLaidOutParagraph(
                    attributedString: last, frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                    rect: CGRect(x: 10, y: 26, width: 300, height: 16), paragraphId: 2
                ),
            ]
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellFrame = CGRect(x: 0, y: 0, width: 320, height: 100)
            let cell = HwpTableCellFrame(
                cellFrame: cellFrame, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: paragraphs, borders: HwpBorderSet.uniform(width: 0.5, color: black),
                fillColor: nil
            )
            let table = HwpTableFrame(
                outerFrame: cellFrame,
                rows: [HwpTableRowFrame(rowFrame: cellFrame, cells: [cell])],
                borderColor: black, borderWidth: 0.5
            )
            let block = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 320, height: 100), kind: .table,
                payload: .table(table)
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block], pageNumber: 1
            )
            let tester = HwpHitTester()
            let x: CGFloat = 50 + 10 + 5
            // 앞 문단: 상자 110…120, 띠는 줄 간격 몫까지 126 — 밑줄(120.2)이 열린다.
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 120.2)))
                == .hyperlink(url: Self.url, blockIndex: 0)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 125.9)))
                == .hyperlink(url: Self.url, blockIndex: 0)
            // 마지막 문단: 상자 126…136에서 끝난다 — 밑줄(136.2) 아래는 셀이다.
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 135.9)))
                == .hyperlink(url: "https://last.example", blockIndex: 0)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 136.2)))
                == .table(blockIndex: 0, row: 0, col: 0)
            // 방출도 같은 rect다.
            let emitted = HwpPaintListBuilder().build(for: page).commands.compactMap { command in
                if case let .hyperlink(rect, url) = command {
                    return (rect, url)
                }
                return nil
            }
            let lastRects = emitted.filter { $0.1 == "https://last.example" }.map(\.0)
            expect(lastRects.count) == 1
            expect(Double(lastRects.first?.maxY ?? 0)).to(beCloseTo(136, within: 0.001))
            let firstRects = emitted.filter { $0.1 == Self.url }.map(\.0)
            expect(Double(firstRects.first?.maxY ?? 0)).to(beCloseTo(126, within: 0.001))
        }

        /// 각주는 **문단마다 블록 하나**라 배열 인덱스로는 목록 끝을 못 가린다 — 같은 각주의 앞
        /// 문단(`isNoteEnd == false`)은 줄 간격 몫까지, 마지막 문단만 줄 상자에서 끝난다 (한글:
        /// 두 문단 각주의 둘째 문단·한 문단 각주의 밑줄 아래는 안 열렸다). 방출도 같은 rect다.
        func testFootnoteParagraphEndsTheListOnlyAtTheNoteEnd() {
            func paragraph(_ url: String) -> HwpLaidOutParagraph {
                HwpLaidOutParagraph(
                    attributedString: Fixtures.applying(
                        Self.percent160, to: Self.linkText(url: url)
                    ),
                    frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 300, height: 16), paragraphId: 1
                )
            }
            let separator = CGRect(x: 50, y: 690, width: 100, height: 1)
            // 앞 문단 블록은 줄 간격까지 16, 각주 끝 블록은 줄 상자 10 (`stackingHeight`).
            let first = HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 700, width: 300, height: 16),
                paragraphs: [paragraph("https://first.example")], number: 1,
                separatorLine: separator, isNoteEnd: false
            )
            let last = HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 716, width: 300, height: 10),
                paragraphs: [paragraph("https://last.example")], number: 1,
                separatorLine: separator
            )
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(frame: first.frame, kind: .footnote, payload: .footnote(first)),
                    AnyHwpBlock(frame: last.frame, kind: .footnote, payload: .footnote(last)),
                ],
                pageNumber: 1
            )
            let tester = HwpHitTester()
            let x: CGFloat = 55
            // 앞 문단: 밑줄(710.2)과 줄 간격 몫(…716)이 열린다.
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 710.2)))
                == .hyperlink(url: "https://first.example", blockIndex: 0)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 715.9)))
                == .hyperlink(url: "https://first.example", blockIndex: 0)
            // 각주 끝: 줄 상자(716…726) 안은 열리고 밑줄(726.2)은 아니다.
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 725.9)))
                == .hyperlink(url: "https://last.example", blockIndex: 1)
            expect(tester.hit(page: page, point: CGPoint(x: x, y: 726.2)))
                != .hyperlink(url: "https://last.example", blockIndex: 1)
            let emitted = HwpPaintListBuilder().build(for: page).commands.compactMap { command in
                if case let .hyperlink(rect, url) = command {
                    return (rect.maxY, url)
                }
                return nil
            }
            expect(emitted.map { Double($0.0) }) == [716, 726]
        }

        // MARK: 표식 없는 문자열

        /// 글꼴 속성도 기본 크기 표식도 없는 문자열(공개 `drawText` 호출자)은 CT가 run에 기본
        /// 글꼴(Helvetica 12)을 달아 주므로 그 크기의 줄 상자가 띠다 — 규칙 표식이 없어 비율
        /// 100%라 상자 그대로다 (종전 CT 지표는 [−9.24, +2.76]).
        func testStringWithoutHwpAttributesUsesTheFontSizeBox() {
            let string = NSAttributedString(
                string: "linked", attributes: [HwpAttributedStringKey.hyperlink: Self.url]
            )
            let line = HwpDrawnTextLayout.lines(
                attributedString: string, origin: Self.origin, lineWidth: Self.width
            )[0]
            let rect = Self.regions(string).first?.rect ?? .null
            expect(Double(line.baselineOrigin.y - Self.origin.y)).to(beCloseTo(10.2, within: 0.001))
            expect(Double(rect.minY)).to(beCloseTo(Double(Self.origin.y), within: 0.001))
            expect(Double(rect.height)).to(beCloseTo(12, within: 0.001))
        }
    }
#endif
