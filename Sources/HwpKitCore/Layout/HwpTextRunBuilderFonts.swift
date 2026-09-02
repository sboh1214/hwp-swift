import CoreHwp
import CoreText
import Foundation

/// 글자 모양 속성 → CTFont 트레이트 합성.
///
/// 본체가 `file_length` 상한에 붙어 분리했다 — 변경 추적·공백 폭이
/// `HwpTextRunBuilderMarks`로 나간 것과 같은 관례다.
extension HwpTextRunBuilder {
    func symbolicTraits(for property: CoreHwp.HwpCharShapeProperty) -> CTFontSymbolicTraits {
        var traits = CTFontSymbolicTraits()
        if property.isBold {
            traits.insert(.traitBold)
        }
        if property.isItalic {
            traits.insert(.traitItalic)
        }
        return traits
    }

    func copy(_ font: CTFont, adding traits: CTFontSymbolicTraits) -> CTFont {
        guard !traits.isEmpty else { return font }
        if let descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
            CTFontCopyFontDescriptor(font),
            traits,
            traits
        ) {
            return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
        }
        // 요청한 조합 페이스가 없는 폰트 (한글 명조 등): 볼드만 먼저 시도하고,
        // 이탤릭은 기울임 매트릭스로 근사한다 (한글.app 동작).
        var result = font
        if traits.contains(.traitBold),
           let boldDescriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
               CTFontCopyFontDescriptor(result),
               .traitBold,
               .traitBold
           )
        {
            result = CTFontCreateWithFontDescriptor(boldDescriptor, CTFontGetSize(result), nil)
        }
        if traits.contains(.traitItalic) {
            var matrix = CTFontGetMatrix(result)
            matrix.c += 0.22
            result = CTFontCreateCopyWithAttributes(result, 0, &matrix, nil)
        }
        return result
    }
}
