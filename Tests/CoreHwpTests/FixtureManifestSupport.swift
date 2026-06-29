// swiftlint:disable file_length
import CoreHwp
import Foundation

struct FixtureManifest: Decodable {
    let id: String
    let generationTool: String
    let hwpVersion: String
    let source: String
    let features: [String]
    let expectations: FixtureExpectations
    let expectedError: FixtureExpectedError?
}

struct FixtureExpectations: Decodable {
    let fileProperty: FixtureFilePropertyExpectations?
    let fileLicense: FixtureFileLicenseExpectations?
    let fileHeaderRawPayloadLength: Int?
    let fileHeaderRawPayloadPrefixBytes: [UInt8]?
    let fileHeaderRawPayloadSuffixBytes: [UInt8]?
    let fileHeaderVersionRawBytes: [UInt8]?
    let fileHeaderReservedLength: Int?
    let fileHeaderReservedPrefixBytes: [UInt8]?
    let fileHeaderReservedSuffixBytes: [UInt8]?
    let documentProperties: FixtureDocumentPropertiesExpectations?
    let compatibleDocument: FixtureCompatibleDocumentExpectations?
    let layoutCompatibility: FixtureLayoutCompatibilityExpectations?
    let docInfoIdMappings: FixtureDocInfoIdMappingsExpectations?
    let docInfoRawRecords: FixtureDocInfoRawRecordsExpectations?
    let docInfoBinData: [FixtureBinDataExpectations]?
    let docInfoStyles: [FixtureStyleExpectations]?
    let docInfoNumberings: [FixtureNumberingExpectations]?
    let docInfoBullets: [FixtureBulletExpectations]?
    let hyperlinks: [FixtureHyperlinkExpectations]?
    let genShapeObjects: [FixtureGenShapeObjectExpectations]?
    let shapeControls: [FixtureShapeControlExpectations]?
    let tables: [FixtureTableExpectations]?
    let columns: [FixtureColumnExpectations]?
    let listControls: [FixtureListControlExpectations]?
    let pageNumberPositions: [FixturePageNumberPositionExpectations]?
    let sections: [FixtureSectionExpectations]?
    let preservedControls: [FixtureControlPreservationExpectations]?
    let preservedControlSamples: [FixtureControlPreservationExpectations]?
    let fieldControls: [FixtureFieldControlExpectations]?
    let otherControls: [FixtureOtherControlExpectations]?
    let otherControlSamples: [FixtureOtherControlExpectations]?
    let encryptVersion: UInt32?
    let koreaOpenLicense: UInt8?
    let sectionCount: Int?
    let sectionRawPayloadCount: Int?
    let sectionRawPayloadTotalByteCount: Int?
    let sectionRawPayloadPrefixBytes: [[UInt8]]?
    let sectionRawPayloadSuffixBytes: [[UInt8]]?
    let sectionParagraphCounts: [Int]?
    let sectionVisibleTexts: [String]?
    let paragraphCount: Int?
    let allParagraphCount: Int?
    let paraTextRawPayloadCount: Int?
    let paraTextRawPayloadTotalByteCount: Int?
    let paraTextRawPayloadPrefixBytes: [[UInt8]]?
    let paraTextRawPayloadSuffixBytes: [[UInt8]]?
    let paraTextPayloadCount: Int?
    let paraTextPayloadTotalByteCount: Int?
    let paraTextPayloadPrefixBytes: [[UInt8]]?
    let paraTextPayloadSuffixBytes: [[UInt8]]?
    let paraTextControlIds: [UInt32]?
    let paraTextControlIdNames: [String]?
    let paraTextControlPayloadLengths: [Int]?
    let paraTextControlPayloadPrefixBytes: [[UInt8]]?
    let paraTextControlPayloadSuffixBytes: [[UInt8]]?
    let paraTextControlTrailingLengths: [Int]?
    let paraTextControlTrailingPrefixBytes: [[UInt8]]?
    let paraTextControlTrailingSuffixBytes: [[UInt8]]?
    let paraHeaderPayloadCount: Int?
    let paraHeaderPayloadTotalByteCount: Int?
    let paraHeaderPayloadPrefixBytes: [[UInt8]]?
    let paraHeaderPayloadSuffixBytes: [[UInt8]]?
    let paraCharShapePayloadCount: Int?
    let paraCharShapePayloadTotalByteCount: Int?
    let paraCharShapePayloadPrefixBytes: [[UInt8]]?
    let paraCharShapePayloadSuffixBytes: [[UInt8]]?
    let paraLineSegPayloadCount: Int?
    let paraLineSegPayloadTotalByteCount: Int?
    let paraLineSegPayloadPrefixBytes: [[UInt8]]?
    let paraLineSegPayloadSuffixBytes: [[UInt8]]?
    let paraRangeTagCount: Int?
    let paraRangeTagPayloadTotalByteCount: Int?
    let paraRangeTags: [FixtureParaRangeTagExpectations]?
    let paragraphUnknownChildCount: Int?
    let paragraphUnknownChildTagIds: [UInt32]?
    let paragraphUnknownChildPayloadLengths: [Int]?
    let paragraphUnknownChildPayloadPrefixBytes: [[UInt8]]?
    let paragraphUnknownChildPayloadSuffixBytes: [[UInt8]]?
    let paragraphUnknownNestedTagIds: [[UInt32]]?
    let paragraphUnknownNestedPayloadLengths: [[Int]]?
    let paragraphUnknownNestedPayloadPrefixBytes: [[[UInt8]]]?
    let paragraphUnknownNestedPayloadSuffixBytes: [[[UInt8]]]?
    let sectionUnknownRecordCount: Int?
    let sectionUnknownRecordTagIds: [UInt32]?
    let sectionUnknownRecordPayloadLengths: [Int]?
    let sectionUnknownRecordPayloadPrefixBytes: [[UInt8]]?
    let sectionUnknownRecordPayloadSuffixBytes: [[UInt8]]?
    let sectionUnknownChildTagIds: [[UInt32]]?
    let sectionUnknownChildPayloadLengths: [[Int]]?
    let sectionUnknownChildPayloadPrefixBytes: [[[UInt8]]]?
    let sectionUnknownChildPayloadSuffixBytes: [[[UInt8]]]?
    let topLevelEntryNames: [String]?
    let bodyTextSectionEntryNames: [String]?
    let summaryLength: Int?
    let summaryPrefixBytes: [UInt8]?
    let summarySuffixBytes: [UInt8]?
    let previewTextLength: Int?
    let previewTextRawPayloadLength: Int?
    let previewTextPrefixBytes: [UInt8]?
    let previewTextSuffixBytes: [UInt8]?
    let previewTextContains: [String]?
    let previewImageLength: Int?
    let previewImageFormat: HwpPreviewImageFormat?
    let previewImagePrefixBytes: [UInt8]?
    let previewImageSuffixBytes: [UInt8]?
    let binaryDataCount: Int?
    let binaryDataNames: [String]?
    let binaryDataEntryNames: [String]?
    let binaryDataStreamIds: [UInt16?]?
    let binaryDataExtensionNames: [String?]?
    let binaryDataPayloadLengths: [Int]?
    let binaryDataPayloadPrefixBytes: [[UInt8]]?
    let binaryDataPayloadSuffixBytes: [[UInt8]]?
    let binaryDataTotalByteCount: Int?
    let docInfoRawPayloadLength: Int?
    let docInfoRawPayloadPrefixBytes: [UInt8]?
    let docInfoRawPayloadSuffixBytes: [UInt8]?
    let docInfoUnknownRecordCount: Int?
    let docInfoUnknownRecordTagIds: [UInt32]?
    let docInfoUnknownRecordPayloadLengths: [Int]?
    let docInfoUnknownRecordPayloadPrefixBytes: [[UInt8]]?
    let docInfoUnknownRecordPayloadSuffixBytes: [[UInt8]]?
    let docInfoUnknownChildTagIds: [[UInt32]]?
    let docInfoUnknownChildPayloadLengths: [[Int]]?
    let docInfoUnknownChildPayloadPrefixBytes: [[[UInt8]]]?
    let docInfoUnknownChildPayloadSuffixBytes: [[[UInt8]]]?
    let docInfoRawRecordCount: Int?
    let controlCount: Int?
    let allControlCount: Int?
    let visibleTextContains: [String]?
    let controlTypeCounts: [String: Int]?
    let allControlTypeCounts: [String: Int]?
}

struct FixtureDocumentPropertiesExpectations: Decodable {
    let sectionSize: UInt16?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let startingIndex: FixtureStartingIndexExpectations?
    let caratLocation: FixtureCaratLocationExpectations?
}

struct FixtureStartingIndexExpectations: Decodable {
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let page: UInt16?
    let footnote: UInt16?
    let endnote: UInt16?
    let picture: UInt16?
    let table: UInt16?
    let equation: UInt16?
}

struct FixtureCaratLocationExpectations: Decodable {
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let listId: UInt32?
    let paragraphId: UInt32?
    let charIndex: UInt32?
}

struct FixtureCompatibleDocumentExpectations: Decodable {
    let targetDocument: UInt32?
    let targetDocumentRawLength: Int?
    let targetDocumentRawPrefixBytes: [UInt8]?
    let targetDocumentRawSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
    let trackChanges: [FixtureRawRecordExpectations]?
    let layoutCompatibility: FixtureLayoutCompatibilityExpectations?
}

struct FixtureLayoutCompatibilityExpectations: Decodable {
    let char: UInt32?
    let paragraph: UInt32?
    let section: UInt32?
    let object: UInt32?
    let field: UInt32?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let fixedFieldsRawLength: Int?
    let fixedFieldsRawPrefixBytes: [UInt8]?
    let fixedFieldsRawSuffixBytes: [UInt8]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureDocInfoRawRecordsExpectations: Decodable {
    let docData: FixtureRawRecordExpectations?
    let distributeDocData: FixtureRawRecordExpectations?
    let trackChanges: [FixtureRawRecordExpectations]?
    let memoShapes: [FixtureRawRecordExpectations]?
    let trackChangeContents: [FixtureRawRecordExpectations]?
    let trackChangeAuthors: [FixtureRawRecordExpectations]?
    let forbiddenChars: [FixtureRawRecordExpectations]?
}

struct FixtureRawRecordExpectations: Decodable {
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let distributeDocDataValues: [UInt32]?
    let distributeDocDataValuesRawLength: Int?
    let distributeDocDataValuesRawPrefixBytes: [UInt8]?
    let distributeDocDataValuesRawSuffixBytes: [UInt8]?
    let distributeDocDataRawTrailingLength: Int?
    let distributeDocDataRawTrailingPrefixBytes: [UInt8]?
    let distributeDocDataRawTrailingSuffixBytes: [UInt8]?
    let docDataValues: [UInt32]?
    let docDataValuesRawLength: Int?
    let docDataValuesRawPrefixBytes: [UInt8]?
    let docDataValuesRawSuffixBytes: [UInt8]?
    let docDataRawTrailingLength: Int?
    let docDataRawTrailingPrefixBytes: [UInt8]?
    let docDataRawTrailingSuffixBytes: [UInt8]?
    let trackChangeHeaderValue: UInt32?
    let trackChangeHeaderRawLength: Int?
    let trackChangeHeaderRawPrefixBytes: [UInt8]?
    let trackChangeHeaderRawSuffixBytes: [UInt8]?
    let trackChangeRawTrailingLength: Int?
    let trackChangeRawTrailingPrefixBytes: [UInt8]?
    let trackChangeRawTrailingSuffixBytes: [UInt8]?
    let memoShapeWidth: UInt32?
    let memoShapeLineType: UInt8?
    let memoShapeLineWidth: UInt8?
    let memoShapeLineColor: [Int]?
    let memoShapeFillColor: [Int]?
    let memoShapeActiveColor: [Int]?
    let memoShapeFixedRawLength: Int?
    let memoShapeFixedRawPrefixBytes: [UInt8]?
    let memoShapeFixedRawSuffixBytes: [UInt8]?
    let memoShapeRawTrailingLength: Int?
    let memoShapeRawTrailingPrefixBytes: [UInt8]?
    let memoShapeRawTrailingSuffixBytes: [UInt8]?
    let trackChangeContentKind: UInt32?
    let trackChangeContentKindRawLength: Int?
    let trackChangeContentKindRawPrefixBytes: [UInt8]?
    let trackChangeContentKindRawSuffixBytes: [UInt8]?
    let trackChangeContentYear: UInt16?
    let trackChangeContentMonth: UInt16?
    let trackChangeContentDay: UInt16?
    let trackChangeContentHour: UInt16?
    let trackChangeContentMinute: UInt16?
    let trackChangeTimestampRawLength: Int?
    let trackChangeTimestampRawPrefixBytes: [UInt8]?
    let trackChangeTimestampRawSuffixBytes: [UInt8]?
    let trackChangeContentRawTrailingLength: Int?
    let trackChangeContentRawTrailingPrefixBytes: [UInt8]?
    let trackChangeContentRawTrailingSuffixBytes: [UInt8]?
    let authorName: String?
    let authorNameLengthRawLength: Int?
    let authorNameLengthRawPrefixBytes: [UInt8]?
    let authorNameLengthRawSuffixBytes: [UInt8]?
    let authorNameRawPayloadLength: Int?
    let authorNameRawPayloadPrefixBytes: [UInt8]?
    let authorNameRawPayloadSuffixBytes: [UInt8]?
    let authorRawTrailingLength: Int?
    let authorRawTrailingPrefixBytes: [UInt8]?
    let authorRawTrailingSuffixBytes: [UInt8]?
    let forbiddenCharCount: Int?
    let forbiddenCharPayloadLengths: [Int]?
    let forbiddenCharPayloadPrefixBytes: [[UInt8]]?
    let forbiddenCharPayloadSuffixBytes: [[UInt8]]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureBinDataExpectations: Decodable {
    let propertyRawValue: UInt16?
    let type: String?
    let compressType: String?
    let state: String?
    let streamId: UInt16?
    let extensionName: String?
    let absolutePathRawPayloadLength: Int?
    let absolutePathRawPayloadPrefixBytes: [UInt8]?
    let absolutePathRawPayloadSuffixBytes: [UInt8]?
    let relativePathRawPayloadLength: Int?
    let relativePathRawPayloadPrefixBytes: [UInt8]?
    let relativePathRawPayloadSuffixBytes: [UInt8]?
    let extensionNameRawPayloadLength: Int?
    let extensionNameRawPayloadPrefixBytes: [UInt8]?
    let extensionNameRawPayloadSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
}

struct FixtureStyleExpectations: Decodable {
    let index: Int
    let localName: String?
    let englishName: String?
    let localNameRawPayloadLength: Int?
    let localNameRawPayloadPrefixBytes: [UInt8]?
    let localNameRawPayloadSuffixBytes: [UInt8]?
    let englishNameRawPayloadLength: Int?
    let englishNameRawPayloadPrefixBytes: [UInt8]?
    let englishNameRawPayloadSuffixBytes: [UInt8]?
    let property: UInt8?
    let nextId: UInt8?
    let languageId: Int16?
    let paraShapeId: UInt16?
    let charShapeId: UInt16?
    let unknownBytes: [UInt8]?
    let undocumentedTrailingLength: Int?
    let undocumentedTrailingPrefixBytes: [UInt8]?
    let undocumentedTrailingSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
}

struct FixtureNumberingExpectations: Decodable {
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
}

struct FixtureBulletExpectations: Decodable {
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let charRawPayloadLength: Int?
    let charRawPayloadPrefixBytes: [UInt8]?
    let charRawPayloadSuffixBytes: [UInt8]?
    let checkCharRawPayloadLength: Int?
    let checkCharRawPayloadPrefixBytes: [UInt8]?
    let checkCharRawPayloadSuffixBytes: [UInt8]?
    let undocumentedTrailingLength: Int?
    let undocumentedTrailingPrefixBytes: [UInt8]?
    let undocumentedTrailingSuffixBytes: [UInt8]?
}

struct FixtureParaRangeTagExpectations: Decodable {
    let start: UInt32?
    let end: UInt32?
    let tag: UInt32?
}

struct FixtureControlPreservationExpectations: Decodable {
    let kind: String
    let ctrlId: UInt32?
    let occurrenceIndex: Int?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureOtherControlExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let occurrenceIndex: Int?
    let bookmarkName: String?
    let bookmarkNameCharacterCount: Int?
    let bookmarkNameLengthRawPayloadLength: Int?
    let bookmarkNameLengthRawPayloadPrefixBytes: [UInt8]?
    let bookmarkNameLengthRawPayloadSuffixBytes: [UInt8]?
    let bookmarkNameRawPayloadLength: Int?
    let bookmarkNameRawPayloadPrefixBytes: [UInt8]?
    let bookmarkNameRawPayloadSuffixBytes: [UInt8]?
    let bookmarkRawTrailingLength: Int?
    let bookmarkRawTrailingPrefixBytes: [UInt8]?
    let bookmarkRawTrailingSuffixBytes: [UInt8]?
    let numberingKind: UInt32?
    let numberingValue: UInt32?
    let numberingFormat: UInt32?
    let numberingRawTrailingLength: Int?
    let numberingRawTrailingPrefixBytes: [UInt8]?
    let numberingRawTrailingSuffixBytes: [UInt8]?
    let pageHideRawValue: UInt32?
    let pageHideRawTrailingLength: Int?
    let pageHideRawTrailingPrefixBytes: [UInt8]?
    let pageHideRawTrailingSuffixBytes: [UInt8]?
    let indexmarkText: String?
    let indexmarkTextCharacterCount: Int?
    let indexmarkTextLengthRawPayloadLength: Int?
    let indexmarkTextLengthRawPayloadPrefixBytes: [UInt8]?
    let indexmarkTextLengthRawPayloadSuffixBytes: [UInt8]?
    let indexmarkTextRawPayloadLength: Int?
    let indexmarkTextRawPayloadPrefixBytes: [UInt8]?
    let indexmarkTextRawPayloadSuffixBytes: [UInt8]?
    let indexmarkRawTrailingLength: Int?
    let indexmarkRawTrailingPrefixBytes: [UInt8]?
    let indexmarkRawTrailingSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
    let ctrlDataCount: Int?
    let ctrlDataPayloadLengths: [Int]?
    let ctrlDataPayloadPrefixBytes: [[UInt8]]?
    let ctrlDataPayloadSuffixBytes: [[UInt8]]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureGenShapeObjectExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let width: UInt32?
    let height: UInt32?
    let commonCtrlPropertyRawPayloadLength: Int?
    let commonCtrlPropertyRawPayloadPrefixBytes: [UInt8]?
    let commonCtrlPropertyRawPayloadSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
    let shapeComponents: [FixtureShapeComponentExpectations]?
    let ctrlDataCount: Int?
    let ctrlDataPayloadLengths: [Int]?
    let ctrlDataPayloadPrefixBytes: [[UInt8]]?
    let ctrlDataPayloadSuffixBytes: [[UInt8]]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureShapeControlExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let commonCtrlPropertyRawPayloadLength: Int?
    let commonCtrlPropertyRawPayloadPrefixBytes: [UInt8]?
    let commonCtrlPropertyRawPayloadSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
    let eqEditCount: Int?
    let eqEditPayloadLengths: [Int]?
    let eqEditPayloadPrefixBytes: [[UInt8]]?
    let eqEditPayloadSuffixBytes: [[UInt8]]?
    let eqEditTextLengths: [UInt16]?
    let eqEditTextLengthRawPayloadLengths: [Int]?
    let eqEditTextLengthRawPayloadPrefixBytes: [[UInt8]]?
    let eqEditTextLengthRawPayloadSuffixBytes: [[UInt8]]?
    let eqEditTexts: [String]?
    let ctrlDataCount: Int?
    let ctrlDataPayloadLengths: [Int]?
    let ctrlDataPayloadPrefixBytes: [[UInt8]]?
    let ctrlDataPayloadSuffixBytes: [[UInt8]]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureShapeComponentExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let pictureCount: Int?
    let pictureRawPayloadLengths: [Int]?
    let pictureRawPayloadPrefixBytes: [[UInt8]]?
    let pictureRawPayloadSuffixBytes: [[UInt8]]?
    let pictureRawTrailingLengths: [Int]?
    let pictureRawTrailingPrefixBytes: [[UInt8]]?
    let pictureRawTrailingSuffixBytes: [[UInt8]]?
    let pictureBinaryDataIds: [UInt16]?
    let rectangleCount: Int?
    let rectangleRawPayloadLengths: [Int]?
    let rectangleRawPayloadPrefixBytes: [[UInt8]]?
    let rectangleRawPayloadSuffixBytes: [[UInt8]]?
    let polygonCount: Int?
    let polygonRawPayloadLengths: [Int]?
    let polygonRawPayloadPrefixBytes: [[UInt8]]?
    let polygonRawPayloadSuffixBytes: [[UInt8]]?
    let oleCount: Int?
    let olePayloadLengths: [Int]?
    let olePayloadPrefixBytes: [[UInt8]]?
    let olePayloadSuffixBytes: [[UInt8]]?
    let oleRawTrailingLengths: [Int]?
    let oleRawTrailingPrefixBytes: [[UInt8]]?
    let oleRawTrailingSuffixBytes: [[UInt8]]?
    let oleBinaryDataIds: [UInt32]?
    let ctrlDataCount: Int?
    let ctrlDataPayloadLengths: [Int]?
    let ctrlDataPayloadPrefixBytes: [[UInt8]]?
    let ctrlDataPayloadSuffixBytes: [[UInt8]]?
    let textBoxListCount: Int?
    let textBoxParagraphCounts: [Int]?
    let textBoxVisibleTextContains: [String]?
    let textBoxListHeaderRawPayloadLengths: [Int]?
    let textBoxListHeaderRawPayloadPrefixBytes: [[UInt8]]?
    let textBoxListHeaderRawPayloadSuffixBytes: [[UInt8]]?
    let rawChildren: [FixtureShapeRawChildExpectations]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}

struct FixtureShapeRawChildExpectations: Decodable {
    let kind: String
    let count: Int?
    let payloadLengths: [Int]?
    let payloadPrefixBytes: [[UInt8]]?
    let payloadSuffixBytes: [[UInt8]]?
    let childCounts: [Int]?
    let childTagIds: [[UInt32]]?
    let childPayloadLengths: [[Int]]?
    let childPayloadPrefixBytes: [[[UInt8]]]?
    let childPayloadSuffixBytes: [[[UInt8]]]?
}
