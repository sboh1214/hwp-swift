@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileRequiredRecordAssemblyTests: XCTestCase {
    func testActualFixtureBasedAssemblyRejectsMissingDocInfoRequiredRecords()
        throws
    {
        let base = try openHwp(#file, "plain-text-minimal")
        let sectionDataArray = base.sectionArray.map(\.rawPayload)
        let cases = [
            HwpDocInfoTag.documentProperties.rawValue,
            HwpDocInfoTag.idMappings.rawValue,
        ]

        for tag in cases {
            let docInfoData = try assemblyRequiredDataRemovingTopLevelRecord(
                tag,
                from: base.docInfo.rawPayload
            )

            expectAssemblyRequiredRecordDoesNotExist(tag) {
                _ = try HwpFile(
                    fileHeader: base.fileHeader,
                    docInfoData: docInfoData,
                    sectionDataArray: sectionDataArray
                )
            }
        }
    }

    func testActualFixtureBasedAssemblyRejectsMissingSectionRequiredRecords()
        throws
    {
        let base = try openHwp(#file, "plain-text-minimal")
        let section = try XCTUnwrap(base.sectionArray.first)

        let sectionWithoutParagraphHeader = try assemblyRequiredDataRemovingTopLevelRecord(
            HwpSectionTag.paraHeader.rawValue,
            from: section.rawPayload
        )
        expectAssemblyRequiredRecordDoesNotExist(HwpSectionTag.paraHeader.rawValue) {
            _ = try HwpFile(
                fileHeader: base.fileHeader,
                docInfoData: base.docInfo.rawPayload,
                sectionDataArray: [sectionWithoutParagraphHeader]
            )
        }

        let sectionWithoutCharShape = try assemblyRequiredDataRemovingChildRecord(
            HwpSectionTag.paraCharShape.rawValue,
            fromFirstTopLevelRecord: HwpSectionTag.paraHeader.rawValue,
            in: section.rawPayload
        )
        expectAssemblyRequiredRecordDoesNotExist(HwpSectionTag.paraCharShape.rawValue) {
            _ = try HwpFile(
                fileHeader: base.fileHeader,
                docInfoData: base.docInfo.rawPayload,
                sectionDataArray: [sectionWithoutCharShape]
            )
        }
    }

    func testAssemblyRejectsMissingDocumentPropertiesRecordWithTypedError() {
        let docInfoData = assemblyRequiredRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: assemblyRequiredIdMappingsPayload()
        )

        expectAssemblyRequiredRecordDoesNotExist(HwpDocInfoTag.documentProperties.rawValue) {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: docInfoData,
                sectionDataArray: [assemblyRequiredMinimalSectionData()]
            )
        }
    }

    func testAssemblyRejectsMissingIdMappingsRecordWithTypedError() {
        let docInfoData = assemblyRequiredRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: assemblyRequiredDocumentPropertiesPayload(sectionSize: 1)
        )

        expectAssemblyRequiredRecordDoesNotExist(HwpDocInfoTag.idMappings.rawValue) {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: docInfoData,
                sectionDataArray: [assemblyRequiredMinimalSectionData()]
            )
        }
    }

    func testAssemblyRejectsMissingParagraphHeaderRecordWithTypedError() {
        expectAssemblyRequiredRecordDoesNotExist(HwpSectionTag.paraHeader.rawValue) {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: assemblyRequiredMinimalDocInfoData(sectionSize: 1),
                sectionDataArray: [Data()]
            )
        }
    }

    func testAssemblyRejectsMissingParagraphCharShapeRecordWithTypedError() {
        let sectionData = assemblyRequiredRecordData(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: assemblyRequiredParaHeaderPayload()
        )

        expectAssemblyRequiredRecordDoesNotExist(HwpSectionTag.paraCharShape.rawValue) {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: assemblyRequiredMinimalDocInfoData(sectionSize: 1),
                sectionDataArray: [sectionData]
            )
        }
    }
}

private func expectAssemblyRequiredRecordDoesNotExist(
    _ expectedTag: UInt32,
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

private func assemblyRequiredMinimalDocInfoData(sectionSize: UInt16) -> Data {
    assemblyRequiredRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: assemblyRequiredDocumentPropertiesPayload(sectionSize: sectionSize)
    )
        + assemblyRequiredRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: assemblyRequiredIdMappingsPayload()
        )
}

private func assemblyRequiredMinimalSectionData() -> Data {
    assemblyRequiredRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: assemblyRequiredParaHeaderPayload()
    )
        + assemblyRequiredRecordData(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: assemblyRequiredParaCharShapePayload()
        )
}

private func assemblyRequiredDocumentPropertiesPayload(sectionSize: UInt16) -> Data {
    assemblyRequiredLittleEndianData(sectionSize) + Data(repeating: 0, count: 24)
}

private func assemblyRequiredIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(assemblyRequiredLittleEndianData(count))
    }
}

private func assemblyRequiredParaHeaderPayload() -> Data {
    assemblyRequiredLittleEndianData(UInt32(0x8000_0000))
        + assemblyRequiredLittleEndianData(UInt32(0))
        + assemblyRequiredLittleEndianData(UInt16(0))
        + Data([0, 0])
        + assemblyRequiredLittleEndianData(UInt16(1))
        + assemblyRequiredLittleEndianData(UInt16(0))
        + assemblyRequiredLittleEndianData(UInt16(0))
        + assemblyRequiredLittleEndianData(UInt32(0))
        + assemblyRequiredLittleEndianData(UInt16(0))
}

private func assemblyRequiredParaCharShapePayload() -> Data {
    assemblyRequiredLittleEndianData(UInt32(0)) + assemblyRequiredLittleEndianData(UInt32(0))
}

private func assemblyRequiredRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = assemblyRequiredLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func assemblyRequiredDataRemovingTopLevelRecord(
    _ tagId: UInt32,
    from data: Data
) throws -> Data {
    let root = try parseTreeRecord(data: data)
    return assemblyRequiredSerializedData(root.children.filter { $0.tagId != tagId })
}

private func assemblyRequiredDataRemovingChildRecord(
    _ childTagId: UInt32,
    fromFirstTopLevelRecord parentTagId: UInt32,
    in data: Data
) throws -> Data {
    let root = try parseTreeRecord(data: data)
    guard let parent = root.children.first(where: { $0.tagId == parentTagId }) else {
        throw HwpError.recordDoesNotExist(tag: parentTagId)
    }
    parent.children.removeAll { $0.tagId == childTagId }
    return assemblyRequiredSerializedData(root.children)
}

private func assemblyRequiredSerializedData(_ records: [HwpRecord]) -> Data {
    records.reduce(into: Data()) { data, record in
        data.append(assemblyRequiredSerializedRecord(record))
    }
}

private func assemblyRequiredSerializedRecord(_ record: HwpRecord) -> Data {
    var data = assemblyRequiredSerializedRecordHeader(
        tagId: record.tagId,
        level: record.level,
        payloadSize: record.payload.count
    )
    data.append(record.payload)
    data.append(assemblyRequiredSerializedData(record.children))
    return data
}

private func assemblyRequiredSerializedRecordHeader(
    tagId: UInt32,
    level: UInt32,
    payloadSize: Int
) -> Data {
    let size = UInt32(payloadSize)
    let tagAndLevel = tagId | (level << 10)

    if size < 0xFFF {
        return assemblyRequiredLittleEndianData(tagAndLevel | (size << 20))
    }

    return assemblyRequiredLittleEndianData(tagAndLevel | (0xFFF << 20))
        + assemblyRequiredLittleEndianData(size)
}

private func assemblyRequiredLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
