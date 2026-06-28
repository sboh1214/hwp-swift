import Nimble

func assertFileHeaderPayloadSamples(_ expectations: FixtureExpectations) {
    expect(payloadSampleIsDeclared(
        length: expectations.fileHeaderRawPayloadLength,
        prefix: expectations.fileHeaderRawPayloadPrefixBytes,
        suffix: expectations.fileHeaderRawPayloadSuffixBytes
    )) == true
    expect(payloadSampleIsDeclared(
        length: expectations.fileHeaderReservedLength,
        prefix: expectations.fileHeaderReservedPrefixBytes,
        suffix: expectations.fileHeaderReservedSuffixBytes
    )) == true
    expect(expectations.fileHeaderVersionRawBytes?.count) == 4
}

func assertLicenseFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.fileProperty?.isCCLDocument) == true
    expect(expectations.fileProperty?.isKOGLDocument) == false
    expect(expectations.fileLicense.map(fileLicenseHasSemanticValues)) == true
    expect(expectations.encryptVersion).notTo(beNil())
    expect(expectations.koreaOpenLicense).notTo(beNil())
}

func assertKoglFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.fileProperty?.isKOGLDocument) == true
    expect(expectations.fileProperty?.isCCLDocument) == false
    expect(expectations.fileLicense.map(fileLicenseHasSemanticValues)) == true
    expect(expectations.encryptVersion).notTo(beNil())
    expect(expectations.koreaOpenLicense).notTo(beNil())
}

private func fileLicenseHasSemanticValues(
    _ license: FixtureFileLicenseExpectations
) -> Bool {
    license.rawValue != nil
        && license.doesHaveKoreaOpenLicense != nil
        && license.doesLimitReplication != nil
        && license.doesHavePermission != nil
}
