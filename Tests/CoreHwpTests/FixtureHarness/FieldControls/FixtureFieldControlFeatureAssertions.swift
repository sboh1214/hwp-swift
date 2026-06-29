import CoreHwp
import Nimble

func fieldControlHasPayloadSamples(_ control: FixtureFieldControlExpectations) -> Bool {
    control.ctrlId != nil
        && control.ctrlIdName?.isEmpty == false
        && control.isRevisionField != nil
        && payloadSampleIsDeclared(
            length: control.rawPayloadLength,
            prefix: control.rawPayloadPrefixBytes,
            suffix: control.rawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: control.rawTrailingLength,
            prefix: control.rawTrailingPrefixBytes,
            suffix: control.rawTrailingSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
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

func assertMemoFeatureExpectations(_ expectations: FixtureExpectations) {
    let memoControlCount = expectations.allControlTypeCounts?["memo"] ?? 0
    let genericFieldControlCount = expectations.allControlTypeCounts?["field"] ?? 0
    expect(memoControlCount + genericFieldControlCount).to(beGreaterThan(0))
    expect(expectations.fieldControls).notTo(beEmpty())
    expect(expectations.fieldControls?.allSatisfy(fieldControlHasPayloadSamples) ?? false) == true

    let memoControls = expectations.fieldControls?.filter { control in
        control.semanticKind == HwpFieldControlKind.memo.rawValue || control.isMemoField == true
    } ?? []
    expect(memoControls).notTo(beEmpty())
    expect(memoControls.allSatisfy(memoFieldControlHasSemanticPayloadSamples)) == true
    expect(expectations.visibleTextContains).notTo(beEmpty())
}

func memoFieldControlHasSemanticPayloadSamples(
    _ control: FixtureFieldControlExpectations
) -> Bool {
    fieldControlHasPayloadSamples(control)
        && control.semanticKind == HwpFieldControlKind.memo.rawValue
        && control.isMemoField == true
        && control.fieldParameter?.isEmpty == false
        && payloadSampleIsDeclared(
            length: control.fieldParameterHeaderRawLength,
            prefix: control.fieldParameterHeaderRawPrefixBytes,
            suffix: control.fieldParameterHeaderRawSuffixBytes
        )
        && control.fieldParameterCharacterCount != nil
        && payloadSampleIsDeclared(
            length: control.fieldParameterLengthRawLength,
            prefix: control.fieldParameterLengthRawPrefixBytes,
            suffix: control.fieldParameterLengthRawSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: control.fieldParameterRawPayloadLength,
            prefix: control.fieldParameterRawPayloadPrefixBytes,
            suffix: control.fieldParameterRawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: control.fieldParameterRawTrailingLength,
            prefix: control.fieldParameterRawTrailingPrefixBytes,
            suffix: control.fieldParameterRawTrailingSuffixBytes
        )
        && memoFieldParameterHasPayloadSamples(control.memoParameter)
}

private func memoFieldParameterHasPayloadSamples(
    _ parameter: FixtureMemoFieldParameterExpectations?
) -> Bool {
    guard let parameter,
          let components = parameter.components,
          let fields = parameter.fields
    else {
        return false
    }

    return parameter.rawValue?.isEmpty == false
        && payloadSampleIsDeclared(
            length: parameter.rawPayloadLength,
            prefix: parameter.rawPayloadPrefixBytes,
            suffix: parameter.rawPayloadSuffixBytes
        )
        && parameter.marker == "MEMO"
        && components.first == "MEMO"
        && fields == Array(components.dropFirst())
        && fields.isEmpty == false
        && parameter.author?.isEmpty == false
        && payloadSampleIsDeclared(
            length: parameter.rawTrailingLength,
            prefix: parameter.rawTrailingPrefixBytes,
            suffix: parameter.rawTrailingSuffixBytes
        )
}
