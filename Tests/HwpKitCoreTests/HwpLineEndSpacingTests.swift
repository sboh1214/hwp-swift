import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 줄의 마지막 글자는 자간을 받지 않는다 (#260) — 한글은 줄 맞춤·오른쪽·가운데·양쪽 정렬을 모두
    /// 마지막 내용 글자를 자간 없는 전진량으로 잰다. 양수 자간(tracking)은 CoreText가 줄 끝에서 매달리는
    /// 공백처럼 빼고 재므로 그대로 같고, 음수(Menlo는 커닝 집합을 모르는 글꼴이라 tracking — kern이어도
    /// 같다)는 `HwpLineBreaker`(줄 맞춤·정렬)와
    /// `HwpWordJustification`(양쪽 정렬)이 뺀다. 결정론 resolver(Menlo, 12pt 글자 모양 헬퍼)로 짠다.
    extension HwpTextRunBuilderTests {
        private enum Alignment: UInt32 {
            case justify = 0
            case left = 1
            case right = 2
        }

        /// Menlo 12pt 라틴 자간 `spacing`%, 정렬 `alignment`의 `text` 조판 문자열.
        private func spacedParagraph(
            _ text: String, spacing: Int8, alignment: Alignment, marginLeft: Int32 = 0
        ) throws -> NSAttributedString {
            let shapes = [UInt32(0): try charShape(faceSpacing: [0, spacing, 0, 0, 0, 0, 0])]
            let documentIndex = HwpIndex(
                charShapes: shapes,
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: alignment.rawValue << 2, marginLeft: marginLeft, tabDefId: 0
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            return HwpTextRunBuilder(index: documentIndex, fontResolver: .testDeterministic)
                .build(paragraph: paragraph(text: text, runs: [(0, 0)]))
        }

        /// Menlo 12pt `a`의 전진량.
        private var menloA: CGFloat {
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil)
            var character: UniChar = 0x61
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width
        }

        /// `aaaaa` × `count` (빈칸 = 고정 폭 6pt × (1 + 자간))의 첫 `words`단어 폭 — 마지막 글자
        /// 자간을 넣고 잰 값과 뺀 값.
        private func widths(words: Int, ratio: CGFloat) -> (full: CGFloat, lineEnd: CGFloat) {
            let glyph = menloA * (1 + ratio)
            let full = CGFloat(words * 5) * glyph + CGFloat(words - 1) * 6 * (1 + ratio)
            return (full, full - menloA * ratio)
        }

        private func firstLineGlyphCount(_ attributed: NSAttributedString, width: CGFloat) -> Int {
            let lines = HwpDrawnTextLayout.lines(attributedString: attributed, origin: .zero, lineWidth: width)
            let string = attributed.string as NSString
            let range = lines[0].stringRange
            return (0 ..< range.length).filter { string.character(at: range.location + $0) == 0x61 }.count
        }

        /// 문자열 위치 `index`의 글리프가 그려지는 x (장평 행렬 포함).
        private static func glyphOrigin(of index: Int, in line: HwpDrawnLine) -> CGFloat? {
            for run in CTLineGetGlyphRuns(line.line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                for (position, stringIndex) in zip(positions, indices) where stringIndex == index {
                    return line.baselineOrigin.x + position.applying(CTRunGetTextMatrix(run)).x
                }
            }
            return nil
        }

        func testNegativeSpacingLineBreaksWithoutTheLastCharacterSpacing() throws {
            // 라틴 −20%, 7단어가 자간을 넣고 재면 들어가고 빼고 재면 넘치는 폭 — 한글처럼 6단어.
            let text = Array(repeating: "aaaaa", count: 8).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .left)
            let seven = widths(words: 7, ratio: -0.2)
            expect(seven.full) < seven.lineEnd
            let width = (seven.full + seven.lineEnd) / 2
            expect(self.firstLineGlyphCount(attributed, width: width)) == 30
            // 대조군: 빼고 재도 들어가는 폭이면 7단어다.
            expect(self.firstLineGlyphCount(attributed, width: seven.lineEnd + 0.01)) == 35
        }

        func testPositiveSpacingLineFitsWithoutTheLastCharacterSpacing() throws {
            // 라틴 +20%, 5단어가 자간을 빼고 재면 들어가는 폭 — CoreText가 줄 끝 양수 tracking을 매달아
            // 그대로 5단어 (한글과 같다).
            let text = Array(repeating: "aaaaa", count: 6).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: 20, alignment: .left)
            let five = widths(words: 5, ratio: 0.2)
            let width = (five.full + five.lineEnd) / 2
            expect(self.firstLineGlyphCount(attributed, width: width)) == 25
        }

        func testRefittedParagraphStaysOneChunkForMeasurementAndRender() throws {
            // 다시 나눈 줄도 청크 하나로 잇는다 — 측정·렌더가 같은 줄 범위를 보고, 공유 코어 한 번의
            // 호출이 문단을 덮는다 (`HwpLayoutRenderParitySweepTests`의 3-way 전제).
            let text = Array(repeating: "aaaaa", count: 20).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .left)
            let seven = widths(words: 7, ratio: -0.2)
            let width = (seven.full + seven.lineEnd) / 2
            let chunk = try XCTUnwrap(HwpLineBreaker.nextFrameChunk(
                framesetter: CTFramesetterCreateWithAttributedString(attributed),
                typesetter: CTTypesetterCreateWithAttributedString(attributed),
                attributedString: attributed, startLocation: 0, fullLength: attributed.length,
                remainingLineBudget: HwpParagraphLayout.maximumLineFrames, lineWidth: width
            ))
            expect(chunk.nextStart) == attributed.length
            let drawn = HwpDrawnTextLayout.lines(attributedString: attributed, origin: .zero, lineWidth: width)
            let measured = HwpParagraphLayout().layout(
                attributedString: attributed,
                paraShape: CoreHwp.HwpParaShape(property1: 1 << 2, marginLeft: 0, tabDefId: 0),
                columnWidth: width
            )
            let coreRanges = chunk.lines.prefix(chunk.keepCount).map { line -> NSRange in
                let range = CTLineGetStringRange(line)
                return NSRange(location: range.location, length: range.length)
            }
            expect(drawn.map(\.stringRange)) == coreRanges
            expect(measured.lines.map(\.attributedRange)) == coreRanges
            // 줄마다 6단어 — 7단어째는 마지막 글자 자간을 빼면 넘친다.
            expect(coreRanges.dropLast().allSatisfy { $0.length == 36 }) == true
        }

        func testRightAlignedLineEndsWithTheUnspacedAdvance() throws {
            // 오른쪽 정렬: 마지막 글자가 오른쪽 끝 − 자간 없는 전진량에 놓인다 (한글 실측: Menlo 20pt
            // 라틴 ±20%에서 둘 다 오른쪽 끝 − 12.00pt).
            for spacing: Int8 in [-20, 20] {
                let attributed = try spacedParagraph("abcd", spacing: spacing, alignment: .right)
                let line = try XCTUnwrap(
                    HwpDrawnTextLayout.lines(attributedString: attributed, origin: .zero, lineWidth: 200).first
                )
                let dOrigin = try XCTUnwrap(Self.glyphOrigin(of: 3, in: line))
                expect(dOrigin + self.menloA).to(beCloseTo(200, within: 0.01), description: "\(spacing)%")
            }
        }

        func testJustifiedLineEndsAtTheMarginWithoutTheLastCharacterSpacing() throws {
            // 양쪽 정렬 줄: 마지막 글자 + 자간 없는 전진량 = 오른쪽 끝 (noori 실물·한글 실측).
            let text = Array(repeating: "aaaaa", count: 12).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .justify)
            let line = try XCTUnwrap(
                HwpDrawnTextLayout.lines(attributedString: attributed, origin: .zero, lineWidth: 200).first
            )
            let lastA = (line.stringRange.location ..< NSMaxRange(line.stringRange)).last {
                (attributed.string as NSString).character(at: $0) == 0x61
            }
            let origin = Self.glyphOrigin(of: try XCTUnwrap(lastA), in: line)
            expect(try XCTUnwrap(origin) + self.menloA).to(beCloseTo(200, within: 0.01))
        }

        func testJustifiedLineWithoutSpacesEndsAtTheMargin() throws {
            // 빈칸 없는 줄은 CoreText가 글자 사이로 벌리는데, 마지막 글자의 음수 자간을 넣고 맞추면 그
            // 글자가 오른쪽 끝을 자간만큼 넘는다 — 그만큼 좁게 다시 맞춘다.
            let attributed = try spacedParagraph(
                String(repeating: "a", count: 60), spacing: -20, alignment: .justify
            )
            let line = try XCTUnwrap(
                HwpDrawnTextLayout.lines(attributedString: attributed, origin: .zero, lineWidth: 200).first
            )
            let last = NSMaxRange(line.stringRange) - 1
            let origin = try XCTUnwrap(Self.glyphOrigin(of: last, in: line))
            expect(origin + self.menloA).to(beCloseTo(200, within: 0.01))
        }

        func testSlightOverflowAlignsTheContentWidth() throws {
            // 한 줄 허용으로 접힌 줄의 정렬은 CoreText가 보통 줄을 정렬하는 내용 폭(줄 끝 공백과 매달린 양수
            // tracking을 뺀 폭)으로 잰다 — 오른쪽 정렬이 마지막 글자를 오른쪽 끝 − 자간 없는 전진량에 둔다.
            // 둘 다 typographic 폭(매달린 몫 포함)은 넘치고 내용 폭은 들어가는 줄이라 허용으로 접힌다.
            let positive = try spacedParagraph("abcd", spacing: 20, alignment: .right)
            let positiveWidth = 4 * menloA * 1.2 - menloA * 0.1
            let trailing = try spacedParagraph("abcd ", spacing: 0, alignment: .right)
            let trailingWidth = 4 * menloA + 4.5
            // 음수 자간 + 줄 끝 빈칸: 빈칸 하나로 허용 경로에 들어온 줄도 마지막 글자의 자간을 뺀 폭으로
            // 정렬한다 (보통 줄의 `lineEndSpacingAligned`와 같은 자리).
            let negative = try spacedParagraph("abcd ", spacing: -20, alignment: .right)
            let negativeWidth: CGFloat = 27
            let cases = [
                (positive, positiveWidth), (trailing, trailingWidth), (negative, negativeWidth),
            ]
            for (attributed, width) in cases {
                expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                    attributedString: attributed, lineWidth: width
                )).toNot(beNil())
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: attributed, origin: .zero, lineWidth: width
                )
                expect(lines.count) == 1
                let dOrigin = try XCTUnwrap(lines.first.flatMap { Self.glyphOrigin(of: 3, in: $0) })
                expect(dOrigin + self.menloA).to(beCloseTo(width, within: 0.01))
            }
            // 마지막 글자의 자간을 빼면 줄에 들지 않는(글꼴 차로 정말 넘치는) 줄은 보통 경로처럼 그 몫을
            // 옮기지 않는다 — CoreText 폭(자간 포함)이 오른쪽 끝에 맞는다.
            let overflowing = try spacedParagraph("abcd", spacing: -20, alignment: .right)
            let overflowWidth = 3 * menloA * 0.8 + menloA * 0.8 - 0.6
            let lines = HwpDrawnTextLayout.lines(
                attributedString: overflowing, origin: .zero, lineWidth: overflowWidth
            )
            expect(lines.count) == 1
            let dOrigin = try XCTUnwrap(lines.first.flatMap { Self.glyphOrigin(of: 3, in: $0) })
            expect(dOrigin + self.menloA * 0.8).to(beCloseTo(overflowWidth, within: 0.01))
        }

        func testRefitMeasuresIndentedTabLinesAtTheirOffset() throws {
            // 들여쓴 문단의 탭 있는 줄은 실제 줄 머리 자리에서 재야 한다 — CoreText의 탭 자리는 프레임 왼쪽
            // 끝 기준이라 0에서 재면 탭 간격만큼 갈려 한 낱말 일찍 나눴다 (`value`가 다음 줄로 밀렸다).
            let text = "item one\tdescription text here\tvalue 123\tnext item\tanother description "
                + "sentence\tend value 45\tsome more words follow here\tand more"
            let attributed = try spacedParagraph(
                text, spacing: -20, alignment: .left, marginLeft: 4000
            )
            let string = attributed.string as NSString
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: 208
            ).map { string.substring(with: $0.stringRange) }
            expect(lines.contains("description sentence\tend value ")) == true
        }

        /// Menlo 12pt 자간 −20%, 양쪽 정렬·왼쪽 여백 `headIndent`·탭 간격 28pt의 조판 문자열 (글자 모양 헬퍼를
        /// 거치지 않고 문단 구분자·탭을 그대로 싣는다).
        private static func justifiedSpaced(_ text: String, headIndent: CGFloat) -> NSAttributedString {
            var alignment = CTTextAlignment.justified
            var indent = headIndent
            var tabInterval: CGFloat = 28
            let style = withUnsafePointer(to: &alignment) { alignment in
                withUnsafePointer(to: &indent) { indent in
                    withUnsafePointer(to: &tabInterval) { tabInterval in
                        CTParagraphStyleCreate([
                            CTParagraphStyleSetting(
                                spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                value: alignment
                            ),
                            CTParagraphStyleSetting(
                                spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size,
                                value: indent
                            ),
                            CTParagraphStyleSetting(
                                spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: indent
                            ),
                            CTParagraphStyleSetting(
                                spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size,
                                value: tabInterval
                            ),
                        ], 4)
                    }
                }
            }
            return HwpTextRunBuilder.letterSpacedString(text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil),
                kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ], ratio: -0.2)
        }

        func testParagraphSeparatorEndsTheJustifiedParagraph() throws {
            // LF·CR·U+2029로 끝나는 줄은 (CoreText) 문단의 마지막 줄이라 양쪽 정렬로 벌리지 않는다 — LF만 보면
            // U+2029로 끝나는 첫 문단 줄이 200pt 끝까지 벌어졌다 (#260 리뷰 실측: 줄 폭 23.12 → 198.56pt).
            for separator in ["\n", "\r", "\u{2029}"] {
                let attributed = Self.justifiedSpaced("abcd" + separator + "efgh", headIndent: 0)
                let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                    attributedString: attributed, origin: .zero, lineWidth: 200
                ).first)
                expect(line.stringRange) == NSRange(location: 0, length: 5)
                expect(Self.glyphOrigin(of: 3, in: line)).to(
                    beCloseTo(3 * menloA * 0.8, within: 0.01),
                    description: separator.debugDescription
                )
            }
        }

        /// 들여쓴(20pt) 양쪽 정렬 탭 문단 `aa→bb→cc→…`.
        private static var indentedTabParagraph: NSAttributedString {
            justifiedSpaced(
                Array(repeating: "aa\tbb\tcc", count: 6).joined(separator: "\t"), headIndent: 20
            )
        }

        /// `line`(문자열 위치 `location`에서 시작, 원점 x `originX`)의 탭 바로 뒤 글리프가 프레임 왼쪽 끝 기준
        /// 탭 자리(28pt 간격)에 있는가. 다시 조판한 줄은 문자열 위치가 부분 문자열 기준(0부터)이다. 줄 머리
        /// 글자는 앞 줄 끝 탭 뒤라도 탭 자리가 아니라 줄 머리 자리라 빼고, 잰 글리프가 없으면 실패한다.
        private static func expectTabbedGlyphsOnStops(
            _ line: CTLine, location: Int, originX: CGFloat, in string: NSString, _ label: String
        ) {
            let base = CTLineGetStringRange(line).location
            var origins: [CGFloat] = []
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                for (position, index) in zip(positions, indices)
                    where index > base && string.character(at: index - base + location - 1) == 0x09
                {
                    origins.append(originX + position.applying(CTRunGetTextMatrix(run)).x)
                }
            }
            expect(origins.isEmpty).to(beFalse(), description: label)
            for origin in origins {
                let stop = (origin / 28).rounded() * 28
                expect(origin).to(beCloseTo(stop, within: 0.01), description: label)
            }
        }

        func testJustifiedTabLinesKeepTheFrameTabStops() {
            // 들여쓴 양쪽 정렬 문단의 탭 줄을 다시 조판하면 프레임 안 줄 머리 자리에서 조판한다 — 0에서 조판하면
            // 탭 뒤 글자가 들여쓰기만큼 앞 탭 자리로 당겨졌다 (#260 리뷰 실측: 왼쪽 여백 20pt 줄의 `bb`가 56 →
            // 48pt).
            let attributed = Self.indentedTabParagraph
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: 208
            )
            expect(lines.count) > 1
            for line in lines {
                Self.expectTabbedGlyphsOnStops(
                    line.line, location: line.stringRange.location, originX: line.baselineOrigin.x,
                    in: attributed.string as NSString, "\(line.stringRange)"
                )
            }
        }

        func testPublicJustificationKeepsTheFrameTabStops() {
            // 공개 진입점은 줄 머리 자리를 문단 스타일에서 얻는다 — 렌더와 같은 자리다. CoreText 프레임 줄을
            // 그대로 받으므로 마지막 글자 자간을 빼도 들어가는 폭(216pt)에서 잰다 (208pt 프레임 줄은 넘쳐 nil).
            let attributed = Self.indentedTabParagraph
            let frame = CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(attributed), CFRange(),
                CGPath(rect: CGRect(x: 0, y: 0, width: 216, height: 10000), transform: nil), nil
            )
            let frameLines = CTFrameGetLines(frame) as? [CTLine] ?? []
            var origins = [CGPoint](repeating: .zero, count: frameLines.count)
            CTFrameGetLineOrigins(frame, CFRange(), &origins)
            var replaced = 0
            for (frameLine, origin) in zip(frameLines, origins) {
                guard let line = HwpWordJustification.wordJustifiedLine(
                    frameLine: frameLine, attributedString: attributed,
                    availableWidth: 216 - origin.x
                ) else { continue }
                replaced += 1
                let location = CTLineGetStringRange(frameLine).location
                Self.expectTabbedGlyphsOnStops(
                    line, location: location, originX: origin.x,
                    in: attributed.string as NSString, "\(location)"
                )
            }
            expect(replaced) > 0
        }

        func testJustifiedLineWithASmallExtraStillEndsAtTheMargin() throws {
            // 남는 폭이 0.25pt 이하인 양쪽 정렬 줄도 마지막 글자 + 자간 없는 전진량이 오른쪽 끝이다 — CoreText
            // 프레임 줄을 그대로 그리면 마지막 글자가 자간만큼 넘친다.
            let text = Array(repeating: "aaaaa", count: 12).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .justify)
            let width = widths(words: 6, ratio: -0.2).lineEnd + 0.1
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: width
            )
            let line = try XCTUnwrap(lines.first)
            expect(line.stringRange.length) == 36
            let lastA = (line.stringRange.location ..< NSMaxRange(line.stringRange)).last {
                (attributed.string as NSString).character(at: $0) == 0x61
            }
            let origin = try XCTUnwrap(Self.glyphOrigin(of: try XCTUnwrap(lastA), in: line))
            expect(origin + self.menloA).to(beCloseTo(width, within: 0.01))
        }

        func testLongParagraphRefitMatchesLineByLine() throws {
            // 고친 줄 뒤는 창 단위로 다시 조판한다 — 창을 여러 번 넘는 문단도 줄마다 6단어(자간을 빼고
            // 재면 7단어째가 넘친다)로, 한 청크로, 측정과 같은 줄로 나뉜다.
            let text = Array(repeating: "aaaaa", count: 400).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .left)
            let seven = widths(words: 7, ratio: -0.2)
            let width = (seven.full + seven.lineEnd) / 2
            let chunk = try XCTUnwrap(HwpLineBreaker.nextFrameChunk(
                framesetter: CTFramesetterCreateWithAttributedString(attributed),
                typesetter: CTTypesetterCreateWithAttributedString(attributed),
                attributedString: attributed, startLocation: 0, fullLength: attributed.length,
                remainingLineBudget: HwpParagraphLayout.maximumLineFrames, lineWidth: width
            ))
            expect(chunk.nextStart) == attributed.length
            let ranges = chunk.lines.prefix(chunk.keepCount).map { line -> NSRange in
                let range = CTLineGetStringRange(line)
                return NSRange(location: range.location, length: range.length)
            }
            expect(ranges.count) == 67
            expect(ranges.dropLast().allSatisfy { $0.length == 36 }) == true
            let contiguous = zip(ranges, ranges.dropFirst()).allSatisfy {
                NSMaxRange($0) == $1.location
            }
            expect(contiguous) == true
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: width
            )
            expect(drawn.map(\.stringRange)) == ranges
        }

        /// Apple SD 산돌고딕 Neo `가나다라마바` — 글자마다 크기 80·40.5·20.5·10.5·5.5·3pt, 한글 자간 −50%.
        private static var shrinkingSizes: NSAttributedString {
            let string = NSMutableAttributedString()
            let sizes: [CGFloat] = [80, 40.5, 20.5, 10.5, 5.5, 3]
            for (character, size) in zip(["가", "나", "다", "라", "마", "바"], sizes) {
                string.append(HwpTextRunBuilder.letterSpacedString(character, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, size, nil),
                ], ratio: -0.5))
            }
            return string
        }

        /// 줄의 한글식 폭 — 내용 폭에서 마지막 글자의 음수 자간을 뺀다.
        private static func hangulWidth(
            of line: CTLine, range: NSRange, in string: NSAttributedString
        ) -> CGFloat {
            HwpLineBreaker.contentWidth(of: line)
                - min(0, HwpLetterSpacing.lineEndExcess(in: string, range: range))
        }

        func testRefitKeepsLookingPastTheFixedPointBudget() throws {
            // 크기가 줄어드는 글자열은 마지막 글자가 바뀔 때마다 빼는 자간이 커져 고정점 반복이 한 자리씩만 당긴다 —
            // 네 번 만에 수렴하지 못해 두 글자 줄(69.6325pt)이 69.21pt 줄 폭에 확정됐다 (#260 PR 리뷰). 한 글자는
            // 69.2pt로 들어간다. 한글 12.30도 같은 구성의 69.42pt 줄에 `가` 한 글자만 둔다(실측, 2026-10-09).
            let string = Self.shrinkingSizes
            for width: CGFloat in [69.21, 69.42] {
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: .zero, lineWidth: width
                )
                let first = try XCTUnwrap(lines.first)
                expect(first.stringRange.length).to(equal(1), description: "\(width)")
                expect(Self.hangulWidth(of: first.line, range: first.stringRange, in: string))
                    .to(beLessThanOrEqualTo(width), description: "\(width)")
            }
        }

        func testRefitKeepsOnlyTheFirstCharacterWhenNothingFits() throws {
            // 첫 글자만으로도 넘쳐 어느 줄 나눔 자리도 들지 않으면 첫 묶음만 둔다 — 한글 12.30 실측(2026-10-09):
            // Apple SD 산돌고딕 Neo `가…차` 96·45·21·10·4.7·2.2·1·1·1·1pt 자간 −50% 뒤 20pt `하` × 12, 줄 폭
            // 76.5·77.5·78.0pt 모두 첫 줄이 `가`. 고정점 반복의 넷째 후보로 되돌아가면 77.5pt에서 `가나`(80.445pt)가
            // 확정됐다 — 결과가 반복 상한에 좌우됐다 (#260 PR 리뷰 적대 검토).
            let string = NSMutableAttributedString()
            let sizes: [CGFloat] = [96, 45, 21, 10, 4.7, 2.2, 1, 1, 1, 1]
            let characters = ["가", "나", "다", "라", "마", "바", "사", "아", "자", "차"]
            for (character, size) in zip(characters, sizes) {
                string.append(HwpTextRunBuilder.letterSpacedString(character, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, size, nil),
                ], ratio: -0.5))
            }
            string.append(HwpTextRunBuilder.letterSpacedString(
                String(repeating: "하", count: 12),
                attributes: [kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 20, nil)],
                ratio: -0.5
            ))
            for width: CGFloat in [76.5, 77.5, 78.0] {
                let first = try XCTUnwrap(HwpDrawnTextLayout.lines(
                    attributedString: string, origin: .zero, lineWidth: width
                ).first)
                expect(first.stringRange).to(
                    equal(NSRange(location: 0, length: 1)), description: "\(width)"
                )
            }
        }

        func testRefitNeverCommitsAnOverflowingLineThatCouldBeShorter() throws {
            // 줄 폭을 0.25pt씩 바꿔도 공유 코어가 커밋하는 줄은 모두 한글식 폭이 줄 폭 안이다 — 더 짧게 나눌 수
            // 없는 한 글자 줄만 예외다. 측정도 같은 줄이다.
            let string = Self.shrinkingSizes
            var width: CGFloat = 40
            while width <= 100 {
                let chunk = try XCTUnwrap(HwpLineBreaker.nextFrameChunk(
                    framesetter: CTFramesetterCreateWithAttributedString(string),
                    typesetter: CTTypesetterCreateWithAttributedString(string),
                    attributedString: string, startLocation: 0, fullLength: string.length,
                    remainingLineBudget: HwpParagraphLayout.maximumLineFrames, lineWidth: width
                ))
                for line in chunk.lines.prefix(chunk.keepCount) {
                    let range = CTLineGetStringRange(line)
                    let nsRange = NSRange(location: range.location, length: range.length)
                    guard nsRange.length > 1 else { continue }
                    expect(Self.hangulWidth(of: line, range: nsRange, in: string))
                        .to(beLessThanOrEqualTo(width + 0.001), description: "\(width) \(nsRange)")
                }
                let measured = HwpParagraphLayout().layout(
                    attributedString: string,
                    paraShape: CoreHwp.HwpParaShape(property1: 1 << 2, marginLeft: 0, tabDefId: 0),
                    columnWidth: width
                )
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: .zero, lineWidth: width
                )
                expect(measured.lines.map(\.attributedRange))
                    .to(equal(drawn.map(\.stringRange)), description: "\(width)")
                width += 0.25
            }
        }

        func testRefitDoesNotCommitTheBudgetCutLine() throws {
            // 예산이 자른 청크를 줄 끝 자간으로 다시 나누면 남은 덜 찬 줄을 커밋하지 않고 다음 호출로
            // 넘긴다 — 커밋하면 줄이 낱말 가운데(예산 경계)에서 끊긴다.
            let text = Array(repeating: "aaaaa", count: 20).joined(separator: " ")
            let attributed = try spacedParagraph(text, spacing: -20, alignment: .left)
            let seven = widths(words: 7, ratio: -0.2)
            let width = (seven.full + seven.lineEnd) / 2
            let chunk = try XCTUnwrap(HwpLineBreaker.nextFrameChunk(
                framesetter: CTFramesetterCreateWithAttributedString(attributed),
                typesetter: CTTypesetterCreateWithAttributedString(attributed),
                attributedString: attributed, startLocation: 0, fullLength: attributed.length,
                remainingLineBudget: 50, lineWidth: width
            ))
            expect(chunk.keepCount) == 1
            expect(chunk.nextStart) == 36
            let first = CTLineGetStringRange(chunk.lines[0])
            expect(first.location) == 0
            expect(first.length) == 36
        }
    }
#endif
