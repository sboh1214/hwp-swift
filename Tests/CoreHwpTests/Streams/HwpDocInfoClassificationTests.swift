@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// DocInfo children 단일 분류 패스 (#125)의 소비 계약 고정:
/// singleton은 첫 레코드만 소비하고 중복은 unknownRecords로, 미지 태그도
/// unknownRecords로 — 둘 다 원래 children 순서를 보존한다.
final class HwpDocInfoClassificationTests: XCTestCase {
    /// 문서에 등장한 적 없는 태그 (HwpDocInfoTag 범위 밖 예약값)
    private let unknownTag: UInt32 = 0x3F

    func testDuplicateSingletonConsumesFirstAndKeepsRestAsUnknown() throws {
        // sectionSize 1 → 2 순서로 중복 — 첫 레코드가 이겨야 한다
        let payload = concatenatedData(
            classificationRecordData(
                tagId: HwpDocInfoTag.documentProperties.rawValue,
                payload: classificationDocumentPropertiesPayload(sectionSize: 1)
            ),
            classificationRecordData(
                tagId: HwpDocInfoTag.idMappings.rawValue,
                payload: classificationIdMappingsPayload()
            ),
            classificationRecordData(
                tagId: HwpDocInfoTag.documentProperties.rawValue,
                payload: classificationDocumentPropertiesPayload(sectionSize: 2)
            )
        )
        var reader = DataReader(payload)

        let docInfo = try HwpDocInfo(&reader, HwpVersion())

        expect(docInfo.documentProperties.sectionSize) == 1
        expect(docInfo.unknownRecords.count) == 1
        expect(docInfo.unknownRecords.first?.tagId)
            == HwpDocInfoTag.documentProperties.rawValue
    }

    func testUnknownTagsSurviveInChildrenOrder() throws {
        let payload = concatenatedData(
            classificationRecordData(tagId: unknownTag, payload: Data([0xAA])),
            classificationRecordData(
                tagId: HwpDocInfoTag.documentProperties.rawValue,
                payload: classificationDocumentPropertiesPayload(sectionSize: 1)
            ),
            classificationRecordData(
                tagId: HwpDocInfoTag.idMappings.rawValue,
                payload: classificationIdMappingsPayload()
            ),
            classificationRecordData(tagId: unknownTag + 1, payload: Data([0xBB]))
        )
        var reader = DataReader(payload)

        let docInfo = try HwpDocInfo(&reader, HwpVersion())

        expect(docInfo.unknownRecords.map(\.tagId)) == [unknownTag, unknownTag + 1]
    }

    func testMissingIdMappingsThrowsItsOwnTag() {
        let payload = classificationRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            payload: classificationDocumentPropertiesPayload(sectionSize: 1)
        )

        expect {
            var reader = DataReader(payload)
            return try HwpDocInfo(&reader, HwpVersion())
        }.to(throwError { (error: HwpError) in
            guard case let .recordDoesNotExist(tag) = error else {
                fail("recordDoesNotExist가 아니라 \(error)")
                return
            }
            expect(tag) == HwpDocInfoTag.idMappings.rawValue
        })
    }
}

private func classificationRecordData(tagId: UInt32, payload: Data) -> Data {
    var data = classificationLittleEndianData(
        tagId | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func classificationDocumentPropertiesPayload(sectionSize: UInt16) -> Data {
    concatenatedData(
        classificationLittleEndianData(sectionSize),
        Data(repeating: 0, count: 24)
    )
}

private func classificationIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(classificationLittleEndianData(count))
    }
}

private func classificationLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
