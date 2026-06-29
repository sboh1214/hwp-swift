@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlPageHideTests: XCTestCase {
    func testPageHideControlExposesRawBitField() throws {
        let extraTrailing = Data([0xAA, 0xBB])
        let rawTrailing = concatenatedData(littleEndianData(UInt32(0x20)), extraTrailing)
        let rawPayload = concatenatedData(littleEndianData(HwpOtherCtrlId.pageHide.rawValue), rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.pageHide(control))
        )

        expect(control.ctrlId) == .pageHide
        expect(control.pageHideInfo?.rawValue) == 0x20
        expect(control.pageHideInfo?.rawTrailing) == extraTrailing
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing

        guard case let .pageHide(roundTripped) = decoded else {
            return fail("Expected pageHide after Codable round-trip")
        }
        expect(roundTripped.pageHideInfo?.rawValue) == 0x20
        expect(roundTripped.pageHideInfo?.rawTrailing) == extraTrailing
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
    }

    func testShortPageHidePayloadIsPreservedWithoutParsedInfo() throws {
        let rawTrailing = Data([0x20, 0x00, 0x00])
        let rawPayload = concatenatedData(littleEndianData(HwpOtherCtrlId.pageHide.rawValue), rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.pageHide(control))
        )

        expect(control.ctrlId) == .pageHide
        expect(control.pageHideInfo).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing

        guard case let .pageHide(roundTripped) = decoded else {
            return fail("Expected pageHide after Codable round-trip")
        }
        expect(roundTripped.pageHideInfo).to(beNil())
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
    }

    func testLegacyFixturePageHideSampleExposesRawBitField() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let pageHideControls = FixtureDerivedValues
            .otherControls(from: hwp)
            .filter { $0.ctrlId == .pageHide }

        expect(pageHideControls).notTo(beEmpty())
        expect(pageHideControls.first?.pageHideInfo?.rawValue) == 32
        expect(pageHideControls.first?.pageHideInfo?.rawTrailing).to(beEmpty())
        expect(pageHideControls.first?.rawPayload) == Data([100, 104, 103, 112, 32, 0, 0, 0])
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
