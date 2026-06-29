func docInfoRawRecordsHavePayloadSamples(
    _ records: FixtureDocInfoRawRecordsExpectations?
) -> Bool {
    guard let records else {
        return false
    }

    let singletonRecords = [
        records.docData,
        records.distributeDocData,
    ].compactMap { $0 }
    let multiRecords = [
        records.trackChanges ?? [],
        records.memoShapes ?? [],
        records.trackChangeContents ?? [],
        records.trackChangeAuthors ?? [],
        records.forbiddenChars ?? [],
    ].flatMap { $0 }
    let allRecords = singletonRecords + multiRecords

    return !allRecords.isEmpty && allRecords.allSatisfy(rawDocInfoRecordHasPayloadSample)
}
