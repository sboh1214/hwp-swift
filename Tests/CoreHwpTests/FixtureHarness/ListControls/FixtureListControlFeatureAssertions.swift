func listControlHasPayloadSamples(_ control: FixtureListControlExpectations) -> Bool {
    control.kind.isEmpty == false
        && control.ctrlId != nil
        && control.ctrlIdName != nil
        && listControlListsAreDeclared(control)
        && payloadSampleIsDeclared(
            length: control.rawPayloadLength,
            prefix: control.rawPayloadPrefixBytes,
            suffix: control.rawPayloadSuffixBytes
        )
        && listControlHeaderPayloadSamplesAreDeclared(control)
        && listControlUnknownChildPayloadSamplesAreDeclared(control)
        && listHeaderUnknownChildPayloadSamplesAreDeclared(control)
        && listHeaderNestedPayloadSamplesAreDeclared(control)
}

private func listControlListsAreDeclared(_ control: FixtureListControlExpectations) -> Bool {
    guard let listCount = control.listCount,
          let paragraphCounts = control.listParagraphCounts,
          listCount > 0
    else {
        return false
    }

    return paragraphCounts.count == listCount
        && paragraphCounts.allSatisfy { $0 >= 0 }
}

private func listControlHeaderPayloadSamplesAreDeclared(
    _ control: FixtureListControlExpectations
) -> Bool {
    countedPayloadSamplesAreDeclared(
        count: control.listCount,
        lengths: control.listHeaderRawPayloadLengths,
        prefixes: control.listHeaderRawPayloadPrefixBytes,
        suffixes: control.listHeaderRawPayloadSuffixBytes
    )
        && countedPayloadSamplesAreDeclared(
            count: control.listCount,
            lengths: control.listHeaderRawTrailingLengths,
            prefixes: control.listHeaderRawTrailingPrefixBytes,
            suffixes: control.listHeaderRawTrailingSuffixBytes
        )
}

private func listControlUnknownChildPayloadSamplesAreDeclared(
    _ control: FixtureListControlExpectations
) -> Bool {
    unknownChildPayloadSamplesAreDeclared(
        count: control.unknownChildCount,
        tagIds: control.unknownChildTagIds,
        lengths: control.unknownChildPayloadLengths,
        prefixes: control.unknownChildPayloadPrefixBytes,
        suffixes: control.unknownChildPayloadSuffixBytes
    )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: control.unknownChildChildTagIds,
            lengths: control.unknownChildChildPayloadLengths,
            prefixes: control.unknownChildChildPayloadPrefixBytes,
            suffixes: control.unknownChildChildPayloadSuffixBytes
        )
}

private func listHeaderUnknownChildPayloadSamplesAreDeclared(
    _ control: FixtureListControlExpectations
) -> Bool {
    guard control.listHeaderUnknownChildCounts != nil ||
        control.listHeaderUnknownChildTagIds != nil ||
        control.listHeaderUnknownChildPayloadLengths != nil ||
        control.listHeaderUnknownChildPayloadPrefixBytes != nil ||
        control.listHeaderUnknownChildPayloadSuffixBytes != nil
    else {
        return true
    }
    guard let counts = control.listHeaderUnknownChildCounts else {
        return false
    }
    if let listCount = control.listCount, counts.count != listCount {
        return false
    }

    return counts.indices.allSatisfy { index in
        unknownChildPayloadSamplesAreDeclared(
            count: counts[index],
            tagIds: nestedExpectation(control.listHeaderUnknownChildTagIds, at: index),
            lengths: nestedExpectation(control.listHeaderUnknownChildPayloadLengths, at: index),
            prefixes: nestedExpectation(
                control.listHeaderUnknownChildPayloadPrefixBytes,
                at: index
            ),
            suffixes: nestedExpectation(
                control.listHeaderUnknownChildPayloadSuffixBytes,
                at: index
            )
        )
    }
}

private func listHeaderNestedPayloadSamplesAreDeclared(
    _ control: FixtureListControlExpectations
) -> Bool {
    guard control.listHeaderNestedChildTagIds != nil ||
        control.listHeaderNestedChildPayloadLengths != nil ||
        control.listHeaderNestedChildPayloadPrefixBytes != nil ||
        control.listHeaderNestedChildPayloadSuffixBytes != nil
    else {
        return true
    }

    return deeplyNestedPayloadSampleArraysAreDeclared(
        tagIds: control.listHeaderNestedChildTagIds,
        lengths: control.listHeaderNestedChildPayloadLengths,
        prefixes: control.listHeaderNestedChildPayloadPrefixBytes,
        suffixes: control.listHeaderNestedChildPayloadSuffixBytes
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
