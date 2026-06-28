@testable import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertPageNumberPositions(
        _ expectations: [FixturePageNumberPositionExpectations],
        _ actualPositions: [HwpPageNumberPosition]
    ) {
        expect(actualPositions.count) == expectations.count

        for (actual, expected) in zip(actualPositions, expectations) {
            assertPageNumberPositionPayload(actual, expected)
            assertPageNumberPositionUnknownChildren(actual, expected)
        }
    }
}

private func assertPageNumberPositionPayload(
    _ actual: HwpPageNumberPosition,
    _ expected: FixturePageNumberPositionExpectations
) {
    if let ctrlId = expected.ctrlId {
        expect(actual.otherCtrlId.rawValue) == ctrlId
    }
    if let ctrlIdName = expected.ctrlIdName {
        expect(String(describing: actual.otherCtrlId)) == ctrlIdName
    }
    if let property = expected.property {
        expect(actual.property) == property
    }
    if let userSymbol = expected.userSymbol {
        expect(actual.userSymbol) == userSymbol
    }
    if let headDecoration = expected.headDecoration {
        expect(actual.headDecoration) == headDecoration
    }
    if let tailDecoration = expected.tailDecoration {
        expect(actual.tailDecoration) == tailDecoration
    }
    if let unused = expected.unused {
        expect(actual.unused) == unused
    }
    if let unknown = expected.unknown {
        expect(actual.unknown) == unknown
    }
    FixtureAssertions.assertPayloadSample(
        actual.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
    FixtureAssertions.assertPayloadSample(
        actual.rawTrailing,
        length: expected.rawTrailingLength,
        prefix: expected.rawTrailingPrefixBytes,
        suffix: expected.rawTrailingSuffixBytes
    )
}

private func assertPageNumberPositionUnknownChildren(
    _ actual: HwpPageNumberPosition,
    _ expected: FixturePageNumberPositionExpectations
) {
    if let unknownChildCount = expected.unknownChildCount {
        expect(actual.unknownChildren.count) == unknownChildCount
    }
    FixtureAssertions.assertUnknownRecordSamples(
        actual.unknownChildren,
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
