import CoreHwp
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
        return "Times New Roman"
    }
}
