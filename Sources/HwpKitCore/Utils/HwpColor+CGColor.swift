import CoreGraphics

public extension CGColor {
    /// Transparent black color (RGBA: 0, 0, 0, 0) for fallback cases.
    static let hwpTransparent: CGColor = .init(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    /// Default stroke/border color.
    static let hwpBlack: CGColor = .init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    /// Default fill color for textbox backgrounds.
    static let hwpWhite: CGColor = .init(srgbRed: 1, green: 1, blue: 1, alpha: 1)
}
