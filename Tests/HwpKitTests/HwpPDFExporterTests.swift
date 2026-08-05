import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// PDF 내보내기 골든 — **폰트 비의존 지표만** 단언한다 (페이지 수·mediaBox·
/// 잉크 비영). 텍스트 벡터 바이트를 비교하면 설치 폰트에 좌우돼 CI에서 깨진다
/// (`HWP_HANCOM_FONTS` opt-in 이후 글리프는 기기 함수다).
final class HwpPDFExporterTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hwp-pdf-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: scratchDirectory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        try super.tearDownWithError()
    }

    private func outputURL(_ name: String = "export.pdf") -> URL {
        scratchDirectory.appendingPathComponent(name)
    }

    // MARK: - 합성 문서 (폰트 무관)

    /// 크기가 서로 다른 페이지들 — 용지 방향(표 13 bit 0)이 반영되면서 구역별로
    /// 실제로 생기는 형상이다. mediaBox를 페이지마다 넘기지 않으면 여기서 깨진다.
    private func makeDocument(sizes: [CGSize]) -> HwpDocument {
        let pages = sizes.enumerated().map { index, size in
            HwpPage(
                size: size,
                margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
                blocks: [],
                pageNumber: index + 1,
                paintList: HwpPaintList(commands: [
                    .fillRect(
                        rect: CGRect(x: 20, y: 20, width: 40, height: 40),
                        color: CGColor(gray: 0, alpha: 1)
                    ),
                ])
            )
        }
        return HwpDocument(
            pages: pages,
            metadata: HwpDocumentMetadata(title: "합성 문서", pageCount: pages.count),
            unsupportedElements: []
        )
    }

    func testExportedPageCountAndMediaBoxesMatchPages() async throws {
        let sizes = [
            CGSize(width: 595, height: 842), // A4 세로
            CGSize(width: 842, height: 595), // A4 가로
            CGSize(width: 612, height: 792), // 레터
        ]
        let url = outputURL()

        try await HwpPDFExporter().export(document: makeDocument(sizes: sizes), to: url)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        expect(pdf.numberOfPages) == sizes.count
        for (index, size) in sizes.enumerated() {
            let page = try XCTUnwrap(pdf.page(at: index + 1))
            let box = page.getBoxRect(.mediaBox)
            expect(box.width).to(beCloseTo(size.width, within: 0.5))
            expect(box.height).to(beCloseTo(size.height, within: 0.5))
        }
    }

    func testExportedDataOpensAsPDF() async throws {
        let document = makeDocument(sizes: [CGSize(width: 300, height: 400)])

        let data = try await HwpPDFExporter().exportData(document: document)

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        expect(pdf.numberOfPages) == 1
    }

    func testProgressReportsEveryPageInOrder() async throws {
        let document = makeDocument(
            sizes: Array(repeating: CGSize(width: 200, height: 300), count: 5)
        )
        let recorder = ProgressRecorder()

        try await HwpPDFExporter().export(document: document, to: outputURL()) { progress in
            recorder.record(progress)
        }

        expect(recorder.pageIndices) == [0, 1, 2, 3, 4]
        expect(recorder.lastFraction).to(beCloseTo(1.0, within: 0.0001))
    }

    /// 취소는 페이지 경계에서 걸리고, 열리지 않는 부분 파일을 남기지 않는다.
    func testCancellationRemovesPartialFile() async {
        let document = makeDocument(
            sizes: Array(repeating: CGSize(width: 400, height: 600), count: 200)
        )
        let url = outputURL()
        let box = CancellationBox()
        let recorder = ProgressRecorder()

        let task = Task {
            try await HwpPDFExporter().export(document: document, to: url) { progress in
                recorder.record(progress)
                // onProgress 2회 후 취소
                if progress.pageIndex >= 1 {
                    box.requestCancellation()
                }
            }
        }
        box.attach(task)

        await expect { try await task.value }
            .to(throwError(errorType: HwpPDFExportError.self) { error in
                if case .cancelled = error {} else {
                    fail("Expected .cancelled, got \(error)")
                }
            })
        expect(recorder.pageIndices.count) < document.pages.count
        expect(FileManager.default.fileExists(atPath: url.path)) == false
    }

    /// 마지막 페이지에서 들어온 취소도 취소로 끝난다. 루프 안 확인만 있으면
    /// 다음 반복이 없어 성공으로 끝나고, 호스트가 사용자의 취소 뒤에 저장
    /// 패널·인쇄를 연다 (샘플 배선이 실제로 그렇다).
    func testCancellationOnFinalPageDoesNotReportSuccess() async {
        let document = makeDocument(
            sizes: Array(repeating: CGSize(width: 200, height: 300), count: 3)
        )
        let lastIndex = document.pages.count - 1
        let url = outputURL("final-page-cancel.pdf")
        let box = CancellationBox()

        let task = Task {
            try await HwpPDFExporter().export(document: document, to: url) { progress in
                if progress.pageIndex == lastIndex {
                    box.requestCancellation()
                }
            }
        }
        box.attach(task)

        await expect { try await task.value }
            .to(throwError(errorType: HwpPDFExportError.self) { error in
                if case .cancelled = error {} else {
                    fail("Expected .cancelled, got \(error)")
                }
            })
        expect(FileManager.default.fileExists(atPath: url.path)) == false
    }

    /// 실패·취소는 사용자의 **이전 PDF**를 파괴하지 않는다. `CGDataConsumer(url:)`
    /// 는 생성 순간 대상 파일을 0바이트로 자르므로(실측), 목적지에 직접 쓰면
    /// 덮어쓰기 도중의 취소가 복구 불가능한 손실이 된다.
    func testCancellationLeavesExistingDestinationIntact() async throws {
        let url = outputURL("existing.pdf")
        let original = Data("이전에 내보낸 PDF".utf8)
        try original.write(to: url)
        let document = makeDocument(
            sizes: Array(repeating: CGSize(width: 400, height: 600), count: 200)
        )
        let box = CancellationBox()

        let task = Task {
            try await HwpPDFExporter().export(document: document, to: url) { progress in
                if progress.pageIndex >= 1 {
                    box.requestCancellation()
                }
            }
        }
        box.attach(task)
        await expect { try await task.value }
            .to(throwError(errorType: HwpPDFExportError.self) { _ in })

        let survived = try Data(contentsOf: url)
        expect(survived) == original
    }

    /// 성공하면 실제로 교체한다 — 보존이 "덮어쓰기 실패"로 퇴화하지 않게.
    func testSuccessfulExportReplacesExistingDestination() async throws {
        let url = outputURL("replace.pdf")
        try Data("이전에 내보낸 PDF".utf8).write(to: url)

        try await HwpPDFExporter().export(
            document: makeDocument(sizes: [CGSize(width: 200, height: 300)]), to: url
        )

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        expect(pdf.numberOfPages) == 1
    }

    func testEmptyDocumentThrows() async {
        let empty = HwpDocument.empty
        let url = outputURL()

        await expect { try await HwpPDFExporter().export(document: empty, to: url) }
            .to(throwError(errorType: HwpPDFExportError.self) { error in
                if case .emptyDocument = error {} else {
                    fail("Expected .emptyDocument, got \(error)")
                }
            })
    }

    // MARK: - 픽스처 (실문서 기하)

    /// 실문서 전 페이지의 mediaBox가 렌더 페이지 크기와 일치한다.
    func testFixtureExportMatchesRenderedPageSizes() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let fixture = try XCTUnwrap(fixtures.first { $0.id == "multi-section" })
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixture.documentURL)
        expect(document.pages.count) >= 2
        let url = outputURL("multi-section.pdf")

        try await HwpPDFExporter().export(document: document, to: url)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        expect(pdf.numberOfPages) == document.pages.count
        for (index, page) in document.pages.enumerated() {
            let pdfPage = try XCTUnwrap(pdf.page(at: index + 1))
            let box = pdfPage.getBoxRect(.mediaBox)
            expect(box.width).to(beCloseTo(page.size.width, within: 0.5))
            expect(box.height).to(beCloseTo(page.size.height, within: 0.5))
        }
    }

    /// 이미지 픽스처를 내보낸 PDF를 래스터화해 잉크가 실제로 찍혔는지 본다 —
    /// 프리디코드가 비면 이미지 자리가 회색/공백으로 남는다.
    func testImageFixtureExportRasterizesWithInk() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let fixture = try XCTUnwrap(fixtures.first { $0.id == "BinData" })
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixture.documentURL)
        let firstPage = try XCTUnwrap(document.pages.first)
        // 이미지 경로를 실제로 밟는 픽스처여야 이 스모크가 의미를 갖는다
        expect(firstPage.paintList.commands.contains { command in
            if case .drawImageReference = command {
                return true
            }
            return false
        }) == true
        let url = outputURL("bindata.pdf")

        try await HwpPDFExporter().export(document: document, to: url)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(pdf.page(at: 1))
        let rasterized = try rasterize(page: page, width: 300, height: 400)
        let grid = try FixturePreview.inkGrid(
            of: rasterized, width: 300, height: 400, columns: 6, rows: 8
        )
        expect(grid.reduce(0, +)) > 0
    }

    /// PDF 페이지 래스터화가 같은 페이지의 비트맵 렌더와 같은 잉크 분포를 낸다.
    ///
    /// 페이지 수·mediaBox·잉크 비영은 **상하 반전을 통과시킨다** — flip 보정은
    /// 무분기라 조용히 깨지면 이런 지표로는 안 걸린다. 두 경로 모두 같은 기기의
    /// 같은 폰트를 쓰므로 이 비교는 환경 독립이고, 반전 대조군으로 이 가드에
    /// 실제로 이빨이 있음을 함께 보인다.
    func testExportedPageMatchesBitmapRenderInkDistribution() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let fixture = try XCTUnwrap(fixtures.first { $0.id == "noori" })
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixture.documentURL)
        let page = try XCTUnwrap(document.pages.first)
        let url = outputURL("noori.pdf")
        let width = 300
        let height = Int((CGFloat(width) * page.size.height / page.size.width).rounded())

        try await HwpPDFExporter().export(document: document, to: url)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let rasterized = try rasterize(
            page: try XCTUnwrap(pdf.page(at: 1)), width: width, height: height
        )
        let bitmap = try await FixturePreview.renderImage(
            page: page,
            imageStore: document.imageStore,
            pixelWidth: width,
            pixelHeight: height
        )
        let columns = 6
        let rows = 8
        let pdfGrid = try FixturePreview.inkGrid(
            of: rasterized, width: width, height: height, columns: columns, rows: rows
        )
        let bitmapGrid = try FixturePreview.inkGrid(
            of: bitmap, width: width, height: height, columns: columns, rows: rows
        )
        let flippedGrid = Self.verticallyFlipped(bitmapGrid, columns: columns, rows: rows)

        let aligned = FixturePreview.meanAbsoluteError(pdfGrid, bitmapGrid)
        let flipped = FixturePreview.meanAbsoluteError(pdfGrid, flippedGrid)
        // 임계는 래스터라이저 차이(안티앨리어싱·서브픽셀)만 흡수할 만큼만 준다
        expect(aligned) < 0.02
        expect(flipped) > aligned * 2
    }

    /// 잉크 그리드를 행 방향으로 뒤집는다 (flip 회귀 대조군).
    private static func verticallyFlipped(
        _ grid: [Double],
        columns: Int,
        rows: Int
    ) -> [Double] {
        var flipped = [Double](repeating: 0, count: grid.count)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                flipped[row * columns + column] = grid[(rows - 1 - row) * columns + column]
            }
        }
        return flipped
    }

    /// PDF 페이지를 흰 바탕 비트맵으로 그린다 (mediaBox를 캔버스에 맞춰 스케일).
    private func rasterize(page: CGPDFPage, width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let box = page.getBoxRect(.mediaBox)
        if box.width > 0, box.height > 0 {
            context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        }
        context.drawPDFPage(page)
        return try XCTUnwrap(context.makeImage())
    }
}

/// 진행 콜백은 임의 스레드에서 발화하므로 잠금으로 모은다.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var indices: [Int] = []
    private var fraction: Double = 0

    func record(_ progress: HwpPDFExportProgress) {
        lock.lock()
        indices.append(progress.pageIndex)
        fraction = progress.fractionCompleted
        lock.unlock()
    }

    var pageIndices: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return indices
    }

    var lastFraction: Double {
        lock.lock()
        defer { lock.unlock() }
        return fraction
    }
}

/// 진행 콜백 안에서 자기 태스크를 취소하기 위한 상자 — 콜백이 태스크 대입보다
/// 먼저 발화해도 취소 요청이 유실되지 않는다.
private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    private var pendingCancellation = false

    func attach(_ task: Task<Void, Error>) {
        lock.lock()
        self.task = task
        let shouldCancel = pendingCancellation
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func requestCancellation() {
        lock.lock()
        let task = task
        pendingCancellation = true
        lock.unlock()
        task?.cancel()
    }
}
