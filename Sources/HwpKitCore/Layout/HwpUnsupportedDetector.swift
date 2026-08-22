import CoreHwp
import Foundation

/// Classifies a control ID into either "supported" (nil) or an unsupported placeholder element.
///
/// 역할 경계 (#66): Detector가 보는 것은 파스 완전성이 아니라 **조판 결과**다 —
/// "미지원 요소가 화면에서 placeholder로 보이는가"(뷰어 UI)를 다루고, 실제 수집은
/// 조판을 구동하는 `HwpPaginator.walkUnsupported`가 하므로 대상은 조판된 쪽에
/// 실린 컨트롤로 한정된다. 복구 placeholder(`collectRecoveredParseFailures`)와
/// 컨테이너 깊이 초과도 같은 `.placeholder` 채널로 나간다. 반면 "파서가 무엇을
/// 해석하지 못했는가"(QA·텔레메트리·버그 리포트·픽스처 회귀 신호)는 조판과
/// 무관하게 문서 전체 — ViewText·메모·중첩 문단 포함 — 를 집계하는
/// `CoreHwp.HwpFile.parseDiagnostics()`가 맡는다.
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
///
/// 렌더에 반영되거나 무해해서 보고하지 않는 컨트롤 (nil):
/// - autoNumber/newNumber — 각주/미주/쪽 번호 렌더에 사용 (표 142~144)
/// - pageHide — 쪽 번호/머리말/꼬리말 감추기에 사용 (표 145)
/// - indexmark/hiddenComment — 화면 출력이 없는 마커
/// - bookmark — 화면 출력이 없는 앵커. #77에서 탐색 목록
///   (`HwpDocumentMetadata.outline`)의 재료로 **소비되므로** 더는 "알 수 없음"이
///   아니다. 이름은 `HwpOtherControlBookmarkInfo.name`으로 읽히고 뷰어 로드
///   (`.viewer` 옵션)에서도 살아 있다
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
            if !component.chartDataArray.isEmpty {
                return "차트"
            }
            if !component.videoDataArray.isEmpty {
                return "동영상"
            }
            if !component.textartArray.isEmpty {
                return "글맵시"
            }
            if !component.formObjectArray.isEmpty {
                return "양식 개체"
            }
            if !component.oleArray.isEmpty {
                return "OLE"
            }
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
             .pageNumberPosition, .header, .footer, .footnote, .endnote, .hyperLink,
             .autoNumber, .newNumber, .pageHide, .indexmark, .hiddenComment,
             .bookmark:
            nil
        case .equation, .equationLegacy:
            "수식"
        case .ole:
            "OLE"
        case .form:
            "알 수 없음: form"
        case .pageCT:
            "알 수 없음: pageCT"
        case .overlapping:
            "알 수 없음: overlapping"
        case .comment:
            "알 수 없음: comment"
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
