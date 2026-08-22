import CoreGraphics

public extension CGColor {
    /// Transparent black color (RGBA: 0, 0, 0, 0) for fallback cases.
    static let hwpTransparent: CGColor = .init(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    /// Default stroke/border color.
    static let hwpBlack: CGColor = .init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    /// Default fill color for textbox backgrounds.
    static let hwpWhite: CGColor = .init(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// 변경 추적 표시색 — 삽입·삭제 글자와 왼쪽 여백 변경 막대가 함께 쓴다.
    /// 실측 튜닝 상수가 아니라 UI 색 리터럴이라 `HwpRenderTuning`이 아니라
    /// 여기 산다 (fidelity 게이트 대상이 아니다).
    static let hwpTrackChange: CGColor = .init(srgbRed: 0.87, green: 0.14, blue: 0.1, alpha: 1)
}
