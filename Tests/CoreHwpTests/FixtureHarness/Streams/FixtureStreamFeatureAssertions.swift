import Nimble

func assertBinaryDataFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(binaryDataStreamHasPayloadSamples(expectations)) == true
    expect(expectations.docInfoBinData).notTo(beEmpty())
    expect(expectations.docInfoBinData?.allSatisfy(binDataHasPayloadSample) ?? false) == true
}

func binaryDataStreamHasPayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    guard let count = expectations.binaryDataCount,
          let names = expectations.binaryDataNames,
          let entryNames = expectations.binaryDataEntryNames,
          let streamIds = expectations.binaryDataStreamIds,
          let extensionNames = expectations.binaryDataExtensionNames,
          let payloadLengths = expectations.binaryDataPayloadLengths,
          let payloadPrefixes = expectations.binaryDataPayloadPrefixBytes,
          let payloadSuffixes = expectations.binaryDataPayloadSuffixBytes,
          let totalByteCount = expectations.binaryDataTotalByteCount
    else {
        return false
    }

    guard count > 0,
          names.count == count,
          entryNames == names,
          streamIds.count == count,
          extensionNames.count == count,
          payloadLengths.count == count,
          payloadPrefixes.count == count,
          payloadSuffixes.count == count,
          totalByteCount == payloadLengths.reduce(0, +),
          payloadLengths.allSatisfy({ $0 > 0 }),
          payloadPrefixes.allSatisfy({ !$0.isEmpty }),
          payloadSuffixes.allSatisfy({ !$0.isEmpty }),
          expectations.docInfoBinData?.count == count
    else {
        return false
    }

    for index in names.indices {
        guard binaryDataMetadataMatchesName(
            name: names[index],
            streamId: streamIds[index],
            extensionName: extensionNames[index]
        ) else {
            return false
        }
    }
    return true
}

private func binaryDataMetadataMatchesName(
    name: String,
    streamId: UInt16?,
    extensionName: String?
) -> Bool {
    let parts = name.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let streamId,
          let extensionName,
          !extensionName.isEmpty
    else {
        return false
    }

    let streamName = parts[0]
    let extensionPart = String(parts[1])
    guard streamName.hasPrefix("BIN"),
          extensionPart == extensionName
    else {
        return false
    }

    let digits = streamName.dropFirst(3)
    return digits.count == 4
        && digits.allSatisfy(\.isASCIIDigit)
        && UInt16(digits) == streamId
}

private extension Character {
    var isASCIIDigit: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.allSatisfy { (0x30 ... 0x39).contains($0.value) }
    }
}
