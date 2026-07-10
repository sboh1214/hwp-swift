import CoreGraphics
@preconcurrency import CoreHwp
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
        if shape.property.underlineType != .none {
            // NSUnderlineStyle.single = 1; no AppKit/UIKit in HwpKitCore
            attributes[.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = shape.underlineColor.cgColor
            // CTLineDraw가 밑줄을 그릴 때 쓰는 색 (없으면 글자색으로 그림)
            attributes[kCTUnderlineColorAttributeName as NSAttributedString.Key] =
                shape.underlineColor.cgColor
        }
        if shape.property.strikethrough != 0 {
            attributes[.strikethroughStyle] = NSNumber(value: 1) // NSUnderlineStyle.single = 1
            attributes[HwpAttributedStringKey.strikethroughColor] =
                (shape.strikethroughColor ?? shape.faceColor).cgColor
        }
        // 음영 — 흰색은 "없음" (한글 기본값)
        let shade = shape.shadeColor
        if shade.red != 255 || shade.green != 255 || shade.blue != 255 {
            attributes[HwpAttributedStringKey.shadeColor] = shade.cgColor
        }
        if shape.property.shadowType != .none {
            attributes[HwpAttributedStringKey.shadowColor] = shape.shadowColor.cgColor
            attributes[HwpAttributedStringKey.shadowOffsetX] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalX) / 100
            )
            attributes[HwpAttributedStringKey.shadowOffsetY] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalY) / 100
            )
        }
        // 외곽선 — CT 양수 stroke width는 stroke 전용 (글자 내부 비움)
        if shape.property.borderlineType != CoreHwp.HwpBorderLineType.none {
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                NSNumber(value: 3.0)
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
