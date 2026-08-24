@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class RevisionFieldControlPreservationTests: XCTestCase {
    func testRevisionFieldControlsPreserveRawPayloadsThroughParagraph() throws {
        for (index, ctrlId) in revisionFieldControlIds.enumerated() {
            let rawTrailing = Data([UInt8(index), 0xCA, 0xFE])
            let rawPayload = concatenatedData(
                revisionFieldLittleEndianData(ctrlId.rawValue),
                rawTrailing
            )
            let record = revisionFieldControlRecord(
                rawPayload: rawPayload,
                childPayload: Data([UInt8(index), 0xDD])
            )
            let paragraph = try HwpParagraph.load(
                revisionFieldParagraphRecord(children: [
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

            assertRevisionFieldControl(
                paragraph.ctrlHeaderArray?.first,
                ctrlId: ctrlId,
                rawPayload: rawPayload,
                rawTrailing: rawTrailing,
                childPayload: Data([UInt8(index), 0xDD])
            )
        }
    }
}

private let revisionFieldControlIds: [HwpFieldCtrlId] = [
    .revisionSign,
    .revisionDelete,
    .revisionAttach,
    .revisionClipping,
    .revisionSawtooth,
    .revisionThinking,
    .revisionPraise,
    .revisionLine,
    .revisionSimpleChange,
    .revisionHyperLink,
    .revisionLineAttach,
    .revisionLineLink,
    .revisionLineRansfer,
    .revisionRightMove,
    .revisionLeftMove,
    .revisionTransfer,
    .revisionSimpleInsert,
    .revisionSplit,
    .revisionChange,
]

private func assertRevisionFieldControl(
    _ control: HwpCtrlId?,
    ctrlId: HwpFieldCtrlId,
    rawPayload: Data,
    rawTrailing: Data,
    childPayload: Data
) {
    guard case let .revision(field) = control else {
        return fail("Expected \(ctrlId) to be preserved as revision field")
    }

    expect(field.ctrlId) == ctrlId
    expect(field.semanticKind) == .revision
    expect(field.isMemoField) == false
    expect(field.isRevisionField) == true
    expect(field.rawPayload) == rawPayload
    expect(field.rawTrailing) == rawTrailing
    expect(field.fieldParameter).to(beNil())
    expect(field.fieldParameterRawPayload).to(beNil())
    expect(field.fieldParameterRawTrailing).to(beNil())
    expect(field.memoParameter).to(beNil())
    expect(field.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FA,
            level: 2,
            payload: childPayload,
            children: [
                expectedTestRecord(tagId: 0x2F9, level: 3, payload: Data([0xEE])),
            ]
        ),
    ]
}

private func revisionFieldControlRecord(
    rawPayload: Data,
    childPayload: Data
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = [
        revisionFieldNestedChildRecord(
            tagId: 0x2FA,
            level: 2,
            payload: childPayload,
            nestedTagId: 0x2F9,
            nestedPayload: Data([0xEE])
        ),
    ]
    return record
}

private func revisionFieldNestedChildRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    nestedTagId: UInt32,
    nestedPayload: Data
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = [
        HwpRecord(tagId: nestedTagId, level: level + 1, payload: nestedPayload),
    ]
    return record
}

private func revisionFieldParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: revisionFieldParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func revisionFieldParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(revisionFieldLittleEndianData(UInt32(0x8000_0000)))
    data.append(revisionFieldLittleEndianData(UInt32(0)))
    data.append(revisionFieldLittleEndianData(UInt16(0)))
    data.append(revisionFieldLittleEndianData(UInt8(0)))
    data.append(revisionFieldLittleEndianData(UInt8(0)))
    data.append(revisionFieldLittleEndianData(UInt16(0)))
    data.append(revisionFieldLittleEndianData(UInt16(0)))
    data.append(revisionFieldLittleEndianData(UInt16(0)))
    data.append(revisionFieldLittleEndianData(UInt32(1)))
    return data
}

private func revisionFieldLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
