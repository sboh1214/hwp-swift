import CoreGraphics
import Foundation

/// A render command for displaying an unsupported placeholder element.
///
/// This struct encapsulates the visual representation of a placeholder for
/// unsupported controls (equation, chart, OLE, etc.) that cannot be rendered
/// in v1 scope.
public struct HwpPlaceholderRenderCommand: Sendable, Hashable {
    /// The frame (position and size) where the placeholder should be drawn.
    public let frame: CGRect

    /// The text to display inside the placeholder (e.g., "[수식]", "[차트]").
    public let text: String

    /// The background color for the placeholder.
    public let color: CGColor

    /// Creates a placeholder render command.
    ///
    /// - Parameters:
    ///   - frame: The frame where the placeholder should be drawn
    ///   - text: The text to display (e.g., "[수식]")
    ///   - color: The background color (defaults to light grey)
    public init(
        frame: CGRect,
        text: String,
        color: CGColor = CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    ) {
        self.frame = frame
        self.text = text
        self.color = color
    }
}
