@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertShapeControls(
        _ expectations: [FixtureShapeControlExpectations],
        _ hwp: HwpFile
    ) {
        let actualControls = FixtureDerivedValues.shapeControls(from: hwp)
        assertShapeControls(expectations, actualControls)
    }

    static func assertShapeControls(
        _ expectations: [FixtureShapeControlExpectations],
        _ actualControls: [HwpShapeControl]
    ) {
        expect(actualControls.count) == expectations.count

        for (actual, expected) in zip(actualControls, expectations) {
            assertShapeControlPayload(actual, expected)
            assertShapeControlChildren(actual, expected)
        }
    }
}

private func assertShapeControlPayload(
    _ actual: HwpShapeControl,
    _ expected: FixtureShapeControlExpectations
) {
    if let ctrlId = expected.ctrlId {
        expect(actual.ctrlId.rawValue) == ctrlId
    }
    if let ctrlIdName = expected.ctrlIdName {
        expect(String(describing: actual.ctrlId)) == ctrlIdName
    }
    if let rawPayloadLength = expected.commonCtrlPropertyRawPayloadLength {
        expect(actual.commonCtrlProperty?.rawPayload.count) == rawPayloadLength
    }
    expectShapePayloadPrefix(
        actual.commonCtrlProperty?.rawPayload,
        expected.commonCtrlPropertyRawPayloadPrefixBytes
    )
    expectShapePayloadSuffix(
        actual.commonCtrlProperty?.rawPayload,
        expected.commonCtrlPropertyRawPayloadSuffixBytes
    )
    if let rawPayloadLength = expected.rawPayloadLength {
        expect(actual.rawPayload.count) == rawPayloadLength
    }
    expectShapePayloadPrefix(actual.rawPayload, expected.rawPayloadPrefixBytes)
    expectShapePayloadSuffix(actual.rawPayload, expected.rawPayloadSuffixBytes)
    if let rawTrailingLength = expected.rawTrailingLength {
        expect(actual.rawTrailing.count) == rawTrailingLength
    }
    expectShapePayloadPrefix(actual.rawTrailing, expected.rawTrailingPrefixBytes)
    expectShapePayloadSuffix(actual.rawTrailing, expected.rawTrailingSuffixBytes)
}

private func assertShapeControlChildren(
    _ actual: HwpShapeControl,
    _ expected: FixtureShapeControlExpectations
) {
    assertShapeControlEquationEdit(actual, expected)
    if let ctrlDataCount = expected.ctrlDataCount {
        expect(actual.ctrlDataRecords.count) == ctrlDataCount
    }
    if let ctrlDataPayloadLengths = expected.ctrlDataPayloadLengths {
        expect(actual.ctrlDataRecords.map(\.rawPayload.count)) == ctrlDataPayloadLengths
    }
    expectShapePayloadPrefixes(
        actual.ctrlDataRecords.map(\.rawPayload),
        expected.ctrlDataPayloadPrefixBytes
    )
    expectShapePayloadSuffixes(
        actual.ctrlDataRecords.map(\.rawPayload),
        expected.ctrlDataPayloadSuffixBytes
    )
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

private func assertShapeControlEquationEdit(
    _ actual: HwpShapeControl,
    _ expected: FixtureShapeControlExpectations
) {
    if let eqEditCount = expected.eqEditCount {
        expect(actual.eqEditRecords.count) == eqEditCount
        expect(actual.eqEditArray.count) == eqEditCount
    }
    if let eqEditPayloadLengths = expected.eqEditPayloadLengths {
        expect(actual.eqEditRecords.map(\.payload.count)) == eqEditPayloadLengths
        expect(actual.eqEditArray.map(\.rawPayload.count)) == eqEditPayloadLengths
    }
    expectShapePayloadPrefixes(
        actual.eqEditRecords.map(\.payload),
        expected.eqEditPayloadPrefixBytes
    )
    expectShapePayloadSuffixes(
        actual.eqEditRecords.map(\.payload),
        expected.eqEditPayloadSuffixBytes
    )
    expectShapePayloadPrefixes(
        actual.eqEditArray.map(\.rawPayload),
        expected.eqEditPayloadPrefixBytes
    )
    expectShapePayloadSuffixes(
        actual.eqEditArray.map(\.rawPayload),
        expected.eqEditPayloadSuffixBytes
    )
    if let eqEditTextLengths = expected.eqEditTextLengths {
        expect(actual.eqEditArray.compactMap(\.equationTextLength)) == eqEditTextLengths
        expect(actual.eqEditArray.map { $0.equationTextRawPayload?.count }) ==
            eqEditTextLengths.map { Optional(Int($0) * MemoryLayout<WCHAR>.size) }
    }
    expectShapePayloadLengths(
        actual.eqEditArray.compactMap(\.equationTextLengthRawPayload),
        expected.eqEditTextLengthRawPayloadLengths
    )
    expectShapePayloadPrefixes(
        actual.eqEditArray.compactMap(\.equationTextLengthRawPayload),
        expected.eqEditTextLengthRawPayloadPrefixBytes
    )
    expectShapePayloadSuffixes(
        actual.eqEditArray.compactMap(\.equationTextLengthRawPayload),
        expected.eqEditTextLengthRawPayloadSuffixBytes
    )
    if let eqEditTexts = expected.eqEditTexts {
        expect(actual.eqEditArray.compactMap(\.equationText)) == eqEditTexts
    }
}

private func expectShapePayloadPrefix(_ actual: Data?, _ expected: [UInt8]?) {
    guard let actual, let expected else {
        return
    }
    expect(Array(actual.prefix(expected.count))) == expected
}

private func expectShapePayloadSuffix(_ actual: Data?, _ expected: [UInt8]?) {
    guard let actual, let expected else {
        return
    }
    expect(Array(actual.suffix(expected.count))) == expected
}

private func expectShapePayloadPrefixes(_ actual: [Data], _ expected: [[UInt8]]?) {
    guard let expected else {
        return
    }
    expect(actual.count) == expected.count
    let actualPrefixes = zip(actual, expected)
        .map { data, prefix in Array(data.prefix(prefix.count)) }
    expect(actualPrefixes) == expected
}

private func expectShapePayloadLengths(_ actual: [Data], _ expected: [Int]?) {
    guard let expected else {
        return
    }
    expect(actual.map(\.count)) == expected
}

private func expectShapePayloadSuffixes(_ actual: [Data], _ expected: [[UInt8]]?) {
    guard let expected else {
        return
    }
    expect(actual.count) == expected.count
    let actualSuffixes = zip(actual, expected)
        .map { data, suffix in Array(data.suffix(suffix.count)) }
    expect(actualSuffixes) == expected
}
