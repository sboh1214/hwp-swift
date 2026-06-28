@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoRawRecordTagValidationTests: XCTestCase {
    func testDocInfoRecordLoaderRejectsUnconsumedPayloadWithTypedError() {
        let record = HwpRecord(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: Data([0xAA, 0xBB, 0xCC])
        )

        expect {
            _ = try loadDocInfoRecord(
                record,
                expectedTag: .docData,
                as: PartialDocInfoRecord.self
            )
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "PartialDocInfoRecord"
            expect(remain) == 2
            expect(error.localizedDescription)
                .to(contain("Bytes are not EOF : 2 bytes remain in PartialDocInfoRecord"))
        })
    }

    func testDocInfoStructuralRecordModelsRejectMismatchedTagsWithTypedError() {
        let payload = Data([0xAA])
        let wrongTag = HwpDocInfoTag.documentProperties.rawValue

        expectMismatchedDocInfoTag(expected: .idMappings, got: wrongTag) {
            _ = try HwpIdMappings.load(
                tagValidationRecord(tagId: wrongTag, payload: payload),
                HwpVersion(5, 0, 3, 2)
            )
        }
        expectMismatchedDocInfoTag(expected: .compatibleDocument, got: wrongTag) {
            _ = try HwpCompatibleDocument.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .layoutCompatibility, got: wrongTag) {
            _ = try HwpLayoutCompatibility.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
    }

    func testDocInfoRawRecordModelsRejectMismatchedTagsWithTypedError() {
        let payload = Data([0xAA])
        let wrongTag = HwpDocInfoTag.documentProperties.rawValue

        expectMismatchedDocInfoTag(expected: .docData, got: wrongTag) {
            _ = try HwpDocData.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .distributeDocData, got: wrongTag) {
            _ = try HwpDistributeDocData.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .trackChange, got: wrongTag) {
            _ = try HwpTrackChange.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .memoShape, got: wrongTag) {
            _ = try HwpMemoShape.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .trackChangeContent, got: wrongTag) {
            _ = try HwpTrackChangeContent.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .trackChangeAuthor, got: wrongTag) {
            _ = try HwpTrackChangeAuthor.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
        expectMismatchedDocInfoTag(expected: .forbiddenChar, got: wrongTag) {
            _ = try HwpForbiddenChar.load(tagValidationRecord(
                tagId: wrongTag,
                payload: payload
            ))
        }
    }
}

private func tagValidationRecord(tagId: UInt32, payload: Data) -> HwpRecord {
    HwpRecord(tagId: tagId, level: 0, payload: payload)
}

private struct PartialDocInfoRecord: HwpFromRecord {
    let firstByte: UInt8

    init(_ reader: inout DataReader, _: [HwpRecord]) throws {
        firstByte = try reader.read(UInt8.self)
    }
}

private func expectMismatchedDocInfoTag(
    expected: HwpDocInfoTag,
    got actualTag: UInt32,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("expected DocInfo tag \(expected.rawValue)"))
        expect(reason).to(contain("got \(actualTag)"))
    })
}
