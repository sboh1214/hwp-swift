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
        // 밑줄 종류 1(글자 아래)만 밑줄로 그린다. 종류 2(글자 위)는 취소선과
        // 함께 저장되는 조합이고 한글이 밑줄을 그리지 않는다 (CharShape 실물
        // 취소선 색 행 — 시안 취소선 단선만 표시).
        if shape.property.underlineType == .under {
            // NSUnderlineStyle.single = 1; no AppKit/UIKit in HwpKitCore
            attributes[.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = shape.underlineColor.cgColor
            // CTLineDraw가 밑줄을 그릴 때 쓰는 색 (없으면 글자색으로 그림)
            attributes[kCTUnderlineColorAttributeName as NSAttributedString.Key] =
                shape.underlineColor.cgColor
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
            attributes[HwpAttributedStringKey.shadowColor] = shape.shadowColor.cgColor
            // 실측 (CharShapeProperty 실물): 한글 그림자 오프셋은 선언 %의
            // 약 1.5배 위치에 찍힌다 (10% 선언 → ~15% 실측)
            attributes[HwpAttributedStringKey.shadowOffsetX] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalX) * 1.5 / 100
            )
            attributes[HwpAttributedStringKey.shadowOffsetY] = NSNumber(
                value: Double(size) * Double(shape.shadowIntervalY) * 1.5 / 100
            )
            if shape.property.shadowType == .continuous {
                attributes[HwpAttributedStringKey.shadowContinuous] = NSNumber(value: true)
            }
        }
        // 외곽선 — 헤어라인 글꼴에서는 CT 양수 stroke만으로 흰 속이 남지
        // 않는다. 렌더러가 굵은 윤곽 + 흰 채움 2-pass로 그린다 (실물: 흰 속).
        if shape.property.borderlineType != CoreHwp.HwpBorderLineType.none {
            attributes[HwpAttributedStringKey.outlineBody] = NSNumber(value: true)
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
