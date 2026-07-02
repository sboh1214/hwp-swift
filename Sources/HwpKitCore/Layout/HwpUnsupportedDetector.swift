@preconcurrency import CoreHwp
import Foundation

/// Classifies a control ID into either "supported" (nil) or an unsupported placeholder element.
///
/// V1 IN (supported, returns nil):
/// - Text runs (paragraph controls)
/// - Table, image (picture), footnote, endnote
/// - Shapes (line, rectangle, ellipse, arc, polygon, curve)
/// - Textbox (genShapeObject with textbox component)
/// - Hyperlink (field %hlk)
/// - Section, column, page-number
/// - Header, footer
///
/// V1 OUT (placeholder, returns HwpUnsupportedElement):
/// - Equation (eqed/equd)
/// - Chart, OLE, video
/// - WordArt, TextArt
/// - Memo (unless treated as field variant)
/// - Any `.notImplemented` or `.unknown` control
public struct HwpUnsupportedDetector: Sendable {
    public init() {}

    /// Classifies a control ID into either supported (nil) or unsupported placeholder.
    ///
    /// - Parameters:
    ///   - ctrl: The control ID to classify
    ///   - page: The page number where this control appears
    /// - Returns: nil if supported, or HwpUnsupportedElement for v1 OUT types
    public func classify(ctrl: CoreHwp.HwpCtrlId, page: Int) -> HwpUnsupportedElement? {
        guard !isSupported(ctrl: ctrl), let hint = unsupportedHint(for: ctrl) else {
            return nil
        }
        return HwpUnsupportedElement(kind: .placeholder, page: page, hint: hint)
    }
}

private extension HwpUnsupportedDetector {
    func isSupported(ctrl: CoreHwp.HwpCtrlId) -> Bool {
        switch ctrl {
        case .table, .shape, .line, .rectangle, .ellipse, .arc, .polygon, .curve,
             .picture, .container, .genShapeObject, .section, .column,
             .pageNumberPosition, .header, .footer, .footnote, .endnote, .hyperLink:
            true
        default:
            false
        }
    }

    func unsupportedHint(for ctrl: CoreHwp.HwpCtrlId) -> String? {
        switch ctrl {
        case .equation, .equationLegacy:
            "수식"
        case .ole:
            "OLE"
        case .form:
            "알 수 없음: form"
        case .autoNumber:
            "알 수 없음: autoNumber"
        case .newNumber:
            "알 수 없음: newNumber"
        case .pageHide:
            "알 수 없음: pageHide"
        case .pageCT:
            "알 수 없음: pageCT"
        case .indexmark:
            "알 수 없음: indexmark"
        case .bookmark:
            "알 수 없음: bookmark"
        case .overlapping:
            "알 수 없음: overlapping"
        case .comment:
            "알 수 없음: comment"
        case .hiddenComment:
            "알 수 없음: hiddenComment"
        case .other:
            "알 수 없음: other"
        case .memo:
            "알 수 없음: memo"
        case .revision:
            "알 수 없음: revision"
        case .field:
            "알 수 없음: field"
        case .notImplemented:
            "알 수 없음: notImplemented"
        case .unknown:
            "알 수 없음: unknown"
        default:
            nil
        }
    }
}
