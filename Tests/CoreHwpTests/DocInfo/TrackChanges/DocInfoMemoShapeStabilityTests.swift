@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoMemoShapeStabilityTests: XCTestCase {
    func testMemoShapeExposesKnownFixedFieldsAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let payload = memoShapePayload(rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            level: 0,
            payload: payload
        )

        let memoShape = try HwpMemoShape.load(record)
        let decoded = try JSONDecoder().decode(
            HwpMemoShape.self,
            from: JSONEncoder().encode(memoShape)
        )

        assertMemoShape(memoShape, rawPayload: payload, rawTrailing: rawTrailing)
        assertMemoShape(decoded, rawPayload: payload, rawTrailing: rawTrailing)
    }

    func testMalformedMemoShapePayloadIsPreservedWithoutParsedInfo() throws {
        let payload = Data([0xAA, 0xBB])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            level: 0,
            payload: payload
        )

        let memoShape = try HwpMemoShape.load(record)
        let decoded = try JSONDecoder().decode(
            HwpMemoShape.self,
            from: JSONEncoder().encode(memoShape)
        )

        expect(memoShape.shapeInfo).to(beNil())
        expect(memoShape.rawPayload) == payload
        expect(decoded.shapeInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testMemoShapePayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let payload = memoShapePayload()
        let slicedPayload = concatenatedData(Data([0xFE, 0xED]), payload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let memoShape = try HwpMemoShape.load(record)

        assertMemoShape(
            memoShape,
            rawPayload: slicedPayload,
            rawTrailing: Data([0x00, 0x00, 0x00, 0x00])
        )
    }

    func testTrackChangesFixtureMemoShapeExposesKnownFixedFields() throws {
        let hwp = try openHwp(#file, "track-changes")
        let memoShape = try XCTUnwrap(hwp.docInfo.memoShapeArray.first)

        expect(memoShape.rawPayload.count) == 22
        expect(memoShape.shapeInfo?.width) == 15024
        expect(memoShape.shapeInfo?.lineType) == 1
        expect(memoShape.shapeInfo?.lineWidth) == 1
        expect(memoShape.shapeInfo?.lineColor) == HwpColor(182, 215, 174)
        expect(memoShape.shapeInfo?.fillColor) == HwpColor(240, 255, 233)
        expect(memoShape.shapeInfo?.activeColor) == HwpColor(207, 241, 199)
        expect(memoShape.shapeInfo?.fixedFieldsRawPayload) ==
            Data(memoShape.rawPayload.prefix(18))
        expect(memoShape.shapeInfo?.rawTrailing) == Data([0, 0, 0, 0])
    }

    func testTrackChangesFixtureMemoShapeSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "track-changes")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let originalMemoShape = try XCTUnwrap(hwp.docInfo.memoShapeArray.first)
        let memoShape = try XCTUnwrap(decoded.docInfo.memoShapeArray.first)

        assertMemoShape(
            memoShape,
            rawPayload: originalMemoShape.rawPayload,
            rawTrailing: Data([0, 0, 0, 0])
        )
        expect(decoded.docInfo.memoShapeArray.map(\.rawPayload)) ==
            hwp.docInfo.memoShapeArray.map(\.rawPayload)
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func assertMemoShape(
    _ memoShape: HwpMemoShape,
    rawPayload: Data,
    rawTrailing: Data
) {
    expect(memoShape.rawPayload) == rawPayload
    expect(memoShape.shapeInfo?.width) == 15024
    expect(memoShape.shapeInfo?.lineType) == 1
    expect(memoShape.shapeInfo?.lineWidth) == 1
    expect(memoShape.shapeInfo?.lineColor) == HwpColor(182, 215, 174)
    expect(memoShape.shapeInfo?.fillColor) == HwpColor(240, 255, 233)
    expect(memoShape.shapeInfo?.activeColor) == HwpColor(207, 241, 199)
    expect(memoShape.shapeInfo?.fixedFieldsRawPayload) == Data(rawPayload.prefix(18))
    expect(memoShape.shapeInfo?.rawTrailing) == rawTrailing
}

private func memoShapePayload(rawTrailing: Data = Data([0x00, 0x00, 0x00, 0x00])) -> Data {
    var payload = Data()
    payload.append(littleEndianData(UInt32(15024)))
    payload.append(littleEndianData(UInt8(1)))
    payload.append(littleEndianData(UInt8(1)))
    payload.append(littleEndianData(COLORREF(0x00AE_D7B6)))
    payload.append(littleEndianData(COLORREF(0x00E9_FFF0)))
    payload.append(littleEndianData(COLORREF(0x00C7_F1CF)))
    payload.append(rawTrailing)
    return payload
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
