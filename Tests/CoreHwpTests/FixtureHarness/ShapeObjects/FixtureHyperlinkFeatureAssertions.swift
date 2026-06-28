func hyperlinkHasPayloadSamples(_ hyperlink: FixtureHyperlinkExpectations) -> Bool {
    hyperlink.ctrlId != nil
        && hyperlink.ctrlIdName?.isEmpty == false
        && hyperlink.url?.isEmpty == false
        && payloadSampleIsDeclared(
            length: hyperlink.urlLengthRawPayloadLength,
            prefix: hyperlink.urlLengthRawPayloadPrefixBytes,
            suffix: hyperlink.urlLengthRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: hyperlink.urlRawPayloadLength,
            prefix: hyperlink.urlRawPayloadPrefixBytes,
            suffix: hyperlink.urlRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: hyperlink.rawPayloadLength,
            prefix: hyperlink.rawPayloadPrefixBytes,
            suffix: hyperlink.rawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: hyperlink.rawTrailingLength,
            prefix: hyperlink.rawTrailingPrefixBytes,
            suffix: hyperlink.rawTrailingSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
            count: hyperlink.unknownChildCount,
            tagIds: hyperlink.unknownChildTagIds,
            lengths: hyperlink.unknownChildPayloadLengths,
            prefixes: hyperlink.unknownChildPayloadPrefixBytes,
            suffixes: hyperlink.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: hyperlink.unknownChildChildTagIds,
            lengths: hyperlink.unknownChildChildPayloadLengths,
            prefixes: hyperlink.unknownChildChildPayloadPrefixBytes,
            suffixes: hyperlink.unknownChildChildPayloadSuffixBytes
        )
}
