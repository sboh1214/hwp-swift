import CoreGraphics
import Foundation
import HwpKitCore

public enum HwpPDFRenderError: Error, Sendable {
    case emptyDocument
    case contextCreationFailed
    case fileWriteFailed(path: String)
    case pageImagesExceedMemoryBudget(pageIndex: Int)
    case incompleteOutput(expectedPages: Int, writtenPages: Int?)
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
        case let .pageImagesExceedMemoryBudget(pageIndex):
            "Page \(pageIndex + 1) references more image data than the decode budget allows"
        case let .incompleteOutput(expectedPages, writtenPages):
            if let writtenPages {
                "PDF output is incomplete: wrote \(writtenPages) of \(expectedPages) pages"
            } else {
                "PDF output could not be reopened after writing "
                    + "(\(expectedPages) pages expected) — the volume may be full"
            }
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
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws {
        try await render(
            document: document,
            to: url,
            imageByteLimit: HwpPageImageProvider.defaultResolvedByteLimit,
            onProgress: onProgress
        )
    }

    /// `imageByteLimit`는 테스트가 예산 초과 경로를 작은 이미지로 재현하기 위한
    /// internal 이음매다 — 낮추면 정상 문서도 실패하므로 공개하지 않는다.
    static func render(
        document: HwpDocument,
        to url: URL,
        imageByteLimit: Int,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws {
        guard !document.pages.isEmpty else { throw HwpPDFRenderError.emptyDocument }
        // 목적지에 직접 쓰지 않는다: `CGDataConsumer(url:)`는 **생성 순간** 그
        // 파일을 0바이트로 자르므로(실측), 취소·실패가 사용자의 이전 PDF를
        // 파괴한다. 임시 파일에 완성한 뒤에만 목적지를 건드린다.
        let staging = stagingDirectory(for: url)
        let stagingFile = staging.url
            .appendingPathComponent("hwp-pdf-export-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: stagingFile)
            if staging.isOwned {
                try? FileManager.default.removeItem(at: staging.url)
            }
        }
        guard let consumer = CGDataConsumer(url: stagingFile as CFURL) else {
            throw HwpPDFRenderError.fileWriteFailed(path: url.path)
        }
        try await write(
            document: document,
            consumer: consumer,
            imageByteLimit: imageByteLimit,
            onProgress: onProgress
        )
        try install(stagingFile, at: url, expectedPages: document.pages.count)
    }

    /// 다 쓴 PDF를 **실제로 열어 본다**. CG는 쓰기 실패를 로그로만 알린다 —
    /// `endPDFPage`/`closePDF`가 `Void`라 디스크가 차도 `write`가 정상 종료하고
    /// 절단 파일이 남는다 (실측: 6MB 볼륨에 11MB PDF → 열리지 않는 5.2MB 파일,
    /// 예외 없음). 그대로 설치하면 멀쩡하던 기존 PDF가 못 여는 파일로 바뀐다.
    static func validate(_ staging: URL, expectedPages: Int) throws {
        guard let pdf = CGPDFDocument(staging as CFURL) else {
            throw HwpPDFRenderError.incompleteOutput(
                expectedPages: expectedPages, writtenPages: nil
            )
        }
        guard pdf.numberOfPages == expectedPages else {
            throw HwpPDFRenderError.incompleteOutput(
                expectedPages: expectedPages, writtenPages: pdf.numberOfPages
            )
        }
    }

    /// 스테이징 자리는 목적지와 **같은 볼륨**이어야 한다 — `replaceItemAt`은 두
    /// 항목이 같은 볼륨일 것을 요구해서, 앱 임시 디렉터리에 두면 외장 드라이브의
    /// 기존 파일을 덮어쓸 때 EXDEV로 실패한다 (실측). `appropriateFor:`가 그
    /// 볼륨의 교체용 디렉터리를 준다.
    ///
    /// 그 자리를 못 얻으면 앱 임시 디렉터리로 돌아간다: 크로스 디바이스를 복사로
    /// 처리하는 `moveItem` 덕에 **새 파일 생성은 살고**, 그 볼륨의 덮어쓰기만
    /// 실패한다 (전부 실패시키는 것보다 낫다).
    private static func stagingDirectory(for url: URL) -> (url: URL, isOwned: Bool) {
        let replacement = try? FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        guard let replacement else {
            return (FileManager.default.temporaryDirectory, false)
        }
        return (replacement, true)
    }

    /// 완성된 임시 파일을 목적지로 옮긴다. 검증을 **여기 안에** 두는 이유는
    /// 그것이 설치의 전제이기 때문이다 — 밖에 두면 호출을 빠뜨려도 테스트가
    /// 통과한다 (실제로 그랬다).
    static func install(_ staging: URL, at url: URL, expectedPages: Int) throws {
        try validate(staging, expectedPages: expectedPages)
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: url)
            }
        } catch {
            throw HwpPDFRenderError.fileWriteFailed(path: url.path)
        }
    }

    /// 문서를 PDF 바이트로 만든다 (전량이 메모리에 남는다 — 대형 문서는
    /// `render(document:to:)`의 파일 스트리밍 쪽을 쓸 것).
    public static func renderData(
        document: HwpDocument,
        onProgress: (@Sendable (HwpPDFExportProgress) -> Void)? = nil
    ) async throws -> Data {
        guard !document.pages.isEmpty else { throw HwpPDFRenderError.emptyDocument }
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else {
            throw HwpPDFRenderError.contextCreationFailed
        }
        try await write(
            document: document,
            consumer: consumer,
            imageByteLimit: HwpPageImageProvider.defaultResolvedByteLimit,
            onProgress: onProgress
        )
        return buffer as Data
    }

    private static func write(
        document: HwpDocument,
        consumer: CGDataConsumer,
        imageByteLimit: Int,
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
        // 이미지는 문서 전용 provider와 **전용 캐시**로 해석한다 — 캐시가
        // binItemId 하나로 키를 잡으므로, 캐시를 문서 간에 공유하면 provider를
        // 새로 만들어도 다른 문서의 비트맵이 그대로 히트한다.
        //
        let provider: HwpPageImageProvider? = document.imageStore.isEmpty
            ? nil
            : HwpPageImageProvider(store: document.imageStore, cache: HwpImageCache())
        provider?.resolvedByteLimit = imageByteLimit
        defer { provider?.cancelOutstanding() }

        for (index, page) in document.pages.enumerated() {
            try Task.checkCancellation()
            if let provider {
                // 프리디코드 결과가 draw 전에 바이트 예산으로 축출되지 않도록
                // 이 페이지 변형만 고정한다 (다음 페이지에서 자연히 풀린다).
                provider.setPinnedImages(HwpPageImageProvider.imageVariantKeys(in: page.paintList))
                await provider.predecodeImageReferences(in: page.paintList)
                try Task.checkCancellation()
                // 프리디코드 뒤에도 확정되지 않은 변형이 있으면 그 페이지 작업셋이
                // 바이트 예산을 넘겨 축출된 것이다. 뷰는 다음 재드로우가 되살리지만
                // 여기는 draw가 한 번뿐이라, 회색 로딩 사각형을 PDF에 박아 넣는
                // 대신 오류로 끝낸다 (디코드 실패는 제외 — 그건 뷰와 같이
                // 플레이스홀더가 정답이다).
                guard provider.unsettledImageVariants(in: page.paintList).isEmpty else {
                    throw HwpPDFRenderError.pageImagesExceedMemoryBudget(pageIndex: index)
                }
            }
            context.beginPDFPage(pageInfo(for: page))
            draw(page: page, in: context, provider: provider)
            context.endPDFPage()
            onProgress?(
                HwpPDFExportProgress(pageIndex: index, pageCount: document.pages.count)
            )
        }
        context.closePDF()
        // 마지막 페이지의 draw·진행 콜백에서 들어온 취소는 다음 반복이 없어
        // 루프 안의 어떤 확인도 보지 못한다 — 호출부가 부분 파일을 지우도록
        // 여기서 한 번 더 본다.
        try Task.checkCancellation()
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
