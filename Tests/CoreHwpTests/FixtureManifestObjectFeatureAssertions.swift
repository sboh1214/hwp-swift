@testable import CoreHwp
import Nimble

func assertObjectBodyFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("image") {
        expect(imageFeatureHasObjectAndBinaryDataSamples(expectations)) == true
    }
    if features.contains("chart") {
        expect(chartFeatureHasOleAndBinaryDataSamples(expectations)) == true
    }
    if features.contains("shape-object") || features.contains("embedded-image-reference") {
        expect(expectations.genShapeObjects).notTo(beEmpty())
        expect(expectations.genShapeObjects?.allSatisfy(genShapeObjectHasPayloadSamples) ?? false)
            == true
    }
    if features.contains("text-box") {
        expect(expectations.genShapeObjects).notTo(beEmpty())
        expect(expectations.genShapeObjects?.contains(where: genShapeObjectHasTextBoxComponent))
            == true
    }
    if features.contains("embedded-image-reference") {
        expect(expectations.genShapeObjects?.contains(where: genShapeObjectHasPictureComponent))
            == true
    }
    if features.contains("legacy-common-control-property") {
        let hasLegacyExpectation = expectations.genShapeObjects?.contains {
            $0.rawPayloadLength == 44
                && $0.rawTrailingLength == 0
                && genShapeObjectHasLegacyPolygonComponent($0)
        } ?? false
        expect(hasLegacyExpectation) == true
    }
}

func chartFeatureHasOleAndBinaryDataSamples(_ expectations: FixtureExpectations) -> Bool {
    let hasObjectSamples = expectations.genShapeObjects?.isEmpty == false
        && (expectations.genShapeObjects?.allSatisfy(genShapeObjectHasPayloadSamples) ?? false)
    let hasOleReference = expectations.genShapeObjects?.contains {
        genShapeObjectHasOleComponent($0)
    } ?? false

    return (expectations.allControlTypeCounts?["genShapeObject"] ?? 0) > 0
        && hasObjectSamples
        && hasOleReference
        && expectations.binaryDataEntryNames == expectations.binaryDataNames
        && binaryDataStreamHasPayloadSamples(expectations)
}

func imageFeatureHasObjectAndBinaryDataSamples(_ expectations: FixtureExpectations) -> Bool {
    let hasObjectSamples = expectations.genShapeObjects?.isEmpty == false
        && (expectations.genShapeObjects?.allSatisfy(genShapeObjectHasPayloadSamples) ?? false)
    let hasImageReference = expectations.genShapeObjects?.contains {
        genShapeObjectHasPictureComponent($0) || genShapeObjectHasOleComponent($0)
    } ?? false

    return hasObjectSamples
        && hasImageReference
        && binaryDataStreamHasPayloadSamples(expectations)
}

func genShapeObjectHasOleComponent(_ object: FixtureGenShapeObjectExpectations) -> Bool {
    object.shapeComponents?.contains {
        $0.ctrlId == HwpCommonCtrlId.ole.rawValue
            && $0.ctrlIdName == "ole"
            && countedPayloadSampleArraysAreDeclared(
                count: $0.oleCount,
                lengths: $0.olePayloadLengths,
                prefixes: $0.olePayloadPrefixBytes,
                suffixes: $0.olePayloadSuffixBytes
            )
            && countedPayloadSampleArraysAreDeclared(
                count: $0.oleCount,
                lengths: $0.oleRawTrailingLengths,
                prefixes: $0.oleRawTrailingPrefixBytes,
                suffixes: $0.oleRawTrailingSuffixBytes
            )
            && binaryDataIdsAreDeclared(count: $0.oleCount, ids: $0.oleBinaryDataIds)
    } ?? false
}

func genShapeObjectHasTextBoxComponent(
    _ object: FixtureGenShapeObjectExpectations
) -> Bool {
    object.shapeComponents?.contains {
        $0.ctrlId == HwpCommonCtrlId.rectangle.rawValue
            && $0.ctrlIdName == "rectangle"
            && textBoxParagraphCountsAreDeclared($0)
            && ($0.textBoxVisibleTextContains?.isEmpty == false)
            && textBoxListHeaderPayloadSamplesAreDeclared($0)
            && rectanglePayloadSamplesAreDeclared($0)
            && $0.unknownChildCount == 0
    } ?? false
}

private func textBoxParagraphCountsAreDeclared(
    _ component: FixtureShapeComponentExpectations
) -> Bool {
    guard let listCount = component.textBoxListCount,
          let paragraphCounts = component.textBoxParagraphCounts,
          listCount > 0
    else {
        return false
    }
    return paragraphCounts.count == listCount
        && paragraphCounts.allSatisfy { $0 > 0 }
}

private func textBoxListHeaderPayloadSamplesAreDeclared(
    _ component: FixtureShapeComponentExpectations
) -> Bool {
    countedPayloadSampleArraysAreDeclared(
        count: component.textBoxListCount,
        lengths: component.textBoxListHeaderRawPayloadLengths,
        prefixes: component.textBoxListHeaderRawPayloadPrefixBytes,
        suffixes: component.textBoxListHeaderRawPayloadSuffixBytes
    )
}

private func rectanglePayloadSamplesAreDeclared(
    _ component: FixtureShapeComponentExpectations
) -> Bool {
    countedPayloadSampleArraysAreDeclared(
        count: component.rectangleCount,
        lengths: component.rectangleRawPayloadLengths,
        prefixes: component.rectangleRawPayloadPrefixBytes,
        suffixes: component.rectangleRawPayloadSuffixBytes
    )
}

func genShapeObjectHasLegacyPolygonComponent(
    _ object: FixtureGenShapeObjectExpectations
) -> Bool {
    object.shapeComponents?.contains {
        $0.ctrlId == HwpCommonCtrlId.polygon.rawValue
            && $0.ctrlIdName == "polygon"
            && countedPayloadSampleArraysAreDeclared(
                count: $0.polygonCount,
                lengths: $0.polygonRawPayloadLengths,
                prefixes: $0.polygonRawPayloadPrefixBytes,
                suffixes: $0.polygonRawPayloadSuffixBytes
            )
    } ?? false
}

private func countedPayloadSampleArraysAreDeclared(
    count: Int?,
    lengths: [Int]?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?
) -> Bool {
    guard let count, count > 0 else {
        return false
    }
    return countedPayloadSamplesAreDeclared(
        count: count,
        lengths: lengths,
        prefixes: prefixes,
        suffixes: suffixes
    )
}

func genShapeObjectHasPictureComponent(
    _ object: FixtureGenShapeObjectExpectations
) -> Bool {
    object.shapeComponents?.contains {
        $0.ctrlId == HwpCommonCtrlId.picture.rawValue
            && $0.ctrlIdName == "picture"
            && countedPayloadSampleArraysAreDeclared(
                count: $0.pictureCount,
                lengths: $0.pictureRawPayloadLengths,
                prefixes: $0.pictureRawPayloadPrefixBytes,
                suffixes: $0.pictureRawPayloadSuffixBytes
            )
            && countedPayloadSampleArraysAreDeclared(
                count: $0.pictureCount,
                lengths: $0.pictureRawTrailingLengths,
                prefixes: $0.pictureRawTrailingPrefixBytes,
                suffixes: $0.pictureRawTrailingSuffixBytes
            )
            && binaryDataIdsAreDeclared(count: $0.pictureCount, ids: $0.pictureBinaryDataIds)
    } ?? false
}

private func binaryDataIdsAreDeclared(count: Int?, ids: [UInt16]?) -> Bool {
    binaryDataIdsAreDeclared(count: count, idCount: ids?.count)
}

private func binaryDataIdsAreDeclared(count: Int?, ids: [UInt32]?) -> Bool {
    binaryDataIdsAreDeclared(count: count, idCount: ids?.count)
}

private func binaryDataIdsAreDeclared(count: Int?, idCount: Int?) -> Bool {
    guard let count, let idCount, count > 0 else {
        return false
    }
    return idCount == count
}
