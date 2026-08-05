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
    // 인쇄 UI를 띄운다. 실패하면 사용자에게 보일 사유를 돌려준다.
    // `onFinish`는 인쇄 대화상자가 닫힌 뒤(= 파일을 더 안 읽는 시점) 불린다 —
    // 호출부가 임시 파일을 지울 자리다. 실패를 반환하면 발화하지 않는다.
    #if os(macOS)
        @discardableResult
        @MainActor
        static func print(
            pdfAt url: URL,
            jobName: String,
            onFinish: @escaping @Sendable () -> Void
        ) -> String? {
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
            // 백킹 PDF는 UUID 파일명이라 이것을 안 주면 인쇄 대화상자·큐에
            // 그 UUID가 그대로 보인다.
            operation.jobTitle = jobName
            operation.run()
            onFinish()
            return nil
        }
    #else
        /// `anchor`는 인쇄를 누른 창의 뷰여야 한다 (iPad 팝오버 기준점).
        @discardableResult
        @MainActor
        static func print(
            pdfAt url: URL,
            jobName: String,
            anchor: UIView?,
            onFinish: @escaping @Sendable () -> Void
        ) -> String? {
            guard UIPrintInteractionController.isPrintingAvailable else {
                return "이 기기에서는 인쇄를 지원하지 않습니다"
            }
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = jobName
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printingItem = url
            // UIKit 헤더가 표시를 기기별로 가른다: `presentAnimated:`는 // iPhone,
            // `presentFromRect:inView:`·`presentFromBarButtonItem:`은 // iPad.
            // 이 타깃은 iPad(device family 2)도 지원하므로 분기한다.
            let completion: UIPrintInteractionController.CompletionHandler = { _, _, _ in
                onFinish()
            }
            // 표시가 시작되지 않으면(예: 다른 모달이 떠 있음) completion도 오지
            // 않는다 — 성공으로 돌려주면 호출부의 임시 파일 정리가 통째로 건너뛴다.
            guard UIDevice.current.userInterfaceIdiom == .pad else {
                guard controller.present(animated: true, completionHandler: completion) else {
                    return "인쇄 UI를 띄우지 못했습니다"
                }
                return nil
            }
            guard let anchor, anchor.window != nil else {
                return "인쇄 UI를 띄울 창을 찾지 못했습니다"
            }
            guard controller.present(
                from: anchor.bounds, in: anchor, animated: true, completionHandler: completion
            ) else {
                return "인쇄 UI를 띄우지 못했습니다"
            }
            return nil
        }
    #endif
}

#if !os(macOS)
    /// iPad 인쇄 팝오버의 앵커를 SwiftUI 계층에서 받아 오는 1×1 브리지.
    ///
    /// 전역 `UIApplication.shared.connectedScenes` 탐색으로는 안 된다:
    /// `connectedScenes`는 Set이라 순서 보장이 없고 다중 scene에서는 창마다
    /// key window가 있어, 인쇄를 누른 창이 아닌 곳에 팝오버가 뜨거나 표시가
    /// 실패한다. 이 뷰는 인쇄 버튼 옆에 놓이므로 정의상 그 창에 있다.
    struct HwpPrintAnchor: UIViewRepresentable {
        final class Box {
            weak var view: UIView?
        }

        let box: Box

        func makeUIView(context _: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            box.view = view
            return view
        }

        func updateUIView(_ view: UIView, context _: Context) {
            box.view = view
        }
    }
#endif
