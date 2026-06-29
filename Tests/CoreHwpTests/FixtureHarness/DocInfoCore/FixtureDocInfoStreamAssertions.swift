@testable import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertDocInfo(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertDocInfo(expectations, hwp.docInfo)
    }

    static func assertDocInfo(_ expectations: FixtureExpectations, _ docInfo: HwpDocInfo) {
        assertPayloadSample(
            docInfo.rawPayload,
            length: expectations.docInfoRawPayloadLength,
            prefix: expectations.docInfoRawPayloadPrefixBytes,
            suffix: expectations.docInfoRawPayloadSuffixBytes
        )
        if let unknownCount = expectations.docInfoUnknownRecordCount {
            expect(docInfo.unknownRecords.count) == unknownCount
        }
        assertUnknownRecordSamples(
            docInfo.unknownRecords,
            rootLevel: 0,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expectations.docInfoUnknownRecordTagIds,
                payloadLengths: expectations.docInfoUnknownRecordPayloadLengths,
                payloadPrefixes: expectations.docInfoUnknownRecordPayloadPrefixBytes,
                payloadSuffixes: expectations.docInfoUnknownRecordPayloadSuffixBytes,
                childTagIds: expectations.docInfoUnknownChildTagIds,
                childPayloadLengths: expectations.docInfoUnknownChildPayloadLengths,
                childPayloadPrefixes: expectations.docInfoUnknownChildPayloadPrefixBytes,
                childPayloadSuffixes: expectations.docInfoUnknownChildPayloadSuffixBytes
            )
        )
        if let rawRecordCount = expectations.docInfoRawRecordCount {
            expect(rawDocInfoRecordCount(docInfo)) == rawRecordCount
        }
    }
}
