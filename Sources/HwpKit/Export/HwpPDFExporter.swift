import Foundation
import HwpKitCore
import HwpKitNative

public enum HwpPDFExportError: Error, Sendable {
    case cancelled
    case emptyDocument
    case incompleteDocument
    case exportFailed(String)
}

extension HwpPDFExportError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled:
            "PDF export was cancelled"
        case .emptyDocument:
            "Document has no pages to export"
        case .incompleteDocument:
            "Document is still loading — export after pagination finishes"
        case let .exportFailed(reason):
            "PDF export failed: \(reason)"
        }
    }
}

extension HwpPDFExportError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// 페이지네이션된 문서를 PDF로 내보낸다.
///
/// 화면 렌더와 **같은 paint list·같은 조판**을 쓴다 (`HwpPageLayer.draw(in:)`가
/// 임의 CGContext에 그리는 순수 오프스크린 렌더러라 뷰 계층이 필요 없다).
/// 텍스트는 벡터로, 이미지는 프리디코드 후 동기 draw로 들어가고, 편집 화면
/// 장식인 메모 풍선 패널은 종이 밖이라 포함되지 않는다.
///
/// 인쇄는 이 결과 PDF를 호스트 앱이 플랫폼 인쇄 API(macOS `PDFDocument
/// .printOperation`, iOS `UIPrintInteractionController`)에 넘겨 처리한다 —
/// 뷰를 직접 인쇄하면 레이어 가상화(visible ± 2)와 충돌한다.
///
/// 페이지가 전부 확정된 문서만 받는다 — `loadUpdates(from:)`의 중간 스냅샷은
/// `.incompleteDocument`로 거부한다 (그대로 내보내면 페이지가 빠진 PDF가
/// 성공으로 나간다).
public struct HwpPDFExporter: Sendable {
    public init() {}

    /// 문서를 `url`에 기록한다. 페이지 단위 스트리밍이라 상주 메모리는 1페이지
    /// 몫이고, 페이지 경계마다 취소를 확인한다 (취소되면 부분 파일을 지운다).
    public func export(
        document: HwpDocument,
        to url: URL,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws {
        do {
            try await HwpPDFRenderer.render(document: document, to: url, onProgress: onProgress)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// 문서를 PDF 바이트로 만든다 — 전량이 메모리에 남으므로 대형 문서는
    /// `export(document:to:)`를 쓸 것.
    public func exportData(
        document: HwpDocument,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws -> Data {
        do {
            return try await HwpPDFRenderer.renderData(document: document, onProgress: onProgress)
        } catch {
            throw Self.mapped(error)
        }
    }

    private static func mapped(_ error: Error) -> HwpPDFExportError {
        if error is CancellationError {
            return .cancelled
        }
        // 호스트가 갈라 다뤄야 하는 실패는 타입으로 살린다 — 미완성 문서는 로드가
        // 끝나면 성공하는 재시도 가능 상태라, 문자열로 접으면 그 사실이 사라진다.
        switch error as? HwpPDFRenderError {
        case .emptyDocument:
            return .emptyDocument
        case .incompleteDocument:
            return .incompleteDocument
        default:
            return .exportFailed(error.localizedDescription)
        }
    }
}
