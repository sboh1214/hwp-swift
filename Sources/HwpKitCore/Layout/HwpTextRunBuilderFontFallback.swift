import CoreHwp
import CoreText
import Foundation

extension HwpTextRunBuilder {
    /// 세리프 계열 라틴/숫자는 Times형 폴백 (noori 실물; 함초롬·설치
    /// 한컴 폰트는 자체 라틴 유지)
    static func serifLatinFallback(_ faceName: String, script: HwpScript) -> String {
        guard script == .english, !faceName.contains("함초롬"),
              HwpInstalledHancomFonts.descriptor(forFaceName: faceName) == nil,
              faceName.contains("명조") || faceName.contains("바탕")
              || faceName.contains("Poppy") || faceName.contains("Batang")
        else { return faceName }
        // 한글.app의 세리프 대체는 함초롬바탕 라틴 (Times풍 세리프) —
        // 진행 폭까지 실물과 일치한다 (noori 'o' 문단 줄바꿈 실측)
        return "함초롬바탕"
    }
}

extension HwpTextRunBuilder {
    /// 글머리표 (표 44 heading 3): 문자 + 공백 전치
    func appendBulletHeading(
        for paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        guard let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId)),
              paraShape.property1Info.hasBulletHeading,
              paraShape.numberingOrBulletId > 0,
              // 글머리표 참조는 1-based (0 = 없음)
              let bullet = index.bullet(id: UInt32(paraShape.numberingOrBulletId) - 1),
              !bullet.char.isEmpty
        else { return }
        let shapeId = activeShapeId(at: 0, in: paragraph.paraCharShape)
        let shape = resolvedShape(id: shapeId, paragraph: paragraph)
        // 글머리표 기호 (□ 등)는 한글 폰트의 전각 글리프로 그린다 —
        // 라틴 폴백 폰트의 기호는 실물보다 작다 (noori 라운드 11 실측:
        // 실물 □ = 글자 높이의 84%, 폴백은 53%)
        var bulletAttributes = attributes(for: shape, script: .korean)
        let isGeometricShape = bullet.char.unicodeScalars
            .allSatisfy { (0x25A0 ... 0x25FF).contains($0.value) }
        if isGeometricShape,
           let fontValue = bulletAttributes[kCTFontAttributeName as NSAttributedString.Key],
           CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
        {
            // 도형 기호는 HCR 함초롬의 전각 글리프 (0.76em)가 실물 크기 —
            // 명조 대체 폰트의 도형은 0.5em으로 작다
            // swiftlint:disable:next force_cast
            let font = fontValue as! CTFont
            bulletAttributes[kCTFontAttributeName as NSAttributedString.Key] =
                fontResolver.resolve(
                    faceName: "함초롬바탕", script: .korean, size: CTFontGetSize(font)
                )
        }
        output.append(NSAttributedString(
            string: bullet.char + " ",
            attributes: bulletAttributes
        ))
    }
}
