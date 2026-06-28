// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class FixturePayloadSampleDeclarationTests: XCTestCase {
    func testPayloadSampleDeclarationRequiresLengthBoundedSamples() {
        expect(payloadSampleIsDeclared(length: 2, prefix: [0xAA], suffix: [0xBB])) == true
        expect(payloadSampleIsDeclared(length: 0, prefix: [], suffix: [])) == true

        expect(payloadSampleIsDeclared(length: nil, prefix: [], suffix: [])) == false
        expect(payloadSampleIsDeclared(length: -1, prefix: [], suffix: [])) == false
        expect(payloadSampleIsDeclared(length: 2, prefix: [0xAA, 0xBB, 0xCC], suffix: [])) ==
            false
        expect(payloadSampleIsDeclared(length: 2, prefix: [], suffix: [])) == false
        expect(payloadSampleIsDeclared(length: 0, prefix: [0xAA], suffix: [])) == false
    }

    func testPayloadSampleArrayDeclarationRequiresAlignedLengthsAndSamples() {
        expect(payloadSampleArraysAreDeclared(
            lengths: [2, 0],
            prefixes: [[0xAA], []],
            suffixes: [[0xBB], []]
        )) == true
        expect(payloadSampleArraysAreDeclared(
            lengths: nil,
            prefixes: nil,
            suffixes: nil
        )) == true

        expect(payloadSampleArraysAreDeclared(
            lengths: nil,
            prefixes: [[]],
            suffixes: [[]]
        )) == false
        expect(payloadSampleArraysAreDeclared(
            lengths: [2],
            prefixes: [[0xAA]],
            suffixes: []
        )) == false
        expect(payloadSampleArraysAreDeclared(
            lengths: [1],
            prefixes: [[0xAA, 0xBB]],
            suffixes: [[0xCC]]
        )) == false
        expect(payloadSampleArraysAreDeclared(
            lengths: [1],
            prefixes: [[]],
            suffixes: [[0xCC]]
        )) == false
    }

    func testUnknownChildPayloadSampleDeclarationRequiresCountAlignedSamples() {
        expect(unknownChildPayloadSamplesAreDeclared(
            count: 2,
            tagIds: [0x201, 0x202],
            lengths: [2, 0],
            prefixes: [[0xAA], []],
            suffixes: [[0xBB], []]
        )) == true
        expect(unknownChildPayloadSamplesAreDeclared(
            count: 0,
            tagIds: [],
            lengths: [],
            prefixes: [],
            suffixes: []
        )) == true
        expect(unknownChildPayloadSamplesAreDeclared(
            count: nil,
            tagIds: nil,
            lengths: [2],
            prefixes: [[0xAA]],
            suffixes: [[0xBB]]
        )) == true

        expect(unknownChildPayloadSamplesAreDeclared(
            count: 1,
            tagIds: [],
            lengths: [2],
            prefixes: [[0xAA]],
            suffixes: [[0xBB]]
        )) == false
        expect(unknownChildPayloadSamplesAreDeclared(
            count: 1,
            tagIds: [0x201],
            lengths: [1],
            prefixes: [[0xAA, 0xBB]],
            suffixes: [[0xCC]]
        )) == false
        expect(unknownChildPayloadSamplesAreDeclared(
            count: 1,
            tagIds: [0x201],
            lengths: [1],
            prefixes: [[]],
            suffixes: [[0xCC]]
        )) == false
    }

    func testSectionUnknownRecordPayloadGateRequiresRawSamples() throws {
        let complete = try decodePayloadSampleExpectations("""
        {
          "sectionUnknownRecordCount": 1,
          "sectionUnknownRecordTagIds": [766],
          "sectionUnknownRecordPayloadLengths": [4],
          "sectionUnknownRecordPayloadPrefixBytes": [[202, 254]],
          "sectionUnknownRecordPayloadSuffixBytes": [[186, 190]],
          "sectionUnknownChildTagIds": [[765]],
          "sectionUnknownChildPayloadLengths": [[3]],
          "sectionUnknownChildPayloadPrefixBytes": [[[170, 187]]],
          "sectionUnknownChildPayloadSuffixBytes": [[[187, 204]]]
        }
        """)
        let missingPayloadSamples = try decodePayloadSampleExpectations("""
        {
          "sectionUnknownRecordCount": 1,
          "sectionUnknownRecordTagIds": [766]
        }
        """)
        let missingNestedSamples = try decodePayloadSampleExpectations("""
        {
          "sectionUnknownRecordCount": 1,
          "sectionUnknownRecordTagIds": [766],
          "sectionUnknownRecordPayloadLengths": [4],
          "sectionUnknownRecordPayloadPrefixBytes": [[202, 254]],
          "sectionUnknownRecordPayloadSuffixBytes": [[186, 190]],
          "sectionUnknownChildTagIds": [[765]]
        }
        """)

        expect(sectionUnknownRecordsHavePayloadSamples(complete)) == true
        expect(sectionUnknownRecordsHavePayloadSamples(missingPayloadSamples)) == false
        expect(sectionUnknownRecordsHavePayloadSamples(missingNestedSamples)) == false
    }

    func testParagraphUnknownChildPayloadGateRequiresRawSamples() throws {
        let complete = try decodePayloadSampleExpectations("""
        {
          "paragraphUnknownChildCount": 1,
          "paragraphUnknownChildTagIds": [764],
          "paragraphUnknownChildPayloadLengths": [4],
          "paragraphUnknownChildPayloadPrefixBytes": [[202, 254]],
          "paragraphUnknownChildPayloadSuffixBytes": [[186, 190]],
          "paragraphUnknownNestedTagIds": [[763]],
          "paragraphUnknownNestedPayloadLengths": [[3]],
          "paragraphUnknownNestedPayloadPrefixBytes": [[[170, 187]]],
          "paragraphUnknownNestedPayloadSuffixBytes": [[[187, 204]]]
        }
        """)
        let missingPayloadSamples = try decodePayloadSampleExpectations("""
        {
          "paragraphUnknownChildCount": 1,
          "paragraphUnknownChildTagIds": [764]
        }
        """)
        let missingNestedSamples = try decodePayloadSampleExpectations("""
        {
          "paragraphUnknownChildCount": 1,
          "paragraphUnknownChildTagIds": [764],
          "paragraphUnknownChildPayloadLengths": [4],
          "paragraphUnknownChildPayloadPrefixBytes": [[202, 254]],
          "paragraphUnknownChildPayloadSuffixBytes": [[186, 190]],
          "paragraphUnknownNestedTagIds": [[763]]
        }
        """)

        expect(paragraphUnknownChildrenHavePayloadSamples(complete)) == true
        expect(paragraphUnknownChildrenHavePayloadSamples(missingPayloadSamples)) == false
        expect(paragraphUnknownChildrenHavePayloadSamples(missingNestedSamples)) == false
    }

    func testCountedPayloadSampleDeclarationRequiresCountAlignedSamples() {
        expect(countedPayloadSamplesAreDeclared(
            count: 2,
            lengths: [2, 0],
            prefixes: [[0xAA], []],
            suffixes: [[0xBB], []]
        )) == true
        expect(countedPayloadSamplesAreDeclared(
            count: 0,
            lengths: [],
            prefixes: [],
            suffixes: []
        )) == true
        expect(countedPayloadSamplesAreDeclared(
            count: nil,
            lengths: [2],
            prefixes: [[0xAA]],
            suffixes: [[0xBB]]
        )) == true

        expect(countedPayloadSamplesAreDeclared(
            count: 1,
            lengths: nil,
            prefixes: nil,
            suffixes: nil
        )) == false
        expect(countedPayloadSamplesAreDeclared(
            count: 2,
            lengths: [2],
            prefixes: [[0xAA]],
            suffixes: [[0xBB]]
        )) == false
        expect(countedPayloadSamplesAreDeclared(
            count: 1,
            lengths: [1],
            prefixes: [[0xAA, 0xBB]],
            suffixes: [[0xCC]]
        )) == false
    }

    func testNestedPayloadSampleArrayDeclarationRequiresAlignedLengthsAndSamples() {
        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: [[2], [0]],
            prefixes: [[[0xAA]], [[]]],
            suffixes: [[[0xBB]], [[]]]
        )) == true
        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: nil,
            prefixes: nil,
            suffixes: nil
        )) == true

        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: nil,
            prefixes: [[[]]],
            suffixes: [[[]]]
        )) == false
        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: [[2]],
            prefixes: [[[0xAA]]],
            suffixes: []
        )) == false
        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: [[1]],
            prefixes: [[[0xAA, 0xBB]]],
            suffixes: [[[0xCC]]]
        )) == false
        expect(nestedPayloadSampleArraysAreDeclared(
            lengths: [[1]],
            prefixes: [[[]]],
            suffixes: [[[0xCC]]]
        )) == false
    }

    func testDocInfoMappingPayloadSampleHelpersRequireLengthBoundedSamples() {
        expect(styleHasPayloadSample(styleExpectation(length: 2, prefix: [0xAA], suffix: [0xBB])))
            == true
        expect(numberingHasPayloadSample(numberingExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB]
        ))) == true
        expect(bulletHasPayloadSample(bulletExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB]
        ))) == true
        expect(binDataHasPayloadSample(binDataExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB]
        ))) == true

        expect(styleHasPayloadSample(styleExpectation(
            length: 1,
            prefix: [0xAA, 0xBB],
            suffix: []
        ))) == false
        expect(numberingHasPayloadSample(numberingExpectation(
            length: 1,
            prefix: [],
            suffix: [0xBB]
        ))) == false
        expect(bulletHasPayloadSample(bulletExpectation(
            length: 0,
            prefix: [0xAA],
            suffix: []
        ))) == false
        expect(binDataHasPayloadSample(binDataExpectation(
            length: 1,
            prefix: [0xAA],
            suffix: []
        ))) == false
    }

    func testPreviewStreamPayloadSampleHelpersRequireLengthBoundedSamples() throws {
        let completePreviewText = try decodePayloadSampleExpectations("""
        {
          "previewTextLength": 1,
          "previewTextRawPayloadLength": 2,
          "previewTextPrefixBytes": [65, 0],
          "previewTextSuffixBytes": [65, 0]
        }
        """)
        let oversizedPreviewTextPrefix = try decodePayloadSampleExpectations("""
        {
          "previewTextLength": 1,
          "previewTextRawPayloadLength": 2,
          "previewTextPrefixBytes": [65, 0, 0],
          "previewTextSuffixBytes": [65, 0]
        }
        """)
        let completePreviewImage = try decodePayloadSampleExpectations("""
        {
          "previewImageLength": 8,
          "previewImageFormat": "png",
          "previewImagePrefixBytes": [137, 80, 78, 71, 13, 10, 26, 10],
          "previewImageSuffixBytes": [10]
        }
        """)
        let oversizedPreviewImageSuffix = try decodePayloadSampleExpectations("""
        {
          "previewImageLength": 8,
          "previewImageFormat": "png",
          "previewImagePrefixBytes": [137, 80, 78, 71, 13, 10, 26, 10],
          "previewImageSuffixBytes": [0, 1, 2, 3, 4, 5, 6, 7, 8]
        }
        """)

        expect(previewTextHasPayloadSamples(completePreviewText)) == true
        expect(previewTextHasPayloadSamples(oversizedPreviewTextPrefix)) == false
        expect(previewImageHasFormatPayloadSamples(completePreviewImage)) == true
        expect(previewImageHasFormatPayloadSamples(oversizedPreviewImageSuffix)) == false
    }

    func testBulletPayloadSampleHelperRequiresTrailingPayloadSamples() {
        expect(bulletHasPayloadSample(bulletExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: [0xCC],
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == true
        expect(bulletHasPayloadSample(bulletExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            charRawPayloadPrefixBytes: nil,
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: [0xCC],
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == false
        expect(bulletHasPayloadSample(bulletExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: nil,
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == false
    }

    func testStylePayloadSampleHelperRequiresTrailingPayloadSamples() {
        expect(styleHasPayloadSample(styleExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: [0xCC],
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == true
        expect(styleHasPayloadSample(styleExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            localNameRawPayloadPrefixBytes: nil,
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: [0xCC],
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == false
        expect(styleHasPayloadSample(styleExpectation(
            length: 2,
            prefix: [0xAA],
            suffix: [0xBB],
            undocumentedTrailingLength: 2,
            undocumentedTrailingPrefixBytes: nil,
            undocumentedTrailingSuffixBytes: [0xDD]
        ))) == false
    }

    func testOtherControlPayloadSampleHelperRequiresCountedCtrlDataPayloadSamples() {
        expect(otherControlHasPayloadSamples(otherControlExpectation(ctrlDataCount: 0))) == true
        expect(otherControlHasPayloadSamples(otherControlExpectation(ctrlDataCount: 1))) == false
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 1,
            ctrlDataPayloadLengths: [16],
            ctrlDataPayloadPrefixBytes: [[0xAA]],
            ctrlDataPayloadSuffixBytes: [[0xBB]]
        ))) == true
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 2,
            ctrlDataPayloadLengths: [16],
            ctrlDataPayloadPrefixBytes: [[0xAA]],
            ctrlDataPayloadSuffixBytes: [[0xBB]]
        ))) == false
    }

    func testOtherControlPayloadSampleHelperRequiresNumberingRawTrailingSamples() {
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 0,
            numberingKind: 1,
            numberingValue: 1,
            numberingFormat: 2_686_976
        ))) == false
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 0,
            numberingKind: 1,
            numberingValue: 1,
            numberingFormat: 2_686_976,
            numberingRawTrailingLength: 0,
            numberingRawTrailingPrefixBytes: [],
            numberingRawTrailingSuffixBytes: []
        ))) == true
    }

    func testOtherControlPayloadSampleHelperRequiresBookmarkRawTrailingSamples() {
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 0,
            bookmarkName: "CoreHwpBookmark",
            bookmarkNameCharacterCount: 15,
            bookmarkNameLengthRawPayloadLength: 2,
            bookmarkNameLengthRawPayloadPrefixBytes: [15, 0],
            bookmarkNameLengthRawPayloadSuffixBytes: [15, 0],
            bookmarkNameRawPayloadLength: 30,
            bookmarkNameRawPayloadPrefixBytes: [67, 0],
            bookmarkNameRawPayloadSuffixBytes: [107, 0]
        ))) == false
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 0,
            bookmarkName: "CoreHwpBookmark",
            bookmarkNameCharacterCount: 15,
            bookmarkRawTrailingLength: 0,
            bookmarkRawTrailingPrefixBytes: [],
            bookmarkRawTrailingSuffixBytes: []
        ))) == false
        expect(otherControlHasPayloadSamples(otherControlExpectation(
            ctrlDataCount: 0,
            bookmarkName: "CoreHwpBookmark",
            bookmarkNameCharacterCount: 15,
            bookmarkNameLengthRawPayloadLength: 2,
            bookmarkNameLengthRawPayloadPrefixBytes: [15, 0],
            bookmarkNameLengthRawPayloadSuffixBytes: [15, 0],
            bookmarkNameRawPayloadLength: 30,
            bookmarkNameRawPayloadPrefixBytes: [67, 0],
            bookmarkNameRawPayloadSuffixBytes: [107, 0],
            bookmarkRawTrailingLength: 0,
            bookmarkRawTrailingPrefixBytes: [],
            bookmarkRawTrailingSuffixBytes: []
        ))) == true
    }

    func testShapeControlPayloadSampleHelperRequiresEquationTextLengthRawSamples() {
        expect(shapeControlHasPayloadSamples(shapeControlExpectation(
            eqEditTextLengths: [3]
        ))) == false
        expect(shapeControlHasPayloadSamples(shapeControlExpectation(
            eqEditTextLengths: [3],
            eqEditTextLengthRawPayloadLengths: [1],
            eqEditTextLengthRawPayloadPrefixBytes: [[0x03]],
            eqEditTextLengthRawPayloadSuffixBytes: [[0x03]]
        ))) == false
        expect(shapeControlHasPayloadSamples(shapeControlExpectation(
            eqEditTextLengths: [3],
            eqEditTextLengthRawPayloadLengths: [2],
            eqEditTextLengthRawPayloadPrefixBytes: [[0x03, 0x00]],
            eqEditTextLengthRawPayloadSuffixBytes: [[0x03, 0x00]]
        ))) == true
    }
}

private func decodePayloadSampleExpectations(_ expectationsJSON: String) throws
    -> FixtureExpectations
{
    let json = """
    {
      "id": "synthetic-payload-samples",
      "generationTool": "synthetic",
      "hwpVersion": "5.0.1.1",
      "source": "unit-test",
      "features": ["synthetic"],
      "expectations": \(expectationsJSON)
    }
    """
    return try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8)).expectations
}

private func styleExpectation(
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?,
    localNameRawPayloadLength: Int? = 2,
    localNameRawPayloadPrefixBytes: [UInt8]? = [0xAA],
    localNameRawPayloadSuffixBytes: [UInt8]? = [0xBB],
    englishNameRawPayloadLength: Int? = 2,
    englishNameRawPayloadPrefixBytes: [UInt8]? = [0xCC],
    englishNameRawPayloadSuffixBytes: [UInt8]? = [0xDD],
    undocumentedTrailingLength: Int? = 0,
    undocumentedTrailingPrefixBytes: [UInt8]? = [],
    undocumentedTrailingSuffixBytes: [UInt8]? = []
) -> FixtureStyleExpectations {
    FixtureStyleExpectations(
        index: 0,
        localName: "바탕글",
        englishName: "Normal",
        localNameRawPayloadLength: localNameRawPayloadLength,
        localNameRawPayloadPrefixBytes: localNameRawPayloadPrefixBytes,
        localNameRawPayloadSuffixBytes: localNameRawPayloadSuffixBytes,
        englishNameRawPayloadLength: englishNameRawPayloadLength,
        englishNameRawPayloadPrefixBytes: englishNameRawPayloadPrefixBytes,
        englishNameRawPayloadSuffixBytes: englishNameRawPayloadSuffixBytes,
        property: nil,
        nextId: nil,
        languageId: nil,
        paraShapeId: nil,
        charShapeId: nil,
        unknownBytes: nil,
        undocumentedTrailingLength: undocumentedTrailingLength,
        undocumentedTrailingPrefixBytes: undocumentedTrailingPrefixBytes,
        undocumentedTrailingSuffixBytes: undocumentedTrailingSuffixBytes,
        rawPayloadLength: length,
        rawPayloadPrefixBytes: prefix,
        rawPayloadSuffixBytes: suffix
    )
}

private func numberingExpectation(
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?
) -> FixtureNumberingExpectations {
    FixtureNumberingExpectations(
        rawPayloadLength: length,
        rawPayloadPrefixBytes: prefix,
        rawPayloadSuffixBytes: suffix
    )
}

private func bulletExpectation(
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?,
    charRawPayloadLength: Int? = 2,
    charRawPayloadPrefixBytes: [UInt8]? = [0xAA],
    charRawPayloadSuffixBytes: [UInt8]? = [0xBB],
    checkCharRawPayloadLength: Int? = 2,
    checkCharRawPayloadPrefixBytes: [UInt8]? = [0xCC],
    checkCharRawPayloadSuffixBytes: [UInt8]? = [0xDD],
    undocumentedTrailingLength: Int? = 0,
    undocumentedTrailingPrefixBytes: [UInt8]? = [],
    undocumentedTrailingSuffixBytes: [UInt8]? = []
) -> FixtureBulletExpectations {
    FixtureBulletExpectations(
        rawPayloadLength: length,
        rawPayloadPrefixBytes: prefix,
        rawPayloadSuffixBytes: suffix,
        charRawPayloadLength: charRawPayloadLength,
        charRawPayloadPrefixBytes: charRawPayloadPrefixBytes,
        charRawPayloadSuffixBytes: charRawPayloadSuffixBytes,
        checkCharRawPayloadLength: checkCharRawPayloadLength,
        checkCharRawPayloadPrefixBytes: checkCharRawPayloadPrefixBytes,
        checkCharRawPayloadSuffixBytes: checkCharRawPayloadSuffixBytes,
        undocumentedTrailingLength: undocumentedTrailingLength,
        undocumentedTrailingPrefixBytes: undocumentedTrailingPrefixBytes,
        undocumentedTrailingSuffixBytes: undocumentedTrailingSuffixBytes
    )
}

private func binDataExpectation(
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?
) -> FixtureBinDataExpectations {
    FixtureBinDataExpectations(
        propertyRawValue: 1,
        type: "embedding",
        compressType: "none",
        state: "neverAccessed",
        streamId: 1,
        extensionName: "png",
        absolutePathRawPayloadLength: nil,
        absolutePathRawPayloadPrefixBytes: nil,
        absolutePathRawPayloadSuffixBytes: nil,
        relativePathRawPayloadLength: nil,
        relativePathRawPayloadPrefixBytes: nil,
        relativePathRawPayloadSuffixBytes: nil,
        extensionNameRawPayloadLength: nil,
        extensionNameRawPayloadPrefixBytes: nil,
        extensionNameRawPayloadSuffixBytes: nil,
        rawPayloadLength: length,
        rawPayloadPrefixBytes: prefix,
        rawPayloadSuffixBytes: suffix
    )
}

// swiftlint:disable:next function_body_length
private func otherControlExpectation(
    ctrlDataCount: Int?,
    bookmarkName: String? = nil,
    bookmarkNameCharacterCount: Int? = nil,
    bookmarkNameLengthRawPayloadLength: Int? = nil,
    bookmarkNameLengthRawPayloadPrefixBytes: [UInt8]? = nil,
    bookmarkNameLengthRawPayloadSuffixBytes: [UInt8]? = nil,
    bookmarkNameRawPayloadLength: Int? = nil,
    bookmarkNameRawPayloadPrefixBytes: [UInt8]? = nil,
    bookmarkNameRawPayloadSuffixBytes: [UInt8]? = nil,
    bookmarkRawTrailingLength: Int? = nil,
    bookmarkRawTrailingPrefixBytes: [UInt8]? = nil,
    bookmarkRawTrailingSuffixBytes: [UInt8]? = nil,
    numberingKind: UInt32? = nil,
    numberingValue: UInt32? = nil,
    numberingFormat: UInt32? = nil,
    numberingRawTrailingLength: Int? = nil,
    numberingRawTrailingPrefixBytes: [UInt8]? = nil,
    numberingRawTrailingSuffixBytes: [UInt8]? = nil,
    ctrlDataPayloadLengths: [Int]? = nil,
    ctrlDataPayloadPrefixBytes: [[UInt8]]? = nil,
    ctrlDataPayloadSuffixBytes: [[UInt8]]? = nil
) -> FixtureOtherControlExpectations {
    FixtureOtherControlExpectations(
        ctrlId: 1_651_469_165,
        ctrlIdName: "bookmark",
        occurrenceIndex: nil,
        bookmarkName: bookmarkName,
        bookmarkNameCharacterCount: bookmarkNameCharacterCount,
        bookmarkNameLengthRawPayloadLength: bookmarkNameLengthRawPayloadLength,
        bookmarkNameLengthRawPayloadPrefixBytes: bookmarkNameLengthRawPayloadPrefixBytes,
        bookmarkNameLengthRawPayloadSuffixBytes: bookmarkNameLengthRawPayloadSuffixBytes,
        bookmarkNameRawPayloadLength: bookmarkNameRawPayloadLength,
        bookmarkNameRawPayloadPrefixBytes: bookmarkNameRawPayloadPrefixBytes,
        bookmarkNameRawPayloadSuffixBytes: bookmarkNameRawPayloadSuffixBytes,
        bookmarkRawTrailingLength: bookmarkRawTrailingLength,
        bookmarkRawTrailingPrefixBytes: bookmarkRawTrailingPrefixBytes,
        bookmarkRawTrailingSuffixBytes: bookmarkRawTrailingSuffixBytes,
        numberingKind: numberingKind,
        numberingValue: numberingValue,
        numberingFormat: numberingFormat,
        numberingRawTrailingLength: numberingRawTrailingLength,
        numberingRawTrailingPrefixBytes: numberingRawTrailingPrefixBytes,
        numberingRawTrailingSuffixBytes: numberingRawTrailingSuffixBytes,
        pageHideRawValue: nil,
        pageHideRawTrailingLength: nil,
        pageHideRawTrailingPrefixBytes: nil,
        pageHideRawTrailingSuffixBytes: nil,
        indexmarkText: nil,
        indexmarkTextCharacterCount: nil,
        indexmarkTextLengthRawPayloadLength: nil,
        indexmarkTextLengthRawPayloadPrefixBytes: nil,
        indexmarkTextLengthRawPayloadSuffixBytes: nil,
        indexmarkTextRawPayloadLength: nil,
        indexmarkTextRawPayloadPrefixBytes: nil,
        indexmarkTextRawPayloadSuffixBytes: nil,
        indexmarkRawTrailingLength: nil,
        indexmarkRawTrailingPrefixBytes: nil,
        indexmarkRawTrailingSuffixBytes: nil,
        rawPayloadLength: 4,
        rawPayloadPrefixBytes: [0x6D, 0x6B],
        rawPayloadSuffixBytes: [0x6F, 0x62],
        rawTrailingLength: 0,
        rawTrailingPrefixBytes: [],
        rawTrailingSuffixBytes: [],
        ctrlDataCount: ctrlDataCount,
        ctrlDataPayloadLengths: ctrlDataPayloadLengths,
        ctrlDataPayloadPrefixBytes: ctrlDataPayloadPrefixBytes,
        ctrlDataPayloadSuffixBytes: ctrlDataPayloadSuffixBytes,
        unknownChildCount: 0,
        unknownChildTagIds: nil,
        unknownChildPayloadLengths: nil,
        unknownChildPayloadPrefixBytes: nil,
        unknownChildPayloadSuffixBytes: nil,
        unknownChildChildTagIds: nil,
        unknownChildChildPayloadLengths: nil,
        unknownChildChildPayloadPrefixBytes: nil,
        unknownChildChildPayloadSuffixBytes: nil
    )
}

private func shapeControlExpectation(
    eqEditTextLengths: [UInt16]?,
    eqEditTextLengthRawPayloadLengths: [Int]? = nil,
    eqEditTextLengthRawPayloadPrefixBytes: [[UInt8]]? = nil,
    eqEditTextLengthRawPayloadSuffixBytes: [[UInt8]]? = nil
) -> FixtureShapeControlExpectations {
    FixtureShapeControlExpectations(
        ctrlId: HwpCommonCtrlId.equation.rawValue,
        ctrlIdName: "equation",
        commonCtrlPropertyRawPayloadLength: 40,
        commonCtrlPropertyRawPayloadPrefixBytes: [0x65, 0x71],
        commonCtrlPropertyRawPayloadSuffixBytes: [0x00, 0x00],
        rawPayloadLength: 40,
        rawPayloadPrefixBytes: [0x65, 0x71],
        rawPayloadSuffixBytes: [0x00, 0x00],
        rawTrailingLength: 0,
        rawTrailingPrefixBytes: [],
        rawTrailingSuffixBytes: [],
        eqEditCount: 1,
        eqEditPayloadLengths: [8],
        eqEditPayloadPrefixBytes: [[0x00, 0x00]],
        eqEditPayloadSuffixBytes: [[0x78, 0x00]],
        eqEditTextLengths: eqEditTextLengths,
        eqEditTextLengthRawPayloadLengths: eqEditTextLengthRawPayloadLengths,
        eqEditTextLengthRawPayloadPrefixBytes: eqEditTextLengthRawPayloadPrefixBytes,
        eqEditTextLengthRawPayloadSuffixBytes: eqEditTextLengthRawPayloadSuffixBytes,
        eqEditTexts: nil,
        ctrlDataCount: 0,
        ctrlDataPayloadLengths: [],
        ctrlDataPayloadPrefixBytes: [],
        ctrlDataPayloadSuffixBytes: [],
        unknownChildCount: 0,
        unknownChildTagIds: nil,
        unknownChildPayloadLengths: nil,
        unknownChildPayloadPrefixBytes: nil,
        unknownChildPayloadSuffixBytes: nil,
        unknownChildChildTagIds: nil,
        unknownChildChildPayloadLengths: nil,
        unknownChildChildPayloadPrefixBytes: nil,
        unknownChildChildPayloadSuffixBytes: nil
    )
}
