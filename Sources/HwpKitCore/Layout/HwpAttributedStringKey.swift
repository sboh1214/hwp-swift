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
    /// 취소선 여부 — NSStrikethrough 키를 쓰면 CTLineDraw가 자체로 한 번 더
    /// 그려 이중선이 된다 (CharShape 실물 대조 2026-07-10)
    public static let strikethroughStyle = NSAttributedString.Key("hwp.strikethroughStyle")
    /// 양각/음각 (NSNumber: 1 양각, 2 음각) — 밝은/어두운 오프셋 사본 3-pass
    public static let reliefStyle = NSAttributedString.Key("hwp.reliefStyle")
    /// 양각/음각 run의 실제 글자색 (CGColor) — 글리프 자체는
    /// kCTForegroundColorFromContext로 그려서 사본 색을 컨텍스트로 바꾼다
    public static let reliefFaceColor = NSAttributedString.Key("hwp.reliefFaceColor")
    /// 강조점 (NSNumber != 0) — 글리프 위 가운데 점
    public static let emphasisMark = NSAttributedString.Key("hwp.emphasisMark")
    /// 글자 위치 (표 33 location) — 줄 안 세로 오프셋 (pt, 양수 = 위).
    /// kCTBaselineOffset은 CTFramesetter가 무시하므로 직접 그린다.
    public static let glyphBaselineOffset = NSAttributedString.Key("hwp.glyphBaselineOffset")
    /// 외곽선 글자 — 굵은 윤곽 스트로크 + 흰 채움 2-pass로 그린다
    public static let outlineBody = NSAttributedString.Key("hwp.outlineBody")
    /// 연속 그림자 — 본체에서 오프셋까지 이어지는 두꺼운 그림자
    public static let shadowContinuous = NSAttributedString.Key("hwp.shadowContinuous")
    /// 배분/나눔 정렬 (표 44 정렬 4·5) — 마지막 줄도 단어 간격을 벌린다
    public static let distributeAlignment = NSAttributedString.Key("hwp.distributeAlignment")
}
