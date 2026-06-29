import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertPreservedControls(
        _ expectations: [FixtureControlPreservationExpectations],
        _ hwp: HwpFile
    ) {
        assertPreservedControls(
            expectations,
            FixtureDerivedValues.preservedControls(from: hwp)
        )
    }

    static func assertPreservedControls(
        _ expectations: [FixtureControlPreservationExpectations],
        _ actualControls: [PreservedControl]
    ) {
        expect(actualControls.count) == expectations.count

        for (actual, expected) in zip(actualControls, expectations) {
            assertPreservedControl(actual, expected)
        }
    }

    static func assertPreservedControlSamples(
        _ expectations: [FixtureControlPreservationExpectations],
        _ hwp: HwpFile
    ) {
        assertPreservedControlSamples(
            expectations,
            FixtureDerivedValues.preservedControls(from: hwp)
        )
    }

    static func assertPreservedControlSamples(
        _ expectations: [FixtureControlPreservationExpectations],
        _ actualControls: [PreservedControl]
    ) {
        for expected in expectations {
            let matchedControls = actualControls.filter { control in
                preservedControl(control, matches: expected)
            }
            let occurrenceIndex = expected.occurrenceIndex ?? 0
            expect(occurrenceIndex).to(beGreaterThanOrEqualTo(0))
            expect(matchedControls.count).to(beGreaterThan(occurrenceIndex))
            guard matchedControls.indices.contains(occurrenceIndex) else {
                continue
            }
            assertPreservedControl(matchedControls[occurrenceIndex], expected)
        }
    }
}

private func preservedControl(
    _ actual: PreservedControl,
    matches expected: FixtureControlPreservationExpectations
) -> Bool {
    guard actual.kind == expected.kind else {
        return false
    }
    if let ctrlId = expected.ctrlId, actual.header.ctrlId != ctrlId {
        return false
    }
    return true
}

private func assertPreservedControl(
    _ actual: PreservedControl,
    _ expected: FixtureControlPreservationExpectations
) {
    expect(actual.kind) == expected.kind
    if let ctrlId = expected.ctrlId {
        expect(actual.header.ctrlId) == ctrlId
    }
    FixtureAssertions.assertPayloadSample(
        actual.header.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
    if let unknownChildCount = expected.unknownChildCount {
        expect(actual.header.unknownChildren.count) == unknownChildCount
    }
    FixtureAssertions.assertUnknownRecordSamples(
        actual.header.unknownChildren,
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
