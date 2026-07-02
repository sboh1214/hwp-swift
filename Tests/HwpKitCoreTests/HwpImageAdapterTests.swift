import Foundation
@testable import HwpKitCore
import Nimble
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
}
