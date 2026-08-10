import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

/// 해석 결과의 바이트 과금 — 변형이 **자기 몫으로** 든 래스터만 센다.
///
/// 디코드 원본은 `HwpImageCache`가 binItemId 하나로 한 번만 보유해 변형들이
/// 공유하므로, 그것까지 변형마다 세면 같은 바이트가 중복 계상된다. 그러면
/// 메모리에 넉넉히 들어가는 페이지가 예산 초과로 판정되고, PDF 경로는 그것을
/// 곧바로 `pageImagesExceedMemoryBudget`으로 바꿔 유효한 내보내기를 중단한다.
final class ImageByteAccountingTests: XCTestCase {
    private let side = 1000
    private let unit = HwpImageRenderStyle.hwpUnitsPerPixel
    /// 원본 ≈ 4MB + crop 4장 ≈ 160KB — 넉넉히 들어가지만, 원본을 변형마다
    /// 중복으로 세면 16MB로 계상돼 넘어간다.
    private let budget = 8_000_000

    private func makePNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination)) == true
        return data as Data
    }

    /// 같은 binItemId를 100×100씩 다른 자리로 자른 변형 4개.
    private func croppedVariants() -> HwpPaintList {
        let bottom = Int32(100 * unit)
        let commands: [HwpPaintCommand] = (0 ..< 4).map { index in
            let left = CGFloat(index * 100) * unit
            let right = CGFloat(index * 100 + 100) * unit
            let style = HwpImageRenderStyle(
                cropLeft: Int32(left), cropTop: 0,
                cropRight: Int32(right), cropBottom: bottom
            )
            let origin = CGFloat(index) * 110
            let rect = CGRect(x: 0, y: origin, width: 100, height: 100)
            return .drawImageReference(binItemId: 1, rect: rect, style: style)
        }
        return HwpPaintList(commands: commands)
    }

    private func makeStore() throws -> HwpImageStore {
        HwpImageStore(
            dataByBinItemId: [1: try makePNG()], extensionByBinItemId: [1: "png"]
        )
    }

    /// 공유 원본을 변형마다 세지 않으므로 넷 다 확정된다.
    func testSharedSourceIsNotChargedToEveryVariant() async throws {
        let paintList = croppedVariants()
        let provider = HwpPageImageProvider(
            store: try makeStore(), cache: HwpImageCache(maxBytes: budget)
        )
        provider.resolvedByteLimit = budget
        provider.retainOnlyImages(HwpPageImageProvider.imageVariantKeys(in: paintList))

        await provider.predecodeImageReferences(in: paintList)

        expect(provider.unsettledImageVariants(in: paintList)).to(beEmpty())
    }

    /// 그 페이지는 실제로 내보내진다 — 위 계상 오류는 곧장 내보내기 중단이었다.
    func testPageWithSharedSourceCropsExports() async throws {
        let page = HwpPage(
            size: CGSize(width: 300, height: 600),
            margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
            blocks: [],
            pageNumber: 1,
            paintList: croppedVariants()
        )
        let document = HwpDocument(
            pages: [page],
            metadata: HwpDocumentMetadata(title: "crops", pageCount: 1),
            unsupportedElements: [],
            imageStore: try makeStore()
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hwp-accounting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("crops.pdf")

        try await HwpPDFRenderer.render(document: document, to: url, imageByteLimit: budget)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        expect(pdf.numberOfPages) == 1
    }
}
