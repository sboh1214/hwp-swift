import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
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
    /// CA presentation 사본 (init(layer:))도 imageProvider를 유지해
    /// .drawImageReference를 플레이스홀더 없이 그린다 (R30 #5).
    func testLayerCopyKeepsImageProvider() {
        let layer = HwpPageLayer()
        layer.pageHeight = 100
        layer.paintList = HwpPaintList(commands: [])
        let provider = HwpPageImageProvider(
            store: HwpImageStore(),
            cache: HwpImageCache()
        )
        layer.imageProvider = provider

        let copy = HwpPageLayer(layer: layer)

        expect(copy.imageProvider).to(beIdenticalTo(provider))
        expect(copy.pageHeight) == 100
        expect(copy.paintList).toNot(beNil())
    }

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

    /// 플레이스홀더 라벨 "[이미지]"의 폰트는 한글 글리프를 직접 가진다 —
    /// "Helvetica" 하드코딩 회귀 방지 (#125). Helvetica는 한글이 없어 CoreText
    /// 캐스케이드 폴백에 전적으로 의존했다.
    func testPlaceholderFontCoversHangulGlyphsDirectly() {
        let characters = Array("이미지".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)

        let covered = CTFontGetGlyphsForCharacters(
            HwpPageLayer.placeholderFont, characters, &glyphs, characters.count
        )

        expect(covered) == true
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

    /// 페이지 상하 반전 회귀 방지: 레이어 자체 isGeometryFlipped를 켜면
    /// flipped NSView 안에서 이중 flip이 되어 페이지가 뒤집힌다.
    func testPageLayerDoesNotFlipItsOwnGeometry() {
        expect(HwpPageLayer().isGeometryFlipped) == false
    }

    /// draw(in:)는 환경과 무관하게 top-down으로 정규화되어야 한다:
    /// 페이지 상단(y 0..10)에 그린 검은 띠가 이미지의 위쪽 행에 나타난다.
    func testTopStripRendersAtTopOfImage() throws {
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.pageHeight = 100
        layer.paintList = HwpPaintList(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: 100, height: 10),
                color: CGColor(gray: 0, alpha: 1)
            ),
        ])

        let context = try XCTUnwrap(makeBitmapContext())
        layer.draw(in: context)
        let image = try XCTUnwrap(context.makeImage())
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))

        /// CGImage의 byte row 0 = 이미지 최상단
        func alpha(atRow row: Int) -> UInt8 {
            bytes[row * image.bytesPerRow + 3]
        }
        expect(alpha(atRow: 5)) > 200 // 상단 띠는 칠해져 있고
        expect(alpha(atRow: 95)) < 16 // 하단은 비어 있다
    }

    // contentsScale은 뷰가 관리한다 — 기본값(1.0)이면 Retina에서 흐릿해진다.
    // (macOS 뷰 경로 검증)
    #if os(macOS)
        @MainActor
        func testDocumentViewAppliesRetinaContentsScaleToPageLayers() {
            let view = HwpDocumentNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            view.document = HwpDocument(
                pages: [HwpPage(
                    size: CGSize(width: 100, height: 100),
                    margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
                    blocks: [],
                    pageNumber: 1
                )],
                metadata: HwpDocumentMetadata(pageCount: 1),
                unsupportedElements: []
            )
            view.updateVisiblePages(range: 0 ..< 1)

            for layer in view.pageLayers.values {
                expect(layer.contentsScale) >= 1
                // 창이 없는 테스트 환경에서는 main screen backing scale로 폴백한다
                let expected = NSScreen.main?.backingScaleFactor ?? 2
                expect(layer.contentsScale) == expected
            }
        }
    #endif
}
