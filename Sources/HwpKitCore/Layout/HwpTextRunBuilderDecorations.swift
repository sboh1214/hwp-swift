import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// 글자 장식 속성 (표 33) — HwpTextRunBuilder.attributes의 장식 부분

extension HwpTextRunBuilder {
    /// 글자 장식 (표 33): 밑줄/취소선/음영/그림자/외곽선/첨자 속성.
    func applyShapeDecorations(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape,
        size: CGFloat
    ) {
        // 밑줄 종류 1(글자 아래)만 밑줄로 그린다. 종류 2(글자 위)는 취소선과
        // 함께 저장되는 조합이고 한글이 밑줄을 그리지 않는다 (CharShape 실물
        // 취소선 색 행 — 시안 취소선 단선만 표시).
        if shape.property.underlineType == .under {
            // CT 밑줄은 두껍다 (실물 헤어라인 대비 3-4배) — 렌더러가
            // 직접 0.4pt 헤어라인으로 그린다 (전용 키)
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = shape.underlineColor.cgColor
        }
        if shape.property.strikethrough != 0 {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] =
                (shape.strikethroughColor ?? shape.faceColor).cgColor
        }
        // 음영 — 흰색은 "없음" (한글 기본값)
        let shade = shape.shadeColor
        if shade.red != 255 || shade.green != 255 || shade.blue != 255 {
            attributes[HwpAttributedStringKey.shadeColor] = shade.cgColor
        }
        if shape.property.shadowType != .none {
            attributes[HwpAttributedStringKey.shadowColor] = shadowColor(for: shape)
            attributes[HwpAttributedStringKey.shadowOffsetX] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalX)
                    * HwpRenderTuning.Text.shadowOffsetScale / 100
            )
            attributes[HwpAttributedStringKey.shadowOffsetY] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalY)
                    * HwpRenderTuning.Text.shadowOffsetScale / 100
            )
            if shape.property.shadowType == .continuous {
                attributes[HwpAttributedStringKey.shadowContinuous] = NSNumber(value: true)
            }
            // 렌더러가 그림자 사본/본문을 컨텍스트 fill 색으로 2-pass 그린다
            attributes[kCTForegroundColorFromContextAttributeName
                as NSAttributedString.Key] = NSNumber(value: true)
        }
        // 외곽선 (표 33): CT stroke 전용 (양수 %) — 실물은 가는 검은
        // 윤곽선의 속 빈 글자 (라운드 6 실측)
        if shape.property.borderlineType != CoreHwp.HwpBorderLineType.none {
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                NSNumber(value: 4.0)
        }
        // 양각/음각 — 밝은/어두운 오프셋 사본 (HwpPageLayer 3-pass).
        // 글리프 색을 컨텍스트에서 바꾸도록 from-context로 전환한다.
        if shape.property.isRelief || shape.property.isCounterRelief {
            attributes[HwpAttributedStringKey.reliefStyle] =
                NSNumber(value: shape.property.isRelief ? 1 : 2)
            attributes[HwpAttributedStringKey.reliefFaceColor] = shape.faceColor.cgColor
            attributes[kCTForegroundColorFromContextAttributeName as NSAttributedString.Key] =
                NSNumber(value: true)
        }
        // 강조점 — 글리프 위 가운데 점 (HwpPageLayer가 그림)
        if shape.property.emphasisType != CoreHwp.HwpEmphasisType.none {
            attributes[HwpAttributedStringKey.emphasisMark] = NSNumber(value: 1)
        }
        // 위/아래 첨자 (표 33): 크기 축소 + 베이스라인 이동
        if shape.property.isSuperscript {
            applySuperscript(to: &attributes, shape: shape)
        } else if shape.property.isSubscript {
            applySubscript(to: &attributes, shape: shape)
        }
    }
}

extension HwpTextRunBuilder {
    /// 그림자 색: 연속 그림자는 실물에서 더 진한 회색으로 획에 밀착된다
    /// (라운드 6 실측: 비연속 연회색 분리 vs 연속 중간회색 밀착)
    func shadowColor(for shape: CoreHwp.HwpCharShape) -> CGColor {
        guard shape.property.shadowType == .continuous else {
            return shape.shadowColor.cgColor
        }
        let base = shape.shadowColor
        return CoreHwp.HwpColor(
            Int(base.red) * 55 / 100,
            Int(base.green) * 55 / 100,
            Int(base.blue) * 55 / 100
        ).cgColor
    }
}
