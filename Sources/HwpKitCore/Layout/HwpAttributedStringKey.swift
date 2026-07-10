import Foundation

public enum HwpAttributedStringKey {
    public static let underlineColor = NSAttributedString.Key("hwp.underlineColor")
    /// extended 컨트롤 문자(U+FFFC)가 가리키는 ctrlHeaderArray index (NSNumber).
    /// k번째 extended 컨트롤 문자 ↔ k번째 컨트롤 헤더 (noori/header-footer 픽스처 검증).
    public static let controlIndex = NSAttributedString.Key("hwp.controlIndex")
    /// 음영 색 (CGColor) — run 배경 칠하기
    public static let shadeColor = NSAttributedString.Key("hwp.shadeColor")
    /// 그림자 색 (CGColor) + 오프셋 (pt, NSNumber) — run 글리프 그림자
    public static let shadowColor = NSAttributedString.Key("hwp.shadowColor")
    public static let shadowOffsetX = NSAttributedString.Key("hwp.shadowOffsetX")
    public static let shadowOffsetY = NSAttributedString.Key("hwp.shadowOffsetY")
    /// 취소선 색 (CGColor)
    public static let strikethroughColor = NSAttributedString.Key("hwp.strikethroughColor")
    /// 양각/음각 (NSNumber: 1 양각, 2 음각) — 밝은/어두운 오프셋 사본 3-pass
    public static let reliefStyle = NSAttributedString.Key("hwp.reliefStyle")
    /// 양각/음각 run의 실제 글자색 (CGColor) — 글리프 자체는
    /// kCTForegroundColorFromContext로 그려서 사본 색을 컨텍스트로 바꾼다
    public static let reliefFaceColor = NSAttributedString.Key("hwp.reliefFaceColor")
    /// 강조점 (NSNumber != 0) — 글리프 위 가운데 점
    public static let emphasisMark = NSAttributedString.Key("hwp.emphasisMark")
}
