import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import XCTest

#if canImport(CoreText)
    /// 줄 전진량 가드들(`HwpLineSpacingRuleTests`·`HwpLineBoxAdvanceTests`)이 공유하는 조판
    /// 입력 빌더 (#180).
    ///
    /// 한글의 줄 상자 모델에서 전진량은 글꼴 지표(ascent·descent·leading)와 무관하다 — 그래서
    /// 입력은 Helvetica로 조판하되 기대값은 한글 12.30이 함초롬바탕 10pt 문서에서 저장한 줄
    /// 캐시(`vertsize`·`spacing`) 값을 그대로 쓴다 (2026-09-15 실측).
    ///
    /// 문단 안의 줄 나눔은 프로덕션과 같이 **한 줄 끝 run**(`lineBreak`, 코드 10)으로 낸다 —
    /// 표식 없는 LF는 CT 문단 구분자라 문단 사이 간격이 들어가므로 (`HwpLineAdvance.paragraphGap`)
    /// 문단 **사이**에만 쓴다 (`twoParagraphs`·`combinedParagraphs`).
    enum LineBoxFixtures {
        /// 블록 상단 — 렌더 입력의 `origin.y`. 첫 줄 상자 상단이 여기에 핀된다.
        static let blockTop: CGFloat = 100
        /// 균일 문단이 여러 줄로 접히는 폭
        static let paragraphWidth: CGFloat = 70
        /// 한 줄 문단이 접히지 않는 폭
        static let wideWidth: CGFloat = 400

        static func rule(_ kind: HwpLineSpacingRule.Kind, _ value: CGFloat) -> HwpLineSpacingRule {
            HwpLineSpacingRule(kind: kind, value: value)
        }

        // MARK: 표 형식 가드의 행

        /// 규칙 하나와 그 기대값 (전진량 하나·줄별 전진량 열·…)
        struct RuleCase<Expected> {
            let rule: HwpLineSpacingRule
            let expected: Expected

            init(_ kind: HwpLineSpacingRule.Kind, _ value: CGFloat, _ expected: Expected) {
                rule = HwpLineSpacingRule(kind: kind, value: value)
                self.expected = expected
            }

            var label: String {
                "\(rule.kind) \(rule.value)"
            }
        }

        /// CT 문단 스타일 스펙 목록과 그 기대값 — 규칙 표식이 없는 문자열의 폴백 가드
        struct StyleCase<Expected> {
            let label: String
            let specs: [(CTParagraphStyleSpecifier, CGFloat)]
            let expected: Expected

            init(
                _ label: String,
                _ specs: [(CTParagraphStyleSpecifier, CGFloat)],
                _ expected: Expected
            ) {
                self.label = label
                self.specs = specs
                self.expected = expected
            }
        }

        /// 한글 12.30 실측 표 — 10pt 글자 줄의 (규칙, 전진량): 비율 100·160·300·80% →
        /// 10·16·30·8, 고정 5·16·30 → 5·16·30, 여백만 0·3·10 → 10·13·20, 최소 5·16·30 → 10·16·30.
        static let hangulTextLineTable: [RuleCase<CGFloat>] = [
            RuleCase(.percent, 100, 10), RuleCase(.percent, 160, 16),
            RuleCase(.percent, 300, 30), RuleCase(.percent, 80, 8),
            RuleCase(.fixed, 5, 5), RuleCase(.fixed, 16, 16), RuleCase(.fixed, 30, 30),
            RuleCase(.marginOnly, 0, 10), RuleCase(.marginOnly, 3, 13),
            RuleCase(.marginOnly, 10, 20),
            RuleCase(.atLeast, 5, 10), RuleCase(.atLeast, 16, 16), RuleCase(.atLeast, 30, 30),
        ]

        // MARK: run 재료

        /// 글자 run 속성 — 조판 글꼴과 **상대크기 적용 전 기본 크기**(`hwp.baseFontSize`).
        /// `baseSize`가 없으면 조판 크기가 곧 기본 크기다.
        static func attributes(
            size: CGFloat,
            baseSize: CGFloat? = nil,
            style: CTParagraphStyle? = nil,
            fontName: String = "Helvetica"
        ) -> [NSAttributedString.Key: Any] {
            var attributes = fontOnlyAttributes(size: size, style: style, fontName: fontName)
            attributes[HwpAttributedStringKey.baseFontSize] = NSNumber(
                value: Double(baseSize ?? size)
            )
            return attributes
        }

        /// 기본 크기 표식이 **없는** 글자 run 속성 — 공개 `HwpPaintCommand.drawText` 호출자가
        /// 문자열을 그대로 넘기는 경로. 줄 상자는 조판 글꼴 크기로 떨어진다.
        static func fontOnlyAttributes(
            size: CGFloat,
            style: CTParagraphStyle? = nil,
            fontName: String = "Helvetica"
        ) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName(fontName as CFString, size, nil),
            ]
            if let style {
                attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] = style
            }
            return attributes
        }

        /// 글자처럼 취급 개체 마커 — 개체 높이만큼 줄 공간을 예약하는 run delegate를 단 U+FFFC
        /// (`HwpInlineObjectReservation`). 마커도 자기 글자 모양(`attributes`)을 싣는다.
        static func objectMarker(
            height: CGFloat, attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            var marker = attributes
            if let delegate = HwpInlineObjectReservation.runDelegate(width: 20, height: height) {
                marker[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
            }
            // 측정 경로(`inlineAnchors`)가 개체 앵커를 내려면 컨트롤 서수가 있어야 한다.
            marker[HwpAttributedStringKey.controlIndex] = NSNumber(value: 0)
            return NSAttributedString(string: "\u{FFFC}", attributes: marker)
        }

        /// 한 줄 끝(코드 10) run — LF에 `hwp.lineBreak` 표식
        /// (`HwpTextRunBuilder.appendLineBreak`와 같은 꼴). CT에는 문단 구분자지만 한글에서는
        /// 같은 문단의 줄 나눔이라 문단 사이 간격이 들어가지 않는다.
        static func lineBreak(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
            var marked = attributes
            marked[HwpAttributedStringKey.lineBreak] = NSNumber(value: true)
            return NSAttributedString(string: "\u{000A}", attributes: marked)
        }

        /// 빈 줄 앵커 — 한 줄 끝으로 끝난 문단의 마지막 빈 줄을 살리는 빈칸 (#137·#145,
        /// `HwpTextRunBuilder.finishEmptyLastLineAnchor`와 같은 꼴).
        static func emptyLineAnchor(
            attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            var marked = attributes
            marked[HwpAttributedStringKey.emptyLineAnchor] = true
            return NSAttributedString(string: " ", attributes: marked)
        }

        /// 스펙 목록을 그대로 싣는 문단 스타일 (비면 스타일 없음)
        static func paragraphStyle(
            specs values: [(CTParagraphStyleSpecifier, CGFloat)],
            justified: Bool = false
        ) -> CTParagraphStyle? {
            guard !values.isEmpty || justified else { return nil }
            var alignment = justified ? CTTextAlignment.justified : .natural
            var numbers = values.map(\.1)
            return numbers.withUnsafeMutableBufferPointer { buffer in
                withUnsafeMutablePointer(to: &alignment) { alignmentPointer in
                    var settings = values.indices.map { index in
                        CTParagraphStyleSetting(
                            spec: values[index].0,
                            valueSize: MemoryLayout<CGFloat>.size,
                            // swiftlint:disable:next force_unwrapping
                            value: buffer.baseAddress! + index
                        )
                    }
                    settings.append(CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ))
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }

        /// 문자열 전체에 줄 간격 규칙(`hwp.lineSpacing`)과 문단 스타일을 단다 — 둘 다 nil이면
        /// 규칙은 폴백(비율 100%)이다.
        static func applying(
            _ rule: HwpLineSpacingRule?,
            style: CTParagraphStyle? = nil,
            to string: NSAttributedString
        ) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: string)
            let range = NSRange(location: 0, length: output.length)
            if let rule {
                output.addAttribute(
                    HwpAttributedStringKey.lineSpacing, value: rule.attributeValue, range: range
                )
            }
            if let style {
                output.addAttribute(
                    kCTParagraphStyleAttributeName as NSAttributedString.Key,
                    value: style, range: range
                )
            }
            return output
        }

        // MARK: 문단

        /// 한 줄 끝으로 나뉜 세 줄(`ab`·`cd`·`ef`) 문단 — 줄마다 (조판 크기, 기본 크기).
        /// 기본 크기가 nil인 줄은 표식 없이 조판 글꼴 크기로 떨어진다.
        static func threeLineParagraph(
            sizes: [(size: CGFloat, baseSize: CGFloat?)],
            rule: HwpLineSpacingRule? = nil,
            fontName: String = "Helvetica"
        ) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for (index, text) in ["ab", "cd", "ef"].enumerated() {
                let spec = sizes[index]
                // 지역 이름을 정적 헬퍼(`attributes(size:)`)와 다르게 둔다 — 같은 이름의 지역
                // 변수를 선언하는 식 안에서 그 헬퍼를 부르면 CI 툴체인이 클로저 안의 호출을
                // 선언 중인 딕셔너리로 풀어 "cannot call value of non-function type"이 난다.
                let runAttributes = spec.baseSize.map {
                    Self.attributes(size: spec.size, baseSize: $0, fontName: fontName)
                } ?? Self.fontOnlyAttributes(size: spec.size, fontName: fontName)
                output.append(NSAttributedString(string: text, attributes: runAttributes))
                if index < 2 {
                    output.append(lineBreak(attributes: runAttributes))
                }
            }
            return applying(rule, to: output)
        }

        /// 10pt·40pt·10pt 세 줄 문단 — 줄마다 상자가 다른 문단 (한글 실측의 혼합 크기 문단과
        /// 같은 꼴: 캐시 `vertsize` 1000·4000·1000).
        static func mixedSizeParagraph(
            rule: HwpLineSpacingRule? = nil, fontName: String = "Helvetica"
        ) -> NSAttributedString {
            threeLineParagraph(
                sizes: [(10, 10), (40, 40), (10, 10)], rule: rule, fontName: fontName
            )
        }

        /// 한 종류 글자로만 된 여러 줄 문단 — `paragraphWidth`에서 여러 줄로 접혀 줄마다 상자가
        /// 같아 간격 규칙만 드러난다.
        static func uniformParagraph(
            rule: HwpLineSpacingRule? = nil,
            specs: [(CTParagraphStyleSpecifier, CGFloat)] = [],
            fontName: String = "Helvetica",
            repeats: Int = 3
        ) -> NSAttributedString {
            let string = NSAttributedString(
                string: String(repeating: "Lorem ipsum dolor ", count: repeats),
                attributes: attributes(size: 10, fontName: fontName)
            )
            return applying(rule, style: paragraphStyle(specs: specs), to: string)
        }

        /// 10pt 세 줄 문단의 한 줄에 `objectHeight`pt 글자처럼 취급 개체가 든 문단 —
        /// 기본은 둘째 줄 끝(`cd▯`), `onFirstLine`이면 첫 줄 앞(`▯ab`).
        static func objectParagraph(
            rule: HwpLineSpacingRule? = nil,
            objectHeight: CGFloat = 30,
            onFirstLine: Bool = false
        ) -> NSAttributedString {
            let text = attributes(size: 10)
            let marker = objectMarker(height: objectHeight, attributes: text)
            let output = NSMutableAttributedString()
            if onFirstLine {
                output.append(marker)
            }
            output.append(NSAttributedString(string: "ab", attributes: text))
            output.append(lineBreak(attributes: text))
            output.append(NSAttributedString(string: "cd", attributes: text))
            if !onFirstLine {
                output.append(marker)
            }
            output.append(lineBreak(attributes: text))
            output.append(NSAttributedString(string: "ef", attributes: text))
            return applying(rule, to: output)
        }

        /// 문단 위/아래 간격 (pt)
        struct Spacing {
            var before: CGFloat = 0
            var after: CGFloat = 0
        }

        /// 10pt 두 문단(`ab`·`cd`) — 구분자는 표식 없는 LF(실제 문단 경계)이고, `marked`면
        /// 한 줄 끝 run이라 한 문단의 줄 나눔이다. 문단마다 자기 간격 스타일이 붙는다.
        static func twoParagraphs(
            rule: HwpLineSpacingRule? = nil,
            first: Spacing,
            second: Spacing,
            marked: Bool = false
        ) -> NSAttributedString {
            let firstAttributes = attributes(size: 10, style: paragraphStyle(specs: [
                (.paragraphSpacingBefore, first.before), (.paragraphSpacing, first.after),
            ]))
            let secondAttributes = attributes(size: 10, style: paragraphStyle(specs: [
                (.paragraphSpacingBefore, second.before), (.paragraphSpacing, second.after),
            ]))
            let output = NSMutableAttributedString(string: "ab", attributes: firstAttributes)
            output.append(
                marked
                    ? lineBreak(attributes: firstAttributes)
                    : NSAttributedString(string: "\n", attributes: firstAttributes)
            )
            output.append(NSAttributedString(string: "cd", attributes: secondAttributes))
            return applying(rule, to: output)
        }

        /// 한 줄 끝 + 빈 줄 앵커로 끝나는 10pt 문단 (`ab⏎␠`) — 문단 위/아래 간격을 같이 싣는다.
        static func trailingEmptyLineParagraph(
            rule: HwpLineSpacingRule? = nil, spacing: Spacing = Spacing()
        ) -> NSAttributedString {
            let text = attributes(size: 10, style: paragraphStyle(specs: [
                (.paragraphSpacingBefore, spacing.before), (.paragraphSpacing, spacing.after),
            ]))
            let output = NSMutableAttributedString(string: "ab", attributes: text)
            output.append(lineBreak(attributes: text))
            output.append(emptyLineAnchor(attributes: text))
            return applying(rule, to: output)
        }

        /// 컨테이너 블록이 문단 둘을 LF로 이은 꼴 (`HwpPaginator.combinedAttributedString`) —
        /// 앞 문단은 10·40·10(+30pt 개체)·10pt 네 줄이고 아래 간격 10pt, 뒤 문단은 10pt 두 줄이고
        /// 위 간격 10pt. 비율 160%. 줄 상자 `[10, 40, 30, 10, 10, 10]`, 전진량
        /// `[16, 64, 36, 16 + 20, 16, 16]`.
        static func combinedParagraphs() -> NSAttributedString {
            let firstStyle = paragraphStyle(specs: [(.paragraphSpacing, 10)])
            let secondStyle = paragraphStyle(specs: [(.paragraphSpacingBefore, 10)])
            let small = attributes(size: 10, style: firstStyle)
            let large = attributes(size: 40, style: firstStyle)
            let output = NSMutableAttributedString(string: "ab", attributes: small)
            output.append(lineBreak(attributes: small))
            output.append(NSAttributedString(string: "cd", attributes: large))
            output.append(lineBreak(attributes: large))
            output.append(NSAttributedString(string: "ef", attributes: small))
            output.append(objectMarker(height: 30, attributes: small))
            output.append(lineBreak(attributes: small))
            output.append(NSAttributedString(string: "gh\n", attributes: small))
            let second = attributes(size: 10, style: secondStyle)
            output.append(NSAttributedString(string: "ij", attributes: second))
            output.append(lineBreak(attributes: second))
            output.append(NSAttributedString(string: "kl", attributes: second))
            return applying(rule(.percent, 160), to: output)
        }

        // MARK: 문단 모양

        /// 표 46 종류 raw 값과 저장값 그대로의 문단 모양 — 5.0.2.5 이상 필드(속성3·`lineSpacing2`)
        /// 를 채우고 정렬은 왼쪽. 문단 위/아래 간격은 표 43 계열 1/2 단위(HWPUNIT × 2)다.
        static func paraShape(
            kindRaw: UInt32, raw: UInt32, before: Int32 = 0, after: Int32 = 0
        ) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                hwpxProperty1: kindRaw | (1 << 2), marginLeft: 0, marginRight: 0, indent: 0,
                paragraphSpacingTop: before, paragraphSpacingBottom: after,
                lineSpacing: Int32(raw), tabDefId: 0, numberingOrBulletId: 0, borderFillId: 0,
                borderSpacingLeft: 0, borderSpacingRight: 0, borderSpacingTop: 0,
                borderSpacingBottom: 0, property3: kindRaw, lineSpacing2: raw
            )
        }

        /// 줄 간격 규칙과 문단 위/아래 간격(pt)을 실은 문단 모양 — 고정·최소·여백만 값과 문단
        /// 간격은 1/2 단위로 (pt × 200), 비율은 % 그대로 싣는다.
        static func paraShape(
            rule: HwpLineSpacingRule, spacing: Spacing = Spacing()
        ) -> CoreHwp.HwpParaShape {
            let raw = switch rule.kind {
            case .percent: UInt32(rule.value)
            case .fixed, .marginOnly, .atLeast: UInt32(rule.value * 200)
            }
            return paraShape(
                kindRaw: UInt32(rule.kind.rawValue), raw: raw,
                before: Int32(spacing.before * 200), after: Int32(spacing.after * 200)
            )
        }

        // MARK: 관찰

        /// 렌더가 그린 줄들의 baseline (top-down) — 블록 상단은 `blockTop`.
        static func baselines(
            _ string: NSAttributedString,
            lineWidth: CGFloat = wideWidth,
            maxLineFrames: Int = HwpParagraphLayout.maximumLineFrames
        ) -> [Double] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: blockTop),
                lineWidth: lineWidth, maxLineFrames: maxLineFrames
            ).map { Double($0.baselineOrigin.y) }
        }

        /// 줄 상자 모델의 기대 baseline — 첫 상자 상단은 `blockTop`, 다음 상자 상단은 앞 상자
        /// 상단 + 그 줄 전진량(+ 그 줄 뒤 문단 간격), baseline은 상자 상단 + 0.85 × 상자.
        static func expectedBaselines(
            boxes: [CGFloat], advances: [CGFloat], gaps: [CGFloat] = []
        ) -> [Double] {
            var top = blockTop
            return boxes.indices.map { index in
                let baseline = top + boxes[index] * HwpRenderTuning.Text.baselineAnchorRatio
                top += advances[index] + (index < gaps.count ? gaps[index] : 0)
                return Double(baseline)
            }
        }
    }
#endif
