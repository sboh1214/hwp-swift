import CoreGraphics
import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// MS 워드 호환 문서의 **줄 상자·베이스라인·전진량** (#194) — 세로 배치가 글꼴 줄 상자
    /// (`HwpMsWordLineBox`)를 따르는 계약.
    ///
    /// 오라클은 한글 12.30.0 (2026-09-20) 이 `targetProgram="MS_WORD"` 합성 HWPX(한글 슬롯
    /// Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo, 줄 캐시 없음)를 다시 저장한 줄 캐시
    /// (`vertsize`·`baseline`·`spacing`)와 PDF 베이스라인이다 — 기대값은 같은 글꼴의 OS/2
    /// 지표에서 `HwpMsWordLineBox`로 계산하고 한글 캐시와 0.03pt 안에서 만난다 (한글은 상자를
    /// 글꼴마다 ±0.03pt 다르게 반올림한다 — Apple SD 10pt 1559 vs 산식 1560, Menlo 1515 vs 1513).
    ///
    /// | 줄 | 한글 `vertsize` | `baseline` | 160% `spacing` |
    /// |---|---:|---:|---:|
    /// | Apple SD 10pt 한글 + CR(Menlo) | 1559 | 1104 | 932 |
    /// | Menlo 10pt 라틴 | 1515 | 1104 | 908 |
    /// | Apple SD 20pt | 3119 | 2207 | 1868 |
    /// | 10pt 줄 + 30pt 글자처럼 취급 표 | 3455 | 3000 | 932 |
    /// | 빈 문단 (Apple SD/Menlo 10pt 글자 모양) | 1515 | 1104 | 908 |
    final class HwpMsWordLineMetricsTests: XCTestCase {
        private typealias Key = NSAttributedString.Key
        private static let blockTop: CGFloat = 100

        private static func font(_ name: String, _ size: CGFloat) -> CTFont {
            CTFontCreateWithName(name as CFString, size, nil)
        }

        private static func box(_ name: String, _ size: CGFloat) -> HwpMsWordLineBox {
            HwpMsWordLineBox.metrics(of: font(name, size)).scaled(by: size)
        }

        /// MS 워드 호환 run 속성 — 글꼴·기본 크기·호환 문서 키.
        private static func attributes(
            _ name: String, _ size: CGFloat, baseSize: CGFloat? = nil, msWord: Bool = true
        ) -> [Key: Any] {
            var attributes: [Key: Any] = [
                kCTFontAttributeName as Key: font(name, size),
                HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(baseSize ?? size)),
            ]
            if msWord {
                attributes[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                    value: HwpCompatibleDocumentTarget.msWord.rawValue
                )
            }
            return attributes
        }

        /// 문단 끝 상자(`hwp.msWordParagraphEndBox`)와 줄 간격 규칙을 문자열 전체에 단다.
        private static func finish(
            _ string: NSMutableAttributedString,
            endBox: HwpMsWordLineBox? = nil,
            rule: HwpLineSpacingRule = HwpLineSpacingRule(kind: .percent, value: 160),
            continued: Bool = false
        ) -> NSAttributedString {
            let range = NSRange(location: 0, length: string.length)
            if let endBox {
                string.addAttribute(
                    HwpAttributedStringKey.msWordParagraphEndBox,
                    value: [
                        NSNumber(value: Double(endBox.lineHeight)),
                        NSNumber(value: Double(endBox.baseline)),
                    ],
                    range: range
                )
            }
            string.addAttribute(
                HwpAttributedStringKey.lineSpacing, value: rule.attributeValue, range: range
            )
            if continued {
                string.addAttribute(
                    HwpAttributedStringKey.continuedParagraphFragment, value: true, range: range
                )
            }
            return string
        }

        private static func lines(
            _ string: NSAttributedString, width: CGFloat = 400
        ) -> [HwpDrawnLine] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: blockTop), lineWidth: width
            )
        }

        private func skipUnlessOracleFonts() throws {
            try XCTSkipUnless(
                Self.box("Apple SD Gothic Neo", 10).cellHeight > 11.5
                    && Self.box("Menlo", 10).cellHeight > 11.5,
                "Apple SD 산돌고딕 Neo·Menlo 없음"
            )
        }

        /// 베이스라인 = 상자 상단 + 글꼴 줄 상자의 베이스라인 (Apple SD 10pt 10.80pt) — 한글
        /// 문서의 0.85 × 기본 크기(8.5pt)가 아니다. 키가 없는 같은 문자열은 종전대로다.
        func testMsWordLineAnchorsOnTheFontBoxBaseline() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let msWord = Self.finish(NSMutableAttributedString(
                string: "가나다", attributes: Self.attributes("Apple SD Gothic Neo", 10)
            ))
            expect(Self.lines(msWord).first?.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + appleSD.baseline, within: 0.001))
            expect(appleSD.baseline).to(beCloseTo(10.8, within: 0.03))
            let native = Self.finish(NSMutableAttributedString(
                string: "가나다", attributes: Self.attributes("Apple SD Gothic Neo", 10, msWord: false)
            ))
            expect(Self.lines(native).first?.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + 8.5, within: 0.001))
        }

        /// 문단 끝 글자(CR) 상자는 **마지막 줄에만** 든다 — Apple SD 10pt 두 줄 문단의 끝 상자가
        /// Menlo면 첫 줄 베이스라인은 Apple SD(10.80), 마지막 줄은 Menlo(11.03)다 (한글 캐시
        /// 1104). 이어지는 조각(`continuedParagraphFragment`)의 끝 줄은 문단 끝이 아니다.
        func testParagraphEndBoxJoinsOnlyTheLastLine() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo = Self.box("Menlo", 10)
            func paragraph(continued: Bool) -> NSAttributedString {
                Self.finish(
                    NSMutableAttributedString(
                        string: "가나다라마바사아자차카타파하",
                        attributes: Self.attributes("Apple SD Gothic Neo", 10)
                    ),
                    endBox: menlo, continued: continued
                )
            }
            let lines = Self.lines(paragraph(continued: false), width: 70)
            expect(lines.count) == 2
            guard lines.count == 2 else { return }
            let advance = appleSD.lineHeight
                + HwpLineSpacingRule.percentShare(of: appleSD.lineHeight, percent: 160)
            expect(lines[0].baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + appleSD.baseline, within: 0.001))
            expect(lines[1].baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + advance + max(appleSD.baseline, menlo.baseline), within: 0.001))
            expect(menlo.baseline).to(beCloseTo(11.04, within: 0.03))
            let continued = Self.lines(paragraph(continued: true), width: 70)
            expect(continued.last?.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + advance + appleSD.baseline, within: 0.001))
        }

        /// 결합 문자열(컨테이너가 문단들을 `\n`으로 이은 것, 공개 `drawText`의 여러 문단)에서는
        /// 앞 문단의 마지막 줄도 문단 끝이다 — 문단 끝 상자가 그 줄에 들고(Menlo 30pt 상자 →
        /// 33.09pt, 홀로 그릴 때와 같다) 다음 문단이 그만큼 아래에 놓인다. 끝 상자(45.40)가 글자
        /// 상자(Apple SD 10pt 15.60)보다 높으므로 줄 상자는 끝 상자 + 글자 상자의 베이스라인 아래
        /// 몫(4.80)이다 (#223 — 한글 12.30 실측: 10pt 글 + 30pt 글자 모양의 끝 글자 줄 `vertsize`
        /// 4999 = Menlo 30 상자 4540 + Apple SD/Menlo 10 글자 상자의 아래 몫 455, #194가 미해석으로
        /// 남긴 1688의 정체). 한 줄 끝 표식(`lineBreak`)으로 끝나는 줄은 문단 끝이 아니다 (PR 리뷰).
        func testCombinedParagraphsKeepEachParagraphEndBox() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo30 = Self.box("Menlo", 30)
            let text = Self.attributes("Apple SD Gothic Neo", 10)
            let first = Self.finish(
                NSMutableAttributedString(string: "가나\n", attributes: text), endBox: menlo30
            )
            let second = Self.finish(NSMutableAttributedString(string: "다라", attributes: text))
            let combined = NSMutableAttributedString(attributedString: first)
            combined.append(second)
            let alone = Self.lines(first)
            let joined = Self.lines(combined)
            expect(joined.count) == 2
            guard joined.count == 2, let aloneFirst = alone.first else { return }
            expect(aloneFirst.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + menlo30.baseline, within: 0.001))
            expect(joined[0].baselineOrigin.y).to(beCloseTo(aloneFirst.baselineOrigin.y, within: 0.001))
            expect(joined[0].endsParagraph).to(beTrue())
            expect(menlo30.baseline).to(beCloseTo(33.09, within: 0.03))
            // 다음 문단은 앞 문단의 (Menlo 30 상자 + 글자 상자 아래 몫 + 끝 상자 기준 비율 여분)
            // 아래에서 시작한다.
            let advance = menlo30.lineHeight + (appleSD.lineHeight - appleSD.baseline)
                + HwpLineSpacingRule.percentShare(of: menlo30.lineHeight, percent: 160)
            expect(joined[1].baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + advance + appleSD.baseline, within: 0.001))
            // 한 줄 끝 run으로 나뉜 줄은 문단 끝이 아니다.
            let broken = NSMutableAttributedString(string: "가나", attributes: text)
            broken.append(LineBoxFixtures.lineBreak(attributes: text))
            broken.append(NSAttributedString(string: "다라", attributes: text))
            let brokenLines = Self.lines(Self.finish(broken, endBox: menlo30))
            expect(brokenLines.count) == 2
            expect(brokenLines.first?.endsParagraph).to(beFalse())
            expect(brokenLines.first?.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + appleSD.baseline, within: 0.001))
            expect(brokenLines.last?.endsParagraph).to(beTrue())
        }

        /// 줄 상자는 run 상자의 **축별 최댓값**이다 — Apple SD 10pt + Menlo 20pt 줄의 높이는
        /// Menlo 20(30.27), 베이스라인도 Menlo 20(22.06) (한글 캐시 3029·2207); Apple SD 20pt +
        /// Menlo 10pt 줄은 높이 Apple SD 20(31.20)·베이스라인 Apple SD 20(21.60)이되 끝 상자가
        /// Menlo 20이면 22.06 (캐시 3119·2207).
        func testMixedRunsTakeEachAxisFromTheTallestBox() throws {
            try skipUnlessOracleFonts()
            let menlo20 = Self.box("Menlo", 20)
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let mixed = NSMutableAttributedString(
                string: "가나", attributes: Self.attributes("Apple SD Gothic Neo", 10)
            )
            mixed.append(NSAttributedString(string: "Agpy", attributes: Self.attributes("Menlo", 20)))
            let line = try XCTUnwrap(Self.lines(Self.finish(mixed, endBox: menlo20)).first)
            let metrics = HwpDrawnTextLayout.lineMetrics(of: line.line, endsParagraph: true)
            expect(metrics.textBoxHeight).to(beCloseTo(menlo20.lineHeight, within: 0.001))
            expect(metrics.baselineAnchor).to(beCloseTo(menlo20.baseline, within: 0.001))
            let reversed = NSMutableAttributedString(
                string: "가나", attributes: Self.attributes("Apple SD Gothic Neo", 20)
            )
            reversed.append(NSAttributedString(string: "Agpy", attributes: Self.attributes("Menlo", 10)))
            let reversedLine = try XCTUnwrap(Self.lines(Self.finish(reversed, endBox: menlo20)).first)
            let reversedMetrics = HwpDrawnTextLayout.lineMetrics(of: reversedLine.line, endsParagraph: true)
            expect(reversedMetrics.textBoxHeight).to(beCloseTo(appleSD20.lineHeight, within: 0.001))
            expect(reversedMetrics.baselineAnchor)
                .to(beCloseTo(max(appleSD20.baseline, menlo20.baseline), within: 0.001))
            expect(appleSD20.lineHeight).to(beCloseTo(31.19, within: 0.03))
            expect(menlo20.baseline).to(beCloseTo(22.07, within: 0.03))
        }

        /// 상자에 곱하는 크기는 글자 모양 **기본 크기**다 — 한글 슬롯 상대 크기 50%(5pt 글꼴)·
        /// 200%(20pt 글꼴)여도 줄 상자는 10pt 기준 그대로다 (한글 캐시 둘 다 1559·1104).
        func testRelativeSizeRunsKeepTheBaseSizeBox() throws {
            try skipUnlessOracleFonts()
            let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
            for scaled: CGFloat in [5, 20] {
                let string = Self.finish(NSMutableAttributedString(
                    string: "가나다",
                    attributes: Self.attributes("Apple SD Gothic Neo", scaled, baseSize: 10)
                ))
                expect(Self.lines(string).first?.baselineOrigin.y)
                    .to(beCloseTo(Self.blockTop + appleSD10.baseline, within: 0.001), description: "\(scaled)")
            }
        }

        /// 글자처럼 취급 개체 줄 — 베이스라인은 max(글꼴 상자 베이스라인, 개체 높이)이고 상자는
        /// 그 아래에 **글자 상자**의 베이스라인 아래 몫이 붙는다: Apple SD/Menlo 10pt 줄(15.59/11.04
        /// — 빈칸이 라틴 슬롯 Menlo다)에 30pt 표를 넣으면 한글 캐시 `vertsize` 3455 = 3000 + 455·
        /// `baseline` 3000, 160% `spacing`은 글자 상자 기준 932 그대로. 개체가 베이스라인보다 낮으면
        /// 상자가 그대로다. 아래 몫은 문단 끝 상자가 아니라 글자 run의 것이다 (#223 실측: 빈칸 없는
        /// Apple SD 10pt 글 + 20pt 표 + Menlo 끝 글자 → 2479 = 2000 + Apple SD의 479).
        func testObjectLinePutsTheObjectBottomOnTheBaseline() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo = Self.box("Menlo", 10)
            let text = Self.attributes("Apple SD Gothic Neo", 10)
            // 한글처럼 빈칸은 라틴 슬롯(Menlo)이다 — 글자 상자가 Apple SD ∪ Menlo가 된다.
            let space = Self.attributes("Menlo", 10)
            func paragraph(objectHeight: CGFloat) -> NSAttributedString {
                let string = NSMutableAttributedString(string: "가나", attributes: text)
                string.append(NSAttributedString(string: " ", attributes: space))
                string.append(LineBoxFixtures.objectMarker(height: objectHeight, attributes: text))
                string.append(NSAttributedString(string: " ", attributes: space))
                string.append(NSAttributedString(string: "뒤", attributes: text))
                return Self.finish(string, endBox: menlo)
            }
            let tall = try XCTUnwrap(Self.lines(paragraph(objectHeight: 30)).first)
            let tallMetrics = HwpDrawnTextLayout.lineMetrics(of: tall.line, endsParagraph: true)
            let below = appleSD.lineHeight - max(appleSD.baseline, menlo.baseline)
            expect(tall.baselineOrigin.y).to(beCloseTo(Self.blockTop + 30, within: 0.001))
            expect(tallMetrics.boxHeight).to(beCloseTo(30 + below, within: 0.001))
            expect(tallMetrics.textBoxHeight).to(beCloseTo(appleSD.lineHeight, within: 0.001))
            expect(30 + below).to(beCloseTo(34.55, within: 0.03))
            // 전진량 = 상자 + 글자 상자 기준 비율 여분 (한글 3455 + 932 = 4387)
            let advance = HwpLineAdvance.lineAdvance(
                of: tall.line, at: 0, in: paragraph(objectHeight: 30)
            )
            expect(advance).to(beCloseTo(
                30 + below + HwpLineSpacingRule.percentShare(of: appleSD.lineHeight, percent: 160),
                within: 0.001
            ))
            expect(advance).to(beCloseTo(43.87, within: 0.1))
            expect(HwpDrawnTextLayout.underlineReturnDrop(of: tall.line)).to(equal(0))
            let short = try XCTUnwrap(Self.lines(paragraph(objectHeight: 5)).first)
            expect(short.baselineOrigin.y)
                .to(beCloseTo(Self.blockTop + max(appleSD.baseline, menlo.baseline), within: 0.001))
            expect(HwpDrawnTextLayout.lineMetrics(of: short.line, endsParagraph: true).boxHeight)
                .to(beCloseTo(appleSD.lineHeight, within: 0.001))
        }

        /// 비율 여분은 4 HWPUNIT 양자다 — 글자 상자를 4 단위로 내림한 뒤 (p − 100)%를 곱해
        /// 반올림한다 (한글 캐시: 1559 → 932·1556·3112·−312, 1515 → 908·1512·3024, 1692 → 1016,
        /// 3383 → 2028, 4678 → 2804, 780 → 468). 한글 문서의 실물 캐시도 같다 — `CCL`·`noori`
        /// 15pt 170% 1052, 헌법주석 각주 9pt 130% 272·10.5pt 160% 628(상자 262.5도 내림)·11pt
        /// 130% 332·9.5pt 130% 284, `noori` 13pt 130% 392·15.5pt 160% 928 — .5는 올린다.
        /// 4의 배수 상자는 산술 그대로다 (10pt 160% → 6).
        func testPercentShareIsQuantizedToFourHwpUnits() {
            let table: [(box: CGFloat, percent: CGFloat, share: CGFloat)] = [
                (15.59, 160, 9.32), (15.59, 200, 15.56), (15.59, 300, 31.12), (15.59, 80, -3.12),
                (15.15, 160, 9.08), (15.15, 200, 15.12), (15.15, 300, 30.24),
                (16.92, 160, 10.16), (33.83, 160, 20.28), (46.78, 160, 28.04), (7.80, 160, 4.68),
                (15, 170, 10.52), (9, 130, 2.72), (10.5, 160, 6.28), (11, 130, 3.32),
                (9.5, 130, 2.84), (13, 130, 3.92), (15.5, 160, 9.28), (12, 170, 8.4),
                (10, 160, 6), (10, 100, 0), (10, 300, 20), (10, 80, -2), (0, 160, 0),
            ]
            for row in table {
                expect(HwpLineSpacingRule.percentShare(of: row.box, percent: row.percent))
                    .to(beCloseTo(row.share, within: 0.0001), description: "\(row.box) \(row.percent)")
            }
            expect(HwpLineSpacingRule(kind: .percent, value: 170).advance(textBoxHeight: 15, objectHeight: 0))
                .to(beCloseTo(25.52, within: 0.0001))
        }

        /// 줄 상자를 직접 주는 전진량 — 고정·여백만·최소는 상자(글꼴 줄 상자, 개체 줄이면 그
        /// 합)에, 비율 여분은 글자 상자에 적용한다 (한글 캐시 `cm194-spacing`·`cm194-objects`).
        func testAdvanceWithAnExplicitLineBox() {
            typealias Rule = HwpLineSpacingRule
            let box: CGFloat = 15.59
            expect(Rule(kind: .fixed, value: 5).advance(lineBoxHeight: box, textBoxHeight: box)) == 5
            expect(Rule(kind: .fixed, value: 16).advance(lineBoxHeight: box, textBoxHeight: box)) == 16
            expect(Rule(kind: .marginOnly, value: 3).advance(lineBoxHeight: box, textBoxHeight: box))
                .to(beCloseTo(18.59, within: 0.0001))
            expect(Rule(kind: .atLeast, value: 5).advance(lineBoxHeight: box, textBoxHeight: box))
                .to(beCloseTo(15.59, within: 0.0001))
            expect(Rule(kind: .atLeast, value: 16).advance(lineBoxHeight: box, textBoxHeight: box)) == 16
            expect(Rule(kind: .percent, value: 160).advance(lineBoxHeight: box, textBoxHeight: box))
                .to(beCloseTo(24.91, within: 0.0001))
            // 개체 줄 (3455/1559): 비율 여분은 글자 상자, 나머지는 상자 전체
            let object: CGFloat = 34.55
            expect(Rule(kind: .percent, value: 160).advance(lineBoxHeight: object, textBoxHeight: box))
                .to(beCloseTo(43.87, within: 0.0001))
            expect(Rule(kind: .fixed, value: 16).advance(lineBoxHeight: object, textBoxHeight: box)) == 16
            expect(Rule(kind: .marginOnly, value: 3).advance(lineBoxHeight: object, textBoxHeight: box))
                .to(beCloseTo(37.55, within: 0.0001))
            expect(Rule(kind: .atLeast, value: 30).advance(lineBoxHeight: object, textBoxHeight: box))
                .to(beCloseTo(34.55, within: 0.0001))
            // 상자와 여분 기준은 독립이다 — 20pt 글자 모양 표 마커가 든 10pt 줄 (한글 1559 + 1200)
            expect(Rule(kind: .percent, value: 160).advance(lineBoxHeight: box, textBoxHeight: 20))
                .to(beCloseTo(27.59, within: 0.0001))
            expect(Rule(kind: .percent, value: 160).advance(textBoxHeight: 10, objectHeight: 30))
                == Rule(kind: .percent, value: 160).advance(lineBoxHeight: 30, textBoxHeight: 10)
        }

        /// 측정(`HwpParagraphLayout.layout`)과 렌더(`lines`)가 같은 상자·앵커·전진량을 쓴다 —
        /// 줄 프레임의 `boxHeight`도 글꼴 줄 상자다.
        func testMeasurementMatchesRenderForMsWordLines() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo = Self.box("Menlo", 10)
            let string = Self.finish(
                NSMutableAttributedString(
                    string: "가나다라마바사아자차카타파하",
                    attributes: Self.attributes("Apple SD Gothic Neo", 10)
                ),
                endBox: menlo
            )
            let frame = HwpParagraphLayout().layout(
                attributedString: string,
                paraShape: LineBoxFixtures.paraShape(rule: HwpLineSpacingRule(kind: .percent, value: 160)),
                columnWidth: 70
            )
            let drawn = Self.lines(string, width: 70)
            expect(frame.lines.count) == drawn.count
            for (measured, line) in zip(frame.lines, drawn) {
                expect(Self.blockTop + measured.origin.y + measured.baseline)
                    .to(beCloseTo(line.baselineOrigin.y, within: 0.0001))
            }
            expect(frame.lines.first?.boxHeight).to(beCloseTo(appleSD.lineHeight, within: 0.001))
            let advance = appleSD.lineHeight
                + HwpLineSpacingRule.percentShare(of: appleSD.lineHeight, percent: 160)
            expect(frame.totalHeight).to(beCloseTo(advance * CGFloat(drawn.count), within: 0.001))
        }

        /// 밴드 바닥 구분선이 빼는 마지막 줄 줄 간격(`measuredTrailingSpacing`)은 그 줄의 줄 상자
        /// 기준이다 — Apple SD 10pt 본문(15.60)에 Menlo 30pt 문단 끝 상자(45.40)면 마지막 줄 상자와
        /// 160% 여분의 기준이 두 상자의 합(축별 최댓값)이다. 다음 단으로 이어지는 조각의 끝 줄은 끝
        /// 상자가 들지 않아 본문 상자 기준이고, 한글 문서는 기본 글자 크기(10pt → 6)다 (PR 리뷰).
        func testTrailingSpacingIncludesTheParagraphEndBox() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo30 = Self.box("Menlo", 30)
            let text = Self.attributes("Apple SD Gothic Neo", 10)
            let whole = Self.finish(
                NSMutableAttributedString(string: "가나", attributes: text), endBox: menlo30
            )
            let union = try XCTUnwrap(HwpMsWordLineBox.union([appleSD, menlo30]))
            expect(HwpColumnBandController.measuredTrailingSpacing(of: whole, lineWidth: 400))
                .to(beCloseTo(
                    HwpLineSpacingRule.percentShare(of: union.lineHeight, percent: 160),
                    within: 0.001
                ))
            let continued = Self.finish(
                NSMutableAttributedString(string: "가나", attributes: text),
                endBox: menlo30, continued: true
            )
            expect(HwpColumnBandController.measuredTrailingSpacing(of: continued, lineWidth: 400))
                .to(beCloseTo(
                    HwpLineSpacingRule.percentShare(of: appleSD.lineHeight, percent: 160),
                    within: 0.001
                ))
            let native = Self.finish(NSMutableAttributedString(
                string: "가나", attributes: Self.attributes("Apple SD Gothic Neo", 10, msWord: false)
            ))
            expect(HwpColumnBandController.measuredTrailingSpacing(of: native, lineWidth: 400))
                .to(beCloseTo(6, within: 0.001))
            expect(HwpColumnBandController.measuredTrailingSpacing(
                of: NSAttributedString(), lineWidth: 400
            )) == 0
        }

        /// 조판 없는 잉크 상한(`verticalInkReach`) — MS 워드 호환 문자열은 run마다 (ascent −
        /// 자기 상자 베이스라인)·(descent − 자기 상자 아래 몫)의 최댓값이고 음수는 0이다.
        func testVerticalInkReachUsesTheFontBoxForMsWordStrings() throws {
            try skipUnlessOracleFonts()
            let font = Self.font("Apple SD Gothic Neo", 10)
            let box = Self.box("Apple SD Gothic Neo", 10)
            let string = NSAttributedString(
                string: "가나", attributes: Self.attributes("Apple SD Gothic Neo", 10)
            )
            let reach = HwpHitTester.verticalInkReach(of: string)
            expect(reach.above).to(beCloseTo(max(0, CTFontGetAscent(font) - box.baseline), within: 0.001))
            expect(reach.below).to(beCloseTo(
                max(0, CTFontGetDescent(font) - (box.lineHeight - box.baseline)), within: 0.001
            ))
            let native = NSAttributedString(
                string: "가나", attributes: Self.attributes("Apple SD Gothic Neo", 10, msWord: false)
            )
            expect(HwpHitTester.msWordVerticalInkReach(of: native)).to(beNil())
        }

        /// 줄 상자가 높이와 베이스라인을 다른 run에서 고르면 run 자신의 상자로 잰 아래 몫은
        /// 상한이 아니다 — Papyrus 10pt(상자 15.43/9.40, descent 6.03) + Menlo 10pt(15.13/11.03)
        /// 줄의 상자는 15.43/11.03이라 `j`가 상자 아래로 1.63pt 새는데 종전 산식은 0이었다
        /// (PR 리뷰: 그 글자 위의 탭이 뒤 블록의 링크를 열었다). 상한은 실제 새는 몫 이상이다.
        func testVerticalInkReachCoversMixedFontLines() throws {
            try skipUnlessOracleFonts()
            let papyrus = Self.font("Papyrus", 10)
            try XCTSkipUnless(CTFontGetDescent(papyrus) > 5, "Papyrus 없음")
            let string = NSMutableAttributedString(string: "j", attributes: Self.attributes("Papyrus", 10))
            string.append(NSAttributedString(string: "A", attributes: Self.attributes("Menlo", 10)))
            let line = try XCTUnwrap(Self.lines(Self.finish(string)).first)
            let metrics = HwpDrawnTextLayout.lineMetrics(of: line.line, in: string)
            let inkBelow = CTFontGetDescent(papyrus) - (metrics.boxHeight - metrics.baselineAnchor)
            expect(inkBelow).to(beGreaterThan(1.5))
            let reach = HwpHitTester.verticalInkReach(of: string)
            expect(reach.below).to(beGreaterThanOrEqualTo(inkBelow))
            expect(reach.below).to(beCloseTo(
                CTFontGetDescent(papyrus) - (Self.box("Menlo", 10).lineHeight - Self.box("Menlo", 10).baseline),
                within: 0.001
            ))
            expect(reach.above).to(beGreaterThanOrEqualTo(
                max(CTFontGetAscent(papyrus), CTFontGetAscent(Self.font("Menlo", 10))) - metrics.baselineAnchor
            ))
        }

        /// 문단 끝 상자는 문단마다 다르다 — Papyrus 두 문단을 이은 결합 문자열에서 마지막
        /// 문단의 끝 글꼴만 Menlo면 그 줄의 상자가 15.43/11.03이라 `j`가 1.63pt 새는데, 첫
        /// 문단의 끝 상자(Papyrus)만 보면 0이다 (두 번째 PR 리뷰). 모든 끝 상자를 훑는다.
        func testVerticalInkReachCoversEveryParagraphEndBox() throws {
            try skipUnlessOracleFonts()
            let papyrus = Self.font("Papyrus", 10)
            try XCTSkipUnless(CTFontGetDescent(papyrus) > 5, "Papyrus 없음")
            let text = Self.attributes("Papyrus", 10)
            let first = Self.finish(
                NSMutableAttributedString(string: "j\n", attributes: text),
                endBox: Self.box("Papyrus", 10)
            )
            let last = Self.finish(
                NSMutableAttributedString(string: "j", attributes: text), endBox: Self.box("Menlo", 10)
            )
            let combined = NSMutableAttributedString(attributedString: first)
            combined.append(last)
            let lines = Self.lines(combined)
            expect(lines.count) == 2
            guard let lastLine = lines.last else { return }
            let metrics = HwpDrawnTextLayout.lineMetrics(of: lastLine.line, in: combined)
            let inkBelow = CTFontGetDescent(papyrus) - (metrics.boxHeight - metrics.baselineAnchor)
            expect(inkBelow).to(beGreaterThan(1.5))
            let reach = HwpHitTester.verticalInkReach(of: combined)
            expect(reach.below).to(beGreaterThanOrEqualTo(inkBelow))
            // 첫 문단만 그리면 Papyrus 상자뿐이라 새는 몫이 없다.
            expect(HwpHitTester.verticalInkReach(of: first).below).to(beCloseTo(0, within: 0.001))
        }

        /// 한글 2007 호환 문서(`hwp200X`)는 **장식선만** 갈린다 (#210) — 줄 상자·베이스라인·
        /// 전진량은 키 없는 한글 문서와 같다. 이 축까지 갈리면 쪽 나눔이 흔들리므로 비대칭을
        /// 여기서 잠근다 (#194의 갈래 판정은 `msWord` 전용이다).
        func testHwp2007KeyKeepsTheNativeVerticalLayout() {
            let text = "가나다라마바사아자차카타파하"
            var compatAttributes = Self.attributes("Apple SD Gothic Neo", 10, msWord: false)
            compatAttributes[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                value: HwpCompatibleDocumentTarget.hwp200X.rawValue
            )
            let compat = Self.lines(Self.finish(NSMutableAttributedString(
                string: text, attributes: compatAttributes
            )), width: 70)
            let native = Self.lines(Self.finish(NSMutableAttributedString(
                string: text,
                attributes: Self.attributes("Apple SD Gothic Neo", 10, msWord: false)
            )), width: 70)
            expect(compat.count) == native.count
            guard compat.count == native.count else { return }
            for (index, line) in compat.enumerated() {
                expect(line.baselineOrigin.y).to(
                    beCloseTo(native[index].baselineOrigin.y, within: 0.001),
                    description: "줄 \(index) 베이스라인"
                )
            }
        }
    }
#endif
