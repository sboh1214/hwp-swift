import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

/// PDF 렌더러의 **자원 한도** 가드 (#74 리뷰 2차).
///
/// 공개 표면(`HwpKit.HwpPDFExporter`)의 골든은 `HwpKitTests`에 있다. 여기는
/// 예산 초과 경로를 작은 이미지로 재현하려고 internal 이음매
/// (`render(document:to:imageByteLimit:)`)를 쓰므로 이 타깃에 둔다.
final class HwpPDFRendererTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hwp-pdf-renderer-\(UUID().uuidString)")
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

    /// 한 페이지 작업셋이 바이트 예산을 넘으면 오류로 끝낸다. 상한을 끄면
    /// 조작 문서가 메모리를 고갈시키고, 상한만 두고 넘어가면 회색 로딩 사각형이
    /// PDF에 박힌다 — 둘 다 안 되므로 예산은 지키고 결과는 실패로 알린다.
    func testExportFailsWhenPageImagesExceedByteBudget() async throws {
        let document = try makeImageDocument(imageCount: 3)
        let url = scratchDirectory.appendingPathComponent("over-budget.pdf")

        await expect {
            try await HwpPDFRenderer.render(document: document, to: url, imageByteLimit: 1)
        }.to(throwError(errorType: HwpPDFRenderError.self) { error in
            if case .pageImagesExceedMemoryBudget = error {} else {
                fail("Expected .pageImagesExceedMemoryBudget, got \(error)")
            }
        })
        expect(FileManager.default.fileExists(atPath: url.path)) == false
    }

    /// 같은 문서가 기본 예산에서는 통과한다 — 위 가드가 상시 실패가 아님을 보인다.
    func testExportSucceedsWithinDefaultByteBudget() async throws {
        let document = try makeImageDocument(imageCount: 3)
        let url = scratchDirectory.appendingPathComponent("within-budget.pdf")

        try await HwpPDFRenderer.render(document: document, to: url)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        expect(pdf.numberOfPages) == 1
    }

    // MARK: - 합성 문서

    private func makeImageDocument(imageCount: UInt32) throws -> HwpDocument {
        let payload = try makePNGData()
        var dataById: [UInt32: Data] = [:]
        var extensionById: [UInt32: String] = [:]
        var commands: [HwpPaintCommand] = []
        for key in 1 ... imageCount {
            dataById[key] = payload
            extensionById[key] = "png"
            commands.append(.drawImageReference(
                binItemId: key,
                rect: CGRect(x: 10, y: CGFloat(key) * 60, width: 50, height: 50)
            ))
        }
        let page = HwpPage(
            size: CGSize(width: 300, height: 400),
            margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
            blocks: [],
            pageNumber: 1,
            paintList: HwpPaintList(commands: commands)
        )
        return HwpDocument(
            pages: [page],
            metadata: HwpDocumentMetadata(title: "images", pageCount: 1),
            unsupportedElements: [],
            imageStore: HwpImageStore(
                dataByBinItemId: dataById, extensionByBinItemId: extensionById
            )
        )
    }

    /// 실제 디코드 경로를 타도록 PNG 바이트를 만든다 (포맷은 매직 바이트로 판별).
    private func makePNGData(width: Int = 32, height: Int = 32) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination)) == true
        return data as Data
    }
}
