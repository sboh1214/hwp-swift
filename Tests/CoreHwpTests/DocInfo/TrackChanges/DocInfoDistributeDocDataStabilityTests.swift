@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoDistributeDocDataStabilityTests: XCTestCase {
    func testDistributeDocDataExposesUInt32ValuesAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0xAA, 0xBB])
        let payload = distributeDocDataPayload(
            values: [0x0100_57D1, 0x0203_0405],
            rawTrailing: rawTrailing
        )
        let record = HwpRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            level: 0,
            payload: payload
        )

        let distributeDocData = try HwpDistributeDocData.load(record)
        let decoded = try JSONDecoder().decode(
            HwpDistributeDocData.self,
            from: JSONEncoder().encode(distributeDocData)
        )

        expect(distributeDocData.distributeDocDataInfo?.values) == [
            0x0100_57D1,
            0x0203_0405,
        ]
        expect(distributeDocData.distributeDocDataInfo?.valuesRawPayload) ==
            Data(payload.dropLast(rawTrailing.count))
        expect(distributeDocData.distributeDocDataInfo?.rawTrailing) == rawTrailing
        expect(distributeDocData.rawPayload) == payload
        expect(decoded.distributeDocDataInfo?.values) == [
            0x0100_57D1,
            0x0203_0405,
        ]
        expect(decoded.distributeDocDataInfo?.valuesRawPayload) ==
            Data(payload.dropLast(rawTrailing.count))
        expect(decoded.distributeDocDataInfo?.rawTrailing) == rawTrailing
        expect(decoded.rawPayload) == payload
    }

    func testDistributeDocDataPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawTrailing = Data([0xAA, 0xBB])
        let payload = distributeDocDataPayload(
            values: [0x0100_57D1],
            rawTrailing: rawTrailing
        )
        let paddedPayload = concatenatedData(Data([0x00, 0x01]), payload)
        let slicedPayload = paddedPayload.dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let distributeDocData = try HwpDistributeDocData.load(record)

        expect(distributeDocData.distributeDocDataInfo?.values) == [0x0100_57D1]
        expect(distributeDocData.distributeDocDataInfo?.valuesRawPayload) ==
            Data(slicedPayload.dropLast(2))
        expect(distributeDocData.distributeDocDataInfo?.rawTrailing) == rawTrailing
        expect(distributeDocData.rawPayload) == slicedPayload
    }

    func testMalformedDistributeDocDataPayloadIsPreservedWithoutParsedInfo() throws {
        let payload = Data([0x1C, 0x02, 0x01])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            level: 0,
            payload: payload
        )

        let distributeDocData = try HwpDistributeDocData.load(record)
        let decoded = try JSONDecoder().decode(
            HwpDistributeDocData.self,
            from: JSONEncoder().encode(distributeDocData)
        )

        expect(distributeDocData.distributeDocDataInfo).to(beNil())
        expect(distributeDocData.rawPayload) == payload
        expect(decoded.distributeDocDataInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }
}

private func distributeDocDataPayload(values: [UInt32], rawTrailing: Data) -> Data {
    let payload = values.reduce(into: Data()) { payload, value in
        payload.append(littleEndianData(value))
    }
    return concatenatedData(payload, rawTrailing)
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
