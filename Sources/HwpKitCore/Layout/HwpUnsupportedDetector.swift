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
        if let hint = unsupportedHint(for: ctrl) {
            return HwpUnsupportedElement(kind: .placeholder, page: page, hint: hint)
        }
        // 지원되는 컨트롤 (gso 등)이라도 개체 요소 안에 v1 OUT 세부 record
        // (차트/동영상/글맵시/양식/OLE)가 있으면 placeholder로 보고한다.
        if let hint = unsupportedComponentHint(for: ctrl) {
            return HwpUnsupportedElement(kind: .placeholder, page: page, hint: hint)
        }
        return nil
    }
}

private extension HwpUnsupportedDetector {
    func unsupportedComponentHint(for ctrl: CoreHwp.HwpCtrlId) -> String? {
        let components: [CoreHwp.HwpShapeComponent] = switch ctrl {
        case let .genShapeObject(genShape):
            genShape.shapeComponentArray
        case let .shape(shape),
             let .line(shape),
             let .rectangle(shape),
             let .ellipse(shape),
             let .arc(shape),
             let .polygon(shape),
             let .curve(shape),
             let .picture(shape),
             let .container(shape):
            shape.shapeComponentArray
        default:
            []
        }
        for component in components {
            if !component.chartDataArray.isEmpty { return "차트" }
            if !component.videoDataArray.isEmpty { return "동영상" }
            if !component.textartArray.isEmpty { return "글맵시" }
            if !component.formObjectArray.isEmpty { return "양식 개체" }
            if !component.oleArray.isEmpty { return "OLE" }
        }
        return nil
    }

    // Exhaustive over HwpCtrlId (no `default:`) so the compiler forces every
    // new control case to be classified as supported (nil) or unsupported.
    // swiftlint:disable:next cyclomatic_complexity
    func unsupportedHint(for ctrl: CoreHwp.HwpCtrlId) -> String? {
        switch ctrl {
        case .table, .shape, .line, .rectangle, .ellipse, .arc, .polygon, .curve,
             .picture, .container, .genShapeObject, .section, .column,
             .pageNumberPosition, .header, .footer, .footnote, .endnote, .hyperLink:
            nil
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
        }
    }
}
