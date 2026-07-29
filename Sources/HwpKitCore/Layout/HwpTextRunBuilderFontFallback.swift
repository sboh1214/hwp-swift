import CoreHwp
import CoreText
import Foundation

extension HwpTextRunBuilder {
    /// 세리프 계열 라틴/숫자는 Times형 폴백 (noori 실물; 함초롬·설치
    /// 한컴 폰트는 자체 라틴 유지)
    ///
    /// - Parameter usesInstalledHancomFonts: `HwpFontResolver` 와 **같은 값**을
    ///   넘겨야 한다. 여기서 한컴 인덱스를 무조건 조회하면 opt-in 이 뚫린다 —
    ///   조회 자체가 앱 번들 폰트 파일 열거이고 (라이선스상 피하려는 동작),
    ///   결과가 한컴오피스 설치 여부에 좌우되면 배포 기본 경로의 렌더가
    ///   기기 의존이 된다. off 면 설치 폰트가 없는 것으로 보고 함초롬 라틴으로
    ///   간다 — 기기와 무관하게 같은 결과가 나온다.
    static func serifLatinFallback(
        _ faceName: String,
        script: HwpScript,
        usesInstalledHancomFonts: Bool
    ) -> String {
        func hasInstalled(_ name: String) -> Bool {
            usesInstalledHancomFonts
                && HwpInstalledHancomFonts.descriptor(forFaceName: name) != nil
        }
        guard script == .english, !faceName.contains("함초롬"),
              !hasInstalled(faceName),
              faceName.contains("명조") || faceName.contains("바탕")
              || faceName.contains("Poppy") || faceName.contains("Batang")
        else { return faceName }
        // 한글.app의 세리프 대체: 바탕/명조 계열은 한컴 실폰트가 있으면
        // 그쪽 (라틴 진행 폭이 좁다 — noori 표 셀 실측 8~11% 격차),
        // 그 외 (HCI Poppy 등)는 함초롬바탕 라틴 (본문 줄바꿈 폭 정합)
        if faceName.contains("바탕") || faceName.contains("Batang"), hasInstalled("한컴바탕") {
            return "한컴바탕"
        }
        if faceName.contains("명조"), hasInstalled("휴먼명조") {
            return "휴먼명조"
        }
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
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)
        // 글머리표 기호 (□ 등)는 한글 폰트의 전각 글리프로 그린다 —
        // 라틴 폴백 폰트의 기호는 실물보다 작다 (noori 라운드 11 실측:
        // 실물 □ = 글자 높이의 84%, 폴백은 53%)
        var bulletAttributes = attributes(for: resolved, script: .korean)
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
