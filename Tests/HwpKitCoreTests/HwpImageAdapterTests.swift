import CoreGraphics
import Foundation
@testable import HwpKitCore
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

final class HwpImageAdapterTests: XCTestCase {
    private let adapter = HwpImageAdapter()

    func testEmptyDataReturnsEmptyPayloadError() {
        let result = adapter.decodeData(Data())
        switch result {
        case .failure(.emptyPayload):
            break
        default:
            fail("Expected .failure(.emptyPayload), got \(result)")
        }
    }

    func testGarbageBytesReturnsUnsupportedFormat() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        let result = adapter.decodeData(garbage)
        switch result {
        case let .failure(.unsupportedFormat(hex)):
            expect(hex).toNot(beEmpty())
        default:
            fail("Expected .failure(.unsupportedFormat), got \(result)")
        }
    }

    func testOneByone1PNGDecodesSuccessfully() throws {
        // swiftlint:disable:next line_length
        let pngData = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="))
        let result = adapter.decodeData(pngData)
        switch result {
        case let .success(decoded):
            expect(decoded.format) == .png
            expect(decoded.pixelSize) == CGSize(width: 1, height: 1)
        case let .failure(error):
            fail("Expected success, got \(error)")
        }
    }

    /// orientation 6(90° 회전)으로 태그된 작은 JPEG: 선언 4x2가 적용 후 2x4로
    /// 스왑돼야 한다 — 풀사이즈 경로가 orientation을 무시하면 4x2로 남는다 (R50 #5).
    func testExifOrientationAppliedOnFullSizePath() throws {
        let oriented = try makeJPEG(width: 4, height: 2, orientation: 6)
        let result = adapter.decodeData(oriented)
        switch result {
        case let .success(decoded):
            expect(decoded.format) == .jpeg
            expect(decoded.pixelSize) == CGSize(width: 2, height: 4)
        case let .failure(error):
            fail("Expected success, got \(error)")
        }
    }

    /// 기본 orientation(1) JPEG은 스왑 없이 선언 크기 그대로 (풀사이즈 경로 불변).
    func testDefaultOrientationJPEGKeepsDeclaredSize() throws {
        let plain = try makeJPEG(width: 4, height: 2, orientation: 1)
        let result = adapter.decodeData(plain)
        switch result {
        case let .success(decoded):
            expect(decoded.pixelSize) == CGSize(width: 4, height: 2)
        case let .failure(error):
            fail("Expected success, got \(error)")
        }
    }

    private func makeJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw HwpImageError.decodeFailed(underlying: "JPEG encode failed")
        }
        return data as Data
    }
}
