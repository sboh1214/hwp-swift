@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class LayoutCompatibilityStabilityTests: XCTestCase {
    func testLayoutCompatibilityDataLoaderPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = layoutCompatibilityPayload(1, 2, 3, 4, 5)
        let slicedPayload = concatenatedData(Data([0xEE]), payload).dropFirst()

        let layoutCompatibility = try HwpLayoutCompatibility.load(slicedPayload)

        expect(layoutCompatibility.rawPayload) == slicedPayload
        expect(layoutCompatibility.fixedFieldsRawPayload) == slicedPayload
        expect(layoutCompatibility.char) == 1
        expect(layoutCompatibility.paragraph) == 2
        expect(layoutCompatibility.section) == 3
        expect(layoutCompatibility.object) == 4
        expect(layoutCompatibility.field) == 5
        expect(layoutCompatibility.unknownChildren).to(beEmpty())
    }

    func testLayoutCompatibilityRejectsTruncatedPayloadWithTypedError() {
        var payload = layoutCompatibilityPayload(1, 2, 3, 4, 5)
        payload.removeLast()

        expect {
            _ = try HwpLayoutCompatibility.load(layoutCompatibilityRecord(
                payload: payload,
                children: []
            ))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 3
        })
    }

    func testLayoutCompatibilityRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(
            layoutCompatibilityPayload(1, 2, 3, 4, 5),
            Data([0xAA, 0xBB])
        )

        expect {
            _ = try HwpLayoutCompatibility.load(layoutCompatibilityRecord(
                payload: payload,
                children: []
            ))
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpLayoutCompatibility"
            expect(remain) == 2
        })
    }

    func testLayoutCompatibilityPreservesUnknownChildrenPayloads() throws {
        let payload = layoutCompatibilityPayload(1, 2, 3, 4, 5)
        let childPayload = Data([0xAA, 0xBB])
        let grandchildPayload = Data([0xCC])
        let child = HwpRecord(tagId: 0x2F1, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x2F2, level: 2, payload: grandchildPayload),
        ]

        let layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibilityRecord(
            payload: payload,
            children: [child]
        ))

        expect(layoutCompatibility.rawPayload) == payload
        expect(layoutCompatibility.fixedFieldsRawPayload) == payload
        expect(layoutCompatibility.char) == 1
        expect(layoutCompatibility.paragraph) == 2
        expect(layoutCompatibility.section) == 3
        expect(layoutCompatibility.object) == 4
        expect(layoutCompatibility.field) == 5
        expect(layoutCompatibility.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2F1,
                level: 1,
                payload: childPayload,
                children: [
                    expectedTestRecord(tagId: 0x2F2, level: 2, payload: grandchildPayload),
                ]
            ),
        ]
    }

    func testLayoutCompatibilityCodableRoundTripPreservesFixedFieldPayload() throws {
        let payload = layoutCompatibilityPayload(1, 2, 3, 4, 5)
        let child = HwpRecord(tagId: 0x2F1, level: 1, payload: Data([0xAA]))
        let layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibilityRecord(
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpLayoutCompatibility.self,
            from: JSONEncoder().encode(layoutCompatibility)
        )

        expect(decoded.rawPayload) == payload
        expect(decoded.fixedFieldsRawPayload) == payload
        expect(decoded.unknownChildren) == [HwpUnknownRecord(child)]
    }
}

private func layoutCompatibilityRecord(payload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
        level: 0,
        payload: payload
    )
    record.children = children
    return record
}

private func layoutCompatibilityPayload(_ values: UInt32...) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(littleEndianData(value))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
