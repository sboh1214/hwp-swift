import CoreGraphics
import Foundation
import HwpKitNative
import Nimble
import XCTest

final class PlatformTypesTests: XCTestCase {
    func testPlatformViewTypeAliasResolves() {
        expect(PlatformView.self == PlatformView.self).to(beTrue())
    }

    func testPlatformViewConstruction() {
        let view = PlatformView()
        expect(view).toNot(beNil())
    }

    func testPlatformScrollViewConstruction() {
        let scrollView = PlatformScrollView()
        expect(scrollView).toNot(beNil())
    }

    func testPlatformColorConstruction() {
        let color = PlatformColor.black
        expect(color).toNot(beNil())
    }

    func testPlatformImageFromCGImage() {
        let cgImage = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        let image = PlatformImage(hwpCgImage: cgImage)
        expect(image).toNot(beNil())
    }

    func testPlatformColorFromCGColor() {
        let cgColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        #if os(macOS)
            let color = NSColor.hwpColor(from: cgColor)
        #elseif os(iOS)
            let color = PlatformColor(hwpCgColor: cgColor)
        #endif
        expect(color).toNot(beNil())
    }

    func testPlatformFontConstruction() {
        #if os(macOS)
            let font = NSFont.systemFont(ofSize: 12)
        #elseif os(iOS)
            let font = UIFont.systemFont(ofSize: 12)
        #endif
        expect(font).toNot(beNil())
    }
}
