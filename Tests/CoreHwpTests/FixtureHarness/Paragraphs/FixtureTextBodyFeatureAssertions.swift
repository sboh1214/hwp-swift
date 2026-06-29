@testable import CoreHwp
import Nimble

func assertTrackChangesBodyFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(trackChangesBodyHasPayloadSamples(expectations)) == true
}

func trackChangesBodyHasPayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    guard let controlIds = expectations.paraTextControlIds,
          let controlIdNames = expectations.paraTextControlIdNames,
          !controlIds.isEmpty,
          controlIdNames.count == controlIds.count,
          paraTextControlNamesMatchIds(controlIds, controlIdNames)
    else {
        return false
    }

    return paraTextControlPayloadSamplesAreDeclared(
        count: controlIds.count,
        lengths: expectations.paraTextControlPayloadLengths,
        prefixes: expectations.paraTextControlPayloadPrefixBytes,
        suffixes: expectations.paraTextControlPayloadSuffixBytes
    )
        && paraTextControlPayloadSamplesAreDeclared(
            count: controlIds.count,
            lengths: expectations.paraTextControlTrailingLengths,
            prefixes: expectations.paraTextControlTrailingPrefixBytes,
            suffixes: expectations.paraTextControlTrailingSuffixBytes
        )
}

private func paraTextControlNamesMatchIds(
    _ controlIds: [UInt32],
    _ controlIdNames: [String]
) -> Bool {
    zip(controlIds, controlIdNames).allSatisfy { controlId, controlIdName in
        paraTextControlName(for: controlId) == controlIdName
    }
}

private func paraTextControlName(for controlId: UInt32) -> String? {
    if let otherCtrlId = HwpOtherCtrlId(rawValue: controlId) {
        return String(describing: otherCtrlId)
    }
    if let commonCtrlId = HwpCommonCtrlId(rawValue: controlId) {
        return String(describing: commonCtrlId)
    }
    if let fieldCtrlId = HwpFieldCtrlId(rawValue: controlId) {
        return String(describing: fieldCtrlId)
    }
    return nil
}

private func paraTextControlPayloadSamplesAreDeclared(
    count: Int,
    lengths: [Int]?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard let lengths, let prefixes, let suffixes else {
        return false
    }

    return lengths.count == count
        && prefixes.count == count
        && suffixes.count == count
        && lengths.allSatisfy { $0 > 0 }
        && prefixes.allSatisfy { !$0.isEmpty }
        && suffixes.allSatisfy { !$0.isEmpty }
}
