// swiftlint:disable file_length

import CoreHwp
import Nimble

func assertPageNumberFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.pageNumberPositions).notTo(beEmpty())
    let hasPayloadSamples = expectations.pageNumberPositions?
        .allSatisfy(pageNumberPositionHasPayloadSamples) ?? false
    expect(hasPayloadSamples) == true
}

func assertFootnoteEndnoteFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.allControlTypeCounts?["footnote"] ?? 0).to(beGreaterThan(0))
    expect(expectations.allControlTypeCounts?["endnote"] ?? 0).to(beGreaterThan(0))
    expect(expectations.listControls?.map(\.kind)).to(contain("footnote"))
    expect(expectations.listControls?.map(\.kind)).to(contain("endnote"))
    expect(expectations.listControls?.allSatisfy(listControlHasPayloadSamples) ?? false) == true
    expect(expectations.allControlTypeCounts?["autoNumber"] ?? 0).to(beGreaterThan(0))
    expect(expectations.otherControls?.allSatisfy(otherControlHasTypedIdAndPayloadSamples) ?? false)
        == true
    expect(expectations.sections?.first.map(sectionHasFootnoteEndnoteSamples) ?? false) == true
    expect(expectations.visibleTextContains).notTo(beEmpty())
}

func assertColumnFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.columns).notTo(beEmpty())
    expect(expectations.columns?.allSatisfy(columnHasPayloadSamples) ?? false) == true
}

func rawDocInfoRecordHasPayloadSample(_ record: FixtureRawRecordExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: record.rawPayloadLength,
        prefix: record.rawPayloadPrefixBytes,
        suffix: record.rawPayloadSuffixBytes
    )
        && unknownChildPayloadSamplesAreDeclared(
            count: record.unknownChildCount,
            tagIds: record.unknownChildTagIds,
            lengths: record.unknownChildPayloadLengths,
            prefixes: record.unknownChildPayloadPrefixBytes,
            suffixes: record.unknownChildPayloadSuffixBytes
        )
        && countedPayloadSamplesAreDeclared(
            count: record.forbiddenCharCount,
            lengths: record.forbiddenCharPayloadLengths,
            prefixes: record.forbiddenCharPayloadPrefixBytes,
            suffixes: record.forbiddenCharPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: record.unknownChildChildTagIds,
            lengths: record.unknownChildChildPayloadLengths,
            prefixes: record.unknownChildChildPayloadPrefixBytes,
            suffixes: record.unknownChildChildPayloadSuffixBytes
        )
}

func compatibleDocumentHasPayloadSamples(
    _ compatibleDocument: FixtureCompatibleDocumentExpectations
) -> Bool {
    payloadSampleIsDeclared(
        length: compatibleDocument.rawPayloadLength,
        prefix: compatibleDocument.rawPayloadPrefixBytes,
        suffix: compatibleDocument.rawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: compatibleDocument.targetDocumentRawLength,
            prefix: compatibleDocument.targetDocumentRawPrefixBytes,
            suffix: compatibleDocument.targetDocumentRawSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
            count: compatibleDocument.unknownChildCount,
            tagIds: compatibleDocument.unknownChildTagIds,
            lengths: compatibleDocument.unknownChildPayloadLengths,
            prefixes: compatibleDocument.unknownChildPayloadPrefixBytes,
            suffixes: compatibleDocument.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: compatibleDocument.unknownChildChildTagIds,
            lengths: compatibleDocument.unknownChildChildPayloadLengths,
            prefixes: compatibleDocument.unknownChildChildPayloadPrefixBytes,
            suffixes: compatibleDocument.unknownChildChildPayloadSuffixBytes
        )
}

func assertLayoutCompatibilityFeatureExpectations(_ expectations: FixtureExpectations) {
    let hasCompatibleDocumentLayoutCompatibility =
        expectations.compatibleDocument.map(compatibleDocumentHasPayloadSamples) == true
            && expectations.compatibleDocument?.unknownChildTagIds != nil
            && expectations.compatibleDocument?.layoutCompatibility.map(
                layoutCompatibilityHasPayloadSample
            ) == true
    let hasTopLevelLayoutCompatibility = expectations.layoutCompatibility.map(
        layoutCompatibilityHasPayloadSample
    ) == true

    expect(hasCompatibleDocumentLayoutCompatibility || hasTopLevelLayoutCompatibility) == true
}

func layoutCompatibilityHasPayloadSample(
    _ layoutCompatibility: FixtureLayoutCompatibilityExpectations
) -> Bool {
    payloadSampleIsDeclared(
        length: layoutCompatibility.rawPayloadLength,
        prefix: layoutCompatibility.rawPayloadPrefixBytes,
        suffix: layoutCompatibility.rawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: layoutCompatibility.fixedFieldsRawLength,
            prefix: layoutCompatibility.fixedFieldsRawPrefixBytes,
            suffix: layoutCompatibility.fixedFieldsRawSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
            count: layoutCompatibility.unknownChildCount,
            tagIds: layoutCompatibility.unknownChildTagIds,
            lengths: layoutCompatibility.unknownChildPayloadLengths,
            prefixes: layoutCompatibility.unknownChildPayloadPrefixBytes,
            suffixes: layoutCompatibility.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: layoutCompatibility.unknownChildChildTagIds,
            lengths: layoutCompatibility.unknownChildChildPayloadLengths,
            prefixes: layoutCompatibility.unknownChildChildPayloadPrefixBytes,
            suffixes: layoutCompatibility.unknownChildChildPayloadSuffixBytes
        )
}

func documentPropertiesHaveSemanticValues(
    _ properties: FixtureDocumentPropertiesExpectations
) -> Bool {
    properties.sectionSize != nil
        && payloadSampleIsDeclared(
            length: properties.rawPayloadLength,
            prefix: properties.rawPayloadPrefixBytes,
            suffix: properties.rawPayloadSuffixBytes
        )
        && startingIndexHasSemanticValues(properties.startingIndex)
        && caratLocationHasSemanticValues(properties.caratLocation)
}

func docInfoMappingsHaveCoreEvidence(
    _ mappings: FixtureDocInfoIdMappingsExpectations
) -> Bool {
    mappings.binDataCount != nil
        && countOrRawTotalIsDeclared(
            mappings.faceNameKoreanCount,
            mappings.faceNameRawPayloadTotalByteCount
        )
        && countOrRawTotalIsDeclared(
            mappings.borderFillCount,
            mappings.borderFillRawPayloadTotalByteCount
        )
        && charShapeEvidenceIsDeclared(mappings)
        && countOrRawTotalIsDeclared(
            mappings.tabDefCount,
            mappings.tabDefRawPayloadTotalByteCount
        )
        && countOrRawTotalIsDeclared(
            mappings.paraShapeCount,
            mappings.paraShapeRawPayloadTotalByteCount
        )
}

private func charShapeEvidenceIsDeclared(
    _ mappings: FixtureDocInfoIdMappingsExpectations
) -> Bool {
    guard countOrRawTotalIsDeclared(
        mappings.charShapeCount,
        mappings.charShapeRawPayloadTotalByteCount
    ) else {
        return false
    }
    guard let charShapeCount = mappings.charShapeCount, charShapeCount > 0 else {
        return true
    }
    return mappings.charShapePropertyRawValues?.count == charShapeCount
}

private func startingIndexHasSemanticValues(
    _ startingIndex: FixtureStartingIndexExpectations?
) -> Bool {
    guard let startingIndex else {
        return false
    }
    return payloadSampleIsDeclared(
        length: startingIndex.rawPayloadLength,
        prefix: startingIndex.rawPayloadPrefixBytes,
        suffix: startingIndex.rawPayloadSuffixBytes
    )
        && startingIndex.page != nil
        && startingIndex.footnote != nil
        && startingIndex.endnote != nil
        && startingIndex.picture != nil
        && startingIndex.table != nil
        && startingIndex.equation != nil
}

private func caratLocationHasSemanticValues(
    _ caratLocation: FixtureCaratLocationExpectations?
) -> Bool {
    guard let caratLocation else {
        return false
    }
    return payloadSampleIsDeclared(
        length: caratLocation.rawPayloadLength,
        prefix: caratLocation.rawPayloadPrefixBytes,
        suffix: caratLocation.rawPayloadSuffixBytes
    )
        && caratLocation.listId != nil
        && caratLocation.paragraphId != nil
        && caratLocation.charIndex != nil
}

private func countOrRawTotalIsDeclared(_ count: Int?, _ rawTotal: Int?) -> Bool {
    count != nil || rawTotal != nil
}

func previewTextHasPayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    (expectations.previewTextLength ?? 0) > 0
        && payloadSampleIsDeclared(
            length: expectations.previewTextRawPayloadLength,
            prefix: expectations.previewTextPrefixBytes,
            suffix: expectations.previewTextSuffixBytes
        )
}

func previewImageHasFormatPayloadSamples(_ expectations: FixtureExpectations) -> Bool {
    previewImageFormatIsKnown(expectations.previewImageFormat)
        && previewImagePrefixMatchesFormat(
            expectations.previewImagePrefixBytes,
            expectations.previewImageFormat
        )
        && payloadSampleIsDeclared(
            length: expectations.previewImageLength,
            prefix: expectations.previewImagePrefixBytes,
            suffix: expectations.previewImageSuffixBytes
        )
}

private func previewImageFormatIsKnown(_ format: HwpPreviewImageFormat?) -> Bool {
    guard let format else {
        return false
    }
    return format != .none && format != .unknown
}

private func previewImagePrefixMatchesFormat(
    _ prefix: [UInt8]?,
    _ format: HwpPreviewImageFormat?
) -> Bool {
    guard let prefix, let format else {
        return false
    }

    let signature: [UInt8]
    switch format {
    case .bmp:
        signature = [0x42, 0x4D]
    case .gif:
        signature = [0x47, 0x49, 0x46, 0x38]
    case .png:
        signature = [0x89, 0x50, 0x4E, 0x47]
    case .jpeg:
        signature = [0xFF, 0xD8, 0xFF]
    case .none, .unknown:
        return false
    }
    return prefix.starts(with: signature)
}

func columnHasPayloadSamples(_ column: FixtureColumnExpectations) -> Bool {
    columnHasTypedId(column)
        && payloadSampleIsDeclared(
            length: column.rawPayloadLength,
            prefix: column.rawPayloadPrefixBytes,
            suffix: column.rawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: column.rawTrailingLength,
            prefix: column.rawTrailingPrefixBytes,
            suffix: column.rawTrailingSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
            count: column.unknownChildCount,
            tagIds: column.unknownChildTagIds,
            lengths: column.unknownChildPayloadLengths,
            prefixes: column.unknownChildPayloadPrefixBytes,
            suffixes: column.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: column.unknownChildChildTagIds,
            lengths: column.unknownChildChildPayloadLengths,
            prefixes: column.unknownChildChildPayloadPrefixBytes,
            suffixes: column.unknownChildChildPayloadSuffixBytes
        )
}

func columnHasTypedId(_ column: FixtureColumnExpectations) -> Bool {
    column.ctrlId != nil && column.ctrlIdName?.isEmpty == false
}

func pageNumberPositionHasPayloadSamples(
    _ position: FixturePageNumberPositionExpectations
) -> Bool {
    position.ctrlId != nil
        && position.ctrlIdName?.isEmpty == false
        && position.property != nil
        && position.userSymbol != nil
        && position.headDecoration != nil
        && position.tailDecoration != nil
        && position.unused != nil
        && position.unknown != nil
        && payloadSampleIsDeclared(
            length: position.rawPayloadLength,
            prefix: position.rawPayloadPrefixBytes,
            suffix: position.rawPayloadSuffixBytes
        )
        && payloadSampleIsDeclared(
            length: position.rawTrailingLength,
            prefix: position.rawTrailingPrefixBytes,
            suffix: position.rawTrailingSuffixBytes
        )
        && unknownChildPayloadSamplesAreDeclared(
            count: position.unknownChildCount,
            tagIds: position.unknownChildTagIds,
            lengths: position.unknownChildPayloadLengths,
            prefixes: position.unknownChildPayloadPrefixBytes,
            suffixes: position.unknownChildPayloadSuffixBytes
        )
        && nestedPayloadSampleArraysAreDeclared(
            tagIds: position.unknownChildChildTagIds,
            lengths: position.unknownChildChildPayloadLengths,
            prefixes: position.unknownChildChildPayloadPrefixBytes,
            suffixes: position.unknownChildChildPayloadSuffixBytes
        )
}

func otherControlHasTypedIdAndPayloadSamples(_ control: FixtureOtherControlExpectations) -> Bool {
    control.ctrlId != nil
        && control.ctrlIdName != nil
        && otherControlHasPayloadSamples(control)
}

func assertBookmarkFeatureExpectations(_ expectations: FixtureExpectations) {
    expect(expectations.allControlTypeCounts?["bookmark"] ?? 0).to(beGreaterThan(0))
    expect(expectations.otherControls).notTo(beEmpty())
    let otherControlsHaveTypedIds = expectations.otherControls?
        .allSatisfy(otherControlHasTypedIdAndPayloadSamples) ?? false
    expect(otherControlsHaveTypedIds) == true
    let bookmarkControlsHaveNames = expectations.otherControls?
        .filter { $0.ctrlId == HwpOtherCtrlId.bookmark.rawValue || $0.ctrlIdName == "bookmark" }
        .allSatisfy {
            $0.bookmarkName?.isEmpty == false
                && $0.bookmarkNameCharacterCount != nil
        } ?? false
    expect(bookmarkControlsHaveNames) == true
    expect(expectations.visibleTextContains).notTo(beEmpty())
}

func otherControlHasPayloadSamples(_ control: FixtureOtherControlExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: control.rawPayloadLength,
        prefix: control.rawPayloadPrefixBytes,
        suffix: control.rawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: control.rawTrailingLength,
            prefix: control.rawTrailingPrefixBytes,
            suffix: control.rawTrailingSuffixBytes
        )
        && bookmarkPayloadSamplesAreDeclared(control)
        && numberingPayloadSamplesAreDeclared(control)
        && indexmarkPayloadSamplesAreDeclared(control)
        && ctrlDataPayloadSamplesAreDeclared(control)
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

private func bookmarkPayloadSamplesAreDeclared(
    _ control: FixtureOtherControlExpectations
) -> Bool {
    control.bookmarkName == nil || payloadSampleIsDeclared(
        length: control.bookmarkNameLengthRawPayloadLength,
        prefix: control.bookmarkNameLengthRawPayloadPrefixBytes,
        suffix: control.bookmarkNameLengthRawPayloadSuffixBytes
    ) && payloadSampleIsDeclared(
        length: control.bookmarkNameRawPayloadLength,
        prefix: control.bookmarkNameRawPayloadPrefixBytes,
        suffix: control.bookmarkNameRawPayloadSuffixBytes
    ) && payloadSampleIsDeclared(
        length: control.bookmarkRawTrailingLength,
        prefix: control.bookmarkRawTrailingPrefixBytes,
        suffix: control.bookmarkRawTrailingSuffixBytes
    )
}

private func numberingPayloadSamplesAreDeclared(
    _ control: FixtureOtherControlExpectations
) -> Bool {
    !(control.numberingKind != nil
        || control.numberingValue != nil
        || control.numberingFormat != nil) || payloadSampleIsDeclared(
        length: control.numberingRawTrailingLength,
        prefix: control.numberingRawTrailingPrefixBytes,
        suffix: control.numberingRawTrailingSuffixBytes
    )
}

private func indexmarkPayloadSamplesAreDeclared(
    _ control: FixtureOtherControlExpectations
) -> Bool {
    control.indexmarkText == nil || payloadSampleIsDeclared(
        length: control.indexmarkTextLengthRawPayloadLength,
        prefix: control.indexmarkTextLengthRawPayloadPrefixBytes,
        suffix: control.indexmarkTextLengthRawPayloadSuffixBytes
    ) && payloadSampleIsDeclared(
        length: control.indexmarkTextRawPayloadLength,
        prefix: control.indexmarkTextRawPayloadPrefixBytes,
        suffix: control.indexmarkTextRawPayloadSuffixBytes
    ) && payloadSampleIsDeclared(
        length: control.indexmarkRawTrailingLength,
        prefix: control.indexmarkRawTrailingPrefixBytes,
        suffix: control.indexmarkRawTrailingSuffixBytes
    )
}

private func ctrlDataPayloadSamplesAreDeclared(
    _ control: FixtureOtherControlExpectations
) -> Bool {
    countedPayloadSamplesAreDeclared(
        count: control.ctrlDataCount,
        lengths: control.ctrlDataPayloadLengths,
        prefixes: control.ctrlDataPayloadPrefixBytes,
        suffixes: control.ctrlDataPayloadSuffixBytes
    )
}

func shapeControlHasPayloadSamples(_ control: FixtureShapeControlExpectations) -> Bool {
    payloadSampleIsDeclared(
        length: control.rawPayloadLength,
        prefix: control.rawPayloadPrefixBytes,
        suffix: control.rawPayloadSuffixBytes
    )
        && payloadSampleIsDeclared(
            length: control.rawTrailingLength,
            prefix: control.rawTrailingPrefixBytes,
            suffix: control.rawTrailingSuffixBytes
        )
        && control.commonCtrlPropertyRawPayloadLength != nil
        && control.commonCtrlPropertyRawPayloadPrefixBytes != nil
        && control.commonCtrlPropertyRawPayloadSuffixBytes != nil
        && control.ctrlId != nil
        && control.ctrlIdName != nil
        && payloadSampleArraysAreDeclared(
            lengths: control.eqEditPayloadLengths,
            prefixes: control.eqEditPayloadPrefixBytes,
            suffixes: control.eqEditPayloadSuffixBytes
        )
        && equationEditTextLengthPayloadSamplesAreDeclared(control)
        && payloadSampleArraysAreDeclared(
            lengths: control.ctrlDataPayloadLengths,
            prefixes: control.ctrlDataPayloadPrefixBytes,
            suffixes: control.ctrlDataPayloadSuffixBytes
        )
}

private func equationEditTextLengthPayloadSamplesAreDeclared(
    _ control: FixtureShapeControlExpectations
) -> Bool {
    guard let eqEditTextLengths = control.eqEditTextLengths else {
        return payloadSampleArraysAreDeclared(
            lengths: control.eqEditTextLengthRawPayloadLengths,
            prefixes: control.eqEditTextLengthRawPayloadPrefixBytes,
            suffixes: control.eqEditTextLengthRawPayloadSuffixBytes
        )
    }

    guard let lengths = control.eqEditTextLengthRawPayloadLengths else {
        return false
    }

    return lengths.count == eqEditTextLengths.count
        && lengths.allSatisfy { $0 == MemoryLayout<UInt16>.size }
        && payloadSampleArraysAreDeclared(
            lengths: lengths,
            prefixes: control.eqEditTextLengthRawPayloadPrefixBytes,
            suffixes: control.eqEditTextLengthRawPayloadSuffixBytes
        )
}

func genShapeObjectHasPayloadSamples(_ object: FixtureGenShapeObjectExpectations) -> Bool {
    object.ctrlId != nil
        && object.ctrlIdName != nil
        && object.commonCtrlPropertyRawPayloadLength != nil
        && object.commonCtrlPropertyRawPayloadPrefixBytes != nil
        && object.commonCtrlPropertyRawPayloadSuffixBytes != nil
        && object.rawPayloadLength != nil
        && object.rawPayloadPrefixBytes != nil
        && object.rawPayloadSuffixBytes != nil
        && object.rawTrailingLength != nil
        && object.rawTrailingPrefixBytes != nil
        && object.rawTrailingSuffixBytes != nil
        && (object.shapeComponents?.allSatisfy(shapeComponentHasPayloadSamples) ?? false)
        && payloadSampleArraysAreDeclared(
            lengths: object.ctrlDataPayloadLengths,
            prefixes: object.ctrlDataPayloadPrefixBytes,
            suffixes: object.ctrlDataPayloadSuffixBytes
        )
}

func shapeComponentHasPayloadSamples(_ component: FixtureShapeComponentExpectations) -> Bool {
    component.ctrlId != nil
        && component.ctrlIdName != nil
        && component.rawPayloadLength != nil
        && component.rawPayloadPrefixBytes != nil
        && component.rawPayloadSuffixBytes != nil
        && shapeComponentPicturePayloadSamplesAreDeclared(component)
        && shapeComponentOlePayloadSamplesAreDeclared(component)
        && payloadSampleArraysAreDeclared(
            lengths: component.rectangleRawPayloadLengths,
            prefixes: component.rectangleRawPayloadPrefixBytes,
            suffixes: component.rectangleRawPayloadSuffixBytes
        )
        && payloadSampleArraysAreDeclared(
            lengths: component.polygonRawPayloadLengths,
            prefixes: component.polygonRawPayloadPrefixBytes,
            suffixes: component.polygonRawPayloadSuffixBytes
        )
        && payloadSampleArraysAreDeclared(
            lengths: component.ctrlDataPayloadLengths,
            prefixes: component.ctrlDataPayloadPrefixBytes,
            suffixes: component.ctrlDataPayloadSuffixBytes
        )
}

private func shapeComponentPicturePayloadSamplesAreDeclared(
    _ component: FixtureShapeComponentExpectations
) -> Bool {
    countedPayloadSamplesAreDeclared(
        count: component.pictureCount,
        lengths: component.pictureRawPayloadLengths,
        prefixes: component.pictureRawPayloadPrefixBytes,
        suffixes: component.pictureRawPayloadSuffixBytes
    )
        && countedPayloadSamplesAreDeclared(
            count: component.pictureCount,
            lengths: component.pictureRawTrailingLengths,
            prefixes: component.pictureRawTrailingPrefixBytes,
            suffixes: component.pictureRawTrailingSuffixBytes
        )
        && binaryDataIdsAreDeclared(
            lengths: component.pictureRawPayloadLengths,
            idsCount: component.pictureBinaryDataIds?.count
        )
}

private func shapeComponentOlePayloadSamplesAreDeclared(
    _ component: FixtureShapeComponentExpectations
) -> Bool {
    countedPayloadSamplesAreDeclared(
        count: component.oleCount,
        lengths: component.olePayloadLengths,
        prefixes: component.olePayloadPrefixBytes,
        suffixes: component.olePayloadSuffixBytes
    )
        && countedPayloadSamplesAreDeclared(
            count: component.oleCount,
            lengths: component.oleRawTrailingLengths,
            prefixes: component.oleRawTrailingPrefixBytes,
            suffixes: component.oleRawTrailingSuffixBytes
        )
        && binaryDataIdsAreDeclared(
            lengths: component.olePayloadLengths,
            idsCount: component.oleBinaryDataIds?.count
        )
}
