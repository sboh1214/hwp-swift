@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertListControls(
        _ expectations: [FixtureListControlExpectations],
        _ hwp: HwpFile
    ) {
        let actualControls = FixtureDerivedValues.listControls(from: hwp)
        assertListControls(expectations, actualControls)
    }

    static func assertListControls(
        _ expectations: [FixtureListControlExpectations],
        _ actualControls: [(kind: String, control: HwpListControl)]
    ) {
        expect(actualControls.map(\.kind)) == expectations.map(\.kind)
        expect(actualControls.count) == expectations.count

        for ((_, actual), expected) in zip(actualControls, expectations) {
            assertListControlHeader(actual, expected)
            assertListControlLists(actual, expected)
            assertListHeaderUnknownChildren(actual.listArray, expected)
            assertListControlUnknownChildren(actual.unknownChildren, expected)
        }
    }
}

private func assertListControlHeader(
    _ actual: HwpListControl,
    _ expected: FixtureListControlExpectations
) {
    if let ctrlId = expected.ctrlId {
        expect(actual.header.ctrlId) == ctrlId
    }
    if let ctrlIdName = expected.ctrlIdName {
        let actualCtrlIdName = HwpOtherCtrlId(rawValue: actual.header.ctrlId)
            .map(String.init(describing:)) ?? "unknown"
        expect(actualCtrlIdName) == ctrlIdName
    }
    FixtureAssertions.assertPayloadSample(
        actual.header.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
}

private func assertListControlLists(
    _ actual: HwpListControl,
    _ expected: FixtureListControlExpectations
) {
    if let listCount = expected.listCount {
        expect(actual.listArray.count) == listCount
    }
    if let listParagraphCounts = expected.listParagraphCounts {
        expect(actual.listArray.map(\.paragraphArray.count)) == listParagraphCounts
    }
    if let listHeaderRawPayloadLengths = expected.listHeaderRawPayloadLengths {
        expect(actual.listArray.map(\.header.rawPayload.count)) == listHeaderRawPayloadLengths
        expect(actual.listArray.map(\.headerRawPayload.count)) == listHeaderRawPayloadLengths
    }
    FixtureAssertions.assertPayloadSamples(
        actual.listArray.map(\.headerRawPayload),
        lengths: expected.listHeaderRawPayloadLengths,
        prefixes: expected.listHeaderRawPayloadPrefixBytes,
        suffixes: expected.listHeaderRawPayloadSuffixBytes
    )
    FixtureAssertions.assertPayloadSamples(
        actual.listArray.map(\.header.rawTrailing),
        lengths: expected.listHeaderRawTrailingLengths,
        prefixes: expected.listHeaderRawTrailingPrefixBytes,
        suffixes: expected.listHeaderRawTrailingSuffixBytes
    )
    if let lengths = expected.listHeaderRawTrailingLengths {
        expect(actual.listArray.map { $0.header.rawTrailingWords?.count }) ==
            lengths.map { $0.isMultiple(of: MemoryLayout<UInt16>.size) ? $0 / 2 : nil }
    }
}

private func assertListHeaderUnknownChildren(
    _ actual: [HwpListControlList],
    _ expected: FixtureListControlExpectations
) {
    let unknownChildren = actual.map(\.headerUnknownChildren)
    if let counts = expected.listHeaderUnknownChildCounts {
        expect(unknownChildren.map(\.count)) == counts
    }
    for index in unknownChildren.indices {
        FixtureAssertions.assertUnknownRecordSamples(
            unknownChildren[index],
            rootLevel: 3,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: listExpectationGroup(expected.listHeaderUnknownChildTagIds, at: index),
                payloadLengths: listExpectationGroup(
                    expected.listHeaderUnknownChildPayloadLengths,
                    at: index
                ),
                payloadPrefixes: listExpectationGroup(
                    expected.listHeaderUnknownChildPayloadPrefixBytes,
                    at: index
                ),
                payloadSuffixes: listExpectationGroup(
                    expected.listHeaderUnknownChildPayloadSuffixBytes,
                    at: index
                ),
                childTagIds: listNestedExpectationGroup(
                    expected.listHeaderNestedChildTagIds,
                    at: index
                ),
                childPayloadLengths: listNestedExpectationGroup(
                    expected.listHeaderNestedChildPayloadLengths,
                    at: index
                ),
                childPayloadPrefixes: listNestedExpectationGroup(
                    expected.listHeaderNestedChildPayloadPrefixBytes,
                    at: index
                ),
                childPayloadSuffixes: listNestedExpectationGroup(
                    expected.listHeaderNestedChildPayloadSuffixBytes,
                    at: index
                )
            )
        )
    }
}

private func assertListControlUnknownChildren(
    _ actual: [HwpUnknownRecord],
    _ expected: FixtureListControlExpectations
) {
    if let count = expected.unknownChildCount {
        expect(actual.count) == count
    }
    FixtureAssertions.assertUnknownRecordSamples(
        actual,
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

private func listExpectationGroup<Element>(
    _ expectations: [[Element]]?,
    at index: Int
) -> [Element]? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}

private func listNestedExpectationGroup<Element>(
    _ expectations: [[[Element]]]?,
    at index: Int
) -> [[Element]]? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}
