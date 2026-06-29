@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ControlPreservationTests: XCTestCase {
    func testCtrlDataPreservesRawPayloadChildrenAndCodableRoundTrip() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlData.rawValue,
            level: 2,
            payload: Data([0xAA, 0xBB])
        )
        record.children = [
            HwpRecord(tagId: 0x2FF, level: 3, payload: Data([0xCC])),
        ]

        let ctrlData = try HwpCtrlData.load(record)

        expect(ctrlData.rawPayload) == Data([0xAA, 0xBB])
        expect(ctrlData.payload) == ctrlData.rawPayload
        expect(ctrlData.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 3, payload: Data([0xCC])),
        ]

        let encoded = try JSONEncoder().encode(ctrlData)
        let decoded = try JSONDecoder().decode(HwpCtrlData.self, from: encoded)
        expect(decoded) == ctrlData
    }

    func testOtherAndBookmarkControlsPreserveRawPayloadTrailingBytesAndChildren() throws {
        let controls: [HwpOtherCtrlId] = [
            .autoNumber, .newNumber, .pageHide, .pageCT, .indexmark, .bookmark,
            .overlapping, .comment, .hiddenComment,
        ]

        for ctrlId in controls {
            try assertOtherControlPreservation(ctrlId: ctrlId, label: String(describing: ctrlId))
        }
    }

    // swiftlint:disable:next function_body_length
    func testCommonShapeControlsPreserveRawPayloadAndChildren() throws {
        let controls: [(HwpCommonCtrlId, String)] = [
            (.line, "line"),
            (.rectangle, "rectangle"),
            (.ellipse, "ellipse"),
            (.arc, "arc"),
            (.polygon, "polygon"),
            (.curve, "curve"),
            (.equation, "equation"),
            (.equationLegacy, "equation-legacy"),
            (.picture, "picture"),
            (.ole, "ole"),
            (.container, "container"),
        ]

        for (ctrlId, label) in controls {
            let rawPayload = commonCtrlPropertyPayload(ctrlId: ctrlId.rawValue)
            let shapeRecord = HwpRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: Data(label.utf8)
            )
            shapeRecord.children = [
                HwpRecord(
                    tagId: HwpSectionTag.shapeComponentPicture.rawValue,
                    level: 3,
                    payload: picturePayload(binaryDataId: 7)
                ),
                HwpRecord(
                    tagId: HwpSectionTag.shapeComponentOle.rawValue,
                    level: 3,
                    payload: Data([0xAC])
                ),
                HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 3, payload: Data([0xCC])),
            ]
            let record = HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: rawPayload
            )
            record.children = [
                shapeRecord,
                HwpRecord(tagId: HwpSectionTag.eqEdit.rawValue, level: 2, payload: Data([0xAB])),
                HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: Data([0xDD])),
                HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
            ]

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

            guard let shapeControl = shapeControl(from: paragraph.ctrlHeaderArray?.first) else {
                return fail("Expected shape control for \(label)")
            }

            expect(shapeControl.ctrlId) == ctrlId
            expect(shapeControl.commonCtrlProperty?.commonCtrlId) == ctrlId
            expect(shapeControl.commonCtrlProperty?.rawPayload) == rawPayload
            expect(shapeControl.rawPayload) == rawPayload
            expect(shapeControl.rawTrailing) == Data()
            expect(shapeControl.shapeComponentArray.map(\.rawPayload)) == [Data(label.utf8)]
            expect(shapeControl.shapeComponentArray.first?.pictureArray.map(\.binaryDataId)) == [7]
            expect(shapeControl.shapeComponentArray.first?.oleArray.map(\.rawPayload)) == [
                Data([0xAC]),
            ]
            expect(shapeControl.shapeComponentArray.first?.oleArray.compactMap(\.binaryDataId))
                .to(beEmpty())
            expect(shapeControl.shapeComponentArray.first?.oleRecords.map(\.payload)) == [
                Data([0xAC]),
            ]
            expect(shapeControl.shapeComponentArray.first?.ctrlDataRecords.map(\.rawPayload)) == [
                Data([0xCC]),
            ]
            expect(shapeControl.eqEditArray.map(\.rawPayload)) == [Data([0xAB])]
            expect(shapeControl.eqEditArray.compactMap(\.equationText)).to(beEmpty())
            expect(shapeControl.eqEditRecords.map(\.payload)) == [Data([0xAB])]
            expect(shapeControl.ctrlDataRecords.map(\.rawPayload)) == [Data([0xDD])]
            expect(shapeControl.unknownChildren) == [
                expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
            ]
        }
    }

    func testGenShapeObjectPreservesRawPayloadAndChildren() throws {
        var ctrlPayload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        let rawTrailing = Data([0xCA, 0xFE])
        ctrlPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        let shapeRecord = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: Data([0xAA])
        )
        shapeRecord.children = [
            HwpRecord(
                tagId: HwpSectionTag.shapeComponentPicture.rawValue,
                level: 3,
                payload: picturePayload(binaryDataId: 5)
            ),
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 3, payload: Data([0xCC])),
        ]
        record.children.append(shapeRecord)
        record.children.append(
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: Data([0xDD]))
        )
        record.children.append(
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xEE]))
        )

        let object = try HwpGenShapeObject.load(record)

        expect(object.rawPayload) == ctrlPayload
        expect(object.commonCtrlProperty.rawPayload) == commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
        )
        expect(object.rawTrailing) == rawTrailing
        expect(object.shapeComponentArray.map(\.rawPayload)) == [Data([0xAA])]
        expect(object.shapeComponentArray.first?.pictureArray.map(\.binaryDataId)) == [5]
        let componentCtrlDataPayloads = object.shapeComponentArray.first?.ctrlDataRecords
            .map(\.rawPayload)
        expect(componentCtrlDataPayloads) == [Data([0xCC])]
        expect(object.ctrlDataRecords.map(\.rawPayload)) == [Data([0xDD])]
        expect(object.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0xEE])),
        ]
    }

    func testColumnControlPreservesRawPayloadAndChildren() throws {
        let rawTrailing = Data([0xCA, 0xFE, 0x01])
        let ctrlPayload = columnPayload(rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        record.children.append(
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xAA, 0xBB]))
        )

        let column = try HwpColumn.load(record)

        expect(column.rawPayload) == ctrlPayload
        expect(column.rawTrailing) == rawTrailing
        expect(column.rawTrailingWords).to(beNil())
        expect(column.unknown) == rawTrailing
        expect(column.property.count) == 1
        expect(column.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0xAA, 0xBB])),
        ]
    }

    func testListControlsPreserveRawPayloadChildrenAndParagraphs() throws {
        let controls: [(UInt32, (HwpCtrlId) -> HwpListControl?)] = [
            (HwpOtherCtrlId.header.rawValue, listControlFromHeader),
            (HwpOtherCtrlId.footer.rawValue, listControlFromFooter),
            (HwpOtherCtrlId.footnote.rawValue, listControlFromFootnote),
            (HwpOtherCtrlId.endnote.rawValue, listControlFromEndnote),
        ]

        for (ctrlId, extract) in controls {
            try assertListControlPreservesRawPayloadChildrenAndParagraphs(
                ctrlId: ctrlId,
                extract: extract
            )
        }
    }

    func testHyperlinkControlPreservesRawPayloadTrailingBytesAndChildren() throws {
        let url = "https://example.test/hwp"
        let rawTrailing = Data([0xCA, 0xFE, 0x01])
        let rawPayload = hyperlinkPayload(url: url, rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xAA])))

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

        guard case let .hyperLink(hyperlink) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected hyperlink control")
        }

        expect(hyperlink.ctrlId) == HwpFieldCtrlId.hyperLink.rawValue
        expect(hyperlink.url) == url
        expect(hyperlink.urlLengthRawPayload) == littleEndianData(WORD(url.utf16.count))
        expect(hyperlink.urlRawPayload) == utf16Payload(url)
        expect(hyperlink.rawPayload) == rawPayload
        expect(hyperlink.rawTrailing) == rawTrailing
        expect(hyperlink.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xAA])),
        ]
    }
}

private func assertOtherControlPreservation(
    ctrlId: HwpOtherCtrlId,
    label: String
) throws {
    let rawTrailing = Data(label.utf8)
    var rawPayload = littleEndianData(ctrlId.rawValue)
    rawPayload.append(rawTrailing)
    let ctrlRecord = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    ctrlRecord.children = [
        HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: Data([0xAA])),
        HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xBB])),
    ]

    let paragraph = try HwpParagraph.load(
        paragraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ctrlRecord,
        ]),
        HwpVersion(5, 0, 1, 1)
    )

    guard let control = otherControl(from: paragraph, ctrlId: ctrlId, label: label) else {
        return
    }
    expect(control.ctrlId) == ctrlId
    expect(control.rawTrailing) == rawTrailing
    expect(control.rawPayload) == rawPayload
    expect(control.ctrlDataRecords.map(\.rawPayload)) == [Data([0xAA])]
    expect(control.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0xBB])),
    ]
}

// swiftlint:disable:next cyclomatic_complexity
private func otherControl(
    from paragraph: HwpParagraph,
    ctrlId: HwpOtherCtrlId,
    label: String
) -> HwpOtherControl? {
    switch paragraph.ctrlHeaderArray?.first {
    case let .autoNumber(autoNumber) where ctrlId == .autoNumber: return autoNumber
    case let .newNumber(newNumber) where ctrlId == .newNumber: return newNumber
    case let .pageHide(pageHide) where ctrlId == .pageHide: return pageHide
    case let .pageCT(pageCT) where ctrlId == .pageCT: return pageCT
    case let .indexmark(indexmark) where ctrlId == .indexmark: return indexmark
    case let .bookmark(bookmark) where ctrlId == .bookmark: return bookmark
    case let .overlapping(overlapping) where ctrlId == .overlapping: return overlapping
    case let .comment(comment) where ctrlId == .comment: return comment
    case let .hiddenComment(hiddenComment) where ctrlId == .hiddenComment: return hiddenComment
    case let .other(other) where ctrlId == .section || ctrlId == .column: return other
    default:
        fail("Expected other-like control for \(label)")
        return nil
    }
}

private func commonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(WORD(0)))
    return data
}

private func columnPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    data.append(littleEndianData(HwpOtherCtrlId.column.rawValue))
    data.append(littleEndianData(UInt16(0x1004)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(COLORREF(0)))
    data.append(rawTrailing)
    return data
}

private func listHeaderPayload(
    paragraphCount: Int32,
    rawTrailing: Data = Data()
) -> Data {
    concatenatedData(
        littleEndianData(paragraphCount),
        littleEndianData(UInt32(0x1122_3344)),
        rawTrailing
    )
}

private func hyperlinkPayload(url: String, rawTrailing: Data) -> Data {
    var data = Data()
    data.append(littleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(BYTE(0)))
    data.append(littleEndianData(WORD(url.utf16.count)))
    data.append(utf16Payload(url))
    data.append(rawTrailing)
    return data
}

private func utf16Payload(_ value: String) -> Data {
    var data = Data()
    for character in value.utf16 {
        data.append(littleEndianData(character))
    }
    return data
}

private func picturePayload(binaryDataId: UInt16) -> Data {
    var data = Data(repeating: 0, count: 74)
    let idBytes = littleEndianData(binaryDataId)
    data[71] = idBytes[0]
    data[72] = idBytes[1]
    return data
}

private func rawControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(contentsOf: [0xAA, 0xBB])
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

private func assertListControlPreservesRawPayloadChildrenAndParagraphs(
    ctrlId: UInt32,
    extract: (HwpCtrlId) -> HwpListControl?
) throws {
    let rawPayload = rawControlPayload(ctrlId: ctrlId)
    let listHeaderTrailing = Data([0xAA, 0xBB])
    let listHeaderPayload = listHeaderPayload(
        paragraphCount: 1,
        rawTrailing: listHeaderTrailing
    )
    let paragraph = try HwpParagraph.load(
        paragraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            listControlRecord(rawPayload, listHeaderPayload),
        ]),
        HwpVersion(5, 0, 1, 1)
    )

    guard let ctrl = paragraph.ctrlHeaderArray?.first,
          let listControl = extract(ctrl)
    else {
        return fail("Expected typed list control for \(ctrlId)")
    }

    expect(listControl.header.ctrlId) == ctrlId
    expect(listControl.header.rawPayload) == rawPayload
    expect(listControl.listArray.count) == 1
    expect(listControl.listArray.first?.header.paragraphCount) == 1
    expect(listControl.listArray.first?.header.property) == 0x1122_3344
    expect(listControl.listArray.first?.header.rawPayload) == listHeaderPayload
    expect(listControl.listArray.first?.header.rawTrailing) == listHeaderTrailing
    expect(listControl.listArray.first?.header.rawTrailingWords) == [UInt16(0xBBAA)]
    expect(listControl.listArray.first?.headerRawPayload) == listHeaderPayload
    expect(listControl.listArray.first?.headerUnknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FC, level: 3, payload: Data([0xAB])),
    ]
    expect(listControl.listArray.first?.paragraphArray.count) == 1
    expect(listControl.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xCD])),
    ]
}

private func listControlRecord(_ rawPayload: Data, _ listHeaderPayload: Data) -> HwpRecord {
    let listHeader = HwpRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 2,
        payload: listHeaderPayload
    )
    listHeader.children = [
        HwpRecord(tagId: 0x2FC, level: 3, payload: Data([0xAB])),
    ]
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = [
        listHeader,
        paragraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 3, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 3, payload: Data()),
        ]),
        HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xCD])),
    ]
    return record
}
