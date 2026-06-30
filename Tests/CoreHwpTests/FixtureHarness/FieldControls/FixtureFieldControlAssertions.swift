@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertFieldControls(
        _ expectations: [FixtureFieldControlExpectations],
        _ hwp: HwpFile
    ) {
        let actualControls = FixtureDerivedValues.fieldControls(from: hwp)
        assertFieldControls(expectations, actualControls)
    }

    static func assertFieldControls(
        _ expectations: [FixtureFieldControlExpectations],
        _ actualControls: [HwpFieldControl]
    ) {
        expect(actualControls.count) == expectations.count

        for (actual, expected) in zip(actualControls, expectations) {
            if let ctrlId = expected.ctrlId {
                expect(actual.ctrlId.rawValue) == ctrlId
            }
            if let ctrlIdName = expected.ctrlIdName {
                expect(String(describing: actual.ctrlId)) == ctrlIdName
            }
            if let semanticKind = expected.semanticKind {
                expect(actual.semanticKind.rawValue) == semanticKind
            }
            if let isMemoField = expected.isMemoField {
                expect(actual.isMemoField) == isMemoField
            }
            if let isRevisionField = expected.isRevisionField {
                expect(actual.isRevisionField) == isRevisionField
            }
            assertFieldControlTypedHeader(actual, expected)
            if let fieldParameter = expected.fieldParameter {
                expect(actual.fieldParameter) == fieldParameter
            }
            assertFieldParameterHeader(actual, expected)
            assertFieldParameterLength(actual, expected)
            assertFieldParameterRawPayload(actual, expected)
            assertFieldParameterRawTrailing(actual, expected)
            assertMemoParameter(actual.memoParameter, expected.memoParameter)
            assertRawPayload(actual, expected)
            assertRawTrailing(actual, expected)
            assertUnknownChildren(actual, expected)
        }
    }
}

private func assertFieldControlTypedHeader(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let properties = expected.properties {
        expect(actual.properties) == properties
        expect(actual.propertyInfo?.rawValue) == properties
    }
    if let propertyInitialState = expected.propertyInitialState {
        expect(actual.propertyInfo?.isInitialState) == propertyInitialState
    }
    if let extraProperties = expected.extraProperties {
        expect(actual.extraProperties) == extraProperties
    }
    if let commandCharacterCount = expected.commandCharacterCount {
        expect(actual.commandCharacterCount) == commandCharacterCount
    }
    if let command = expected.command {
        expect(actual.command) == command
    }
    assertCommandLength(actual, expected)
    assertCommandRawPayload(actual, expected)
    assertCommandRawTrailing(actual, expected)
    if let fieldId = expected.fieldId {
        expect(actual.fieldId) == fieldId
    }
    if let memoIndex = expected.memoIndex {
        expect(actual.memoIndex) == memoIndex
    }
}

private func assertCommandLength(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawLength = expected.commandLengthRawLength {
        expect(actual.commandLengthRawPayload?.count) == rawLength
    }
    if let rawPrefixBytes = expected.commandLengthRawPrefixBytes {
        let prefix = Array(actual.commandLengthRawPayload?.prefix(rawPrefixBytes.count) ?? Data())
        expect(prefix) == rawPrefixBytes
    }
    if let rawSuffixBytes = expected.commandLengthRawSuffixBytes {
        let suffix = Array(actual.commandLengthRawPayload?.suffix(rawSuffixBytes.count) ?? Data())
        expect(suffix) == rawSuffixBytes
    }
}

private func assertCommandRawPayload(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawLength = expected.commandRawPayloadLength {
        expect(actual.commandRawPayload?.count) == rawLength
    }
    if let rawPrefixBytes = expected.commandRawPayloadPrefixBytes {
        let prefix = Array(actual.commandRawPayload?.prefix(rawPrefixBytes.count) ?? Data())
        expect(prefix) == rawPrefixBytes
    }
    if let rawSuffixBytes = expected.commandRawPayloadSuffixBytes {
        let suffix = Array(actual.commandRawPayload?.suffix(rawSuffixBytes.count) ?? Data())
        expect(suffix) == rawSuffixBytes
    }
}

private func assertCommandRawTrailing(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawLength = expected.commandRawTrailingLength {
        expect(actual.commandRawTrailing?.count) == rawLength
    }
    if let rawPrefixBytes = expected.commandRawTrailingPrefixBytes {
        let prefix = Array(actual.commandRawTrailing?.prefix(rawPrefixBytes.count) ?? Data())
        expect(prefix) == rawPrefixBytes
    }
    if let rawSuffixBytes = expected.commandRawTrailingSuffixBytes {
        let suffix = Array(actual.commandRawTrailing?.suffix(rawSuffixBytes.count) ?? Data())
        expect(suffix) == rawSuffixBytes
    }
}

private func assertFieldParameterHeader(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawLength = expected.fieldParameterHeaderRawLength {
        expect(actual.fieldParameterHeaderRawPayload?.count) == rawLength
    }
    if let rawPrefixBytes = expected.fieldParameterHeaderRawPrefixBytes {
        let prefix = Array(
            actual.fieldParameterHeaderRawPayload?.prefix(rawPrefixBytes.count) ?? Data()
        )
        expect(prefix) == rawPrefixBytes
    }
    if let rawSuffixBytes = expected.fieldParameterHeaderRawSuffixBytes {
        let suffix = Array(
            actual.fieldParameterHeaderRawPayload?.suffix(rawSuffixBytes.count) ?? Data()
        )
        expect(suffix) == rawSuffixBytes
    }
}

private func assertFieldParameterLength(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let characterCount = expected.fieldParameterCharacterCount {
        expect(actual.fieldParameterCharacterCount) == characterCount
    }
    if let rawLength = expected.fieldParameterLengthRawLength {
        expect(actual.fieldParameterLengthRawPayload?.count) == rawLength
    }
    if let rawPrefixBytes = expected.fieldParameterLengthRawPrefixBytes {
        let prefix = Array(
            actual.fieldParameterLengthRawPayload?.prefix(rawPrefixBytes.count) ?? Data()
        )
        expect(prefix) == rawPrefixBytes
    }
    if let rawSuffixBytes = expected.fieldParameterLengthRawSuffixBytes {
        let suffix = Array(
            actual.fieldParameterLengthRawPayload?.suffix(rawSuffixBytes.count) ?? Data()
        )
        expect(suffix) == rawSuffixBytes
    }
}

private func assertMemoParameter(
    _ actual: HwpMemoFieldParameter?,
    _ expected: FixtureMemoFieldParameterExpectations?
) {
    guard let expected else {
        return
    }
    if let rawValue = expected.rawValue {
        expect(actual?.rawValue) == rawValue
    }
    assertMemoParameterRawPayload(actual, expected)
    if let marker = expected.marker {
        expect(actual?.marker) == marker
    }
    if let components = expected.components {
        expect(actual?.components) == components
    }
    if let fields = expected.fields {
        expect(actual?.fields) == fields
    }
    if let author = expected.author {
        expect(actual?.author) == author
    }
    if let rawTrailingLength = expected.rawTrailingLength {
        expect(actual?.rawTrailing.count) == rawTrailingLength
    }
    if let rawTrailingPrefixBytes = expected.rawTrailingPrefixBytes {
        let prefix = Array(actual?.rawTrailing.prefix(rawTrailingPrefixBytes.count) ?? Data())
        expect(prefix) == rawTrailingPrefixBytes
    }
    if let rawTrailingSuffixBytes = expected.rawTrailingSuffixBytes {
        let suffix = Array(actual?.rawTrailing.suffix(rawTrailingSuffixBytes.count) ?? Data())
        expect(suffix) == rawTrailingSuffixBytes
    }
}

private func assertMemoParameterRawPayload(
    _ actual: HwpMemoFieldParameter?,
    _ expected: FixtureMemoFieldParameterExpectations
) {
    if let rawPayloadLength = expected.rawPayloadLength {
        expect(actual?.rawPayload.count) == rawPayloadLength
    }
    if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
        let prefix = Array(actual?.rawPayload.prefix(rawPayloadPrefixBytes.count) ?? Data())
        expect(prefix) == rawPayloadPrefixBytes
    }
    if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
        let suffix = Array(actual?.rawPayload.suffix(rawPayloadSuffixBytes.count) ?? Data())
        expect(suffix) == rawPayloadSuffixBytes
    }
}

private func assertFieldParameterRawPayload(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let fieldParameterRawPayloadLength = expected.fieldParameterRawPayloadLength {
        expect(actual.fieldParameterRawPayload?.count) == fieldParameterRawPayloadLength
    }
    if let fieldParameterRawPayloadPrefixBytes = expected.fieldParameterRawPayloadPrefixBytes {
        let prefix = Array(
            actual.fieldParameterRawPayload?.prefix(fieldParameterRawPayloadPrefixBytes.count)
                ?? Data()
        )
        expect(prefix) == fieldParameterRawPayloadPrefixBytes
    }
    if let fieldParameterRawPayloadSuffixBytes = expected.fieldParameterRawPayloadSuffixBytes {
        let suffix = Array(
            actual.fieldParameterRawPayload?.suffix(fieldParameterRawPayloadSuffixBytes.count)
                ?? Data()
        )
        expect(suffix) == fieldParameterRawPayloadSuffixBytes
    }
}

private func assertFieldParameterRawTrailing(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let fieldParameterRawTrailingLength = expected.fieldParameterRawTrailingLength {
        expect(actual.fieldParameterRawTrailing?.count) == fieldParameterRawTrailingLength
    }
    if let fieldParameterRawTrailingPrefixBytes = expected.fieldParameterRawTrailingPrefixBytes {
        let prefix = Array(
            actual.fieldParameterRawTrailing?.prefix(fieldParameterRawTrailingPrefixBytes.count)
                ?? Data()
        )
        expect(prefix) == fieldParameterRawTrailingPrefixBytes
    }
    if let fieldParameterRawTrailingSuffixBytes = expected.fieldParameterRawTrailingSuffixBytes {
        let suffix = Array(
            actual.fieldParameterRawTrailing?.suffix(fieldParameterRawTrailingSuffixBytes.count)
                ?? Data()
        )
        expect(suffix) == fieldParameterRawTrailingSuffixBytes
    }
}

private func assertRawPayload(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawPayloadLength = expected.rawPayloadLength {
        expect(actual.rawPayload.count) == rawPayloadLength
    }
    if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
        let prefix = Array(actual.rawPayload.prefix(rawPayloadPrefixBytes.count))
        expect(prefix) == rawPayloadPrefixBytes
    }
    if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
        let suffix = Array(actual.rawPayload.suffix(rawPayloadSuffixBytes.count))
        expect(suffix) == rawPayloadSuffixBytes
    }
}

private func assertRawTrailing(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
) {
    if let rawTrailingLength = expected.rawTrailingLength {
        expect(actual.rawTrailing.count) == rawTrailingLength
    }
    if let rawTrailingPrefixBytes = expected.rawTrailingPrefixBytes {
        let prefix = Array(actual.rawTrailing.prefix(rawTrailingPrefixBytes.count))
        expect(prefix) == rawTrailingPrefixBytes
    }
    if let rawTrailingSuffixBytes = expected.rawTrailingSuffixBytes {
        let suffix = Array(actual.rawTrailing.suffix(rawTrailingSuffixBytes.count))
        expect(suffix) == rawTrailingSuffixBytes
    }
}

private func assertUnknownChildren(
    _ actual: HwpFieldControl,
    _ expected: FixtureFieldControlExpectations
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
