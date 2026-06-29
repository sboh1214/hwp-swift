import Nimble

func assertTableFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.tables).notTo(beEmpty())
    expect(expectations.tables?.allSatisfy(tableHasPayloadSamples) ?? false) == true
    expect(expectations.allParagraphCount).notTo(beNil())
}

func tableHasPayloadSamples(_ table: FixtureTableExpectations) -> Bool {
    table.ctrlId != nil
        && table.ctrlIdName != nil
        && (table.rawPayloadLength.map { $0 > 0 } ?? true)
        && tableCellCountsAreDeclared(table)
        && tableCorePayloadSamplesAreDeclared(table)
        && tableCellPayloadSamplesAreDeclared(table)
        && tableUnknownChildPayloadSamplesAreDeclared(table)
        && tableCellHeaderUnknownChildPayloadSamplesAreDeclared(table)
        && tableCellHeaderNestedPayloadSamplesAreDeclared(table)
}

private func tableCorePayloadSamplesAreDeclared(_ table: FixtureTableExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: table.commonCtrlPropertyRawPayloadLength,
        prefix: table.commonCtrlPropertyRawPayloadPrefixBytes,
        suffix: table.commonCtrlPropertyRawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: table.rawTrailingLength,
            prefix: table.rawTrailingPrefixBytes,
            suffix: table.rawTrailingSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: table.tablePropertyRawPayloadLength,
            prefix: table.tablePropertyRawPayloadPrefixBytes,
            suffix: table.tablePropertyRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: table.tablePropertyRawTrailingLength,
            prefix: table.tablePropertyRawTrailingPrefixBytes,
            suffix: table.tablePropertyRawTrailingSuffixBytes
        )
}

private func tableCellPayloadSamplesAreDeclared(_ table: FixtureTableExpectations) -> Bool {
    countedPayloadSamplesAreDeclared(
        count: table.cellCount,
        lengths: table.cellHeaderRawPayloadLengths,
        prefixes: table.cellHeaderRawPayloadPrefixBytes,
        suffixes: table.cellHeaderRawPayloadSuffixBytes
    )
        && countedPayloadSamplesAreDeclared(
            count: table.cellCount,
            lengths: table.cellHeaderRawTrailingLengths,
            prefixes: table.cellHeaderRawTrailingPrefixBytes,
            suffixes: table.cellHeaderRawTrailingSuffixBytes
        )
}

private func tableUnknownChildPayloadSamplesAreDeclared(
    _ table: FixtureTableExpectations
) -> Bool {
    unknownChildPayloadSamplesAreDeclared(
        count: table.unknownChildCount,
        tagIds: table.unknownChildTagIds,
        lengths: table.unknownChildPayloadLengths,
        prefixes: table.unknownChildPayloadPrefixBytes,
        suffixes: table.unknownChildPayloadSuffixBytes
    )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: table.unknownChildChildTagIds,
            lengths: table.unknownChildChildPayloadLengths,
            prefixes: table.unknownChildChildPayloadPrefixBytes,
            suffixes: table.unknownChildChildPayloadSuffixBytes
        )
}

private func tableCellCountsAreDeclared(_ table: FixtureTableExpectations) -> Bool {
    guard let rowCount = table.rowCount,
          let columnCount = table.columnCount,
          let cellCount = table.cellCount,
          let paragraphCount = table.paragraphCount,
          let cellParagraphCounts = table.cellParagraphCounts,
          rowCount > 0,
          columnCount > 0,
          cellCount > 0
    else {
        return false
    }

    return cellParagraphCounts.count == cellCount
        && cellParagraphCounts.reduce(0, +) == paragraphCount
}

private func tableCellHeaderUnknownChildPayloadSamplesAreDeclared(
    _ table: FixtureTableExpectations
) -> Bool {
    guard table.cellHeaderUnknownChildCounts != nil ||
        table.cellHeaderUnknownChildTagIds != nil ||
        table.cellHeaderUnknownChildPayloadLengths != nil ||
        table.cellHeaderUnknownChildPayloadPrefixBytes != nil ||
        table.cellHeaderUnknownChildPayloadSuffixBytes != nil
    else {
        return true
    }
    guard let counts = table.cellHeaderUnknownChildCounts else {
        return false
    }
    if let cellCount = table.cellCount, counts.count != cellCount {
        return false
    }

    return counts.indices.allSatisfy { index in
        unknownChildPayloadSamplesAreDeclared(
            count: counts[index],
            tagIds: nestedExpectation(table.cellHeaderUnknownChildTagIds, at: index),
            lengths: nestedExpectation(table.cellHeaderUnknownChildPayloadLengths, at: index),
            prefixes: nestedExpectation(table.cellHeaderUnknownChildPayloadPrefixBytes, at: index),
            suffixes: nestedExpectation(table.cellHeaderUnknownChildPayloadSuffixBytes, at: index)
        )
    }
}

private func tableCellHeaderNestedPayloadSamplesAreDeclared(
    _ table: FixtureTableExpectations
) -> Bool {
    guard table.cellHeaderNestedChildTagIds != nil ||
        table.cellHeaderNestedChildPayloadLengths != nil ||
        table.cellHeaderNestedChildPayloadPrefixBytes != nil ||
        table.cellHeaderNestedChildPayloadSuffixBytes != nil
    else {
        return true
    }

    return deeplyNestedPayloadSampleArraysAreDeclared(
        tagIds: table.cellHeaderNestedChildTagIds,
        lengths: table.cellHeaderNestedChildPayloadLengths,
        prefixes: table.cellHeaderNestedChildPayloadPrefixBytes,
        suffixes: table.cellHeaderNestedChildPayloadSuffixBytes
    )
}

private func nestedExpectation<Element>(
    _ expectations: [[Element]]?,
    at index: Int
) -> [Element]? {
    guard let expectations, expectations.indices.contains(index) else {
        return nil
    }
    return expectations[index]
}
