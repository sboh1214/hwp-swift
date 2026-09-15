import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// HwpParagraphLayout의 문단 메트릭 (표 43/44/46 해석)

extension HwpParagraphLayout {
    struct ParagraphMetrics {
        var firstLineHeadIndent: CGFloat
        var headIndent: CGFloat
        var tailIndent: CGFloat
        var paragraphSpacingBefore: CGFloat
        var paragraphSpacing: CGFloat
        /// 문서 정의 탭 스톱 (표 36 탭 정의 — 위치는 표 43 계열 1/2 단위)
        var tabStops: [CTTextTab] = []

        /// 줄 전진량 규칙 (표 46 종류 + 값) — 측정·렌더가 줄바꿈 뒤 줄마다 이 규칙으로
        /// 전진량을 낸다 (`HwpLineAdvance`). 조판 문자열에는
        /// `HwpAttributedStringKey.lineSpacing`으로 실린다.
        var lineSpacingRule: HwpLineSpacingRule

        /// CT 문단 스타일에 싣는 줄 높이 **힌트** — 세로 배치에는 쓰이지 않고 (전진량은
        /// `lineSpacingRule`이 정한다) 서식 복사(`HwpSelectionRTF`)와 규칙 표식이 없는
        /// 문자열의 폴백(`HwpLineSpacingRule.fallback`)에만 남는다.
        ///
        /// - 비율 → `lineHeightMultiple` (p/100). 종전에는 문단 최대 글자 크기 × 비율로
        ///   `minimumLineHeight = maximumLineHeight`를 못박았는데, CT는 그 높이에 안 들어가는
        ///   글자가 있으면 줄을 놓지 않아 (#202) 문단이 통째로 사라졌다.
        /// - 고정·최소 → `minimumLineHeight` (상한은 두지 않는다 — 같은 이유).
        /// - 여백만 → `lineSpacingAdjustment`.
        var lineHeightMultiple: CGFloat = 0
        var minimumLineHeight: CGFloat = 0
        var lineSpacingAdjustment: CGFloat = 0

        init(paraShape: CoreHwp.HwpParaShape, attributedString: NSAttributedString? = nil) {
            // 표 43 여백/들여쓰기는 1/2 단위 (HWPUNIT×2)로 저장된다 — 실측:
            // noori □ 문단 indent −4776 = 본문 23.9pt(8.4mm) 들임 (실물 8.2mm),
            // 'o' 문단 −6550 = 11.6mm (실물 11.4mm). 음수 indent(내어쓰기)는
            // 첫 줄을 여백에 두고 본문을 |indent|만큼 들인다 (각주 '1)' 첫 줄이
            // 여백에 정렬 — footnote-endnote 실물 실측).
            let marginLeft = HwpUnits.points(fromHwpUnit: paraShape.marginLeft) / 2
            let indent = HwpUnits.points(fromHwpUnit: paraShape.indent) / 2
            if indent >= 0 {
                firstLineHeadIndent = marginLeft + indent
                headIndent = marginLeft
            } else {
                firstLineHeadIndent = marginLeft
                headIndent = marginLeft - indent
            }
            // 번호 라벨의 자동 내어쓰기 (#154): 둘째 줄부터를 첫 줄의 본문 시작
            // (라벨 + 본문과의 거리 뒤)에 맞춘다 — 한컴 도움말 "번호가 차지하는
            // 너비만큼 자동으로 문단을 내어쓰기하여 본문의 세로 위치를 가지런히
            // 맞춥니다". 표 43 들여쓰기가 양수면 라벨이 그 뒤에서 시작하므로 거기서
            // 재고, 음수(수동 내어쓰기)면 그 위에 더한다.
            // 번호 너비 안 정렬로 라벨 앞에 남는 폭은 첫 줄 들여쓰기다 (실측: 오른쪽
            // 정렬 1수준의 둘째 줄은 여백에서 시작한다 — 라벨만 밀린다).
            if let inset = attributedString.flatMap({
                Self.numberingValue(HwpAttributedStringKey.numberingFirstLineInset, in: $0)
            }) {
                firstLineHeadIndent += inset
            }
            if let hanging = attributedString.flatMap({
                Self.numberingValue(HwpAttributedStringKey.numberingHeadIndent, in: $0)
            }) {
                headIndent = max(firstLineHeadIndent, headIndent) + hanging
            }
            tailIndent = -HwpUnits.points(fromHwpUnit: paraShape.marginRight) / 2
            // 문단 간격도 표 43 여백 계열과 같은 1/2 단위 (noori 제목 3행
            // spTop=1200 → 6pt가 실물 간격에 부합)
            paragraphSpacingBefore = HwpUnits.points(
                fromHwpUnit: paraShape.paragraphSpacingTop
            ) / 2
            paragraphSpacing = HwpUnits.points(
                fromHwpUnit: paraShape.paragraphSpacingBottom
            ) / 2

            // 줄 간격 (표 44/46): 고정·최소·여백만 값도 1/2 단위다 (#192) —
            // `HwpLineSpacingRule.init(paraShape:)`가 나눈다.
            let rule = HwpLineSpacingRule(paraShape: paraShape)
            lineSpacingRule = rule
            switch rule.kind {
            case .percent:
                lineHeightMultiple = max(0, rule.value / 100)
            case .fixed, .atLeast:
                minimumLineHeight = max(0, rule.value)
            case .marginOnly:
                lineSpacingAdjustment = max(0, rule.value)
            }
        }

        /// 문단 앞 번호 라벨의 pt 값 표식(자동 내어쓰기 전진량·첫 줄 여백) — 라벨은
        /// 언제나 조판 문자열의 첫머리라 첫 글자의 속성만 본다
        /// (`HwpTextRunBuilder.appendNumberingHeading`).
        static func numberingValue(
            _ key: NSAttributedString.Key, in attributedString: NSAttributedString
        ) -> CGFloat? {
            guard attributedString.length > 0,
                  let value = attributedString.attribute(key, at: 0, effectiveRange: nil) as? NSNumber
            else { return nil }
            return CGFloat(value.doubleValue)
        }
    }
}
