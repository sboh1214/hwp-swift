@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class PageNumberPositionStabilityTests: XCTestCase {
    func testPageNumberPositionInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let ctrlPayload = pageNumberPositionPayload(rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), ctrlPayload).dropFirst()
        let unknownPayload = Data([0xCC])
        let unknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: unknownPayload)
        var reader = DataReader(slicedPayload)

        let pageNumberPosition = try HwpPageNumberPosition(&reader, [unknownChild])

        expect(pageNumberPosition.rawPayload) == slicedPayload
        expect(pageNumberPosition.rawTrailing) == rawTrailing
        expect(pageNumberPosition.otherCtrlId) == .pageNumberPosition
        expect(pageNumberPosition.property) == 0x0102_0304
        expect(pageNumberPosition.unknown) == 0xAABB_CCDD
        expect(pageNumberPosition.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testPageNumberPositionPreservesRawPayloadAndChildren() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let ctrlPayload = pageNumberPositionPayload(rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        record.children.append(
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xCC]))
        )

        let pageNumberPosition = try HwpPageNumberPosition.load(record)

        expect(pageNumberPosition.rawPayload) == ctrlPayload
        expect(pageNumberPosition.rawTrailing) == rawTrailing
        expect(pageNumberPosition.otherCtrlId) == .pageNumberPosition
        expect(pageNumberPosition.property) == 0x0102_0304
        expect(pageNumberPosition.userSymbol) == 0
        expect(pageNumberPosition.headDecoration) == 45
        expect(pageNumberPosition.tailDecoration) == 45
        expect(pageNumberPosition.unused) == 45
        expect(pageNumberPosition.unknown) == 0xAABB_CCDD
        expect(pageNumberPosition.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xCC])),
        ]
    }

    func testPageNumberPositionAcceptsFixtureLengthPayloadWithoutUnknownField() throws {
        let ctrlPayload = pageNumberPositionPayload(includeUnknown: false)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )

        let pageNumberPosition = try HwpPageNumberPosition.load(record)

        expect(pageNumberPosition.rawPayload) == ctrlPayload
        expect(pageNumberPosition.rawTrailing).to(beEmpty())
        expect(pageNumberPosition.property) == 0x0102_0304
        expect(pageNumberPosition.userSymbol) == 0
        expect(pageNumberPosition.headDecoration) == 45
        expect(pageNumberPosition.tailDecoration) == 45
        expect(pageNumberPosition.unused) == 45
        expect(pageNumberPosition.unknown) == 0
    }

    func testPageNumberPositionPreservesPartialUnknownFieldAsRawTrailing() throws {
        for rawTrailing in [Data([0xAA]), Data([0xAA, 0xBB]), Data([0xAA, 0xBB, 0xCC])] {
            let ctrlPayload = pageNumberPositionPayload(
                includeUnknown: false,
                rawTrailing: rawTrailing
            )
            let record = HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: ctrlPayload
            )

            let pageNumberPosition = try HwpPageNumberPosition.load(record)

            expect(pageNumberPosition.rawPayload) == ctrlPayload
            expect(pageNumberPosition.rawTrailing) == rawTrailing
            expect(pageNumberPosition.unknown) == 0
        }
    }

    func testPageNumberPositionRejectsInvalidControlIdWithTypedError() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: pageNumberPositionPayload(ctrlId: HwpOtherCtrlId.pageHide.rawValue)
        )

        expect {
            _ = try HwpPageNumberPosition.load(record)
        }.to(throwError { error in
            guard case HwpError.invalidCtrlId(HwpOtherCtrlId.pageHide.rawValue) = error else {
                return fail("Expected invalidCtrlId, got \(error)")
            }
        })
    }

    func testParagraphPreservesTruncatedPageNumberPositionAsGenericOtherControl() throws {
        let rawPayload = truncatedPageNumberPositionPayload()
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FB, level: 2, payload: Data([0xAA])))

        expect {
            _ = try HwpPageNumberPosition.load(record)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 0
        })

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .other(other) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated pageNumberPosition to be preserved as other")
        }

        expect(other.ctrlId) == .pageNumberPosition
        expect(other.rawPayload) == rawPayload
        expect(other.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(other.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FB, level: 2, payload: Data([0xAA])),
        ]
    }
}

private func pageNumberPositionPayload(
    includeUnknown: Bool = true,
    rawTrailing: Data = Data()
) -> Data {
    pageNumberPositionPayload(
        ctrlId: HwpOtherCtrlId.pageNumberPosition.rawValue,
        includeUnknown: includeUnknown,
        rawTrailing: rawTrailing
    )
}

private func pageNumberPositionPayload(
    ctrlId: UInt32,
    includeUnknown: Bool = true,
    rawTrailing: Data = Data()
) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(UInt32(0x0102_0304)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(WCHAR(45)))
    if includeUnknown {
        data.append(littleEndianData(UInt32(0xAABB_CCDD)))
    }
    data.append(rawTrailing)
    return data
}

private func truncatedPageNumberPositionPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(HwpOtherCtrlId.pageNumberPosition.rawValue))
    data.append(littleEndianData(UInt32(0x0102_0304)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(WCHAR(45)))
    return data
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

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
