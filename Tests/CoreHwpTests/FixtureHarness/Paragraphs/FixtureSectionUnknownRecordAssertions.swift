import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertSectionUnknownRecords(
        _ expectations: FixtureExpectations,
        _ sections: [HwpSection]
    ) {
        let unknownRecords = sections.flatMap(\.unknownRecords)
        if let sectionUnknownRecordCount = expectations.sectionUnknownRecordCount {
            expect(unknownRecords.count) == sectionUnknownRecordCount
        }
        assertUnknownRecordSamples(
            unknownRecords,
            rootLevel: 0,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expectations.sectionUnknownRecordTagIds,
                payloadLengths: expectations.sectionUnknownRecordPayloadLengths,
                payloadPrefixes: expectations.sectionUnknownRecordPayloadPrefixBytes,
                payloadSuffixes: expectations.sectionUnknownRecordPayloadSuffixBytes,
                childTagIds: expectations.sectionUnknownChildTagIds,
                childPayloadLengths: expectations.sectionUnknownChildPayloadLengths,
                childPayloadPrefixes: expectations.sectionUnknownChildPayloadPrefixBytes,
                childPayloadSuffixes: expectations.sectionUnknownChildPayloadSuffixBytes
            )
        )
    }
}
