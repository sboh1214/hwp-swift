import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 한글 줄 **전진량** 규칙 자체의 계약 (#180·#192·#198) — `HwpLineSpacingRule`.
    ///
    /// 오라클은 한글 12.30.0 (2026-09-15) 이 함초롬바탕 10pt 문서에서 저장한 줄 캐시
    /// (`vertsize` + `spacing`) 다 (`LineBoxFixtures.hangulTextLineTable`): 비율 100·160·300% →
    /// 10·16·30, 고정 5·16·30 → 5·16·30 (고정 5는 줄이 겹친다), 여백만 0·3·10 → 10·13·20, 최소
    /// 5·16·30 → 10·16·30, 비율 80% → 8. 30pt 글자처럼 취급 개체가 든 10pt 줄은 비율 160% → 36
    /// (48이 아니다 — 비율 여분은 글자 상자 기준이다), 여백만 3 → 33, 최소 16 → 30, 고정 16 → 16.
    final class HwpLineSpacingRuleTests: XCTestCase {
        private typealias Rule = HwpLineSpacingRule
        private typealias Fixtures = LineBoxFixtures

        /// 글자 줄의 전진량 표 — 비율은 상자 × p/100, 고정은 값 그대로 (상자보다 작아도),
        /// 여백만은 상자 + 값, 최소는 max(상자, 값).
        func testAdvanceTableMatchesHangulForTextLines() {
            for row in Fixtures.hangulTextLineTable {
                expect(row.rule.advance(textBoxHeight: 10, objectHeight: 0))
                    .to(equal(row.expected), description: row.label)
            }
        }

        /// 개체가 상자를 정한 줄 — 비율의 여분은 **글자 상자** 기준이라 30pt 개체가 든 10pt 줄은
        /// 160%에서 36이지 48이 아니다 (실물 캐시: `CCL` 40.87pt 로고 줄 `spacing` 600 = 10pt ×
        /// 0.6). 여백만·최소·고정은 상자(= max(글자, 개체))에 그대로 적용한다. 글자보다 작은
        /// 개체는 상자를 바꾸지 않는다.
        func testAdvanceOfObjectLinesAppliesThePercentShareToTheTextBox() {
            let table: [Fixtures.RuleCase<CGFloat>] = [
                .init(.percent, 160, 36), .init(.percent, 100, 30), .init(.marginOnly, 3, 33),
                .init(.atLeast, 16, 30), .init(.atLeast, 40, 40), .init(.fixed, 16, 16),
            ]
            for row in table {
                expect(row.rule.advance(textBoxHeight: 10, objectHeight: 30))
                    .to(equal(row.expected), description: row.label)
            }
            expect(Rule(kind: .percent, value: 160).advance(textBoxHeight: 10, objectHeight: 5))
                .to(equal(16))
        }

        /// 0·음수 전진량은 뒤 줄이 앞 줄 위로 올라가므로 1pt가 바닥이다 — 손상 문서의 고정 0·
        /// 비율 0·음수 여백과, 음수 상자(0으로 본다)까지.
        func testAdvanceIsFlooredAtOnePoint() {
            let floored: [Fixtures.RuleCase<(text: CGFloat, object: CGFloat)>] = [
                .init(.fixed, 0, (10, 0)), .init(.fixed, -5, (10, 0)), .init(.percent, 0, (10, 0)),
                .init(.marginOnly, -20, (10, 0)), .init(.percent, 160, (-5, 0)),
                .init(.atLeast, 0, (0, -3)),
            ]
            for row in floored {
                expect(row.rule.advance(
                    textBoxHeight: row.expected.text, objectHeight: row.expected.object
                )).to(equal(1), description: row.label)
            }
            // 바닥 바로 위는 그대로다.
            expect(Rule(kind: .fixed, value: 1.5).advance(textBoxHeight: 10, objectHeight: 0))
                .to(equal(1.5))
        }

        /// 문단 모양의 고정·최소·여백만 값은 표 43 여백 계열과 같은 1/2 단위(HWPUNIT × 2)라
        /// 반으로 나눈다 (#192: 한글 대화상자 고정 16pt → 저장값 3200). 비율은 % 그대로다.
        func testRuleFromParaShapeHalvesTheHwpUnitValues() {
            expect(Rule(paraShape: Fixtures.paraShape(kindRaw: 1, raw: 3200)))
                .to(equal(Rule(kind: .fixed, value: 16)))
            expect(Rule(paraShape: Fixtures.paraShape(kindRaw: 3, raw: 3200)))
                .to(equal(Rule(kind: .atLeast, value: 16)))
            expect(Rule(paraShape: Fixtures.paraShape(kindRaw: 2, raw: 600)))
                .to(equal(Rule(kind: .marginOnly, value: 3)))
            expect(Rule(paraShape: Fixtures.paraShape(kindRaw: 0, raw: 160)))
                .to(equal(Rule(kind: .percent, value: 160)))
            // 속성3이 없는 기본 문단 모양은 속성1 종류(비율)와 `lineSpacing` 160이다.
            expect(Rule(paraShape: CoreHwp.HwpParaShape()))
                .to(equal(Rule(kind: .percent, value: 160)))
            // `HwpParagraphLayout.lineSpacingRule(for:)`는 같은 init이다.
            let fixed = Fixtures.paraShape(kindRaw: 1, raw: 3200)
            expect(HwpParagraphLayout.lineSpacingRule(for: fixed))
                .to(equal(Rule(kind: .fixed, value: 16)))
        }

        /// `attributeValue`(NSArray [종류 raw, 값])는 `init?(attributeValue:)`로 되돌아오고,
        /// 형식이 다른 값은 nil이다.
        func testAttributeValueRoundTrips() {
            for row in Fixtures.hangulTextLineTable {
                expect(Rule(attributeValue: row.rule.attributeValue))
                    .to(equal(row.rule), description: row.label)
            }
            expect(Rule(attributeValue: nil)).to(beNil())
            expect(Rule(attributeValue: NSNumber(value: 160))).to(beNil())
            expect(Rule(attributeValue: [NSNumber(value: 0)] as NSArray)).to(beNil())
            expect(Rule(attributeValue: [NSNumber(value: 9), NSNumber(value: 16)] as NSArray))
                .to(beNil(), description: "모르는 종류")
            expect(Rule(attributeValue: ["percent", "160"] as NSArray)).to(beNil())
        }

        /// 규칙 표식이 없는 문자열(공개 `HwpPaintCommand.drawText` 호출자)은 CT 문단 스타일의
        /// 줄 높이 지정을 같은 상자 모델로 읽는다 — `lineHeightMultiple` → 비율,
        /// `minimumLineHeight` == `maximumLineHeight` → 고정, 하한만 → 최소,
        /// `lineSpacingAdjustment` → 여백만, 아무것도 없으면 비율 100%.
        /// `minimumLineSpacing`·`maximumLineSpacing`(줄 사이 간격의 CT 상·하한)은 무시한다.
        func testFallbackFromCoreTextStyleReadsTheLineHeightSpecifiers() {
            let table: [Fixtures.StyleCase<Rule>] = [
                .init("배수", [(.lineHeightMultiple, 1.6)], Rule(kind: .percent, value: 160)),
                .init("min = max", [(.minimumLineHeight, 16), (.maximumLineHeight, 16)],
                      Rule(kind: .fixed, value: 16)),
                .init("min만", [(.minimumLineHeight, 16)], Rule(kind: .atLeast, value: 16)),
                .init("min < max", [(.minimumLineHeight, 16), (.maximumLineHeight, 30)],
                      Rule(kind: .atLeast, value: 16)),
                .init("max만", [(.maximumLineHeight, 16)], Rule(kind: .percent, value: 100)),
                .init("간격", [(.lineSpacingAdjustment, 3)], Rule(kind: .marginOnly, value: 3)),
                .init("음수 간격", [(.lineSpacingAdjustment, -3)], Rule(kind: .percent, value: 100)),
                .init("상·하한만", [(.minimumLineSpacing, 8), (.maximumLineSpacing, 4)],
                      Rule(kind: .percent, value: 100)),
                .init("간격 + 상·하한", [(.lineSpacingAdjustment, 3), (.minimumLineSpacing, 8)],
                      Rule(kind: .marginOnly, value: 3)),
                .init("배수가 못박음보다 우선", [
                    (.lineHeightMultiple, 1.6), (.minimumLineHeight, 16), (.maximumLineHeight, 16),
                ], Rule(kind: .percent, value: 160)),
                .init("하한이 간격보다 우선", [(.minimumLineHeight, 16), (.lineSpacingAdjustment, 3)],
                      Rule(kind: .atLeast, value: 16)),
            ]
            for row in table {
                let rule = Rule.fallback(from: Fixtures.paragraphStyle(specs: row.specs))
                expect(rule.kind).to(equal(row.expected.kind), description: row.label)
                expect(Double(rule.value)).to(
                    beCloseTo(Double(row.expected.value), within: 0.0001), description: row.label
                )
            }
            expect(Rule.fallback(from: nil)).to(equal(Rule(kind: .percent, value: 100)))
        }

        /// 문자열의 규칙 — 표식(`hwp.lineSpacing`)이 있으면 CT 스타일보다 우선하고, 없으면 그
        /// 자리 스타일의 폴백이며, 빈 문자열은 비율 100%다.
        func testRuleInStringPrefersTheAttributeKeyOverTheStyle() {
            let style = Fixtures.paragraphStyle(specs: [(.lineHeightMultiple, 3)])
            let plain = Fixtures.uniformParagraph(specs: [(.lineHeightMultiple, 3)])
            expect(Rule.rule(in: plain, at: 0)).to(equal(Rule(kind: .percent, value: 300)))
            let keyed = Fixtures.applying(Rule(kind: .fixed, value: 5), style: style, to: plain)
            expect(Rule.rule(in: keyed, at: 0)).to(equal(Rule(kind: .fixed, value: 5)))
            expect(Rule.rule(in: keyed, at: keyed.length + 10))
                .to(equal(Rule(kind: .fixed, value: 5)), description: "범위 밖 위치는 끝으로 접는다")
            expect(Rule.rule(in: NSAttributedString(), at: 0))
                .to(equal(Rule(kind: .percent, value: 100)))
        }
    }

    /// 줄 전진량이 **줄 상자 모델**로 그려지고 재어지는지 (#180) — `HwpDrawnTextLayout.lines`와
    /// `HwpParagraphLayout.layout`이 `HwpLineAdvance.advances(of:in:)`를 공유한다.
    ///
    /// 줄바꿈 뒤 줄마다: 상자 = max(그 줄 글자들의 기본 크기, 개체 높이), 전진량 = 상자에 줄
    /// 간격 규칙 적용, baseline = 상자 상단 + 0.85 × 상자 (`HwpBaselineAnchorTests`). 첫 상자
    /// 상단은 블록 상단이고 다음 상자 상단은 앞 상자 상단 + 전진량이며, 줄이 실제 문단을
    /// 끝내면 문단 아래 간격 + 다음 문단 위 간격이 더해진다. CT 줄 origin·슬롯·글꼴 지표는
    /// 세로 배치에 관여하지 않는다 — 종전 구현은 CT 슬롯을 복원해 상자를 타일하느라 글꼴
    /// 지표·못박은 높이보다 큰 글자·프레임 첫 슬롯 특례가 전진량에 남았다 (#198·#202).
    final class HwpLineBoxAdvanceTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures

        /// 균일한 10pt 문단은 줄마다 규칙 전진량 그대로 내려간다 — 한글 실측 표 전부.
        func testUniformParagraphLinesAdvanceByTheRule() {
            for row in Fixtures.hangulTextLineTable {
                let baselines = Fixtures.baselines(
                    Fixtures.uniformParagraph(rule: row.rule), lineWidth: Fixtures.paragraphWidth
                )
                expect(baselines.count).to(beGreaterThan(2), description: row.label)
                let expected = Fixtures.expectedBaselines(
                    boxes: Array(repeating: 10, count: baselines.count),
                    advances: Array(repeating: row.expected, count: baselines.count)
                )
                expect(baselines).to(beCloseTo(expected, within: 0.001), description: row.label)
            }
        }

        /// 전진량은 글꼴 지표와 무관하다 — ascent가 크거나(Times) 작은(Menlo) 글꼴, 한글
        /// 글꼴 모두 같은 자리다. 종전 구현은 leading이 있는 글꼴에서 상자가 그만큼 어긋났다.
        func testAdvanceDoesNotDependOnTheFont() {
            let rule = Fixtures.rule(.percent, 160)
            let reference = Fixtures.baselines(Fixtures.mixedSizeParagraph(rule: rule))
            expect(reference).to(equal(Fixtures.expectedBaselines(
                boxes: [10, 40, 10], advances: [16, 64, 16]
            )))
            for name in ["Times New Roman", "Menlo", "Apple SD Gothic Neo", "Hiragino Sans"] {
                expect(Fixtures.baselines(Fixtures.mixedSizeParagraph(rule: rule, fontName: name)))
                    .to(beCloseTo(reference, within: 0.001), description: name)
            }
        }

        /// 규칙 표식이 없는 문자열은 CT 스타일의 폴백 규칙으로 같은 자리에 그려진다 — 못박음은
        /// 고정, 배수는 비율, 간격은 여백만, 상·하한만은 비율 100%. 표식이 있으면 표식이 이긴다.
        func testCoreTextStyleOnlyStringFallsBackToTheSameAdvances() {
            let table: [Fixtures.StyleCase<CGFloat>] = [
                .init("못박음 16", [(.minimumLineHeight, 16), (.maximumLineHeight, 16)], 16),
                .init("배수 1.6", [(.lineHeightMultiple, 1.6)], 16),
                .init("간격 3", [(.lineSpacingAdjustment, 3)], 13),
                .init("하한 16", [(.minimumLineHeight, 16)], 16),
                .init("상·하한만", [(.minimumLineSpacing, 8), (.maximumLineSpacing, 4)], 10),
            ]
            for row in table {
                let baselines = Fixtures.baselines(
                    Fixtures.uniformParagraph(specs: row.specs), lineWidth: Fixtures.paragraphWidth
                )
                expect(baselines.count).to(beGreaterThan(2), description: row.label)
                expect(baselines).to(beCloseTo(Fixtures.expectedBaselines(
                    boxes: Array(repeating: 10, count: baselines.count),
                    advances: Array(repeating: row.expected, count: baselines.count)
                ), within: 0.001), description: row.label)
            }
            let keyed = Fixtures.baselines(
                Fixtures.uniformParagraph(
                    rule: Fixtures.rule(.fixed, 5), specs: [(.lineHeightMultiple, 3)]
                ),
                lineWidth: Fixtures.paragraphWidth
            )
            expect(keyed).to(beCloseTo(Fixtures.expectedBaselines(
                boxes: Array(repeating: 10, count: keyed.count),
                advances: Array(repeating: 5, count: keyed.count)
            ), within: 0.001))
        }

        /// 크기가 섞인 문단은 **줄마다** 자기 상자로 전진한다 (한글 실측: 10·40·10pt 줄 —
        /// 여백만 0 → 10·40·10, 최소 16 → 16·40·16, 고정 16 → 16·16·16, 비율 160 → 16·64·16).
        /// 고정 16에서는 40pt 줄이 상자보다 작게 전진해 그 baseline이 **다음 줄 baseline보다
        /// 아래**에 놓인다 — 한글도 그렇게 겹친다.
        func testMixedSizeParagraphUsesPerLineBoxes() {
            let table: [Fixtures.RuleCase<[CGFloat]>] = [
                .init(.marginOnly, 0, [10, 40, 10]), .init(.atLeast, 16, [16, 40, 16]),
                .init(.fixed, 16, [16, 16, 16]), .init(.percent, 160, [16, 64, 16]),
                .init(.percent, 100, [10, 40, 10]),
            ]
            for row in table {
                expect(Fixtures.baselines(Fixtures.mixedSizeParagraph(rule: row.rule))).to(
                    equal(Fixtures.expectedBaselines(boxes: [10, 40, 10], advances: row.expected)),
                    description: row.label
                )
            }
            let overlapped = Fixtures.baselines(
                Fixtures.mixedSizeParagraph(rule: Fixtures.rule(.fixed, 16))
            )
            expect(overlapped).to(equal([108.5, 150, 140.5]))
            expect(overlapped[1]).to(beGreaterThan(overlapped[2]), description: "40pt 줄이 겹친다")
        }

        /// 상대크기 run(기본 10pt·조판 25pt)의 줄 상자는 **기본 크기**다 — 글리프가 상자를
        /// 넘쳐도 전진량은 10 (비율 100%)·16 (160%) 이다 (한글 실측: 상대크기 줄의
        /// `vertsize` 1000). 기본 크기 표식이 없으면 조판 크기 25로 떨어진다.
        func testRelativeSizeRunKeepsTheBaseSizeBox() {
            let relative: [(size: CGFloat, baseSize: CGFloat?)] = [(25, 10), (25, 10), (25, 10)]
            expect(Fixtures.baselines(Fixtures.threeLineParagraph(
                sizes: relative, rule: Fixtures.rule(.percent, 100)
            ))).to(equal([108.5, 118.5, 128.5]))
            expect(Fixtures.baselines(Fixtures.threeLineParagraph(
                sizes: relative, rule: Fixtures.rule(.percent, 160)
            ))).to(equal([108.5, 124.5, 140.5]))
            let unmarked: [(size: CGFloat, baseSize: CGFloat?)] = [(25, nil), (25, nil), (25, nil)]
            expect(Fixtures.baselines(Fixtures.threeLineParagraph(
                sizes: unmarked, rule: Fixtures.rule(.percent, 100)
            ))).to(equal([121.25, 146.25, 171.25]))
        }

        /// 30pt 글자처럼 취급 개체가 든 10pt 줄 — 상자는 30이고 전진량은 비율 160 → 36
        /// (여분은 글자 상자 10 기준), 여백만 3 → 33, 최소 16 → 30, 고정 16 → 16 (한글 실측).
        /// 첫 줄에 있어도 같다.
        func testObjectLinesAdvanceByTheRule() {
            let table: [Fixtures.RuleCase<[CGFloat]>] = [
                .init(.percent, 160, [16, 36, 16]), .init(.marginOnly, 3, [13, 33, 13]),
                .init(.atLeast, 16, [16, 30, 16]), .init(.fixed, 16, [16, 16, 16]),
                .init(.percent, 100, [10, 30, 10]),
            ]
            for row in table {
                expect(Fixtures.baselines(Fixtures.objectParagraph(rule: row.rule))).to(
                    equal(Fixtures.expectedBaselines(boxes: [10, 30, 10], advances: row.expected)),
                    description: row.label
                )
            }
            expect(Fixtures.baselines(
                Fixtures.objectParagraph(rule: Fixtures.rule(.percent, 160), onFirstLine: true)
            )).to(equal(Fixtures.expectedBaselines(boxes: [30, 10, 10], advances: [36, 16, 16])))
        }

        /// 문단 사이 간격은 **실제 문단 경계**(표식 없는 LF)에서만 들어간다 — 앞 문단 아래 10 +
        /// 뒤 문단 위 10 = 20. 한 줄 끝(`hwp.lineBreak`)은 CT에는 문단 구분자지만 한글에서는
        /// 같은 문단의 줄 나눔이라 간격 없이 16 그대로다 (2026-09-15 한글 12.30 실측).
        func testParagraphGapAppliesOnlyAtARealParagraphBoundary() {
            let rule = Fixtures.rule(.percent, 160)
            let spacing = Fixtures.Spacing(before: 10, after: 10)
            expect(Fixtures.baselines(Fixtures.twoParagraphs(
                rule: rule, first: spacing, second: spacing
            ))).to(equal(Fixtures.expectedBaselines(
                boxes: [10, 10], advances: [16, 16], gaps: [20]
            )))
            expect(Fixtures.baselines(Fixtures.twoParagraphs(
                rule: rule, first: spacing, second: spacing, marked: true
            ))).to(equal(Fixtures.expectedBaselines(boxes: [10, 10], advances: [16, 16])))
        }

        /// 간격은 줄 **자신의 문단**에서 아래 간격을, **다음 줄의 문단**에서 위 간격을 읽는다
        /// (컨테이너 블록이 문단들을 LF로 이으면 문단마다 자기 스타일이 붙는다) — 앞 문단의
        /// 위 간격과 뒤 문단의 아래 간격은 이 경계의 것이 아니다. 음수 간격은 0으로 본다.
        func testParagraphGapReadsEachSideFromItsOwnParagraph() {
            let rule = Fixtures.rule(.percent, 160)
            let twoLines: (CGFloat) -> [Double] = { gap in
                Fixtures.expectedBaselines(boxes: [10, 10], advances: [16, 16], gaps: [gap])
            }
            expect(Fixtures.baselines(Fixtures.twoParagraphs(
                rule: rule,
                first: Fixtures.Spacing(before: 99, after: 6),
                second: Fixtures.Spacing(before: 4, after: 99)
            ))).to(equal(twoLines(10)))
            expect(Fixtures.baselines(Fixtures.twoParagraphs(
                rule: rule,
                first: Fixtures.Spacing(before: 0, after: -10),
                second: Fixtures.Spacing(before: -10, after: 0)
            ))).to(equal(twoLines(0)))
            expect(Fixtures.baselines(Fixtures.twoParagraphs(
                rule: rule,
                first: Fixtures.Spacing(before: 0, after: -10),
                second: Fixtures.Spacing(before: 4, after: 0)
            ))).to(equal(twoLines(4)))
        }

        /// 측정(`HwpParagraphLayout.layout`)과 렌더가 같은 자리에 줄을 놓는다 — 줄 프레임의
        /// `origin.y`는 첫 상자 상단 기준 상자 상단, `baseline`은 앵커이고, 문단 높이는 위 간격 +
        /// 전진량 합(마지막 줄의 줄 간격 몫 포함 — 한글 캐시의 `lineHeight + lineSpacing`) +
        /// 아래 간격이다. 입력은 `attachParagraphStyle`이 단 문단 스타일 + 규칙 표식이다.
        func testMeasurementMatchesRenderForAMixedSizeParagraph() {
            let table: [Fixtures.RuleCase<[CGFloat]>] = [
                .init(.percent, 160, [16, 64, 16]), .init(.fixed, 16, [16, 16, 16]),
                .init(.atLeast, 16, [16, 40, 16]), .init(.marginOnly, 3, [13, 43, 13]),
            ]
            for row in table {
                expectMeasurementMatchesRender(
                    Fixtures.mixedSizeParagraph(), boxes: [10, 40, 10], row: row
                )
            }
        }

        /// 개체 문단도 같다 — 개체 줄의 프레임은 개체 앵커를 내고, 그 줄 baseline은 개체 상단 +
        /// 0.85 × 개체 높이다.
        func testMeasurementMatchesRenderForAnObjectParagraph() {
            let table: [Fixtures.RuleCase<[CGFloat]>] = [
                .init(.percent, 160, [16, 36, 16]), .init(.fixed, 16, [16, 16, 16]),
                .init(.atLeast, 16, [16, 30, 16]), .init(.marginOnly, 3, [13, 33, 13]),
            ]
            for row in table {
                let frame = expectMeasurementMatchesRender(
                    Fixtures.objectParagraph(), boxes: [10, 30, 10], row: row
                )
                expect(frame.lines.map(\.inlineAnchors.count)).to(equal([0, 1, 0]))
                expect(frame.lines.dropFirst().first?.inlineAnchors.first?.ascent).to(equal(30))
            }
        }

        /// slight-overflow 한 줄(개행 없이 폭을 허용 배율 이내로 넘는 문단)도 같은 규칙이다 —
        /// 렌더는 한 줄로 그리고 측정은 위 간격 + 그 줄 전진량 + 아래 간격이다.
        func testSlightOverflowSingleLineUsesTheSameAdvance() {
            let string = NSAttributedString(
                string: "Lorem ipsum dolor", attributes: Fixtures.attributes(size: 10)
            )
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(string), nil, nil, nil
            ))
            let width = natural * 0.98
            let shape = Fixtures.paraShape(
                rule: Fixtures.rule(.fixed, 5), spacing: Fixtures.Spacing(before: 6, after: 4)
            )
            let styled = NSMutableAttributedString(attributedString: string)
            HwpParagraphLayout.attachParagraphStyle(to: styled, paraShape: shape)
            let frame = HwpParagraphLayout().layout(
                attributedString: styled, paraShape: shape, columnWidth: width
            )
            expect(frame.lines.count).to(equal(1))
            expect(frame.lines.first?.baseline).to(equal(8.5))
            expect(Double(frame.totalHeight)).to(beCloseTo(6 + 5 + 4, within: 0.001))
            expect(Fixtures.baselines(styled, lineWidth: width)).to(equal([108.5]))
        }

        /// 청크 예산(`maxLineFrames`)은 줄을 옮기지 않는다 — 예산은 청크마다 문자를 그만큼
        /// 잘라 조판하고 줄 수도 거기서 자르므로, 예산 k의 결과는 전체 조판의 앞 min(k, 줄 수)
        /// 줄과 같은 자리여야 한다. 개체 줄·크기 변화·문단 경계(간격 20)가 청크 경계에 걸려도
        /// 다음 청크 첫 상자 상단은 앞 청크 마지막 상자 상단 + 그 줄 전진량(+ 간격)이다.
        func testChunkBudgetDoesNotMoveLines() {
            let string = Fixtures.combinedParagraphs()
            let whole = Fixtures.baselines(string)
            expect(whole).to(equal(Fixtures.expectedBaselines(
                boxes: [10, 40, 30, 10, 10, 10], advances: [16, 64, 36, 16, 16, 16],
                gaps: [0, 0, 0, 20]
            )))
            for budget in [2, 3, 4, 5, 7, 9] {
                let chunked = Fixtures.baselines(string, maxLineFrames: budget)
                let label = "예산 \(budget)"
                expect(chunked.count).to(equal(min(budget, whole.count)), description: label)
                expect(chunked).to(equal(Array(whole.prefix(chunked.count))), description: label)
            }
        }

        /// 한 줄 끝 + 빈 줄 앵커(`ab⏎␠`)로 끝나는 문단은 마지막 빈 줄을 한 전진량 아래에 둔다 —
        /// 문단 위/아래 간격이 있어도 한 줄 끝이라 사이에 간격이 들어가지 않고, 측정 높이는
        /// 위 간격 + 두 줄 전진량 + 아래 간격이다.
        func testTrailingLineBreakPlacesTheEmptyLineOneAdvanceBelow() {
            let rule = Fixtures.rule(.percent, 160)
            let spacing = Fixtures.Spacing(before: 10, after: 10)
            expect(Fixtures.baselines(Fixtures.trailingEmptyLineParagraph(rule: rule)))
                .to(equal([108.5, 124.5]))
            expect(Fixtures.baselines(
                Fixtures.trailingEmptyLineParagraph(rule: rule, spacing: spacing)
            )).to(equal([108.5, 124.5]))
            let shape = Fixtures.paraShape(rule: rule, spacing: spacing)
            let styled = NSMutableAttributedString(
                attributedString: Fixtures.trailingEmptyLineParagraph()
            )
            HwpParagraphLayout.attachParagraphStyle(to: styled, paraShape: shape)
            let frame = HwpParagraphLayout().layout(
                attributedString: styled, paraShape: shape, columnWidth: Fixtures.wideWidth
            )
            expect(frame.lines.map(\.origin.y)).to(equal([0, 16]))
            expect(frame.lines.map(\.baseline)).to(equal([8.5, 8.5]))
            expect(Double(frame.totalHeight)).to(beCloseTo(10 + 16 + 16 + 10, within: 0.001))
        }

        /// 측정 ≡ 렌더 공유 단언 — `string`에 `row.rule`·위 6pt·아래 4pt 문단 모양을
        /// `attachParagraphStyle`로 달아 재고 그린다. 렌더 baseline = 블록 상단 + 프레임 상자
        /// 상단 + 앵커, 앵커 = 0.85 × 상자, 문단 높이 = 6 + Σ전진량(`row.expected`) + 4.
        @discardableResult
        private func expectMeasurementMatchesRender(
            _ string: NSAttributedString,
            boxes: [CGFloat],
            row: Fixtures.RuleCase<[CGFloat]>
        ) -> HwpParagraphFrame {
            let shape = Fixtures.paraShape(
                rule: row.rule, spacing: Fixtures.Spacing(before: 6, after: 4)
            )
            let styled = NSMutableAttributedString(attributedString: string)
            HwpParagraphLayout.attachParagraphStyle(to: styled, paraShape: shape)
            let frame = HwpParagraphLayout().layout(
                attributedString: styled, paraShape: shape, columnWidth: Fixtures.wideWidth
            )
            let drawn = Fixtures.baselines(styled)
            let label = row.label
            expect(frame.lines.count).to(equal(boxes.count), description: label)
            expect(drawn).to(
                equal(Fixtures.expectedBaselines(boxes: boxes, advances: row.expected)),
                description: label
            )
            expect(frame.lines.map { Double(Fixtures.blockTop + $0.origin.y + $0.baseline) })
                .to(beCloseTo(drawn, within: 0.001), description: label)
            expect(frame.lines.map(\.baseline)).to(
                equal(boxes.map { $0 * HwpRenderTuning.Text.baselineAnchorRatio }),
                description: label
            )
            expect(Double(frame.totalHeight)).to(
                beCloseTo(Double(6 + row.expected.reduce(0, +) + 4), within: 0.001),
                description: label
            )
            return frame
        }
    }
#endif
