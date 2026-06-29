@testable import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertHyperlinks(
        _ expectations: [FixtureHyperlinkExpectations],
        _ hwp: HwpFile
    ) {
        let actualHyperlinks = FixtureDerivedValues.hyperlinks(from: hwp)
        assertHyperlinks(expectations, actualHyperlinks)
    }

    static func assertHyperlinks(
        _ expectations: [FixtureHyperlinkExpectations],
        _ actualHyperlinks: [HwpHyperlink]
    ) {
        expect(actualHyperlinks.count) == expectations.count

        for (actual, expected) in zip(actualHyperlinks, expectations) {
            if let ctrlId = expected.ctrlId {
                expect(actual.ctrlId) == ctrlId
            }
            if let ctrlIdName = expected.ctrlIdName {
                let actualCtrlIdName = HwpFieldCtrlId(rawValue: actual.ctrlId)
                    .map(String.init(describing:)) ?? "unknown"
                expect(actualCtrlIdName) == ctrlIdName
            }
            if let url = expected.url {
                expect(actual.url) == url
            }
            assertHyperlinkURLLengthRawPayload(actual, expected)
            assertHyperlinkURLRawPayload(actual, expected)
            assertHyperlinkRawPayload(actual, expected)
            assertHyperlinkRawTrailing(actual, expected)
            assertHyperlinkUnknownChildren(actual, expected)
        }
    }
}

private extension FixtureAssertions {
    static func assertHyperlinkURLRawPayload(
        _ actual: HwpHyperlink,
        _ expected: FixtureHyperlinkExpectations
    ) {
        FixtureAssertions.assertPayloadSample(
            actual.urlRawPayload,
            length: expected.urlRawPayloadLength,
            prefix: expected.urlRawPayloadPrefixBytes,
            suffix: expected.urlRawPayloadSuffixBytes
        )
    }

    static func assertHyperlinkURLLengthRawPayload(
        _ actual: HwpHyperlink,
        _ expected: FixtureHyperlinkExpectations
    ) {
        FixtureAssertions.assertPayloadSample(
            actual.urlLengthRawPayload,
            length: expected.urlLengthRawPayloadLength,
            prefix: expected.urlLengthRawPayloadPrefixBytes,
            suffix: expected.urlLengthRawPayloadSuffixBytes
        )
    }

    static func assertHyperlinkRawPayload(
        _ actual: HwpHyperlink,
        _ expected: FixtureHyperlinkExpectations
    ) {
        FixtureAssertions.assertPayloadSample(
            actual.rawPayload,
            length: expected.rawPayloadLength,
            prefix: expected.rawPayloadPrefixBytes,
            suffix: expected.rawPayloadSuffixBytes
        )
    }

    static func assertHyperlinkRawTrailing(
        _ actual: HwpHyperlink,
        _ expected: FixtureHyperlinkExpectations
    ) {
        FixtureAssertions.assertPayloadSample(
            actual.rawTrailing,
            length: expected.rawTrailingLength,
            prefix: expected.rawTrailingPrefixBytes,
            suffix: expected.rawTrailingSuffixBytes
        )
    }

    static func assertHyperlinkUnknownChildren(
        _ actual: HwpHyperlink,
        _ expected: FixtureHyperlinkExpectations
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.unknownChildren.count) == unknownChildCount
        }
        FixtureAssertions.assertUnknownRecordSamples(
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
