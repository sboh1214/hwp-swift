import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

/// 승격된 페이지 → 비트맵 렌더러의 계약.
///
/// 픽스처 기반 렌더 회귀는 `HwpKitTests`의 커밋된 골든이 본다 (그쪽
/// `FixturePreview.renderImage`가 이 API에 위임하므로 리팩터가 깨지면 상시 CI가
/// 곧바로 잡는다). 여기는 그 골든이 **못 보는 것**만 잰다 — 픽셀 크기 계약,
/// 상하 방향, `sourceRect` 기하, 미확정 이미지 정책이 호출자마다 갈리는 것.
final class HwpPageBitmapRendererTests: XCTestCase {
    // MARK: - 크기 계약

    func testRenderProducesRequestedPixelSize() async throws {
        let page = Self.makePage(commands: [])

        let image = try await HwpPageBitmapRenderer.render(
            page: page, imageStore: HwpImageStore(), pixelWidth: 120, pixelHeight: 160
        )

        expect(image.width) == 120
        expect(image.height) == 160
    }

    /// 종횡비 헬퍼는 골든이 손으로 계산하던 식과 같아야 한다 — 갈리면 커밋된
    /// 기준선과 축소판이 서로 다른 크기로 그려진다.
    func testPixelHeightPreservesPageAspectRatio() {
        let page = Self.makePage(commands: [], size: CGSize(width: 300, height: 400))

        expect(HwpPageBitmapRenderer.pixelHeight(for: page, pixelWidth: 150)) == 200
        // 0 크기 페이지에서도 유효한 픽셀 수를 준다 (CGContext가 0을 거부한다)
        let degenerate = Self.makePage(commands: [], size: .zero)
        expect(HwpPageBitmapRenderer.pixelHeight(for: degenerate, pixelWidth: 64)) == 64
    }

    func testRejectsNonPositivePixelSize() async {
        let page = Self.makePage(commands: [])

        await expect {
            try await HwpPageBitmapRenderer.render(
                page: page, imageStore: HwpImageStore(), pixelWidth: 0, pixelHeight: 10
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case .invalidPixelSize = error else {
                return fail("Expected .invalidPixelSize, got \(error)")
            }
        })
    }

    // MARK: - 방향 · 기하

    /// **상하 반전을 실제로 잡는다.** 잉크 비영만으로는 뒤집혀도 통과하므로
    /// (`HwpPDFExporterTests`의 같은 지적) 위쪽에만 칠한 쪽을 그려 위 절반의
    /// 잉크가 아래 절반보다 많은지를 본다.
    func testTopOfPageRendersAtTopOfBitmap() async throws {
        // paint 명령은 top-down 페이지 좌표다 — y=0이 종이의 맨 위.
        let page = Self.makePage(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: 300, height: 100),
                color: CGColor(gray: 0, alpha: 1)
            ),
        ])

        let image = try await HwpPageBitmapRenderer.render(
            page: page, imageStore: HwpImageStore(), pixelWidth: 60, pixelHeight: 80
        )

        let ink = try Self.rowInk(of: image)
        let top = ink[0 ..< ink.count / 2].reduce(0, +)
        let bottom = ink[(ink.count / 2)...].reduce(0, +)
        expect(top) > 0
        expect(top) > bottom * 5
    }

    /// `sourceRect`는 캔버스를 채울 페이지 영역이다. 좌상단 1/2을 요청하면 위
    /// 100pt 띠가 캔버스의 위 **절반**을 채운다 (전체를 요청하면 1/4이다).
    func testSourceRectMagnifiesRequestedRegion() async throws {
        let page = Self.makePage(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: 300, height: 100),
                color: CGColor(gray: 0, alpha: 1)
            ),
        ])
        let full = try await HwpPageBitmapRenderer.render(
            page: page, imageStore: HwpImageStore(), pixelWidth: 60, pixelHeight: 80
        )
        let magnified = try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: HwpImageStore(),
            pixelWidth: 60,
            pixelHeight: 80,
            sourceRect: CGRect(x: 0, y: 0, width: 150, height: 200)
        )

        let fullInk = try Self.rowInk(of: full)
        let magnifiedInk = try Self.rowInk(of: magnified)
        // 400pt 중 100pt = 1/4 → 80행 중 20행, 200pt 중 100pt = 1/2 → 40행.
        expect(Double(Self.inkedRowCount(fullInk))).to(beCloseTo(20, within: 1))
        expect(Double(Self.inkedRowCount(magnifiedInk))).to(beCloseTo(40, within: 1))
    }

    /// 종이 밖을 요청해도 캔버스가 투명으로 남지 않는다 — 알파를 무시하거나
    /// 검정에 합성하는 소비자(JPEG 인코딩, 불투명 백킹 뷰)에게 검정 띠가 된다.
    ///
    /// **RGBA 바이트를 직접 읽는다.** 잉크 그리드로 재면 안 된다 — 그쪽은 흰
    /// 바탕에 source-over로 합성하므로 알파 0인 픽셀도 흰색으로 읽혀, 캔버스
    /// 선칠을 통째로 지워도 통과한다 (실측 확인).
    func testCanvasOutsideThePaperStaysOpaqueWhite() async throws {
        let page = Self.makePage(commands: [])

        let image = try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: HwpImageStore(),
            pixelWidth: 40,
            pixelHeight: 40,
            // 페이지(300×400)보다 큰 영역 — 캔버스의 좌상단 20×20만 종이다.
            sourceRect: CGRect(x: 0, y: 0, width: 600, height: 800)
        )

        // 종이 안 (좌상단)과 종이 밖 (우하단) 둘 다 불투명 흰색이어야 한다
        for point in [(x: 4, y: 4), (x: 39, y: 39), (x: 39, y: 4), (x: 4, y: 39)] {
            let pixel = try Self.pixel(of: image, x: point.x, y: point.y)
            expect(pixel.alpha) == 255
            expect(pixel.red) == 255
            expect(pixel.green) == 255
            expect(pixel.blue) == 255
        }
    }

    // MARK: - 미확정 이미지 정책

    /// 같은 입력에서 정책만 바뀌면 결과가 갈린다 — 이 축이 없으면 축소판이
    /// 그림 하나 때문에 쪽 전체를 잃거나, 픽스처 하네스가 회색 사각형을 기준선에
    /// 굳힌다.
    func testUnresolvedPolicyDecidesBetweenPlaceholderAndFailure() async throws {
        let document = try Self.makeImageDocument(imageCount: 3)
        let page = try XCTUnwrap(document.pages.first)

        await expect {
            try await HwpPageBitmapRenderer.render(
                page: page,
                imageStore: document.imageStore,
                pixelWidth: 60,
                pixelHeight: 80,
                unresolvedImages: .fail,
                imageByteLimit: 1
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case let .unresolvedImages(variants) = error else {
                return fail("Expected .unresolvedImages, got \(error)")
            }
            expect(variants).toNot(beEmpty())
        })

        let placeholder = try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: document.imageStore,
            pixelWidth: 60,
            pixelHeight: 80,
            unresolvedImages: .drawPlaceholder,
            imageByteLimit: 1
        )
        expect(placeholder.width) == 60
    }

    /// 예산이 넉넉하면 `.fail`도 통과한다 — 위 가드가 상시 실패가 아님을 보인다.
    func testDefaultBudgetResolvesImagesForStrictPolicy() async throws {
        let document = try Self.makeImageDocument(imageCount: 3)
        let page = try XCTUnwrap(document.pages.first)

        let image = try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: document.imageStore,
            pixelWidth: 60,
            pixelHeight: 80,
            unresolvedImages: .fail
        )

        let ink = try Self.rowInk(of: image)
        expect(ink.reduce(0, +)) > 0
    }

    func testErrorDescriptionsCoverEveryCase() {
        let errors: [HwpPageBitmapRenderError] = [
            .pageOutOfRange(index: 3, pageCount: 2),
            .invalidPixelSize(width: 0, height: 10),
            .invalidSourceRect(.zero),
            .contextCreationFailed,
            .imageCreationFailed,
            .unresolvedImages(variants: ["1"]),
        ]

        for error in errors {
            expect(error.description).toNot(beEmpty())
            expect(error.errorDescription) == error.description
        }
        // 쪽은 1부터 세어 보인다 — 인덱스가 그대로 새면 오해를 부른다
        expect(HwpPageBitmapRenderError.pageOutOfRange(index: 3, pageCount: 2).description)
            .to(contain("Page 4"))
    }

    // MARK: - 합성 입력 · 측정

    static func makePage(
        commands: [HwpPaintCommand],
        size: CGSize = CGSize(width: 300, height: 400)
    ) -> HwpPage {
        HwpPage(
            size: size,
            margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
            blocks: [],
            pageNumber: 1,
            paintList: HwpPaintList(commands: commands)
        )
    }

    /// 행별 평균 잉크 (0 = 백지, 1 = 전부 검정). 위/아래 분포만 보면 되므로
    /// 열은 접는다.
    static func rowInk(of image: CGImage) throws -> [Double] {
        let width = image.width
        let height = image.height
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let raw = try XCTUnwrap(context.data)
        let pixels = raw.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        // 비트맵 버퍼는 **위에서 아래로** 담긴다 (그리기 좌표계가 y-up인 것과
        // 별개다) — 행 0이 이미지의 맨 위다. `FixturePreview.inkGrid`도 같은 규약.
        return (0 ..< height).map { row in
            var sum = 0.0
            for x in 0 ..< width {
                sum += 1.0 - Double(pixels[row * context.bytesPerRow + x]) / 255.0
            }
            return sum / Double(width)
        }
    }

    static func inkedRowCount(_ ink: [Double]) -> Int {
        ink.filter { $0 > 0.5 }.count
    }

    struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    /// 렌더 결과의 RGBA 바이트를 **합성 없이** 읽는다. 알파 계약을 재려면
    /// 이래야 한다 — 흰 바탕에 그려 읽으면 알파 0이 흰색으로 둔갑한다.
    static func pixel(of image: CGImage, x: Int, y: Int) throws -> Pixel {
        expect(image.bitsPerPixel) == 32
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        // premultipliedLast + DeviceRGB → 버퍼는 위에서 아래로, 픽셀당 RGBA 4바이트
        let offset = y * image.bytesPerRow + x * 4
        expect(offset + 3) < CFDataGetLength(data)
        return Pixel(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }

    /// 캐시·세대 가드 테스트가 쓰는 임의 비트맵 (렌더 경로를 타지 않는다).
    static func makeBitmap(width: Int = 4, height: Int = 4) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    /// 실제 디코드 경로를 타는 이미지 문서 (`HwpPDFRendererTests`와 같은 형상).
    static func makeImageDocument(imageCount: UInt32) throws -> HwpDocument {
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
        return HwpDocument(
            pages: [makePage(commands: commands)],
            metadata: HwpDocumentMetadata(title: "images", pageCount: 1, isComplete: true),
            unsupportedElements: [],
            imageStore: HwpImageStore(
                dataByBinItemId: dataById, extensionByBinItemId: extensionById
            )
        )
    }

    /// 포맷은 매직 바이트로 판별되므로 실제 PNG 바이트를 만든다.
    static func makePNGData(width: Int = 32, height: Int = 32) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(context.makeImage())
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            buffer as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination)) == true
        return buffer as Data
    }
}
