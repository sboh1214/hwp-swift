@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertTables(
        _ expectations: [FixtureTableExpectations],
        _ actualTables: [HwpTable]
    ) {
        expect(actualTables.count) == expectations.count

        for (actual, expected) in zip(actualTables, expectations) {
            if let ctrlId = expected.ctrlId {
                expect(actual.commonCtrlProperty.commonCtrlId.rawValue) == ctrlId
            }
            if let ctrlIdName = expected.ctrlIdName {
                expect(String(describing: actual.commonCtrlProperty.commonCtrlId)) == ctrlIdName
            }
            if let rowCount = expected.rowCount {
                expect(actual.tableProperty.rowCount) == rowCount
            }
            if let columnCount = expected.columnCount {
                expect(actual.tableProperty.columnCount) == columnCount
            }
            assertTablePayload(actual, expected)
            assertTablePropertyPayload(actual.tableProperty, expected)
            assertTableCells(actual.cellArray, expected)
            assertTableUnknownChildren(actual.unknownChildren, expected)
        }
    }

    static func assertTablePayload(
        _ actual: HwpTable,
        _ expected: FixtureTableExpectations
    ) {
        assertPayloadSample(
            actual.commonCtrlProperty.rawPayload,
            length: expected.commonCtrlPropertyRawPayloadLength,
            prefix: expected.commonCtrlPropertyRawPayloadPrefixBytes,
            suffix: expected.commonCtrlPropertyRawPayloadSuffixBytes
        )
        assertPayloadSample(
            actual.rawPayload,
            length: expected.rawPayloadLength,
            prefix: nil,
            suffix: nil
        )
        assertPayloadSample(
            actual.rawTrailing,
            length: expected.rawTrailingLength,
            prefix: expected.rawTrailingPrefixBytes,
            suffix: expected.rawTrailingSuffixBytes
        )
    }

    static func assertTablePropertyPayload(
        _ actual: HwpTableProperty,
        _ expected: FixtureTableExpectations
    ) {
        assertPayloadSample(
            actual.rawPayload,
            length: expected.tablePropertyRawPayloadLength,
            prefix: expected.tablePropertyRawPayloadPrefixBytes,
            suffix: expected.tablePropertyRawPayloadSuffixBytes
        )
        assertPayloadSample(
            actual.rawTrailing,
            length: expected.tablePropertyRawTrailingLength,
            prefix: expected.tablePropertyRawTrailingPrefixBytes,
            suffix: expected.tablePropertyRawTrailingSuffixBytes
        )
    }

    static func assertTableCells(
        _ actual: [HwpTableCell],
        _ expected: FixtureTableExpectations
    ) {
        if let cellCount = expected.cellCount {
            expect(actual.count) == cellCount
        }
        if let paragraphCount = expected.paragraphCount {
            let actualCount = actual.reduce(0) { result, cell in
                result + cell.paragraphArray.count
            }
            expect(actualCount) == paragraphCount
        }
        if let cellParagraphCounts = expected.cellParagraphCounts {
            expect(actual.map(\.paragraphArray.count)) == cellParagraphCounts
        }
        assertPayloadSamples(
            actual.map(\.header.rawPayload),
            lengths: expected.cellHeaderRawPayloadLengths,
            prefixes: expected.cellHeaderRawPayloadPrefixBytes,
            suffixes: expected.cellHeaderRawPayloadSuffixBytes
        )
        assertPayloadSamples(
            actual.map(\.header.rawTrailing),
            lengths: expected.cellHeaderRawTrailingLengths,
            prefixes: expected.cellHeaderRawTrailingPrefixBytes,
            suffixes: expected.cellHeaderRawTrailingSuffixBytes
        )
        assertTableCellUnknownChildren(actual.map(\.header.unknownChildren), expected)
    }

    static func assertTableUnknownChildren(
        _ actual: [HwpUnknownRecord],
        _ expected: FixtureTableExpectations
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
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

    static func assertTableCellUnknownChildren(
        _ actual: [[HwpUnknownRecord]],
        _ expected: FixtureTableExpectations
    ) {
        if let counts = expected.cellHeaderUnknownChildCounts {
            expect(actual.map(\.count)) == counts
        }
        for index in actual.indices {
            assertUnknownRecordSamples(
                actual[index],
                rootLevel: 3,
                expectations: FixtureUnknownRecordSampleExpectations(
                    tagIds: tableExpectationGroup(expected.cellHeaderUnknownChildTagIds, at: index),
                    payloadLengths: tableExpectationGroup(
                        expected.cellHeaderUnknownChildPayloadLengths,
                        at: index
                    ),
                    payloadPrefixes: tableExpectationGroup(
                        expected.cellHeaderUnknownChildPayloadPrefixBytes,
                        at: index
                    ),
                    payloadSuffixes: tableExpectationGroup(
                        expected.cellHeaderUnknownChildPayloadSuffixBytes,
                        at: index
                    ),
                    childTagIds: tableNestedExpectationGroup(
                        expected.cellHeaderNestedChildTagIds,
                        at: index
                    ),
                    childPayloadLengths: tableNestedExpectationGroup(
                        expected.cellHeaderNestedChildPayloadLengths,
                        at: index
                    ),
                    childPayloadPrefixes: tableNestedExpectationGroup(
                        expected.cellHeaderNestedChildPayloadPrefixBytes,
                        at: index
                    ),
                    childPayloadSuffixes: tableNestedExpectationGroup(
                        expected.cellHeaderNestedChildPayloadSuffixBytes,
                        at: index
                    )
                )
            )
        }
    }
}

private func tableExpectationGroup<Element>(
    _ expectations: [[Element]]?,
    at index: Int
) -> [Element]? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}

private func tableNestedExpectationGroup<Element>(
    _ expectations: [[[Element]]]?,
    at index: Int
) -> [[Element]]? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}
