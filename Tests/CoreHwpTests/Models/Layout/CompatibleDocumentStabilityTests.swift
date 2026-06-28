@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class CompatibleDocumentStabilityTests: XCTestCase {
    func testCompatibleDocumentInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = (Data([0xEF]) + littleEndianData(UInt32(7))).dropFirst()
        let unknownPayload = Data([0xA0])
        let unknown = HwpRecord(tagId: 0x2FA, level: 1, payload: unknownPayload)
        var reader = DataReader(payload)

        let compatibleDocument = try HwpCompatibleDocument(&reader, [unknown])

        expect(compatibleDocument.rawPayload) == payload
        expect(compatibleDocument.targetDocumentRawPayload) == payload
        expect(compatibleDocument.targetDocument) == 7
        expect(compatibleDocument.layoutCompatibility).to(beNil())
        expect(compatibleDocument.trackChangeArray).to(beEmpty())
        expect(compatibleDocument.unknownChildren) == [HwpUnknownRecord(unknown)]
        expect(reader.isEOF) == true
    }

    func testCompatibleDocumentRejectsTruncatedTargetDocumentWithTypedError() {
        expect {
            _ = try HwpCompatibleDocument.load(compatibleDocumentRecord(
                payload: Data([0x00, 0x00, 0x00]),
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

    func testCompatibleDocumentRejectsTrailingBytesWithTypedError() {
        let payload = littleEndianData(UInt32(7)) + Data([0xAA])

        expect {
            _ = try HwpCompatibleDocument.load(compatibleDocumentRecord(
                payload: payload,
                children: []
            ))
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpCompatibleDocument"
            expect(remain) == 1
        })
    }

    func testCompatibleDocumentAllowsMissingLayoutAndPreservesUnknownChildren() throws {
        let payload = littleEndianData(UInt32(7))
        let unknownPayload = Data([0xA0, 0xA1])
        let unknownGrandchildPayload = Data([0xB0])
        let unknown = HwpRecord(tagId: 0x2FA, level: 1, payload: unknownPayload)
        unknown.children = [
            HwpRecord(tagId: 0x2FB, level: 2, payload: unknownGrandchildPayload),
        ]

        let compatibleDocument = try HwpCompatibleDocument.load(compatibleDocumentRecord(
            payload: payload,
            children: [unknown]
        ))

        expect(compatibleDocument.rawPayload) == payload
        expect(compatibleDocument.targetDocumentRawPayload) == payload
        expect(compatibleDocument.targetDocument) == 7
        expect(compatibleDocument.layoutCompatibility).to(beNil())
        expect(compatibleDocument.trackChangeArray).to(beEmpty())
        expect(compatibleDocument.unknownChildren) == [HwpUnknownRecord(unknown)]
    }

    func testCompatibleDocumentPreservesDuplicateLayoutCompatibilityAsUnknownChild() throws {
        let firstLayoutPayload = layoutCompatibilityPayload(1, 2, 3, 4, 5)
        let duplicateLayoutPayload = layoutCompatibilityPayload(6, 7, 8, 9, 10)
        let duplicateLayoutChildPayload = Data([0xCA, 0xFE])
        let trackChangePayload = Data([0xDD])
        let duplicateLayout = HwpRecord(
            tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
            level: 1,
            payload: duplicateLayoutPayload
        )
        duplicateLayout.children = [
            HwpRecord(tagId: 0x2FC, level: 2, payload: duplicateLayoutChildPayload),
        ]

        let compatibleDocument = try HwpCompatibleDocument.load(compatibleDocumentRecord(
            payload: littleEndianData(UInt32(0)),
            children: [
                HwpRecord(
                    tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
                    level: 1,
                    payload: firstLayoutPayload
                ),
                duplicateLayout,
                HwpRecord(
                    tagId: HwpDocInfoTag.trackChange.rawValue,
                    level: 1,
                    payload: trackChangePayload
                ),
            ]
        ))

        expect(compatibleDocument.layoutCompatibility?.rawPayload) == firstLayoutPayload
        expect(compatibleDocument.layoutCompatibility?.fixedFieldsRawPayload) == firstLayoutPayload
        expect(compatibleDocument.layoutCompatibility?.field) == 5
        expect(compatibleDocument.trackChangeArray.map(\.rawPayload)) == [trackChangePayload]
        expect(compatibleDocument.unknownChildren) == [HwpUnknownRecord(duplicateLayout)]
    }

    func testNooriCompatibleDocumentSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "noori")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        assertNooriCompatibleDocument(decoded.docInfo.compatibleDocument)
        expect(decoded.docInfo.compatibleDocument?.rawPayload) ==
            hwp.docInfo.compatibleDocument?.rawPayload
        expect(decoded.docInfo.compatibleDocument?.targetDocumentRawPayload) ==
            hwp.docInfo.compatibleDocument?.targetDocumentRawPayload
        expect(decoded.docInfo.compatibleDocument?.layoutCompatibility?.rawPayload) ==
            hwp.docInfo.compatibleDocument?.layoutCompatibility?.rawPayload
        expect(decoded.docInfo.compatibleDocument?.layoutCompatibility?.fixedFieldsRawPayload) ==
            hwp.docInfo.compatibleDocument?.layoutCompatibility?.fixedFieldsRawPayload
        expect(decoded.docInfo.compatibleDocument?.trackChangeArray.map(\.rawPayload)) ==
            hwp.docInfo.compatibleDocument?.trackChangeArray.map(\.rawPayload)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func assertNooriCompatibleDocument(_ compatibleDocument: HwpCompatibleDocument?) {
    expect(compatibleDocument?.targetDocument) == 0
    expect(compatibleDocument?.targetDocumentRawPayload) == Data(repeating: 0, count: 4)
    expect(compatibleDocument?.rawPayload) == Data(repeating: 0, count: 4)
    expect(compatibleDocument?.unknownChildren).to(beEmpty())

    let layoutCompatibility = compatibleDocument?.layoutCompatibility
    expect(layoutCompatibility?.rawPayload) == Data(repeating: 0, count: 20)
    expect(layoutCompatibility?.fixedFieldsRawPayload) == Data(repeating: 0, count: 20)
    expect(layoutCompatibility?.char) == 0
    expect(layoutCompatibility?.paragraph) == 0
    expect(layoutCompatibility?.section) == 0
    expect(layoutCompatibility?.object) == 0
    expect(layoutCompatibility?.field) == 0
    expect(layoutCompatibility?.unknownChildren).to(beEmpty())

    expect(compatibleDocument?.trackChangeArray.count) == 1
    let trackChange = compatibleDocument?.trackChangeArray.first
    expect(trackChange?.rawPayload.count) == 1032
    expect(Array(trackChange?.rawPayload.prefix(8) ?? Data())) == [56, 0, 0, 0, 0, 0, 0, 0]
    expect(Array(trackChange?.rawPayload.suffix(8) ?? Data())) == Array(repeating: 0, count: 8)
    expect(trackChange?.unknownChildren).to(beEmpty())
}

private func compatibleDocumentRecord(payload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpDocInfoTag.compatibleDocument.rawValue,
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
