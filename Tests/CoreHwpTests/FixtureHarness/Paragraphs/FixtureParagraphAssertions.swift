@testable import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertParaTextPayloads(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertParaTextRawPayloads(expectations, hwp)
        let payloads = FixtureDerivedValues.paraTextPayloads(from: hwp)
        if let paraTextPayloadCount = expectations.paraTextPayloadCount {
            expect(payloads.count) == paraTextPayloadCount
        }
        if let paraTextPayloadTotalByteCount = expectations.paraTextPayloadTotalByteCount {
            let actual = payloads.reduce(0) { $0 + $1.count }
            expect(actual) == paraTextPayloadTotalByteCount
        }
        assertPayloadSamples(
            payloads,
            lengths: nil,
            prefixes: expectations.paraTextPayloadPrefixBytes,
            suffixes: expectations.paraTextPayloadSuffixBytes
        )
        assertParaTextInlineControls(expectations, hwp)
        assertParaHeaderPayloads(expectations, hwp)
        assertParaCharShapePayloads(expectations, hwp)
        assertParaLineSegPayloads(expectations, hwp)
        assertParaRangeTags(expectations, hwp)
        assertParagraphUnknownChildren(expectations, hwp)
    }

    private static func assertParaTextInlineControls(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let controls = FixtureDerivedValues.paraTextInlineControls(from: hwp)
        if let paraTextControlIds = expectations.paraTextControlIds {
            expect(controls.compactMap(\.rawControlId)) == paraTextControlIds
        }
        if let paraTextControlIdNames = expectations.paraTextControlIdNames {
            expect(controls.map(\.ctrlIdName)) == paraTextControlIdNames
        }
        assertPayloadSamples(
            controls.map(\.rawPayload),
            lengths: expectations.paraTextControlPayloadLengths,
            prefixes: expectations.paraTextControlPayloadPrefixBytes,
            suffixes: expectations.paraTextControlPayloadSuffixBytes
        )
        assertPayloadSamples(
            controls.map(\.rawTrailing),
            lengths: expectations.paraTextControlTrailingLengths,
            prefixes: expectations.paraTextControlTrailingPrefixBytes,
            suffixes: expectations.paraTextControlTrailingSuffixBytes
        )
    }

    private static func assertParaTextRawPayloads(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let payloads = FixtureDerivedValues.paraTextRawPayloads(from: hwp)
        if let paraTextRawPayloadCount = expectations.paraTextRawPayloadCount {
            expect(payloads.count) == paraTextRawPayloadCount
        }
        if let paraTextRawPayloadTotalByteCount = expectations.paraTextRawPayloadTotalByteCount {
            expect(payloads.reduce(0) { $0 + $1.count }) == paraTextRawPayloadTotalByteCount
        }
        assertPayloadSamples(
            payloads,
            lengths: nil,
            prefixes: expectations.paraTextRawPayloadPrefixBytes,
            suffixes: expectations.paraTextRawPayloadSuffixBytes
        )
    }

    private static func assertParaHeaderPayloads(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let payloads = FixtureDerivedValues.paraHeaderPayloads(from: hwp)
        if let paraHeaderPayloadCount = expectations.paraHeaderPayloadCount {
            expect(payloads.count) == paraHeaderPayloadCount
        }
        if let paraHeaderPayloadTotalByteCount = expectations.paraHeaderPayloadTotalByteCount {
            expect(payloads.reduce(0) { $0 + $1.count }) == paraHeaderPayloadTotalByteCount
        }
        assertPayloadSamples(
            payloads,
            lengths: nil,
            prefixes: expectations.paraHeaderPayloadPrefixBytes,
            suffixes: expectations.paraHeaderPayloadSuffixBytes
        )
    }

    private static func assertParaCharShapePayloads(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let payloads = FixtureDerivedValues.paraCharShapePayloads(from: hwp)
        if let paraCharShapePayloadCount = expectations.paraCharShapePayloadCount {
            expect(payloads.count) == paraCharShapePayloadCount
        }
        if let totalByteCount = expectations.paraCharShapePayloadTotalByteCount {
            expect(payloads.reduce(0) { $0 + $1.count }) == totalByteCount
        }
        assertPayloadSamples(
            payloads,
            lengths: nil,
            prefixes: expectations.paraCharShapePayloadPrefixBytes,
            suffixes: expectations.paraCharShapePayloadSuffixBytes
        )
    }

    private static func assertParaLineSegPayloads(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let payloads = FixtureDerivedValues.paraLineSegPayloads(from: hwp)
        if let paraLineSegPayloadCount = expectations.paraLineSegPayloadCount {
            expect(payloads.count) == paraLineSegPayloadCount
        }
        if let paraLineSegPayloadTotalByteCount = expectations.paraLineSegPayloadTotalByteCount {
            expect(payloads.reduce(0) { $0 + $1.count }) == paraLineSegPayloadTotalByteCount
        }
        assertPayloadSamples(
            payloads,
            lengths: nil,
            prefixes: expectations.paraLineSegPayloadPrefixBytes,
            suffixes: expectations.paraLineSegPayloadSuffixBytes
        )
    }

    private static func assertParaRangeTags(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        let actual = FixtureDerivedValues.paraRangeTags(from: hwp)
        if let paraRangeTagCount = expectations.paraRangeTagCount {
            expect(actual.count) == paraRangeTagCount
        }
        if let paraRangeTagPayloadTotalByteCount = expectations.paraRangeTagPayloadTotalByteCount {
            let payloads = FixtureDerivedValues.paraRangeTagPayloads(from: hwp)
            expect(payloads.reduce(0) { $0 + $1.count }) == paraRangeTagPayloadTotalByteCount
        }
        if let paraRangeTags = expectations.paraRangeTags {
            expect(actual.count) == paraRangeTags.count
            for (offset, expectation) in paraRangeTags.enumerated() {
                guard actual.indices.contains(offset) else {
                    return
                }
                if let start = expectation.start {
                    expect(actual[offset].start) == start
                }
                if let end = expectation.end {
                    expect(actual[offset].end) == end
                }
                if let tag = expectation.tag {
                    expect(actual[offset].tag) == tag
                }
            }
        }
    }

    private static func assertParagraphUnknownChildren(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        let unknownChildren = FixtureDerivedValues.allParagraphs(from: hwp)
            .flatMap(\.unknownChildren)
        if let paragraphUnknownChildCount = expectations.paragraphUnknownChildCount {
            expect(unknownChildren.count) == paragraphUnknownChildCount
        }
        assertUnknownRecordSamples(
            unknownChildren,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expectations.paragraphUnknownChildTagIds,
                payloadLengths: expectations.paragraphUnknownChildPayloadLengths,
                payloadPrefixes: expectations.paragraphUnknownChildPayloadPrefixBytes,
                payloadSuffixes: expectations.paragraphUnknownChildPayloadSuffixBytes,
                childTagIds: expectations.paragraphUnknownNestedTagIds,
                childPayloadLengths: expectations.paragraphUnknownNestedPayloadLengths,
                childPayloadPrefixes: expectations.paragraphUnknownNestedPayloadPrefixBytes,
                childPayloadSuffixes: expectations.paragraphUnknownNestedPayloadSuffixBytes
            )
        )
    }
}
