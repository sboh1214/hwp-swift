@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ListControlStabilityTests: XCTestCase {
    func testListHeaderInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = listHeaderPayload(paragraphCount: 2) + rawTrailing
        let slicedPayload = (Data([0xEF]) + rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let header = try HwpListHeader(&reader)

        expect(header.rawPayload) == slicedPayload
        expect(header.rawTrailing) == rawTrailing
        expect(header.rawTrailingWords) == [UInt16(0xFECA)]
        expect(header.paragraphCount) == 2
        expect(header.property) == 0
        expect(reader.isEOF) == true
    }

    func testListHeaderOddTrailingBytesRemainRawOnly() throws {
        let rawTrailing = Data([0xAA])
        let rawPayload = listHeaderPayload(paragraphCount: 1) + rawTrailing
        var reader = DataReader(rawPayload)

        let header = try HwpListHeader(&reader)

        expect(header.rawPayload) == rawPayload
        expect(header.rawTrailing) == rawTrailing
        expect(header.rawTrailingWords).to(beNil())
        expect(header.paragraphCount) == 1
        expect(header.property) == 0
    }

    func testParagraphPreservesTruncatedListHeaderAsGenericOtherControl() throws {
        let rawPayload = littleEndianData(HwpOtherCtrlId.header.rawValue)
        let listHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: Data([0xAA])
        )
        let record = listControlRecord(rawPayload: rawPayload, children: [
            listHeader,
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB])),
        ])

        expect {
            _ = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 1
        })

        let paragraph = try HwpParagraph.load(
            listControlParagraphRecord(children: [
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
            return fail("Expected truncated list control to be preserved as other")
        }

        expect(other.ctrlId) == .header
        expect(other.rawPayload) == rawPayload
        expect(other.rawTrailing).to(beEmpty())
        expect(other.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: Data([0xAA])
            ),
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB])),
        ]
    }

    func testParagraphDoesNotHideInvalidListTreeAsGenericOtherControl() {
        let record = listControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload(paragraphCount: 1)
            ),
        ])

        expect {
            _ = try HwpParagraph.load(
                listControlParagraphRecord(children: [
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
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "list control paragraph is missing"
        })
    }

    func testParagraphDoesNotHideMissingListHeaderAsGenericOtherControl() {
        let record = listControlRecord(children: [
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xAA])),
        ])

        expectRecordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue) {
            _ = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))
        }
        expectRecordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue) {
            _ = try HwpParagraph.load(
                listControlParagraphRecord(children: [
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
        }
    }

    func testListControlNegativeParagraphCountThrowsTypedError() {
        let record = listControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload(paragraphCount: -1)
            ),
        ])

        expectInvalidListControl {
            _ = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testListControlPreservesHeaderAndControlUnknownChildren() throws {
        let headerUnknownChild = HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xCA]))
        headerUnknownChild.children = [
            HwpRecord(tagId: 0x2FC, level: 4, payload: Data([0xCB])),
        ]
        let listHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: listHeaderPayload(paragraphCount: 0)
        )
        listHeader.children = [headerUnknownChild]
        let controlUnknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xDD]))
        let record = listControlRecord(children: [
            listHeader,
            controlUnknownChild,
        ])

        let control = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))

        expect(control.listArray.count) == 1
        expect(control.listArray.first?.headerRawPayload) == listHeaderPayload(paragraphCount: 0)
        expect(control.listArray.first?.headerUnknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2FD,
                level: 3,
                payload: Data([0xCA]),
                children: [
                    expectedTestRecord(tagId: 0x2FC, level: 4, payload: Data([0xCB])),
                ]
            ),
        ]
        expect(control.listArray.first?.paragraphArray).to(beEmpty())
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xDD])),
        ]
    }

    func testListControlMissingParagraphThrowsTypedError() {
        let record = listControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload(paragraphCount: 1)
            ),
        ])

        expectInvalidListControl {
            _ = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testListControlUnexpectedParagraphTagThrowsTypedError() {
        let record = listControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload(paragraphCount: 1)
            ),
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data()),
        ])

        expectInvalidListControl {
            _ = try HwpListControl.load(record, HwpVersion(5, 0, 1, 1))
        }
    }
}

private func expectInvalidListControl(_ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("list control"))
    })
}

private func expectRecordDoesNotExist(
    tag expectedTag: UInt32,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.recordDoesNotExist(tag) = error else {
            return fail("Expected recordDoesNotExist, got \(error)")
        }
        expect(tag) == expectedTag
    })
}

private func listControlRecord(children: [HwpRecord]) -> HwpRecord {
    listControlRecord(
        rawPayload: littleEndianData(HwpOtherCtrlId.header.rawValue),
        children: children
    )
}

private func listControlRecord(rawPayload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = children
    return record
}

private func listControlParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: listControlParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func listControlParagraphHeaderPayload() -> Data {
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

private func listHeaderPayload(paragraphCount: Int32) -> Data {
    littleEndianData(paragraphCount) + littleEndianData(UInt32(0))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
