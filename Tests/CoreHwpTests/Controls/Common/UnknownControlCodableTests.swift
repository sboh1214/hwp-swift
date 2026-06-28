@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class UnknownControlCodableTests: XCTestCase {
    func testParagraphPreservesUnknownControlRawPayloadAndChildren() throws {
        let record = unknownControlRecord()

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .unknown(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected unknown control")
        }

        assertPreservedHeader(.unknown(header), expected: try HwpCtrlHeader.load(record))
        expect(paragraph.unknownChildren).to(beEmpty())
    }

    func testParagraphPreservesMultipleUnknownControlsInRecordOrder() throws {
        let firstRecord = unknownControlRecord(
            ctrlId: 0x1234_5678,
            rawTrailing: Data([0xBB]),
            childPayload: Data([0xCA, 0xFE])
        )
        let secondRecord = unknownControlRecord(
            ctrlId: 0x8765_4321,
            rawTrailing: Data([0xCC, 0xDD]),
            childPayload: Data([0xFA, 0xCE])
        )

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                firstRecord,
                secondRecord,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        let headers = (paragraph.ctrlHeaderArray ?? []).compactMap { control -> HwpCtrlHeader? in
            guard case let .unknown(header) = control else {
                return nil
            }
            return header
        }

        expect(headers.map(\.ctrlId)) == [0x1234_5678, 0x8765_4321]
        expect(headers.map(\.rawPayload)) == [firstRecord.payload, secondRecord.payload]
        expect(headers.map(\.unknownChildren)) == [
            [
                expectedTestUnknownRecord(
                    tagId: 0x2FE,
                    level: 2,
                    payload: Data([0xCA, 0xFE]),
                    children: [
                        expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xAA])),
                    ]
                ),
            ],
            [
                expectedTestUnknownRecord(
                    tagId: 0x2FE,
                    level: 2,
                    payload: Data([0xFA, 0xCE]),
                    children: [
                        expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xAA])),
                    ]
                ),
            ],
        ]
        expect(paragraph.unknownChildren).to(beEmpty())
    }

    func testUnknownAndNotImplementedControlsPreserveRawPayloadAndChildrenThroughCodable() throws {
        let header = try HwpCtrlHeader.load(unknownControlRecord())
        let controls: [HwpCtrlId] = [
            .unknown(header),
            .notImplemented(header),
        ]

        for control in controls {
            let data = try JSONEncoder().encode(control)
            let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: data)

            expect(decoded) == control
            assertPreservedHeader(decoded, expected: header)
        }
    }

    func testTruncatedUnknownControlHeaderSurvivesCodableRoundTrip() throws {
        let childPayload = Data([0xA1, 0xA2])
        let child = HwpRecord(tagId: 0x2FE, level: 2, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xA3])),
        ]
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: Data([0x01, 0x02, 0x03])
        )
        record.children = [child]
        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )

        let control = try XCTUnwrap(decoded.ctrlHeaderArray?.first)
        guard case let .unknown(header) = control else {
            return fail("Expected truncated control header to stay unknown after Codable")
        }
        expect(header.ctrlId) == 0
        expect(header.rawPayload) == record.payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2FE,
                level: 2,
                payload: childPayload,
                children: [
                    expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xA3])),
                ]
            ),
        ]
    }
}

private func unknownControlRecord(
    ctrlId: UInt32 = 0x1234_5678,
    rawTrailing: Data = Data([0xBB]),
    childPayload: Data = Data([0xCA, 0xFE])
) -> HwpRecord {
    let child = HwpRecord(tagId: 0x2FE, level: 2, payload: childPayload)
    child.children = [
        HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xAA])),
    ]
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: littleEndianData(ctrlId) + rawTrailing
    )
    record.children = [child]
    return record
}

private func paragraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: paragraphHeaderPayload()
    )
    record.children = children
    return record
}

private func paragraphHeaderPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x8000_0000)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt32(1)))
    return data
}

private func assertPreservedHeader(_ control: HwpCtrlId, expected: HwpCtrlHeader) {
    let actual: HwpCtrlHeader
    switch control {
    case let .unknown(header),
         let .notImplemented(header):
        actual = header
    default:
        fail("Expected unknown or notImplemented control, got \(control)")
        return
    }

    expect(actual.ctrlId) == expected.ctrlId
    expect(actual.rawPayload) == expected.rawPayload
    expect(actual.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xCA, 0xFE]),
            children: [
                expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xAA])),
            ]
        ),
    ]
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
