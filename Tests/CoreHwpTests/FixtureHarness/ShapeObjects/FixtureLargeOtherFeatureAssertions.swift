import Nimble

func assertLargeDocumentFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.sectionCount ?? 0).to(beGreaterThan(10))
    expect(expectations.allParagraphCount ?? 0).to(beGreaterThan(1000))
    expect(expectations.allControlCount ?? 0).to(beGreaterThan(1000))
    expect(expectations.sectionRawPayloadTotalByteCount ?? 0).to(beGreaterThan(1_000_000))
    expect(expectations.previewTextRawPayloadLength ?? 0).to(beGreaterThan(0))
    expect(expectations.previewImageLength ?? 0).to(beGreaterThan(0))
}

func assertOtherKnownControlFeatureExpectations(_ expectations: FixtureExpectations) {
    let expectedControlNames = [
        "autoNumber",
        "newNumber",
        "pageHide",
        "indexmark",
        "hiddenComment",
    ]

    for controlName in expectedControlNames {
        expect(expectations.allControlTypeCounts?[controlName] ?? 0).to(beGreaterThan(0))
    }

    let samples = expectations.otherControlSamples ?? []
    let sampleNames = Set(samples.compactMap(\.ctrlIdName))
    expect(expectedControlNames.allSatisfy { sampleNames.contains($0) }) == true
    expect(samples.allSatisfy(otherControlHasPayloadSamples)) == true

    let hiddenComment = samples.first { $0.ctrlIdName == "hiddenComment" }
    expect(hiddenComment?.unknownChildCount ?? 0).to(beGreaterThan(0))
    expect(hiddenComment.map(otherControlHasPayloadSamples) ?? false) == true

    let pageHide = samples.first { $0.ctrlIdName == "pageHide" }
    expect(pageHide?.pageHideRawValue).notTo(beNil())
    expect(pageHide?.pageHideRawTrailingLength).notTo(beNil())

    let indexmark = samples.first { $0.ctrlIdName == "indexmark" }
    expect(indexmark?.indexmarkText).notTo(beNil())
    expect(indexmark?.indexmarkTextCharacterCount).notTo(beNil())
    expect(indexmark?.indexmarkTextLengthRawPayloadLength).notTo(beNil())
    expect(indexmark?.indexmarkTextRawPayloadLength).notTo(beNil())
    expect(indexmark?.indexmarkRawTrailingLength).notTo(beNil())
}

func assertAutoNumberFeatureExpectations(_ expectations: FixtureExpectations) {
    let control = expectOtherControlSample(named: "autoNumber", expectations)
    expect(control?.numberingKind).notTo(beNil())
    expect(control?.numberingValue).notTo(beNil())
    expect(control?.numberingFormat).notTo(beNil())
    expect(control?.numberingRawTrailingLength).notTo(beNil())
}

func assertNewNumberFeatureExpectations(_ expectations: FixtureExpectations) {
    expectOtherControlSample(named: "newNumber", expectations)
}

func assertPageHideFeatureExpectations(_ expectations: FixtureExpectations) {
    let control = expectOtherControlSample(named: "pageHide", expectations)
    expect(control?.pageHideRawValue).notTo(beNil())
    expect(control?.pageHideRawTrailingLength).notTo(beNil())
}

func assertIndexmarkFeatureExpectations(_ expectations: FixtureExpectations) {
    let control = expectOtherControlSample(named: "indexmark", expectations)
    expect(control?.indexmarkText).notTo(beNil())
    expect(control?.indexmarkTextCharacterCount).notTo(beNil())
    expect(control?.indexmarkTextLengthRawPayloadLength).notTo(beNil())
    expect(control?.indexmarkTextRawPayloadLength).notTo(beNil())
    expect(control?.indexmarkRawTrailingLength).notTo(beNil())
}

func assertHiddenCommentFeatureExpectations(_ expectations: FixtureExpectations) {
    let control = expectOtherControlSample(named: "hiddenComment", expectations)
    expect(control?.unknownChildCount ?? 0).to(beGreaterThan(0))
}

@discardableResult
private func expectOtherControlSample(
    named controlName: String,
    _ expectations: FixtureExpectations
) -> FixtureOtherControlExpectations? {
    expect(expectations.allControlTypeCounts?[controlName] ?? 0).to(beGreaterThan(0))
    let control = expectations.otherControlSamples?.first { $0.ctrlIdName == controlName }
    expect(control).notTo(beNil())
    expect(control.map(otherControlHasPayloadSamples) ?? false) == true
    return control
}
