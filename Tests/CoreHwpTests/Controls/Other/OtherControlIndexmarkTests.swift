@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlIndexmarkTests: XCTestCase {
    func testIndexmarkControlExposesTextAndRawTrailing() throws {
        let text = "개별행위설"
        let extraTrailing = Data([0xAA, 0xBB])
        let rawTrailing = indexmarkRawTrailing(text: text, rawTrailing: extraTrailing)
        let rawPayload = littleEndianData(HwpOtherCtrlId.indexmark.rawValue) + rawTrailing
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.indexmark(control))
        )

        expect(control.ctrlId) == .indexmark
        expect(control.indexmarkInfo?.textCharacterCount) == text.utf16.count
        expect(control.indexmarkInfo?.textLengthRawPayload) ==
            littleEndianData(UInt16(text.utf16.count))
        expect(control.indexmarkInfo?.text) == text
        expect(control.indexmarkInfo?.textRawPayload) == utf16LittleEndianData(text)
        expect(control.indexmarkInfo?.rawTrailing) == extraTrailing
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing

        guard case let .indexmark(roundTripped) = decoded else {
            return fail("Expected indexmark after Codable round-trip")
        }
        expect(roundTripped.indexmarkInfo?.textCharacterCount) == text.utf16.count
        expect(roundTripped.indexmarkInfo?.textLengthRawPayload) ==
            littleEndianData(UInt16(text.utf16.count))
        expect(roundTripped.indexmarkInfo?.text) == text
        expect(roundTripped.indexmarkInfo?.textRawPayload) == utf16LittleEndianData(text)
        expect(roundTripped.indexmarkInfo?.rawTrailing) == extraTrailing
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
    }

    func testMalformedIndexmarkPayloadIsPreservedWithoutParsedInfo() throws {
        let rawTrailing = littleEndianData(UInt16(3)) + littleEndianData(UInt16(0xAC1C))
        let rawPayload = littleEndianData(HwpOtherCtrlId.indexmark.rawValue) + rawTrailing
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.indexmark(control))
        )

        expect(control.ctrlId) == .indexmark
        expect(control.indexmarkInfo).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing

        guard case let .indexmark(roundTripped) = decoded else {
            return fail("Expected indexmark after Codable round-trip")
        }
        expect(roundTripped.indexmarkInfo).to(beNil())
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
    }

    func testInvalidIndexmarkUtf16IsPreservedWithoutParsedInfo() throws {
        let rawTrailing = littleEndianData(UInt16(1)) + littleEndianData(UInt16(0xD800))
        let rawPayload = littleEndianData(HwpOtherCtrlId.indexmark.rawValue) + rawTrailing
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.indexmark(control))
        )

        expect(control.ctrlId) == .indexmark
        expect(control.indexmarkInfo).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing

        guard case let .indexmark(roundTripped) = decoded else {
            return fail("Expected indexmark after Codable round-trip")
        }
        expect(roundTripped.indexmarkInfo).to(beNil())
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
    }

    func testLegacyFixtureIndexmarkSampleExposesTextAndRawTrailing() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let indexmarkControls = FixtureDerivedValues
            .otherControls(from: hwp)
            .filter { $0.ctrlId == .indexmark }

        expect(indexmarkControls).notTo(beEmpty())
        expect(indexmarkControls.first?.indexmarkInfo?.textCharacterCount) == 5
        expect(indexmarkControls.first?.indexmarkInfo?.textLengthRawPayload) == Data([5, 0])
        expect(indexmarkControls.first?.indexmarkInfo?.text) == "개별행위설"
        expect(indexmarkControls.first?.indexmarkInfo?.textRawPayload) == Data([
            28, 172, 196, 188, 137, 213, 4, 199, 36, 193,
        ])
        expect(indexmarkControls.first?.indexmarkInfo?.rawTrailing) == Data([
            0, 0, 0, 0, 0, 0,
        ])
        expect(indexmarkControls.first?.rawPayload.prefix(4)) == Data([
            109, 120, 100, 105,
        ])
    }
}

private func indexmarkRawTrailing(text: String, rawTrailing: Data = Data()) -> Data {
    var payload = littleEndianData(UInt16(text.utf16.count))
    payload.append(utf16LittleEndianData(text))
    payload.append(rawTrailing)
    return payload
}

private func utf16LittleEndianData(_ text: String) -> Data {
    text.utf16.reduce(into: Data()) { data, character in
        data.append(littleEndianData(character))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
