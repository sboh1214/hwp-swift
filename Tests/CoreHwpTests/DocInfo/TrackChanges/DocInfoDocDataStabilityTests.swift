@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoDocDataStabilityTests: XCTestCase {
    func testDocDataExposesUInt32ValuesAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0xEE, 0xFF])
        let payload = docDataPayload(values: [0x0102_0304, 0xAABB_CCDD], rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: payload
        )

        let docData = try HwpDocData.load(record)
        let decoded = try JSONDecoder().decode(
            HwpDocData.self,
            from: JSONEncoder().encode(docData)
        )

        expect(docData.docDataInfo?.values) == [0x0102_0304, 0xAABB_CCDD]
        expect(docData.docDataInfo?.valuesRawPayload) == Data(payload.dropLast(rawTrailing.count))
        expect(docData.docDataInfo?.rawTrailing) == rawTrailing
        expect(docData.rawPayload) == payload
        expect(decoded.docDataInfo?.values) == [0x0102_0304, 0xAABB_CCDD]
        expect(decoded.docDataInfo?.valuesRawPayload) ==
            Data(payload.dropLast(rawTrailing.count))
        expect(decoded.docDataInfo?.rawTrailing) == rawTrailing
        expect(decoded.rawPayload) == payload
    }

    func testMalformedDocDataPayloadIsPreservedWithoutParsedInfo() throws {
        let payload = Data([0x1C, 0x02, 0x01])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: payload
        )

        let docData = try HwpDocData.load(record)
        let decoded = try JSONDecoder().decode(
            HwpDocData.self,
            from: JSONEncoder().encode(docData)
        )

        expect(docData.docDataInfo).to(beNil())
        expect(docData.rawPayload) == payload
        expect(decoded.docDataInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testNooriFixtureExposesActualDocDataWords() throws {
        let hwp = try openHwp(#file, "noori")
        let docData = try XCTUnwrap(hwp.docInfo.docData)

        expect(docData.rawPayload.count) == 80
        expect(docData.docDataInfo?.values) == [
            0x0001_021C,
            0x0207_0000,
            0x0207_8000,
            0x0000_0008,
            0x0006_400A,
            0x0000_0000,
            0x0006_400E,
            0x0000_0000,
            0x0006_4006,
            0x0000_0000,
            0x0007_4010,
            0x0000_0000,
            0x0007_401F,
            0x0000_0064,
            0x0006_401A,
            0x0000_0000,
            0x0006_401D,
            0x0000_0000,
            0x0007_4020,
            0x0000_0064,
        ]
        expect(docData.docDataInfo?.valuesRawPayload) == docData.rawPayload
        expect(docData.docDataInfo?.rawTrailing).to(beEmpty())
    }

    func testDocDataPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawTrailing = Data([0xEE, 0xFF])
        let payload = docDataPayload(values: [0x0102_0304], rawTrailing: rawTrailing)
        let paddedPayload = concatenatedData(Data([0x00, 0x01]), payload)
        let slicedPayload = paddedPayload.dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let docData = try HwpDocData.load(record)

        expect(docData.docDataInfo?.values) == [0x0102_0304]
        expect(docData.docDataInfo?.valuesRawPayload) == Data(slicedPayload.dropLast(2))
        expect(docData.docDataInfo?.rawTrailing) == rawTrailing
        expect(docData.rawPayload) == slicedPayload
    }
}

private func docDataPayload(values: [UInt32], rawTrailing: Data) -> Data {
    let payload = values.reduce(into: Data()) { payload, value in
        payload.append(littleEndianData(value))
    }
    return concatenatedData(payload, rawTrailing)
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
