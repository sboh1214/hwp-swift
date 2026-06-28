@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertCompatibleDocument(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertCompatibleDocument(expectations, hwp.docInfo)
    }

    static func assertLayoutCompatibility(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertLayoutCompatibility(expectations, hwp.docInfo)
    }

    static func assertLayoutCompatibility(
        _ expectations: FixtureExpectations,
        _ docInfo: HwpDocInfo
    ) {
        guard let expected = expectations.layoutCompatibility else {
            return
        }

        assertLayoutCompatibility(expected, docInfo.layoutCompatibility)
    }

    static func assertCompatibleDocument(
        _ expectations: FixtureExpectations,
        _ docInfo: HwpDocInfo
    ) {
        guard let expected = expectations.compatibleDocument else {
            return
        }

        let actual = docInfo.compatibleDocument
        expect(actual).notTo(beNil())
        if let targetDocument = expected.targetDocument {
            expect(actual?.targetDocument) == targetDocument
        }
        FixtureAssertions.assertPayloadSample(
            actual?.targetDocumentRawPayload,
            length: expected.targetDocumentRawLength,
            prefix: expected.targetDocumentRawPrefixBytes,
            suffix: expected.targetDocumentRawSuffixBytes
        )
        if let rawPayloadLength = expected.rawPayloadLength {
            expect(actual?.rawPayload.count) == rawPayloadLength
        }
        if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
            expect(Array(actual?.rawPayload.prefix(rawPayloadPrefixBytes.count) ?? Data())) ==
                rawPayloadPrefixBytes
        }
        if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
            expect(Array(actual?.rawPayload.suffix(rawPayloadSuffixBytes.count) ?? Data())) ==
                rawPayloadSuffixBytes
        }
        assertUnknownChildren(
            actual?.unknownChildren ?? [],
            UnknownChildExpectation(expected),
            rootLevel: 1
        )
        assertCompatibleDocumentTrackChanges(expected.trackChanges, actual?.trackChangeArray ?? [])
        if let layoutCompatibility = expected.layoutCompatibility {
            assertLayoutCompatibility(
                layoutCompatibility,
                actual?.layoutCompatibility,
                rootLevel: 2
            )
        }
    }

    static func assertLayoutCompatibility(
        _ expectations: FixtureLayoutCompatibilityExpectations,
        _ actual: HwpLayoutCompatibility?,
        rootLevel: UInt32 = 1
    ) {
        expect(actual).notTo(beNil())
        if let char = expectations.char {
            expect(actual?.char) == char
        }
        if let paragraph = expectations.paragraph {
            expect(actual?.paragraph) == paragraph
        }
        if let section = expectations.section {
            expect(actual?.section) == section
        }
        if let object = expectations.object {
            expect(actual?.object) == object
        }
        if let field = expectations.field {
            expect(actual?.field) == field
        }
        if let rawPayloadLength = expectations.rawPayloadLength {
            expect(actual?.rawPayload.count) == rawPayloadLength
        }
        if let rawPayloadPrefixBytes = expectations.rawPayloadPrefixBytes {
            expect(Array(actual?.rawPayload.prefix(rawPayloadPrefixBytes.count) ?? Data())) ==
                rawPayloadPrefixBytes
        }
        if let rawPayloadSuffixBytes = expectations.rawPayloadSuffixBytes {
            expect(Array(actual?.rawPayload.suffix(rawPayloadSuffixBytes.count) ?? Data())) ==
                rawPayloadSuffixBytes
        }
        FixtureAssertions.assertPayloadSample(
            actual?.fixedFieldsRawPayload,
            length: expectations.fixedFieldsRawLength,
            prefix: expectations.fixedFieldsRawPrefixBytes,
            suffix: expectations.fixedFieldsRawSuffixBytes
        )
        assertUnknownChildren(
            actual?.unknownChildren ?? [],
            UnknownChildExpectation(expectations),
            rootLevel: rootLevel
        )
    }
}

private func assertCompatibleDocumentTrackChanges(
    _ expectedRecords: [FixtureRawRecordExpectations]?,
    _ actualRecords: [HwpTrackChange]
) {
    guard let expectedRecords else {
        return
    }

    expect(actualRecords.count) == expectedRecords.count
    for (expected, actual) in zip(expectedRecords, actualRecords) {
        if let rawPayloadLength = expected.rawPayloadLength {
            expect(actual.rawPayload.count) == rawPayloadLength
        }
        if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
            expect(Array(actual.rawPayload.prefix(rawPayloadPrefixBytes.count))) ==
                rawPayloadPrefixBytes
        }
        if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
            expect(Array(actual.rawPayload.suffix(rawPayloadSuffixBytes.count))) ==
                rawPayloadSuffixBytes
        }
        assertTrackChangeInfo(expected, actual)
        assertUnknownChildren(
            actual.unknownChildren,
            UnknownChildExpectation(expected),
            rootLevel: 2
        )
    }
}

private func assertTrackChangeInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: HwpTrackChange
) {
    if let trackChangeHeaderValue = expected.trackChangeHeaderValue {
        expect(actual.trackChangeInfo?.headerValue) == trackChangeHeaderValue
    }
    FixtureAssertions.assertPayloadSample(
        actual.trackChangeInfo?.headerRawPayload,
        length: expected.trackChangeHeaderRawLength,
        prefix: expected.trackChangeHeaderRawPrefixBytes,
        suffix: expected.trackChangeHeaderRawSuffixBytes
    )
    if let trackChangeRawTrailingLength = expected.trackChangeRawTrailingLength {
        expect(actual.trackChangeInfo?.rawTrailing.count) == trackChangeRawTrailingLength
    }
    if let trackChangeRawTrailingPrefixBytes = expected.trackChangeRawTrailingPrefixBytes {
        let prefix = actual.trackChangeInfo?.rawTrailing.prefix(
            trackChangeRawTrailingPrefixBytes.count
        ) ?? Data()
        expect(Array(prefix)) == trackChangeRawTrailingPrefixBytes
    }
    if let trackChangeRawTrailingSuffixBytes = expected.trackChangeRawTrailingSuffixBytes {
        let suffix = actual.trackChangeInfo?.rawTrailing.suffix(
            trackChangeRawTrailingSuffixBytes.count
        ) ?? Data()
        expect(Array(suffix)) == trackChangeRawTrailingSuffixBytes
    }
}

private struct UnknownChildExpectation {
    let count: Int?
    let tagIds: [UInt32]?
    let payloadLengths: [Int]?
    let payloadPrefixes: [[UInt8]]?
    let payloadSuffixes: [[UInt8]]?
    let childTagIds: [[UInt32]]?
    let childPayloadLengths: [[Int]]?
    let childPayloadPrefixes: [[[UInt8]]]?
    let childPayloadSuffixes: [[[UInt8]]]?

    init(_ expected: FixtureCompatibleDocumentExpectations) {
        count = expected.unknownChildCount
        tagIds = expected.unknownChildTagIds
        payloadLengths = expected.unknownChildPayloadLengths
        payloadPrefixes = expected.unknownChildPayloadPrefixBytes
        payloadSuffixes = expected.unknownChildPayloadSuffixBytes
        childTagIds = expected.unknownChildChildTagIds
        childPayloadLengths = expected.unknownChildChildPayloadLengths
        childPayloadPrefixes = expected.unknownChildChildPayloadPrefixBytes
        childPayloadSuffixes = expected.unknownChildChildPayloadSuffixBytes
    }

    init(_ expected: FixtureLayoutCompatibilityExpectations) {
        count = expected.unknownChildCount
        tagIds = expected.unknownChildTagIds
        payloadLengths = expected.unknownChildPayloadLengths
        payloadPrefixes = expected.unknownChildPayloadPrefixBytes
        payloadSuffixes = expected.unknownChildPayloadSuffixBytes
        childTagIds = expected.unknownChildChildTagIds
        childPayloadLengths = expected.unknownChildChildPayloadLengths
        childPayloadPrefixes = expected.unknownChildChildPayloadPrefixBytes
        childPayloadSuffixes = expected.unknownChildChildPayloadSuffixBytes
    }

    init(_ expected: FixtureRawRecordExpectations) {
        count = expected.unknownChildCount
        tagIds = expected.unknownChildTagIds
        payloadLengths = expected.unknownChildPayloadLengths
        payloadPrefixes = expected.unknownChildPayloadPrefixBytes
        payloadSuffixes = expected.unknownChildPayloadSuffixBytes
        childTagIds = expected.unknownChildChildTagIds
        childPayloadLengths = expected.unknownChildChildPayloadLengths
        childPayloadPrefixes = expected.unknownChildChildPayloadPrefixBytes
        childPayloadSuffixes = expected.unknownChildChildPayloadSuffixBytes
    }
}

private func assertUnknownChildren(
    _ actual: [HwpUnknownRecord],
    _ expected: UnknownChildExpectation,
    rootLevel: UInt32
) {
    if let count = expected.count {
        expect(actual.count) == count
    }
    FixtureAssertions.assertUnknownRecordSamples(
        actual,
        rootLevel: rootLevel,
        expectations: FixtureUnknownRecordSampleExpectations(
            tagIds: expected.tagIds,
            payloadLengths: expected.payloadLengths,
            payloadPrefixes: expected.payloadPrefixes,
            payloadSuffixes: expected.payloadSuffixes,
            childTagIds: expected.childTagIds,
            childPayloadLengths: expected.childPayloadLengths,
            childPayloadPrefixes: expected.childPayloadPrefixes,
            childPayloadSuffixes: expected.childPayloadSuffixes
        )
    )
}
