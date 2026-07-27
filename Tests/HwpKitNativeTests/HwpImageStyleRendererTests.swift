import CoreGraphics
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 알려진 픽셀 배치의 작은 이미지로 crop/밝기/효과 적용 결과를 픽셀 단위 검증한다.
final class HwpImageStyleRendererTests: XCTestCase {
    /// 왼쪽 절반 빨강, 오른쪽 절반 파랑인 4×2 이미지
    private func makeHalfRedHalfBlueImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 4,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 4 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 2, y: 0, width: 2, height: 2))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeGrayImage(gray: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 2 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try XCTUnwrap(context.makeImage())
    }

    /// 이미지를 RGBA8로 다시 그려 (x, y) 픽셀을 읽는다.
    private func pixel(at x: Int, _ y: Int, in image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return Array(buffer[offset ..< offset + 4])
    }

    func testCropKeepsOnlyLeftHalfPixels() throws {
        let image = try makeHalfRedHalfBlueImage()
        // 왼쪽 2×2 px = crop (0,0,150,150) HWPUNIT (px × 75)
        let style = HwpImageRenderStyle(cropRight: 150, cropBottom: 150)

        let cropped = HwpImageStyleRenderer.apply(style, to: image)

        expect(cropped.width) == 2
        expect(cropped.height) == 2
        // 모든 픽셀이 빨강 (파랑 절반이 잘려 나감)
        for x in 0 ..< 2 {
            for y in 0 ..< 2 {
                let rgba = try pixel(at: x, y, in: cropped)
                expect(rgba[0]) > 200
                expect(rgba[2]) < 50
            }
        }
    }

    func testNilOrIdentityStyleReturnsOriginal() throws {
        let image = try makeHalfRedHalfBlueImage()
        expect(HwpImageStyleRenderer.apply(nil, to: image)) === image
        let untouched = HwpImageStyleRenderer.apply(HwpImageRenderStyle(), to: image)
        expect(untouched.width) == 4
        let rgba = try pixel(at: 3, 0, in: untouched)
        expect(rgba[2]) > 200
    }

    func testGrayscaleEffectEqualizesChannels() throws {
        let image = try makeHalfRedHalfBlueImage()
        let style = HwpImageRenderStyle(effect: .grayscale)

        let gray = HwpImageStyleRenderer.apply(style, to: image)

        let rgba = try pixel(at: 0, 0, in: gray)
        expect(abs(Int(rgba[0]) - Int(rgba[1]))) <= 2
        expect(abs(Int(rgba[1]) - Int(rgba[2]))) <= 2
    }

    func testBlackWhiteEffectThresholdsToExtremes() throws {
        let dark = HwpImageStyleRenderer.apply(
            HwpImageRenderStyle(effect: .blackWhite),
            to: try makeGrayImage(gray: 0.15)
        )
        let bright = HwpImageStyleRenderer.apply(
            HwpImageRenderStyle(effect: .blackWhite),
            to: try makeGrayImage(gray: 0.9)
        )

        let darkPixel = try pixel(at: 0, 0, in: dark)
        let brightPixel = try pixel(at: 0, 0, in: bright)
        expect(darkPixel[0]) < 16
        expect(brightPixel[0]) > 240
    }

    func testBrightnessLightensMidGray() throws {
        let image = try makeGrayImage(gray: 0.5)
        let brightened = HwpImageStyleRenderer.apply(
            HwpImageRenderStyle(brightness: 60),
            to: image
        )

        let original = try pixel(at: 0, 0, in: image)
        let adjusted = try pixel(at: 0, 0, in: brightened)
        expect(Int(adjusted[0])) > Int(original[0]) + 30
    }

    func testCropCombinesWithEffect() throws {
        let image = try makeHalfRedHalfBlueImage()
        // 오른쪽 절반(파랑)만 남기고 grayscale
        let style = HwpImageRenderStyle(
            cropLeft: 150,
            cropTop: 0,
            cropRight: 300,
            cropBottom: 150,
            effect: .grayscale
        )

        let result = HwpImageStyleRenderer.apply(style, to: image)

        expect(result.width) == 2
        let rgba = try pixel(at: 0, 0, in: result)
        expect(abs(Int(rgba[0]) - Int(rgba[2]))) <= 2
    }
}
