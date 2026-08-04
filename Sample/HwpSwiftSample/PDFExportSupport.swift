import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
    import PDFKit
#else
    import UIKit
#endif

/// 이미 만들어 둔 PDF 파일을 `fileExporter`로 넘기기 위한 얇은 래퍼.
///
/// `Data`가 아니라 URL을 감싸는 이유: 내보내기는 페이지 단위 스트리밍이라
/// 1,030쪽 문서도 상주 1페이지 몫인데, 여기서 전량을 메모리로 올리면 그 이점이
/// 사라진다.
struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.pdf]
    }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration _: ReadConfiguration) throws {
        // 이 샘플은 PDF를 읽지 않는다 (내보내기 전용).
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}

/// 생성된 PDF를 플랫폼 인쇄 UI로 넘긴다.
///
/// 문서 뷰를 직접 인쇄하지 않는다 — 뷰는 가시 ± 2쪽만 레이어로 들고 있어
/// (레이어 가상화) 인쇄 페이지네이션과 충돌한다. PDF를 한 번 만들어 그것을
/// 인쇄하는 쪽이 화면과 결과가 같음을 보장한다.
enum HwpSamplePrinter {
    /// 인쇄 UI를 띄운다. 실패하면 사용자에게 보일 사유를 돌려준다.
    @discardableResult
    @MainActor
    static func print(pdfAt url: URL) -> String? {
        #if os(macOS)
            guard let pdf = PDFDocument(url: url) else {
                return "PDF를 열 수 없습니다"
            }
            guard let operation = pdf.printOperation(
                for: NSPrintInfo.shared,
                scalingMode: .pageScaleDownToFit,
                autoRotate: true
            ) else {
                return "인쇄 작업을 만들 수 없습니다"
            }
            operation.run()
            return nil
        #else
            guard UIPrintInteractionController.isPrintingAvailable else {
                return "이 기기에서는 인쇄를 지원하지 않습니다"
            }
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = url.deletingPathExtension().lastPathComponent
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printingItem = url
            controller.present(animated: true, completionHandler: nil)
            return nil
        #endif
    }
}
