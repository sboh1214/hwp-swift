@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// TRACK_CHANGE_AUTHOR의 거대 WCHAR count가 32비트 Int(watchOS arm64_32)
/// 길이 산술을 트랩시키지 않고 best-effort nil + rawPayload 보존으로
/// 남는지 (P1).
final class TrackChangeAuthorMalformedTests: XCTestCase {
    private func loadAuthor(characterCount: UInt32) throws -> HwpTrackChangeAuthor {
        var payload = Data()
        withUnsafeBytes(of: characterCount.littleEndian) { payload.append(contentsOf: $0) }
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )
        return try HwpTrackChangeAuthor.load(record)
    }

    func testHugeCharacterCountKeepsRawPayloadWithoutTrapping() throws {
        // 0x40000000: Int32 변환은 성공하지만 ×2(WCHAR)가 32비트에서
        // 오버플로하는 경계값. UInt32.max는 변환 자체가 실패하는 값.
        let boundary = try loadAuthor(characterCount: 0x4000_0000)
        expect(boundary.authorInfo).to(beNil())
        expect(boundary.rawPayload.count) == 4

        let maxCount = try loadAuthor(characterCount: UInt32.max)
        expect(maxCount.authorInfo).to(beNil())
        expect(maxCount.rawPayload.count) == 4
    }
}
