import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

private func makeBitmapContext(width: Int = 100, height: Int = 100) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func topLeftPixel(in image: CGImage) -> [UInt8] {
    guard let data = image.dataProvider?.data else { return [] }
    let bytes = CFDataGetBytePtr(data)
    return (0 ..< 4).map { bytes?[$0] ?? 255 }
}

final class HwpPageLayerTests: XCTestCase {
    func testFillRectDrawsBlackPixel() throws {
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.pageHeight = 100
        layer.paintList = HwpPaintList(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: 100, height: 100),
                color: CGColor(gray: 0, alpha: 1)
            ),
        ])

        let context = try XCTUnwrap(makeBitmapContext())
        layer.draw(in: context)
        let image = try XCTUnwrap(context.makeImage())
        let pixel = topLeftPixel(in: image)

        expect(pixel.count) == 4
        expect(pixel[0]) < 16
        expect(pixel[1]) < 16
        expect(pixel[2]) < 16
    }

    func testDrawImageReferenceWithoutProviderDrawsPlaceholder() throws {
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.pageHeight = 100
        layer.paintList = HwpPaintList(commands: [
            .drawImageReference(
                binItemId: 1,
                rect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
        ])

        let context = try XCTUnwrap(makeBitmapContext())
        layer.draw(in: context)
        let image = try XCTUnwrap(context.makeImage())
        let pixel = topLeftPixel(in: image)

        // provider가 없으면 placeholder 배경 (gray 0.9)이 채워진다
        expect(pixel.count) == 4
        expect(pixel[0]) > 180
        expect(pixel[0]) < 250
        expect(pixel[3]) == 255
    }

    func testDrawImageReferenceWithResolvedProviderDrawsImage() throws {
        // 1x1 빨간 픽셀 PNG
        let redPixelPNG = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
            0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x03, 0x01, 0x01, 0x00, 0xC9, 0xFE, 0x92, 0xEF, 0x00, 0x00, 0x00,
            0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ])
        let store = HwpImageStore(
            dataByBinItemId: [1: redPixelPNG],
            extensionByBinItemId: [1: "png"]
        )
        let provider = HwpPageImageProvider(store: store, cache: HwpImageCache())
        let resolved = expectation(description: "image resolved")
        provider.onImageResolved = { _ in resolved.fulfill() }
        provider.requestImage(for: 1)
        wait(for: [resolved], timeout: 5)
        expect(provider.cachedImage(for: 1)).toNot(beNil())

        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.pageHeight = 100
        layer.imageProvider = provider
        layer.paintList = HwpPaintList(commands: [
            .drawImageReference(
                binItemId: 1,
                rect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
        ])

        let context = try XCTUnwrap(makeBitmapContext())
        layer.draw(in: context)
        let image = try XCTUnwrap(context.makeImage())
        let pixel = topLeftPixel(in: image)

        expect(pixel.count) == 4
        expect(pixel[0]) > 200 // red 채널
        expect(pixel[1]) < 64
        expect(pixel[2]) < 64
    }

    func testDrawTextExecutesWithoutCrash() throws {
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
        layer.pageHeight = 120
        let attributedString = NSAttributedString(
            string: "Hello HWP",
            attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                .foregroundColor: CGColor(gray: 0, alpha: 1),
            ]
        )
        layer.paintList = HwpPaintList(commands: [
            .drawText(
                attributedString: attributedString,
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])

        let context = try XCTUnwrap(makeBitmapContext(width: 200, height: 120))
        layer.draw(in: context)
        let image = context.makeImage()

        expect(image).toNot(beNil())
    }
}
