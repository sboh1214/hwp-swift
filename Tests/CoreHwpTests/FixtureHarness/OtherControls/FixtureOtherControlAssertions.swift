@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertOtherControls(
        _ expectations: [FixtureOtherControlExpectations],
        _ hwp: HwpFile
    ) {
        let actualControls = FixtureDerivedValues.otherControls(from: hwp)
        assertOtherControls(expectations, actualControls)
    }

    static func assertOtherControls(
        _ expectations: [FixtureOtherControlExpectations],
        _ actualControls: [HwpOtherControl]
    ) {
        expect(actualControls.count) == expectations.count

        for (actual, expected) in zip(actualControls, expectations) {
            assertOtherControl(actual, expected)
        }
    }

    static func assertOtherControlSamples(
        _ expectations: [FixtureOtherControlExpectations],
        _ hwp: HwpFile
    ) {
        let actualControls = FixtureDerivedValues.otherControls(from: hwp)
        assertOtherControlSamples(expectations, actualControls)
    }

    static func assertOtherControlSamples(
        _ expectations: [FixtureOtherControlExpectations],
        _ actualControls: [HwpOtherControl]
    ) {
        for expected in expectations {
            expect(otherControlSelectorIsDeclared(expected)) == true
            let matchedControls = actualControls.filter { control in
                otherControl(control, matches: expected)
            }
            let occurrenceIndex = expected.occurrenceIndex ?? 0
            expect(occurrenceIndex).to(beGreaterThanOrEqualTo(0))
            expect(matchedControls.count).to(beGreaterThan(occurrenceIndex))
            guard matchedControls.indices.contains(occurrenceIndex) else {
                continue
            }
            assertOtherControl(matchedControls[occurrenceIndex], expected)
        }
    }
}

private extension FixtureAssertions {
    static func assertOtherControl(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let ctrlId = expected.ctrlId {
            expect(actual.ctrlId.rawValue) == ctrlId
        }
        if let ctrlIdName = expected.ctrlIdName {
            expect(String(describing: actual.ctrlId)) == ctrlIdName
        }
        if let bookmarkName = expected.bookmarkName {
            expect(actual.bookmarkInfo?.name) == bookmarkName
        }
        assertOtherControlBookmarkInfo(actual, expected)
        assertOtherControlNumberingInfo(actual, expected)
        assertOtherControlPageHideInfo(actual, expected)
        assertOtherControlIndexmarkInfo(actual, expected)
        assertOtherControlRawPayload(actual, expected)
        assertOtherControlRawTrailing(actual, expected)
        assertOtherControlCtrlData(actual, expected)
        assertOtherControlUnknownChildren(actual, expected)
    }

    static func otherControlSelectorIsDeclared(
        _ expected: FixtureOtherControlExpectations
    ) -> Bool {
        expected.ctrlId != nil || expected.ctrlIdName != nil
    }

    static func otherControl(
        _ actual: HwpOtherControl,
        matches expected: FixtureOtherControlExpectations
    ) -> Bool {
        if let ctrlId = expected.ctrlId, actual.ctrlId.rawValue != ctrlId {
            return false
        }
        if let ctrlIdName = expected.ctrlIdName, String(describing: actual.ctrlId) != ctrlIdName {
            return false
        }
        return true
    }

    static func assertOtherControlBookmarkInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        assertOtherControlBookmarkLengthInfo(actual, expected)
        assertOtherControlBookmarkNamePayload(actual, expected)
        assertOtherControlBookmarkRawTrailing(actual, expected)
    }

    static func assertOtherControlBookmarkLengthInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let bookmarkNameCharacterCount = expected.bookmarkNameCharacterCount {
            expect(actual.bookmarkInfo?.nameCharacterCount) == bookmarkNameCharacterCount
        }
        if let bookmarkNameLengthRawPayloadLength = expected
            .bookmarkNameLengthRawPayloadLength
        {
            expect(actual.bookmarkInfo?.nameLengthRawPayload.count) ==
                bookmarkNameLengthRawPayloadLength
        }
        if let bookmarkNameLengthRawPayloadPrefixBytes = expected
            .bookmarkNameLengthRawPayloadPrefixBytes
        {
            let lengthRawPayload = actual.bookmarkInfo?.nameLengthRawPayload ?? Data()
            expect(Array(
                lengthRawPayload.prefix(bookmarkNameLengthRawPayloadPrefixBytes.count)
            )) == bookmarkNameLengthRawPayloadPrefixBytes
        }
        if let bookmarkNameLengthRawPayloadSuffixBytes = expected
            .bookmarkNameLengthRawPayloadSuffixBytes
        {
            let lengthRawPayload = actual.bookmarkInfo?.nameLengthRawPayload ?? Data()
            expect(Array(
                lengthRawPayload.suffix(bookmarkNameLengthRawPayloadSuffixBytes.count)
            )) == bookmarkNameLengthRawPayloadSuffixBytes
        }
    }

    static func assertOtherControlBookmarkNamePayload(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let bookmarkNameRawPayloadLength = expected.bookmarkNameRawPayloadLength {
            expect(actual.bookmarkInfo?.nameRawPayload.count) == bookmarkNameRawPayloadLength
        }
        if let bookmarkNameRawPayloadPrefixBytes = expected.bookmarkNameRawPayloadPrefixBytes {
            let nameRawPayload = actual.bookmarkInfo?.nameRawPayload ?? Data()
            expect(Array(
                nameRawPayload.prefix(bookmarkNameRawPayloadPrefixBytes.count)
            )) == bookmarkNameRawPayloadPrefixBytes
        }
        if let bookmarkNameRawPayloadSuffixBytes = expected.bookmarkNameRawPayloadSuffixBytes {
            let nameRawPayload = actual.bookmarkInfo?.nameRawPayload ?? Data()
            expect(Array(
                nameRawPayload.suffix(bookmarkNameRawPayloadSuffixBytes.count)
            )) == bookmarkNameRawPayloadSuffixBytes
        }
    }

    static func assertOtherControlBookmarkRawTrailing(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let bookmarkRawTrailingLength = expected.bookmarkRawTrailingLength {
            expect(actual.bookmarkInfo?.rawTrailing.count) == bookmarkRawTrailingLength
        }
        if let bookmarkRawTrailingPrefixBytes = expected.bookmarkRawTrailingPrefixBytes {
            let rawTrailing = actual.bookmarkInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.prefix(bookmarkRawTrailingPrefixBytes.count)
            )) == bookmarkRawTrailingPrefixBytes
        }
        if let bookmarkRawTrailingSuffixBytes = expected.bookmarkRawTrailingSuffixBytes {
            let rawTrailing = actual.bookmarkInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.suffix(bookmarkRawTrailingSuffixBytes.count)
            )) == bookmarkRawTrailingSuffixBytes
        }
    }

    static func assertOtherControlNumberingInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let numberingKind = expected.numberingKind {
            expect(actual.numberingInfo?.kind) == numberingKind
        }
        if let numberingValue = expected.numberingValue {
            expect(actual.numberingInfo?.number) == numberingValue
        }
        if let numberingFormat = expected.numberingFormat {
            expect(actual.numberingInfo?.format) == numberingFormat
        }
        if let numberingRawTrailingLength = expected.numberingRawTrailingLength {
            expect(actual.numberingInfo?.rawTrailing.count) == numberingRawTrailingLength
        }
        if let numberingRawTrailingPrefixBytes = expected.numberingRawTrailingPrefixBytes {
            let rawTrailing = actual.numberingInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.prefix(numberingRawTrailingPrefixBytes.count)
            )) == numberingRawTrailingPrefixBytes
        }
        if let numberingRawTrailingSuffixBytes = expected.numberingRawTrailingSuffixBytes {
            let rawTrailing = actual.numberingInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.suffix(numberingRawTrailingSuffixBytes.count)
            )) == numberingRawTrailingSuffixBytes
        }
    }

    static func assertOtherControlPageHideInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let pageHideRawValue = expected.pageHideRawValue {
            expect(actual.pageHideInfo?.rawValue) == pageHideRawValue
        }
        if let pageHideRawTrailingLength = expected.pageHideRawTrailingLength {
            expect(actual.pageHideInfo?.rawTrailing.count) == pageHideRawTrailingLength
        }
        if let pageHideRawTrailingPrefixBytes = expected.pageHideRawTrailingPrefixBytes {
            let rawTrailing = actual.pageHideInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.prefix(pageHideRawTrailingPrefixBytes.count)
            )) == pageHideRawTrailingPrefixBytes
        }
        if let pageHideRawTrailingSuffixBytes = expected.pageHideRawTrailingSuffixBytes {
            let rawTrailing = actual.pageHideInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.suffix(pageHideRawTrailingSuffixBytes.count)
            )) == pageHideRawTrailingSuffixBytes
        }
    }

    static func assertOtherControlIndexmarkInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        assertOtherControlIndexmarkLengthInfo(actual, expected)
        assertOtherControlIndexmarkTextPayload(actual, expected)
        assertOtherControlIndexmarkRawTrailing(actual, expected)
    }

    static func assertOtherControlIndexmarkLengthInfo(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let indexmarkTextCharacterCount = expected.indexmarkTextCharacterCount {
            expect(actual.indexmarkInfo?.textCharacterCount) == indexmarkTextCharacterCount
        }
        if let indexmarkTextLengthRawPayloadLength = expected
            .indexmarkTextLengthRawPayloadLength
        {
            expect(actual.indexmarkInfo?.textLengthRawPayload.count) ==
                indexmarkTextLengthRawPayloadLength
        }
        if let indexmarkTextLengthRawPayloadPrefixBytes = expected
            .indexmarkTextLengthRawPayloadPrefixBytes
        {
            let lengthRawPayload = actual.indexmarkInfo?.textLengthRawPayload ?? Data()
            expect(Array(
                lengthRawPayload.prefix(indexmarkTextLengthRawPayloadPrefixBytes.count)
            )) == indexmarkTextLengthRawPayloadPrefixBytes
        }
        if let indexmarkTextLengthRawPayloadSuffixBytes = expected
            .indexmarkTextLengthRawPayloadSuffixBytes
        {
            let lengthRawPayload = actual.indexmarkInfo?.textLengthRawPayload ?? Data()
            expect(Array(
                lengthRawPayload.suffix(indexmarkTextLengthRawPayloadSuffixBytes.count)
            )) == indexmarkTextLengthRawPayloadSuffixBytes
        }
    }

    static func assertOtherControlIndexmarkTextPayload(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let indexmarkText = expected.indexmarkText {
            expect(actual.indexmarkInfo?.text) == indexmarkText
        }
        if let indexmarkTextRawPayloadLength = expected.indexmarkTextRawPayloadLength {
            expect(actual.indexmarkInfo?.textRawPayload.count) == indexmarkTextRawPayloadLength
        }
        if let indexmarkTextRawPayloadPrefixBytes = expected.indexmarkTextRawPayloadPrefixBytes {
            let textRawPayload = actual.indexmarkInfo?.textRawPayload ?? Data()
            expect(Array(
                textRawPayload.prefix(indexmarkTextRawPayloadPrefixBytes.count)
            )) == indexmarkTextRawPayloadPrefixBytes
        }
        if let indexmarkTextRawPayloadSuffixBytes = expected.indexmarkTextRawPayloadSuffixBytes {
            let textRawPayload = actual.indexmarkInfo?.textRawPayload ?? Data()
            expect(Array(
                textRawPayload.suffix(indexmarkTextRawPayloadSuffixBytes.count)
            )) == indexmarkTextRawPayloadSuffixBytes
        }
    }

    static func assertOtherControlIndexmarkRawTrailing(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let indexmarkRawTrailingLength = expected.indexmarkRawTrailingLength {
            expect(actual.indexmarkInfo?.rawTrailing.count) == indexmarkRawTrailingLength
        }
        if let indexmarkRawTrailingPrefixBytes = expected.indexmarkRawTrailingPrefixBytes {
            let rawTrailing = actual.indexmarkInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.prefix(indexmarkRawTrailingPrefixBytes.count)
            )) == indexmarkRawTrailingPrefixBytes
        }
        if let indexmarkRawTrailingSuffixBytes = expected.indexmarkRawTrailingSuffixBytes {
            let rawTrailing = actual.indexmarkInfo?.rawTrailing ?? Data()
            expect(Array(
                rawTrailing.suffix(indexmarkRawTrailingSuffixBytes.count)
            )) == indexmarkRawTrailingSuffixBytes
        }
    }

    static func assertOtherControlRawPayload(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
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
    }

    static func assertOtherControlRawTrailing(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let rawTrailingLength = expected.rawTrailingLength {
            expect(actual.rawTrailing.count) == rawTrailingLength
        }
        if let rawTrailingPrefixBytes = expected.rawTrailingPrefixBytes {
            expect(Array(actual.rawTrailing.prefix(rawTrailingPrefixBytes.count))) ==
                rawTrailingPrefixBytes
        }
        if let rawTrailingSuffixBytes = expected.rawTrailingSuffixBytes {
            expect(Array(actual.rawTrailing.suffix(rawTrailingSuffixBytes.count))) ==
                rawTrailingSuffixBytes
        }
    }

    static func assertOtherControlCtrlData(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let ctrlDataCount = expected.ctrlDataCount {
            expect(actual.ctrlDataRecords.count) == ctrlDataCount
        }
        if let ctrlDataPayloadLengths = expected.ctrlDataPayloadLengths {
            expect(actual.ctrlDataRecords.map(\.rawPayload.count)) == ctrlDataPayloadLengths
        }
        if let ctrlDataPayloadPrefixBytes = expected.ctrlDataPayloadPrefixBytes {
            expect(actual.ctrlDataRecords.count) == ctrlDataPayloadPrefixBytes.count
            let actualPrefixes = zip(actual.ctrlDataRecords, ctrlDataPayloadPrefixBytes)
                .map { record, prefixBytes in Array(record.rawPayload.prefix(prefixBytes.count)) }
            expect(actualPrefixes) == ctrlDataPayloadPrefixBytes
        }
        if let ctrlDataPayloadSuffixBytes = expected.ctrlDataPayloadSuffixBytes {
            expect(actual.ctrlDataRecords.count) == ctrlDataPayloadSuffixBytes.count
            let actualSuffixes = zip(actual.ctrlDataRecords, ctrlDataPayloadSuffixBytes)
                .map { record, suffixBytes in Array(record.rawPayload.suffix(suffixBytes.count)) }
            expect(actualSuffixes) == ctrlDataPayloadSuffixBytes
        }
    }

    static func assertOtherControlUnknownChildren(
        _ actual: HwpOtherControl,
        _ expected: FixtureOtherControlExpectations
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.unknownChildren.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
            actual.unknownChildren,
            rootLevel: 2,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expected.unknownChildTagIds,
                payloadLengths: expected.unknownChildPayloadLengths,
                payloadPrefixes: expected.unknownChildPayloadPrefixBytes,
                payloadSuffixes: expected.unknownChildPayloadSuffixBytes,
                childTagIds: expected.unknownChildChildTagIds,
                childPayloadLengths: expected.unknownChildChildPayloadLengths,
                childPayloadPrefixes: expected.unknownChildChildPayloadPrefixBytes,
                childPayloadSuffixes: expected.unknownChildChildPayloadSuffixBytes
            )
        )
    }
}
