import Nimble

func assertParagraphTextFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.visibleTextContains).notTo(beEmpty())
    expect(paragraphTextHasPayloadSamples(expectations)) == true
}

private func paragraphTextHasPayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    payloadSampleBatchIsDeclared(
        count: expectations.paraTextRawPayloadCount,
        totalByteCount: expectations.paraTextRawPayloadTotalByteCount,
        prefixes: expectations.paraTextRawPayloadPrefixBytes,
        suffixes: expectations.paraTextRawPayloadSuffixBytes
    )
        && payloadSampleBatchIsDeclared(
            count: expectations.paraTextPayloadCount,
            totalByteCount: expectations.paraTextPayloadTotalByteCount,
            prefixes: expectations.paraTextPayloadPrefixBytes,
            suffixes: expectations.paraTextPayloadSuffixBytes
        )
        && payloadSampleBatchIsDeclared(
            count: expectations.paraHeaderPayloadCount,
            totalByteCount: expectations.paraHeaderPayloadTotalByteCount,
            prefixes: expectations.paraHeaderPayloadPrefixBytes,
            suffixes: expectations.paraHeaderPayloadSuffixBytes
        )
        && payloadSampleBatchIsDeclared(
            count: expectations.paraCharShapePayloadCount,
            totalByteCount: expectations.paraCharShapePayloadTotalByteCount,
            prefixes: expectations.paraCharShapePayloadPrefixBytes,
            suffixes: expectations.paraCharShapePayloadSuffixBytes
        )
        && payloadSampleBatchIsDeclared(
            count: expectations.paraLineSegPayloadCount,
            totalByteCount: expectations.paraLineSegPayloadTotalByteCount,
            prefixes: expectations.paraLineSegPayloadPrefixBytes,
            suffixes: expectations.paraLineSegPayloadSuffixBytes
        )
        && paraRangeTagEvidenceIsDeclared(expectations)
}

private func paraRangeTagEvidenceIsDeclared(_ expectations: FixtureExpectations) -> Bool {
    guard let count = expectations.paraRangeTagCount,
          let totalByteCount = expectations.paraRangeTagPayloadTotalByteCount
    else {
        return false
    }
    if count == 0 {
        return totalByteCount == 0
    }
    return totalByteCount > 0
        && expectations.paraRangeTags?.count == count
        && (expectations.paraRangeTags?.allSatisfy(paraRangeTagHasSemanticValues) ?? false)
}

private func paraRangeTagHasSemanticValues(_ tag: FixtureParaRangeTagExpectations) -> Bool {
    tag.start != nil
        && tag.end != nil
        && tag.tag != nil
}

private func payloadSampleBatchIsDeclared(
    count: Int?,
    totalByteCount: Int?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard let count, let totalByteCount, let prefixes, let suffixes else {
        return false
    }
    return count > 0
        && totalByteCount > 0
        && prefixes.count == count
        && suffixes.count == count
        && prefixes.allSatisfy { !$0.isEmpty }
        && suffixes.allSatisfy { !$0.isEmpty }
}
