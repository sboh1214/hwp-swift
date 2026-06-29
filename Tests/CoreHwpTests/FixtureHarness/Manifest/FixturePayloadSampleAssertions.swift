import CoreHwp
import Foundation
import Nimble

struct FixtureUnknownRecordSampleExpectations {
    static let empty = FixtureUnknownRecordSampleExpectations()

    var tagIds: [UInt32]?
    var payloadLengths: [Int]?
    var payloadPrefixes: [[UInt8]]?
    var payloadSuffixes: [[UInt8]]?
    var childTagIds: [[UInt32]]?
    var childPayloadLengths: [[Int]]?
    var childPayloadPrefixes: [[[UInt8]]]?
    var childPayloadSuffixes: [[[UInt8]]]?
}

extension FixtureAssertions {
    static func assertPayloadSample(
        _ actual: Data,
        length: Int?,
        prefix: [UInt8]?,
        suffix: [UInt8]?
    ) {
        if let length {
            expect(actual.count) == length
        }
        if let prefix {
            expect(Array(actual.prefix(prefix.count))) == prefix
        }
        if let suffix {
            expect(Array(actual.suffix(suffix.count))) == suffix
        }
    }

    static func assertPayloadSample(
        _ actual: Data?,
        length: Int?,
        prefix: [UInt8]?,
        suffix: [UInt8]?
    ) {
        guard length != nil || prefix != nil || suffix != nil else {
            return
        }

        expect(actual).notTo(beNil())
        assertPayloadSample(
            actual ?? Data(),
            length: length,
            prefix: prefix,
            suffix: suffix
        )
    }

    static func assertPayloadSamples(
        _ actual: [Data],
        lengths: [Int]?,
        prefixes: [[UInt8]]?,
        suffixes: [[UInt8]]?
    ) {
        if let lengths {
            expect(actual.map(\.count)) == lengths
        }
        if let prefixes {
            expect(actual.count) == prefixes.count
            for (data, prefix) in zip(actual, prefixes) {
                expect(Array(data.prefix(prefix.count))) == prefix
            }
        }
        if let suffixes {
            expect(actual.count) == suffixes.count
            for (data, suffix) in zip(actual, suffixes) {
                expect(Array(data.suffix(suffix.count))) == suffix
            }
        }
    }

    static func assertNestedPayloadSamples(
        _ actual: [[Data]],
        lengths: [[Int]]?,
        prefixes: [[[UInt8]]]?,
        suffixes: [[[UInt8]]]?
    ) {
        if let lengths {
            expect(lengths.count) == actual.count
        }
        if let prefixes {
            expect(prefixes.count) == actual.count
        }
        if let suffixes {
            expect(suffixes.count) == actual.count
        }

        for index in actual.indices {
            assertPayloadSamples(
                actual[index],
                lengths: nestedExpectation(lengths, at: index),
                prefixes: nestedExpectation(prefixes, at: index),
                suffixes: nestedExpectation(suffixes, at: index)
            )
        }
    }

    static func assertDeeplyNestedPayloadSamples(
        _ actual: [[[Data]]],
        lengths: [[[Int]]]?,
        prefixes: [[[[UInt8]]]]?,
        suffixes: [[[[UInt8]]]]?
    ) {
        if let lengths {
            expect(lengths.count) == actual.count
        }
        if let prefixes {
            expect(prefixes.count) == actual.count
        }
        if let suffixes {
            expect(suffixes.count) == actual.count
        }

        for index in actual.indices {
            assertNestedPayloadSamples(
                actual[index],
                lengths: nestedExpectation(lengths, at: index),
                prefixes: nestedExpectation(prefixes, at: index),
                suffixes: nestedExpectation(suffixes, at: index)
            )
        }
    }

    static func assertUnknownRecordSamples(
        _ records: [HwpUnknownRecord],
        rootLevel: UInt32,
        expectations: FixtureUnknownRecordSampleExpectations
    ) {
        assertUnknownRecordLevels(records, rootLevel: rootLevel)
        assertUnknownRecordSampleValues(records, expectations: expectations)
    }

    static func assertUnknownRecordSamples(
        _ records: [HwpUnknownRecord],
        expectations: FixtureUnknownRecordSampleExpectations
    ) {
        assertUnknownRecordChildLevels(records)
        assertUnknownRecordSampleValues(records, expectations: expectations)
    }

    static func assertUnknownRecordLevels(
        _ records: [HwpUnknownRecord],
        rootLevel: UInt32
    ) {
        for record in records {
            assertUnknownRecordLevel(record, expectedLevel: rootLevel)
        }
    }

    static func assertUnknownRecordChildLevels(_ records: [HwpUnknownRecord]) {
        for record in records {
            assertUnknownRecordLevel(record, expectedLevel: record.level)
        }
    }
}

private func assertRecordExpectationCounts(
    recordCount: Int,
    expectations: FixtureUnknownRecordSampleExpectations
) {
    expect(expectations.tagIds?.count ?? recordCount) == recordCount
    expect(expectations.payloadLengths?.count ?? recordCount) == recordCount
    expect(expectations.payloadPrefixes?.count ?? recordCount) == recordCount
    expect(expectations.payloadSuffixes?.count ?? recordCount) == recordCount
    expect(expectations.childTagIds?.count ?? recordCount) == recordCount
    expect(expectations.childPayloadLengths?.count ?? recordCount) == recordCount
    expect(expectations.childPayloadPrefixes?.count ?? recordCount) == recordCount
    expect(expectations.childPayloadSuffixes?.count ?? recordCount) == recordCount
}

private func assertUnknownRecordSampleValues(
    _ records: [HwpUnknownRecord],
    expectations: FixtureUnknownRecordSampleExpectations
) {
    assertRecordExpectationCounts(
        recordCount: records.count,
        expectations: expectations
    )

    for (index, record) in records.enumerated() {
        assertUnknownRecordSample(
            record,
            at: index,
            expectations: expectations
        )
    }
}

private func assertUnknownRecordSample(
    _ record: HwpUnknownRecord,
    at index: Int,
    expectations: FixtureUnknownRecordSampleExpectations
) {
    if let expectedTagId = expectation(expectations.tagIds, at: index) {
        expect(record.tagId) == expectedTagId
    }
    FixtureAssertions.assertPayloadSample(
        record.payload,
        length: expectation(expectations.payloadLengths, at: index),
        prefix: expectation(expectations.payloadPrefixes, at: index),
        suffix: expectation(expectations.payloadSuffixes, at: index)
    )
    FixtureAssertions.assertUnknownRecordSamples(
        record.children,
        rootLevel: record.level + 1,
        expectations: FixtureUnknownRecordSampleExpectations(
            tagIds: expectation(expectations.childTagIds, at: index),
            payloadLengths: expectation(expectations.childPayloadLengths, at: index),
            payloadPrefixes: expectation(expectations.childPayloadPrefixes, at: index),
            payloadSuffixes: expectation(expectations.childPayloadSuffixes, at: index),
            childTagIds: nil,
            childPayloadLengths: nil,
            childPayloadPrefixes: nil,
            childPayloadSuffixes: nil
        )
    )
}

private func assertUnknownRecordLevel(
    _ record: HwpUnknownRecord,
    expectedLevel: UInt32
) {
    expect(record.level) == expectedLevel
    for child in record.children {
        assertUnknownRecordLevel(child, expectedLevel: expectedLevel + 1)
    }
}

private func nestedExpectation<Element>(_ expectations: [[Element]]?, at index: Int) -> [Element]? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}

private func expectation<Element>(_ expectations: [Element]?, at index: Int) -> Element? {
    guard let expectations, expectations.indices.contains(index) else { return nil }
    return expectations[index]
}
