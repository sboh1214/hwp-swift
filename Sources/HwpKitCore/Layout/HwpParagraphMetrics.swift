import CoreGraphics
@preconcurrency import CoreHwp
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
        /// 여백만 지정 (표 46 종류 2): 줄 사이 추가 간격 (pt)
        var lineSpacingAdjustment: CGFloat = 0
        /// 비율/고정/최소 줄 간격의 강제 줄 높이 하한 (pt, 0 = 없음)
        var minimumLineHeight: CGFloat = 0
        /// 비율/고정 줄 간격의 강제 줄 높이 상한 (pt, 0 = 없음).
        /// 글자처럼 취급 개체가 줄 공간을 예약한 문단은 개체가 잘리지 않게
        /// 상한을 두지 않는다 (한글: 줄 높이 = max(글자 기준 높이, 개체 높이)).
        var maximumLineHeight: CGFloat = 0

        /// applyLineHeight가 여분을 줄 뒤 간격으로 돌렸는지 — 마지막 줄 뒤
        /// 몫도 문단 전진량에 포함해야 한다 (한글 캐시: lineHeight+lineSpacing 합)
        var lineHeightAppliedAsSpacing = false

        /// 목표 줄 높이 적용. 한글은 줄 여분을 글자 아래에만 붙인다 (첫 줄
        /// 글리프 상단 = 본문 상단 — plain-text/bookmark 실물 실측 +1.3mm 보정).
        /// CT min/max 줄 높이는 여분을 위아래로 나누므로, 자연 높이보다 큰
        /// 여분은 lineSpacingAdjustment (줄 뒤 간격)로만 준다.
        private mutating func applyLineHeight(
            _ lineHeight: CGFloat,
            attributedString: NSAttributedString?
        ) {
            let natural = attributedString.map(Self.maxNaturalLineHeight(in:)) ?? 0
            if natural > 0, lineHeight >= natural {
                lineSpacingAdjustment = lineHeight - natural
                lineHeightAppliedAsSpacing = true
                return
            }
            minimumLineHeight = lineHeight
            if attributedString.map(Self.hasInlineObjects(in:)) != true {
                maximumLineHeight = lineHeight
            }
        }

        /// run 폰트들의 자연 줄 높이 최대값 (ascent + descent + leading)
        static func maxNaturalLineHeight(in attributedString: NSAttributedString) -> CGFloat {
            var maxHeight: CGFloat = 0
            attributedString.enumerateAttribute(
                kCTFontAttributeName as NSAttributedString.Key,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, _ in
                guard let value, CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                else { return }
                let font = value as! CTFont // swiftlint:disable:this force_cast
                let height = CTFontGetAscent(font) + CTFontGetDescent(font)
                    + CTFontGetLeading(font)
                maxHeight = max(maxHeight, height)
            }
            return maxHeight
        }

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
            tailIndent = -HwpUnits.points(fromHwpUnit: paraShape.marginRight) / 2
            // 문단 간격도 표 43 여백 계열과 같은 1/2 단위 (noori 제목 3행
            // spTop=1200 → 6pt가 실물 간격에 부합)
            paragraphSpacingBefore = HwpUnits.points(
                fromHwpUnit: paraShape.paragraphSpacingTop
            ) / 2
            paragraphSpacing = HwpUnits.points(
                fromHwpUnit: paraShape.paragraphSpacingBottom
            ) / 2

            let value = paraShape.resolvedLineSpacingValue
            switch paraShape.resolvedLineSpacingKind {
            case .percent:
                // 글자에 따라(%): 줄 높이 = 글자 크기 × 값 / 100 (표 44/46 종류 0)
                let fontSize = attributedString.map(Self.maxFontSize(in:)) ?? 0
                guard fontSize > 0, value > 0 else { break }
                let lineHeight = fontSize * CGFloat(value) / 100
                applyLineHeight(lineHeight, attributedString: attributedString)
            case .fixed:
                let lineHeight = max(1, HwpUnits.points(fromHwpUnit: value))
                applyLineHeight(lineHeight, attributedString: attributedString)
            case .marginOnly:
                lineSpacingAdjustment = max(0, HwpUnits.points(fromHwpUnit: value))
            case .atLeast:
                minimumLineHeight = max(0, HwpUnits.points(fromHwpUnit: value))
            }
        }

        /// 자연 줄 높이에 min/max 강제 줄 높이 제약을 적용한다 (0 = 제약 없음)
        func clampedLineHeight(_ natural: CGFloat) -> CGFloat {
            var height = natural
            if maximumLineHeight > 0 {
                height = min(height, maximumLineHeight)
            }
            if minimumLineHeight > 0 {
                height = max(height, minimumLineHeight)
            }
            return height
        }

        /// 문자열 run들의 최대 글꼴 크기 (비율 줄 간격의 기준 글자 크기)
        static func maxFontSize(in attributedString: NSAttributedString) -> CGFloat {
            // % 줄 간격의 기준은 상대크기 적용 전 기본 크기다 (한글 실물:
            // 상대크기 170% 줄도 전진량이 일반 줄과 동일 — CharShape 실측).
            var maxBase: CGFloat = 0
            attributedString.enumerateAttribute(
                HwpAttributedStringKey.baseFontSize,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, _ in
                if let number = value as? NSNumber {
                    maxBase = max(maxBase, CGFloat(number.doubleValue))
                }
            }
            if maxBase > 0 {
                return maxBase
            }
            var maxSize: CGFloat = 0
            attributedString.enumerateAttribute(
                kCTFontAttributeName as NSAttributedString.Key,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, _ in
                guard let value, CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else {
                    return
                }
                let font = value as! CTFont // swiftlint:disable:this force_cast
                maxSize = max(maxSize, CTFontGetSize(font))
            }
            return maxSize
        }

        /// 줄 공간을 예약한 (높이 > 0) 글자처럼 취급 개체 run이 있는지
        static func hasInlineObjects(in attributedString: NSAttributedString) -> Bool {
            var found = false
            attributedString.enumerateAttribute(
                HwpAttributedStringKey.inlineObjectHeight,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, stop in
                if let number = value as? NSNumber, number.doubleValue > 0 {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }
    }
}
