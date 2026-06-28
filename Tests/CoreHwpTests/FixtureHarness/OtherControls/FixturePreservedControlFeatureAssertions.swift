import Nimble

func assertUnknownControlPreservationExpectations(_ expectations: FixtureExpectations) {
    let preservedCount = (expectations.allControlTypeCounts?["unknown"] ?? 0)
        + (expectations.allControlTypeCounts?["notImplemented"] ?? 0)
    guard preservedCount > 0 else {
        return
    }

    if let preservedControls = expectations.preservedControls {
        expect(preservedControls.count) == preservedCount
        expect(preservedControls.allSatisfy(preservedControlHasPayloadSamples)) == true
    } else {
        expect(expectations.preservedControlSamples).notTo(beEmpty())
        expect(
            expectations.preservedControlSamples?.allSatisfy(preservedControlHasPayloadSamples)
                ?? false
        ) == true
    }
}

func preservedControlHasPayloadSamples(
    _ expectation: FixtureControlPreservationExpectations
) -> Bool {
    payloadSampleIsDeclared(
        length: expectation.rawPayloadLength,
        prefix: expectation.rawPayloadPrefixBytes,
        suffix: expectation.rawPayloadSuffixBytes
    )
        && unknownChildPayloadSamplesAreDeclared(
            count: expectation.unknownChildCount,
            tagIds: expectation.unknownChildTagIds,
            lengths: expectation.unknownChildPayloadLengths,
            prefixes: expectation.unknownChildPayloadPrefixBytes,
            suffixes: expectation.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: expectation.unknownChildChildTagIds,
            lengths: expectation.unknownChildChildPayloadLengths,
            prefixes: expectation.unknownChildChildPayloadPrefixBytes,
            suffixes: expectation.unknownChildChildPayloadSuffixBytes
        )
}
