import CoreGraphics
import Foundation
import HwpKitCore

public enum HwpPDFRenderError: Error, Sendable {
    case emptyDocument
    case contextCreationFailed
    case fileWriteFailed(path: String)
}

extension HwpPDFRenderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyDocument:
            "Document has no pages to export"
        case .contextCreationFailed:
            "Could not create a PDF context"
        case let .fileWriteFailed(path):
            "Could not open '\(path)' for writing"
        }
    }
}

extension HwpPDFRenderError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// 페이지네이션된 `HwpDocument`를 CGPDFContext에 기록한다.
///
/// 뷰 계층과 무관하게 임의 `CGContext`에 그리는 `HwpPageLayer.draw(in:)`를
/// 그대로 쓴다 — 즉 화면과 같은 paint list, 같은 조판이다. flip 보정도 무분기다:
/// macOS의 독립 레이어는 `contentsAreFlipped() == false`라 스스로 뒤집고,
/// iOS는 CGPDFContext가 y-up(`ctm.d > 0`)이라 같은 가지로 들어온다.
///
/// 메모 패널(`HwpPage.memoPanel`)은 종이 밖 편집 화면 장식이라 `page.paintList`만
/// 그리는 이 경로에서 자연히 빠진다 (한글의 인쇄 뷰·PrvImage와 같다).
public enum HwpPDFRenderer {
    /// 문서를 `url`에 PDF로 기록한다. 페이지 하나씩 스트리밍하므로 상주 메모리는
    /// 1페이지 몫이다. 취소되면 부분 파일을 지우고 `CancellationError`를 던진다.
    public static func render(
        document: HwpDocument,
        to url: URL,
        cache: HwpImageCache? = nil,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws {
        guard !document.pages.isEmpty else { throw HwpPDFRenderError.emptyDocument }
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw HwpPDFRenderError.fileWriteFailed(path: url.path)
        }
        do {
            try await write(
                document: document, consumer: consumer, cache: cache, onProgress: onProgress
            )
        } catch {
            // 취소·실패로 남은 부분 파일은 지운다 — 열리지 않는 PDF가 사용자
            // 디렉터리에 남으면 성공과 구분되지 않는다.
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// 문서를 PDF 바이트로 만든다 (전량이 메모리에 남는다 — 대형 문서는
    /// `render(document:to:)`의 파일 스트리밍 쪽을 쓸 것).
    public static func renderData(
        document: HwpDocument,
        cache: HwpImageCache? = nil,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws -> Data {
        guard !document.pages.isEmpty else { throw HwpPDFRenderError.emptyDocument }
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else {
            throw HwpPDFRenderError.contextCreationFailed
        }
        try await write(
            document: document, consumer: consumer, cache: cache, onProgress: onProgress
        )
        return buffer as Data
    }

    private static func write(
        document: HwpDocument,
        consumer: CGDataConsumer,
        cache: HwpImageCache?,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)?
    ) async throws {
        // 페이지마다 mediaBox를 따로 주므로 컨텍스트 기본값은 첫 페이지 크기로
        // 둔다 (용지 방향·구역별 용지 크기가 다르면 페이지별 값이 이긴다).
        var defaultBox = CGRect(origin: .zero, size: document.pages[0].size)
        guard let context = CGContext(
            consumer: consumer, mediaBox: &defaultBox, documentInfo(of: document)
        ) else {
            throw HwpPDFRenderError.contextCreationFailed
        }
        // 이미지는 문서 전용 provider로 해석한다 — binItemId가 문서-로컬 키라
        // 뷰어의 provider를 재사용하면 다른 문서의 이미지가 섞인다.
        let provider = document.imageStore.isEmpty
            ? nil
            : HwpPageImageProvider(store: document.imageStore, cache: cache ?? HwpImageCache())
        defer { provider?.cancelOutstanding() }

        for (index, page) in document.pages.enumerated() {
            try Task.checkCancellation()
            if let provider {
                // 프리디코드 결과가 draw 전에 바이트 예산으로 축출되지 않도록
                // 이 페이지 변형만 고정한다 (다음 페이지에서 자연히 풀린다).
                provider.setPinnedImages(HwpPageImageProvider.imageVariantKeys(in: page.paintList))
                await provider.predecodeImageReferences(in: page.paintList)
                try Task.checkCancellation()
            }
            context.beginPDFPage(pageInfo(for: page))
            draw(page: page, in: context, provider: provider)
            context.endPDFPage()
            onProgress?(
                HwpPDFExportProgress(pageIndex: index, pageCount: document.pages.count)
            )
        }
        context.closePDF()
    }

    /// 페이지 크기를 mediaBox로 넘긴다. 값은 **CGRect를 값째 담은 CFData**여야
    /// 한다 (참조 전달이 아니다) — 형식이 틀리면 CG가 조용히 기본 상자를 쓴다.
    private static func pageInfo(for page: HwpPage) -> CFDictionary {
        var box = CGRect(origin: .zero, size: page.size)
        let boxData = withUnsafeBytes(of: &box) { Data($0) }
        return [kCGPDFContextMediaBox: boxData as CFData] as CFDictionary
    }

    private static func documentInfo(of document: HwpDocument) -> CFDictionary {
        var info: [CFString: Any] = [kCGPDFContextCreator: "hwp-swift"]
        if let title = document.metadata.title, !title.isEmpty {
            info[kCGPDFContextTitle] = title
        }
        return info as CFDictionary
    }

    private static func draw(
        page: HwpPage,
        in context: CGContext,
        provider: HwpPageImageProvider?
    ) {
        // PDF 페이지는 기본이 투명이라 배경을 뷰어·프린터가 정하게 두면 종이
        // 은유가 깨진다 — 화면의 페이지 레이어 배경과 같은 흰 종이를 깐다.
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: page.size))
        context.restoreGState()

        let layer = HwpPageLayer()
        layer.bounds = CGRect(origin: .zero, size: page.size)
        layer.pageHeight = page.size.height
        layer.imageProvider = provider
        layer.paintList = page.paintList
        layer.draw(in: context)
    }
}
