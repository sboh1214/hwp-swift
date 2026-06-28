@testable import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertColumns(
        _ expectations: [FixtureColumnExpectations],
        _ actualColumns: [HwpColumn]
    ) {
        expect(actualColumns.count) == expectations.count

        for (actual, expected) in zip(actualColumns, expectations) {
            if let ctrlId = expected.ctrlId {
                expect(actual.otherCtrlId.rawValue) == ctrlId
            }
            if let ctrlIdName = expected.ctrlIdName {
                expect(String(describing: actual.otherCtrlId)) == ctrlIdName
            }
            if let propertyRawValue = expected.propertyRawValue {
                expect(actual.property.rawValue) == propertyRawValue
            }
            if let propertyCount = expected.propertyCount {
                expect(actual.property.count) == propertyCount
            }
            if let isSameWidth = expected.isSameWidth {
                expect(actual.property.isSameWidth) == isSameWidth
            }
            assertPayloadSample(
                actual.rawPayload,
                length: expected.rawPayloadLength,
                prefix: expected.rawPayloadPrefixBytes,
                suffix: expected.rawPayloadSuffixBytes
            )
            assertPayloadSample(
                actual.rawTrailing,
                length: expected.rawTrailingLength,
                prefix: expected.rawTrailingPrefixBytes,
                suffix: expected.rawTrailingSuffixBytes
            )
            if let rawTrailingLength = expected.rawTrailingLength {
                expect(actual.rawTrailingWords?.count) ==
                    (rawTrailingLength.isMultiple(of: MemoryLayout<UInt16>.size)
                        ? rawTrailingLength / 2
                        : nil)
            }
            assertColumnUnknownChildren(actual.unknownChildren, expected)
        }
    }

    static func assertColumnUnknownChildren(
        _ actual: [HwpUnknownRecord],
        _ expected: FixtureColumnExpectations
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
            actual,
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
