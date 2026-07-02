import CoreGraphics

public extension CGColor {
    /// Transparent black color (RGBA: 0, 0, 0, 0) for fallback cases.
    static let hwpTransparent: CGColor = .init(srgbRed: 0, green: 0, blue: 0, alpha: 0)
}
