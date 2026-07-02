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
            .fillRect(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: CGColor(gray: 0, alpha: 1)),
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
            .drawText(attributedString: attributedString, origin: CGPoint(x: 8, y: 8), lineWidth: 180),
        ])

        let context = try XCTUnwrap(makeBitmapContext(width: 200, height: 120))
        layer.draw(in: context)
        let image = context.makeImage()

        expect(image).toNot(beNil())
    }
}
