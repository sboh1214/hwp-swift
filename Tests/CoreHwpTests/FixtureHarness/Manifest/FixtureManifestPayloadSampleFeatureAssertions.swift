import Nimble

func binaryDataIdsAreDeclared(
    lengths: [Int]?,
    idsCount: Int?
) -> Bool {
    guard let lengths else {
        return true
    }
    return idsCount == lengths.count
}

func payloadSampleArraysAreDeclared(
    lengths: [Int]?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard lengths != nil || prefixes != nil || suffixes != nil else {
        return true
    }
    guard let lengths,
          let prefixes,
          let suffixes,
          prefixes.count == lengths.count,
          suffixes.count == lengths.count
    else {
        return false
    }

    return lengths.indices.allSatisfy { index in
        payloadSampleIsDeclared(
            length: lengths[index],
            prefix: prefixes[index],
            suffix: suffixes[index]
        )
    }
}

func countedPayloadSamplesAreDeclared(
    count: Int?,
    lengths: [Int]?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard let count else {
        return payloadSampleArraysAreDeclared(
            lengths: lengths,
            prefixes: prefixes,
            suffixes: suffixes
        )
    }

    if count == 0 {
        return (lengths?.isEmpty ?? true)
            && (prefixes?.isEmpty ?? true)
            && (suffixes?.isEmpty ?? true)
    }

    return lengths?.count == count
        && payloadSampleArraysAreDeclared(
            lengths: lengths,
            prefixes: prefixes,
            suffixes: suffixes
        )
}

func nestedPayloadSampleArraysAreDeclared(
    tagIds: [[UInt32]]?,
    lengths: [[Int]]?,
    prefixes: [[[UInt8]]]?,
    suffixes: [[[UInt8]]]?
) -> Bool {
    guard tagIds != nil || lengths != nil || prefixes != nil || suffixes != nil else {
        return true
    }
    guard let tagIds, let lengths, tagIds.count == lengths.count else {
        return false
    }
    return nestedPayloadSampleArraysAreDeclared(
        lengths: lengths,
        prefixes: prefixes,
        suffixes: suffixes
    )
}

func nestedPayloadSampleArraysAreDeclared(
    lengths: [[Int]]?,
    prefixes: [[[UInt8]]]?,
    suffixes: [[[UInt8]]]?
) -> Bool {
    guard lengths != nil || prefixes != nil || suffixes != nil else {
        return true
    }

    guard let lengths,
          let prefixes,
          let suffixes,
          prefixes.count == lengths.count,
          suffixes.count == lengths.count
    else {
        return false
    }

    return lengths.indices.allSatisfy { index in
        payloadSampleArraysAreDeclared(
            lengths: lengths[index],
            prefixes: prefixes[index],
            suffixes: suffixes[index]
        )
    }
}

func deeplyNestedPayloadSampleArraysAreDeclared(
    tagIds: [[[UInt32]]]?,
    lengths: [[[Int]]]?,
    prefixes: [[[[UInt8]]]]?,
    suffixes: [[[[UInt8]]]]?
) -> Bool {
    guard tagIds != nil || lengths != nil || prefixes != nil || suffixes != nil else {
        return true
    }
    guard let tagIds, let lengths, tagIds.count == lengths.count else {
        return false
    }
    if let prefixes, prefixes.count != lengths.count {
        return false
    }
    if let suffixes, suffixes.count != lengths.count {
        return false
    }
    return tagIds.indices.allSatisfy { index in
        nestedPayloadSampleArraysAreDeclared(
            tagIds: tagIds[index],
            lengths: lengths[index],
            prefixes: prefixes?[index],
            suffixes: suffixes?[index]
        )
    }
}

func deeplyNestedPayloadSampleArraysAreDeclared(
    lengths: [[[Int]]]?,
    prefixes: [[[[UInt8]]]]?,
    suffixes: [[[[UInt8]]]]?
) -> Bool {
    guard lengths != nil || prefixes != nil || suffixes != nil else {
        return true
    }

    guard let lengths,
          let prefixes,
          let suffixes,
          prefixes.count == lengths.count,
          suffixes.count == lengths.count
    else {
        return false
    }

    return lengths.indices.allSatisfy { index in
        nestedPayloadSampleArraysAreDeclared(
            lengths: lengths[index],
            prefixes: prefixes[index],
            suffixes: suffixes[index]
        )
    }
}

func unknownChildPayloadSamplesAreDeclared(
    count: Int?,
    tagIds: [UInt32]?,
    lengths: [Int]?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard let count else {
        return payloadSampleArraysAreDeclared(
            lengths: lengths,
            prefixes: prefixes,
            suffixes: suffixes
        )
    }

    if count == 0 {
        return (tagIds?.isEmpty ?? true)
            && (lengths?.isEmpty ?? true)
            && (prefixes?.isEmpty ?? true)
            && (suffixes?.isEmpty ?? true)
    }

    return tagIds?.count == count
        && lengths?.count == count
        && payloadSampleArraysAreDeclared(
            lengths: lengths,
            prefixes: prefixes,
            suffixes: suffixes
        )
}

func sectionUnknownRecordsHavePayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    unknownChildPayloadSamplesAreDeclared(
        count: expectations.sectionUnknownRecordCount,
        tagIds: expectations.sectionUnknownRecordTagIds,
        lengths: expectations.sectionUnknownRecordPayloadLengths,
        prefixes: expectations.sectionUnknownRecordPayloadPrefixBytes,
        suffixes: expectations.sectionUnknownRecordPayloadSuffixBytes
    )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: expectations.sectionUnknownChildTagIds,
            lengths: expectations.sectionUnknownChildPayloadLengths,
            prefixes: expectations.sectionUnknownChildPayloadPrefixBytes,
            suffixes: expectations.sectionUnknownChildPayloadSuffixBytes
        )
}

func paragraphUnknownChildrenHavePayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    unknownChildPayloadSamplesAreDeclared(
        count: expectations.paragraphUnknownChildCount,
        tagIds: expectations.paragraphUnknownChildTagIds,
        lengths: expectations.paragraphUnknownChildPayloadLengths,
        prefixes: expectations.paragraphUnknownChildPayloadPrefixBytes,
        suffixes: expectations.paragraphUnknownChildPayloadSuffixBytes
    )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: expectations.paragraphUnknownNestedTagIds,
            lengths: expectations.paragraphUnknownNestedPayloadLengths,
            prefixes: expectations.paragraphUnknownNestedPayloadPrefixBytes,
            suffixes: expectations.paragraphUnknownNestedPayloadSuffixBytes
        )
}

func payloadSampleIsDeclared(
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?
) -> Bool {
    guard let length,
          let prefix,
          let suffix,
          length >= 0,
          prefix.count <= length,
          suffix.count <= length
    else {
        return false
    }

    if length == 0 {
        return prefix.isEmpty && suffix.isEmpty
    }
    return !prefix.isEmpty && !suffix.isEmpty
}

func styleHasPayloadSample(_ style: FixtureStyleExpectations) -> Bool {
    style.localName != nil
        && style.englishName != nil
        && payloadSampleIsDeclared(
            length: style.localNameRawPayloadLength,
            prefix: style.localNameRawPayloadPrefixBytes,
            suffix: style.localNameRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: style.englishNameRawPayloadLength,
            prefix: style.englishNameRawPayloadPrefixBytes,
            suffix: style.englishNameRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: style.rawPayloadLength,
            prefix: style.rawPayloadPrefixBytes,
            suffix: style.rawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: style.undocumentedTrailingLength,
            prefix: style.undocumentedTrailingPrefixBytes,
            suffix: style.undocumentedTrailingSuffixBytes
        )
}

func numberingHasPayloadSample(_ numbering: FixtureNumberingExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: numbering.rawPayloadLength,
        prefix: numbering.rawPayloadPrefixBytes,
        suffix: numbering.rawPayloadSuffixBytes
    )
}

func bulletHasPayloadSample(_ bullet: FixtureBulletExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: bullet.rawPayloadLength,
        prefix: bullet.rawPayloadPrefixBytes,
        suffix: bullet.rawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: bullet.charRawPayloadLength,
            prefix: bullet.charRawPayloadPrefixBytes,
            suffix: bullet.charRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: bullet.checkCharRawPayloadLength,
            prefix: bullet.checkCharRawPayloadPrefixBytes,
            suffix: bullet.checkCharRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: bullet.undocumentedTrailingLength,
            prefix: bullet.undocumentedTrailingPrefixBytes,
            suffix: bullet.undocumentedTrailingSuffixBytes
        )
}

func binDataHasPayloadSample(_ binData: FixtureBinDataExpectations) -> Bool {
    binData.propertyRawValue != nil
        && binData.type != nil
        && binData.compressType != nil
        && binData.state != nil
        && binData.streamId != nil
        && binData.extensionName != nil
        && payloadSampleIsDeclared(
            length: binData.rawPayloadLength,
            prefix: binData.rawPayloadPrefixBytes,
            suffix: binData.rawPayloadSuffixBytes
        )
}

func assertSupportedFixtureCorePayloadSamples(
    _ expectations: FixtureExpectations,
    _ features: Set<String>
) {
    let sectionRawPayloadCount = expectations.sectionRawPayloadCount ?? 0
    expect(sectionRawPayloadCount).to(beGreaterThan(0))
    expect(expectations.sectionRawPayloadTotalByteCount ?? 0).to(beGreaterThan(0))
    expect(expectations.sectionRawPayloadPrefixBytes?.count) == sectionRawPayloadCount
    expect(expectations.sectionRawPayloadSuffixBytes?.count) == sectionRawPayloadCount
    expect(expectations.sectionRawPayloadPrefixBytes?.allSatisfy { !$0.isEmpty } ?? false) == true
    expect(expectations.sectionRawPayloadSuffixBytes?.allSatisfy { !$0.isEmpty } ?? false) == true

    expect(payloadSampleIsDeclared(
        length: expectations.docInfoRawPayloadLength,
        prefix: expectations.docInfoRawPayloadPrefixBytes,
        suffix: expectations.docInfoRawPayloadSuffixBytes
    )) == true
    if features.contains("derived-missing-summary") {
        expect(expectations.summaryLength) == 0
        expect(expectations.summaryPrefixBytes) == []
        expect(expectations.summarySuffixBytes) == []
    } else {
        expect(payloadSampleIsDeclared(
            length: expectations.summaryLength,
            prefix: expectations.summaryPrefixBytes,
            suffix: expectations.summarySuffixBytes
        )) == true
    }
    expect(sectionUnknownRecordsHavePayloadSamples(expectations)) == true
    expect(paragraphUnknownChildrenHavePayloadSamples(expectations)) == true
}
