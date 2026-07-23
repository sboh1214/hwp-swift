@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// main이 인코딩한 아카이브(신규 키 부재)는 브랜치 디코더가 기본값으로
/// 폴백해 keyNotFound 없이 열려야 한다 (R61 #1).
final class LegacyArchiveDecodingTests: XCTestCase {
    private func legacyJSON(
        of value: some Encodable, removingKey key: String
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testHwpFileDecodesLegacyArchiveWithoutViewSectionArray() throws {
        let legacy = try legacyJSON(of: HwpFile(), removingKey: "viewSectionArray")

        let decoded = try JSONDecoder().decode(HwpFile.self, from: legacy)

        expect(decoded.viewSectionArray).to(beEmpty())
        expect(decoded.sectionArray.count) == 1
        expect(decoded.displaySectionArray.count) == 1
    }

    func testHwpReadLimitsDecodeLegacyArchiveWithoutAggregateKey() throws {
        let legacy = try legacyJSON(
            of: HwpReadLimits.default, removingKey: "maxAggregateStreamBytes"
        )

        let decoded = try JSONDecoder().decode(HwpReadLimits.self, from: legacy)

        expect(decoded.maxAggregateStreamBytes) == 1024 * 1024 * 1024
        expect(decoded.maxCompressedStreamBytes) == HwpReadLimits.default.maxCompressedStreamBytes
    }

    func testHwpBulletDecodesLegacyArchiveWithoutHeadCharShapeId() throws {
        let bullet = HwpBullet(
            rawPayload: Data([1]),
            info: [0, 0, 0, 0, 0, 0, 0, 0],
            headCharShapeId: 7,
            char: "-",
            charRawPayload: Data([2]),
            imageId: 0,
            imageProperty: [0, 0, 0, 0],
            checkChar: "*",
            checkCharRawPayload: Data([3]),
            undocumentedTrailing: []
        )
        let legacy = try legacyJSON(of: bullet, removingKey: "headCharShapeId")

        let decoded = try JSONDecoder().decode(HwpBullet.self, from: legacy)

        expect(decoded.headCharShapeId) == -1
        expect(decoded.char) == "-"
        expect(decoded.checkChar) == "*"
        expect(decoded.info) == [0, 0, 0, 0, 0, 0, 0, 0]
    }
}
