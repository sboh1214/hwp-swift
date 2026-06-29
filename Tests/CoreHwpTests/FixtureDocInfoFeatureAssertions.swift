import Nimble

func assertDocInfoFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    assertBasicDocInfoFeatureExpectations(features, expectations)
    assertRawDocInfoFeatureExpectations(features, expectations)
    assertDocInfoMappingFeatureExpectations(features, expectations)
}

private func assertBasicDocInfoFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("doc-properties") {
        expect(expectations.documentProperties.map(documentPropertiesHaveSemanticValues)) == true
    }
    if features.contains("doc-info") {
        expect(expectations.docInfoIdMappings.map(docInfoMappingsHaveCoreEvidence)) == true
    }
    if features.contains("doc-data") {
        expectRawDocInfoRecord(expectations.docInfoRawRecords?.docData)
        expect(
            expectations.docInfoRawRecords?.docData.map(docDataHasTypedWords) ?? false
        ) == true
    }
    if features.contains("layout-compatibility") {
        assertLayoutCompatibilityFeatureExpectations(expectations)
    }
}

private func assertRawDocInfoFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("distribute-doc-data") {
        expectRawDocInfoRecord(expectations.docInfoRawRecords?.distributeDocData)
        expect(
            expectations.docInfoRawRecords?.distributeDocData
                .map(distributeDocDataHasTypedWords) ?? false
        ) == true
    }
    if features.contains("track-change-records") {
        expect(
            topLevelTrackChangeRecordsHavePayloadSamples(expectations) ||
                compatibleTrackChangeRecordsHavePayloadSamples(expectations)
        ) == true
    }
    if features.contains("top-level-track-change-records") {
        expect(topLevelTrackChangeRecordsHavePayloadSamples(expectations)) == true
    }
    if features.contains("compatible-track-change-records") {
        expect(compatibleTrackChangeRecordsHavePayloadSamples(expectations)) == true
    }
    if features.contains("memo-shape") {
        expectRawDocInfoRecords(expectations.docInfoRawRecords?.memoShapes)
        expect(
            expectations.docInfoRawRecords?.memoShapes?
                .allSatisfy(memoShapeHasTypedFields) ?? false
        ) == true
    }
    if features.contains("track-change-content") {
        expectRawDocInfoRecords(expectations.docInfoRawRecords?.trackChangeContents)
        expect(
            expectations.docInfoRawRecords?.trackChangeContents?
                .allSatisfy(trackChangeContentHasTypedTimestamp) ?? false
        ) == true
    }
    if features.contains("track-change-author") {
        expectRawDocInfoRecords(expectations.docInfoRawRecords?.trackChangeAuthors)
        expect(
            expectations.docInfoRawRecords?.trackChangeAuthors?
                .allSatisfy(trackChangeAuthorHasTypedName) ?? false
        ) == true
    }
    if features.contains("forbidden-char") {
        let forbiddenCharCount = expectations.docInfoRawRecords?.docData?.forbiddenCharCount
        expect(forbiddenCharCount ?? 0).to(beGreaterThan(0))
        expect(expectations.docInfoRawRecords?.docData?.forbiddenCharPayloadLengths)
            .notTo(beEmpty())
        expect(expectations.docInfoRawRecords?.docData?.forbiddenCharPayloadPrefixBytes)
            .notTo(beEmpty())
        expect(expectations.docInfoRawRecords?.docData?.forbiddenCharPayloadSuffixBytes)
            .notTo(beEmpty())
    }
}

private func assertDocInfoMappingFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("styles") {
        expect(expectations.docInfoIdMappings?.styleCount ?? 0).to(beGreaterThan(0))
        expect(expectations.docInfoStyles).notTo(beEmpty())
        expect(expectations.docInfoStyles?.allSatisfy(styleHasPayloadSample) ?? false) == true
    }
    if features.contains("bullets-numbering") {
        expect(expectations.docInfoIdMappings?.numberingCount ?? 0).to(beGreaterThan(0))
        expect(expectations.docInfoIdMappings?.bulletCount ?? 0).to(beGreaterThan(0))
        expect(expectations.docInfoNumberings).notTo(beEmpty())
        expect(expectations.docInfoNumberings?.allSatisfy(numberingHasPayloadSample) ?? false) ==
            true
        expect(expectations.docInfoBullets).notTo(beEmpty())
        expect(expectations.docInfoBullets?.allSatisfy(bulletHasPayloadSample) ?? false) == true
    }
}

private func expectRawDocInfoRecord(_ record: FixtureRawRecordExpectations?) {
    expect(record).notTo(beNil())
    expect(record.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
}

private func expectRawDocInfoRecords(_ records: [FixtureRawRecordExpectations]?) {
    expect(records).notTo(beEmpty())
    expect(records?.allSatisfy(rawDocInfoRecordHasPayloadSample) ?? false) == true
}

func topLevelTrackChangeRecordsHavePayloadSamples(
    _ expectations: FixtureExpectations
) -> Bool {
    let topLevelTrackChanges = expectations.docInfoRawRecords?.trackChanges
    return topLevelTrackChanges.map {
        !$0.isEmpty && $0.allSatisfy(trackChangeRecordHasTypedHeader)
    } == true
}

func compatibleTrackChangeRecordsHavePayloadSamples(
    _ expectations: FixtureExpectations
) -> Bool {
    let compatibleTrackChanges = expectations.compatibleDocument?.trackChanges
    return compatibleTrackChanges.map {
        !$0.isEmpty && $0.allSatisfy(trackChangeRecordHasTypedHeader)
    } == true
}

private func trackChangeRecordHasTypedHeader(_ record: FixtureRawRecordExpectations) -> Bool {
    rawDocInfoRecordHasPayloadSample(record)
        && record.trackChangeHeaderValue != nil
        && payloadSampleIsDeclared(
            length: record.trackChangeHeaderRawLength,
            prefix: record.trackChangeHeaderRawPrefixBytes,
            suffix: record.trackChangeHeaderRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.trackChangeRawTrailingLength,
            prefix: record.trackChangeRawTrailingPrefixBytes,
            suffix: record.trackChangeRawTrailingSuffixBytes
        )
}

func distributeDocDataHasTypedWords(_ record: FixtureRawRecordExpectations) -> Bool {
    record.distributeDocDataValues?.isEmpty == false
        && payloadSampleIsDeclared(
            length: record.distributeDocDataValuesRawLength,
            prefix: record.distributeDocDataValuesRawPrefixBytes,
            suffix: record.distributeDocDataValuesRawSuffixBytes
        )
        && record.distributeDocDataRawTrailingLength != nil
}

func trackChangeAuthorHasTypedName(_ record: FixtureRawRecordExpectations) -> Bool {
    record.authorName?.isEmpty == false
        && payloadSampleIsDeclared(
            length: record.authorNameLengthRawLength,
            prefix: record.authorNameLengthRawPrefixBytes,
            suffix: record.authorNameLengthRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.authorNameRawPayloadLength,
            prefix: record.authorNameRawPayloadPrefixBytes,
            suffix: record.authorNameRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.authorRawTrailingLength,
            prefix: record.authorRawTrailingPrefixBytes,
            suffix: record.authorRawTrailingSuffixBytes
        )
}

func docDataHasTypedWords(_ record: FixtureRawRecordExpectations) -> Bool {
    record.docDataValues?.isEmpty == false
        && payloadSampleIsDeclared(
            length: record.docDataValuesRawLength,
            prefix: record.docDataValuesRawPrefixBytes,
            suffix: record.docDataValuesRawSuffixBytes
        )
        && record.docDataRawTrailingLength != nil
}

func memoShapeHasTypedFields(_ record: FixtureRawRecordExpectations) -> Bool {
    record.memoShapeWidth != nil
        && record.memoShapeLineType != nil
        && record.memoShapeLineWidth != nil
        && colorSampleIsDeclared(record.memoShapeLineColor)
        && colorSampleIsDeclared(record.memoShapeFillColor)
        && colorSampleIsDeclared(record.memoShapeActiveColor)
        && payloadSampleIsDeclared(
            length: record.memoShapeFixedRawLength,
            prefix: record.memoShapeFixedRawPrefixBytes,
            suffix: record.memoShapeFixedRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.memoShapeRawTrailingLength,
            prefix: record.memoShapeRawTrailingPrefixBytes,
            suffix: record.memoShapeRawTrailingSuffixBytes
        )
}

func trackChangeContentHasTypedTimestamp(_ record: FixtureRawRecordExpectations) -> Bool {
    record.trackChangeContentKind != nil
        && record.trackChangeContentYear != nil
        && record.trackChangeContentMonth != nil
        && record.trackChangeContentDay != nil
        && record.trackChangeContentHour != nil
        && record.trackChangeContentMinute != nil
        && payloadSampleIsDeclared(
            length: record.trackChangeContentKindRawLength,
            prefix: record.trackChangeContentKindRawPrefixBytes,
            suffix: record.trackChangeContentKindRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.trackChangeTimestampRawLength,
            prefix: record.trackChangeTimestampRawPrefixBytes,
            suffix: record.trackChangeTimestampRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: record.trackChangeContentRawTrailingLength,
            prefix: record.trackChangeContentRawTrailingPrefixBytes,
            suffix: record.trackChangeContentRawTrailingSuffixBytes
        )
}

private func colorSampleIsDeclared(_ color: [Int]?) -> Bool {
    color?.count == 3
}
