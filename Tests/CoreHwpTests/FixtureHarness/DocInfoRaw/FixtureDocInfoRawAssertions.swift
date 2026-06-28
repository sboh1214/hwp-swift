import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertDocInfoRawRecords(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertDocInfoRawRecords(expectations, hwp.docInfo)
    }

    static func assertDocInfoRawRecords(
        _ expectations: FixtureExpectations,
        _ docInfo: HwpDocInfo
    ) {
        guard let expected = expectations.docInfoRawRecords else {
            return
        }

        assertRawRecord(expected.docData, actualRecord(docInfo.docData))
        assertRawRecord(expected.distributeDocData, actualRecord(docInfo.distributeDocData))
        assertRawRecords(expected.trackChanges, docInfo.topLevelTrackChangeArray.map(actualRecord))
        assertRawRecords(expected.memoShapes, docInfo.memoShapeArray.map(actualRecord))
        assertRawRecords(
            expected.trackChangeContents,
            docInfo.trackChangeContentArray.map(actualRecord)
        )
        assertRawRecords(
            expected.trackChangeAuthors,
            docInfo.trackChangeAuthorArray.map(actualRecord)
        )
        assertRawRecords(
            expected.forbiddenChars,
            docInfo.topLevelForbiddenCharArray.map(actualRecord)
        )
    }

    static func rawDocInfoRecordCount(_ docInfo: HwpDocInfo) -> Int {
        [
            docInfo.docData?.rawPayload,
            docInfo.distributeDocData?.rawPayload,
        ].compactMap { $0 }.count
            + docInfo.topLevelTrackChangeArray.count
            + docInfo.memoShapeArray.count
            + docInfo.trackChangeContentArray.count
            + docInfo.trackChangeAuthorArray.count
            + docInfo.topLevelForbiddenCharArray.count
    }
}

private struct ActualRawRecord {
    let rawPayload: Data
    let distributeDocDataInfo: HwpDistributeDocDataInfo?
    let docDataInfo: HwpDocDataInfo?
    let trackChangeInfo: HwpTrackChangeInfo?
    let memoShapeInfo: HwpMemoShapeInfo?
    let forbiddenChars: [HwpForbiddenChar]
    let trackChangeContentInfo: HwpTrackChangeContentInfo?
    let authorInfo: HwpTrackChangeAuthorInfo?
    let unknownChildren: [HwpUnknownRecord]
}

private func actualRecord(_ record: HwpDocData?) -> ActualRawRecord? {
    record.map {
        ActualRawRecord(
            rawPayload: $0.rawPayload,
            distributeDocDataInfo: nil,
            docDataInfo: $0.docDataInfo,
            trackChangeInfo: nil,
            memoShapeInfo: nil,
            forbiddenChars: $0.forbiddenCharArray,
            trackChangeContentInfo: nil,
            authorInfo: nil,
            unknownChildren: $0.unknownChildren
        )
    }
}

private func actualRecord(_ record: HwpDistributeDocData?) -> ActualRawRecord? {
    record.map {
        ActualRawRecord(
            rawPayload: $0.rawPayload,
            distributeDocDataInfo: $0.distributeDocDataInfo,
            docDataInfo: nil,
            trackChangeInfo: nil,
            memoShapeInfo: nil,
            forbiddenChars: [],
            trackChangeContentInfo: nil,
            authorInfo: nil,
            unknownChildren: $0.unknownChildren
        )
    }
}

private func actualRecord(_ record: HwpTrackChange) -> ActualRawRecord {
    ActualRawRecord(
        rawPayload: record.rawPayload,
        distributeDocDataInfo: nil,
        docDataInfo: nil,
        trackChangeInfo: record.trackChangeInfo,
        memoShapeInfo: nil,
        forbiddenChars: [],
        trackChangeContentInfo: nil,
        authorInfo: nil,
        unknownChildren: record.unknownChildren
    )
}

private func actualRecord(_ record: HwpMemoShape) -> ActualRawRecord {
    ActualRawRecord(
        rawPayload: record.rawPayload,
        distributeDocDataInfo: nil,
        docDataInfo: nil,
        trackChangeInfo: nil,
        memoShapeInfo: record.shapeInfo,
        forbiddenChars: [],
        trackChangeContentInfo: nil,
        authorInfo: nil,
        unknownChildren: record.unknownChildren
    )
}

private func actualRecord(_ record: HwpTrackChangeContent) -> ActualRawRecord {
    ActualRawRecord(
        rawPayload: record.rawPayload,
        distributeDocDataInfo: nil,
        docDataInfo: nil,
        trackChangeInfo: nil,
        memoShapeInfo: nil,
        forbiddenChars: [],
        trackChangeContentInfo: record.contentInfo,
        authorInfo: nil,
        unknownChildren: record.unknownChildren
    )
}

private func actualRecord(_ record: HwpTrackChangeAuthor) -> ActualRawRecord {
    ActualRawRecord(
        rawPayload: record.rawPayload,
        distributeDocDataInfo: nil,
        docDataInfo: nil,
        trackChangeInfo: nil,
        memoShapeInfo: nil,
        forbiddenChars: [],
        trackChangeContentInfo: nil,
        authorInfo: record.authorInfo,
        unknownChildren: record.unknownChildren
    )
}

private func actualRecord(_ record: HwpForbiddenChar) -> ActualRawRecord {
    ActualRawRecord(
        rawPayload: record.rawPayload,
        distributeDocDataInfo: nil,
        docDataInfo: nil,
        trackChangeInfo: nil,
        memoShapeInfo: nil,
        forbiddenChars: [],
        trackChangeContentInfo: nil,
        authorInfo: nil,
        unknownChildren: record.unknownChildren
    )
}

private func assertRawRecords(
    _ expectedRecords: [FixtureRawRecordExpectations]?,
    _ actualRecords: [ActualRawRecord]
) {
    guard let expectedRecords else {
        return
    }

    expect(actualRecords.count) == expectedRecords.count
    for (expected, actual) in zip(expectedRecords, actualRecords) {
        assertRawRecord(expected, actual)
    }
}

private func assertRawRecord(
    _ expected: FixtureRawRecordExpectations?,
    _ actual: ActualRawRecord?
) {
    guard let expected else {
        return
    }

    expect(actual).notTo(beNil())
    assertRawPayload(expected, actual)
    assertDistributeDocDataInfo(expected, actual)
    assertDocDataInfo(expected, actual)
    assertTrackChangeInfo(expected, actual)
    assertMemoShapeInfo(expected, actual)
    assertTrackChangeContentInfo(expected, actual)
    assertTrackChangeAuthorInfo(expected, actual)
    assertForbiddenChars(expected, actual)
    assertUnknownChildren(expected, actual)
}

private func assertRawPayload(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let rawPayloadLength = expected.rawPayloadLength {
        expect(actual?.rawPayload.count) == rawPayloadLength
    }
    if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
        let prefix = actual?.rawPayload.prefix(rawPayloadPrefixBytes.count) ?? Data()
        expect(Array(prefix)) == rawPayloadPrefixBytes
    }
    if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
        let suffix = actual?.rawPayload.suffix(rawPayloadSuffixBytes.count) ?? Data()
        expect(Array(suffix)) == rawPayloadSuffixBytes
    }
}

private func assertDistributeDocDataInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let distributeDocDataValues = expected.distributeDocDataValues {
        expect(actual?.distributeDocDataInfo?.values) == distributeDocDataValues
    }
    FixtureAssertions.assertPayloadSample(
        actual?.distributeDocDataInfo?.valuesRawPayload,
        length: expected.distributeDocDataValuesRawLength,
        prefix: expected.distributeDocDataValuesRawPrefixBytes,
        suffix: expected.distributeDocDataValuesRawSuffixBytes
    )
    if let distributeDocDataRawTrailingLength = expected.distributeDocDataRawTrailingLength {
        expect(actual?.distributeDocDataInfo?.rawTrailing.count) ==
            distributeDocDataRawTrailingLength
    }
    if let distributeDocDataRawTrailingPrefixBytes =
        expected.distributeDocDataRawTrailingPrefixBytes
    {
        let prefix = actual?.distributeDocDataInfo?.rawTrailing.prefix(
            distributeDocDataRawTrailingPrefixBytes.count
        ) ?? Data()
        expect(Array(prefix)) == distributeDocDataRawTrailingPrefixBytes
    }
    if let distributeDocDataRawTrailingSuffixBytes =
        expected.distributeDocDataRawTrailingSuffixBytes
    {
        let suffix = actual?.distributeDocDataInfo?.rawTrailing.suffix(
            distributeDocDataRawTrailingSuffixBytes.count
        ) ?? Data()
        expect(Array(suffix)) == distributeDocDataRawTrailingSuffixBytes
    }
}

private func assertDocDataInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let docDataValues = expected.docDataValues {
        expect(actual?.docDataInfo?.values) == docDataValues
    }
    FixtureAssertions.assertPayloadSample(
        actual?.docDataInfo?.valuesRawPayload,
        length: expected.docDataValuesRawLength,
        prefix: expected.docDataValuesRawPrefixBytes,
        suffix: expected.docDataValuesRawSuffixBytes
    )
    if let docDataRawTrailingLength = expected.docDataRawTrailingLength {
        expect(actual?.docDataInfo?.rawTrailing.count) == docDataRawTrailingLength
    }
    if let docDataRawTrailingPrefixBytes = expected.docDataRawTrailingPrefixBytes {
        let prefix = actual?.docDataInfo?.rawTrailing.prefix(
            docDataRawTrailingPrefixBytes.count
        ) ?? Data()
        expect(Array(prefix)) == docDataRawTrailingPrefixBytes
    }
    if let docDataRawTrailingSuffixBytes = expected.docDataRawTrailingSuffixBytes {
        let suffix = actual?.docDataInfo?.rawTrailing.suffix(
            docDataRawTrailingSuffixBytes.count
        ) ?? Data()
        expect(Array(suffix)) == docDataRawTrailingSuffixBytes
    }
}

private func assertTrackChangeInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let trackChangeHeaderValue = expected.trackChangeHeaderValue {
        expect(actual?.trackChangeInfo?.headerValue) == trackChangeHeaderValue
    }
    FixtureAssertions.assertPayloadSample(
        actual?.trackChangeInfo?.headerRawPayload,
        length: expected.trackChangeHeaderRawLength,
        prefix: expected.trackChangeHeaderRawPrefixBytes,
        suffix: expected.trackChangeHeaderRawSuffixBytes
    )
    FixtureAssertions.assertPayloadSample(
        actual?.trackChangeInfo?.rawTrailing,
        length: expected.trackChangeRawTrailingLength,
        prefix: expected.trackChangeRawTrailingPrefixBytes,
        suffix: expected.trackChangeRawTrailingSuffixBytes
    )
}

private func assertMemoShapeInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let memoShapeWidth = expected.memoShapeWidth {
        expect(actual?.memoShapeInfo?.width) == memoShapeWidth
    }
    if let memoShapeLineType = expected.memoShapeLineType {
        expect(actual?.memoShapeInfo?.lineType) == memoShapeLineType
    }
    if let memoShapeLineWidth = expected.memoShapeLineWidth {
        expect(actual?.memoShapeInfo?.lineWidth) == memoShapeLineWidth
    }
    assertColor(expected.memoShapeLineColor, actual?.memoShapeInfo?.lineColor)
    assertColor(expected.memoShapeFillColor, actual?.memoShapeInfo?.fillColor)
    assertColor(expected.memoShapeActiveColor, actual?.memoShapeInfo?.activeColor)
    FixtureAssertions.assertPayloadSample(
        actual?.memoShapeInfo?.fixedFieldsRawPayload,
        length: expected.memoShapeFixedRawLength,
        prefix: expected.memoShapeFixedRawPrefixBytes,
        suffix: expected.memoShapeFixedRawSuffixBytes
    )
    FixtureAssertions.assertPayloadSample(
        actual?.memoShapeInfo?.rawTrailing,
        length: expected.memoShapeRawTrailingLength,
        prefix: expected.memoShapeRawTrailingPrefixBytes,
        suffix: expected.memoShapeRawTrailingSuffixBytes
    )
}

private func assertColor(_ expected: [Int]?, _ actual: HwpColor?) {
    if let expected {
        expect(actual.map { [$0.red, $0.green, $0.blue] }) == expected
    }
}

private func assertTrackChangeAuthorInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let authorName = expected.authorName {
        expect(actual?.authorInfo?.name) == authorName
    }
    FixtureAssertions.assertPayloadSample(
        actual?.authorInfo?.nameLengthRawPayload,
        length: expected.authorNameLengthRawLength,
        prefix: expected.authorNameLengthRawPrefixBytes,
        suffix: expected.authorNameLengthRawSuffixBytes
    )
    FixtureAssertions.assertPayloadSample(
        actual?.authorInfo?.nameRawPayload,
        length: expected.authorNameRawPayloadLength,
        prefix: expected.authorNameRawPayloadPrefixBytes,
        suffix: expected.authorNameRawPayloadSuffixBytes
    )
    FixtureAssertions.assertPayloadSample(
        actual?.authorInfo?.rawTrailing,
        length: expected.authorRawTrailingLength,
        prefix: expected.authorRawTrailingPrefixBytes,
        suffix: expected.authorRawTrailingSuffixBytes
    )
}

private func assertForbiddenChars(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let forbiddenCharCount = expected.forbiddenCharCount {
        expect(actual?.forbiddenChars.count) == forbiddenCharCount
    }
    if let forbiddenCharPayloadLengths = expected.forbiddenCharPayloadLengths {
        expect(actual?.forbiddenChars.map(\.rawPayload.count)) == forbiddenCharPayloadLengths
    }
    FixtureAssertions.assertPayloadSamples(
        actual?.forbiddenChars.map(\.rawPayload) ?? [],
        lengths: nil,
        prefixes: expected.forbiddenCharPayloadPrefixBytes,
        suffixes: expected.forbiddenCharPayloadSuffixBytes
    )
}

private func assertTrackChangeContentInfo(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let trackChangeContentKind = expected.trackChangeContentKind {
        expect(actual?.trackChangeContentInfo?.kind) == trackChangeContentKind
    }
    FixtureAssertions.assertPayloadSample(
        actual?.trackChangeContentInfo?.kindRawPayload,
        length: expected.trackChangeContentKindRawLength,
        prefix: expected.trackChangeContentKindRawPrefixBytes,
        suffix: expected.trackChangeContentKindRawSuffixBytes
    )
    if let trackChangeContentYear = expected.trackChangeContentYear {
        expect(actual?.trackChangeContentInfo?.timestamp.year) == trackChangeContentYear
    }
    if let trackChangeContentMonth = expected.trackChangeContentMonth {
        expect(actual?.trackChangeContentInfo?.timestamp.month) == trackChangeContentMonth
    }
    if let trackChangeContentDay = expected.trackChangeContentDay {
        expect(actual?.trackChangeContentInfo?.timestamp.day) == trackChangeContentDay
    }
    if let trackChangeContentHour = expected.trackChangeContentHour {
        expect(actual?.trackChangeContentInfo?.timestamp.hour) == trackChangeContentHour
    }
    if let trackChangeContentMinute = expected.trackChangeContentMinute {
        expect(actual?.trackChangeContentInfo?.timestamp.minute) == trackChangeContentMinute
    }
    assertTrackChangeContentTimestampRawPayload(expected, actual)
    FixtureAssertions.assertPayloadSample(
        actual?.trackChangeContentInfo?.rawTrailing,
        length: expected.trackChangeContentRawTrailingLength,
        prefix: expected.trackChangeContentRawTrailingPrefixBytes,
        suffix: expected.trackChangeContentRawTrailingSuffixBytes
    )
}

private func assertTrackChangeContentTimestampRawPayload(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    FixtureAssertions.assertPayloadSample(
        actual?.trackChangeContentInfo?.timestampRawPayload,
        length: expected.trackChangeTimestampRawLength,
        prefix: expected.trackChangeTimestampRawPrefixBytes,
        suffix: expected.trackChangeTimestampRawSuffixBytes
    )
}

private func assertUnknownChildren(
    _ expected: FixtureRawRecordExpectations,
    _ actual: ActualRawRecord?
) {
    if let unknownChildCount = expected.unknownChildCount {
        expect(actual?.unknownChildren.count) == unknownChildCount
    }
    FixtureAssertions.assertUnknownRecordSamples(
        actual?.unknownChildren ?? [],
        rootLevel: 1,
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
