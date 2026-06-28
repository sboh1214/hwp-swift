// swiftlint:disable file_length

import Foundation
import Nimble
import XCTest

final class FixtureObjectFeatureGateTests: XCTestCase {
    func testTextBoxGateAcceptsAlignedShapeComponentSamples() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611476835,
          "ctrlIdName": "rectangle",
          "textBoxListCount": 1,
          "textBoxParagraphCounts": [2],
          "textBoxVisibleTextContains": ["inside box"],
          "textBoxListHeaderRawPayloadLengths": [33],
          "textBoxListHeaderRawPayloadPrefixBytes": [[2, 0]],
          "textBoxListHeaderRawPayloadSuffixBytes": [[0, 0]],
          "rectangleCount": 1,
          "rectangleRawPayloadLengths": [33],
          "rectangleRawPayloadPrefixBytes": [[0, 152]],
          "rectangleRawPayloadSuffixBytes": [[207, 35]],
          "unknownChildCount": 0
        }
        """)

        expect(genShapeObjectHasTextBoxComponent(object)) == true
    }

    func testTextBoxGateRequiresParagraphCountsToMatchListCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611476835,
          "ctrlIdName": "rectangle",
          "textBoxListCount": 2,
          "textBoxParagraphCounts": [2],
          "textBoxVisibleTextContains": ["inside box"],
          "textBoxListHeaderRawPayloadLengths": [33, 33],
          "textBoxListHeaderRawPayloadPrefixBytes": [[2, 0], [2, 0]],
          "textBoxListHeaderRawPayloadSuffixBytes": [[0, 0], [0, 0]],
          "rectangleCount": 1,
          "rectangleRawPayloadLengths": [33],
          "rectangleRawPayloadPrefixBytes": [[0, 152]],
          "rectangleRawPayloadSuffixBytes": [[207, 35]],
          "unknownChildCount": 0
        }
        """)

        expect(genShapeObjectHasTextBoxComponent(object)) == false
    }

    func testTextBoxGateRequiresListHeaderSamplesToMatchListCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611476835,
          "ctrlIdName": "rectangle",
          "textBoxListCount": 1,
          "textBoxParagraphCounts": [2],
          "textBoxVisibleTextContains": ["inside box"],
          "textBoxListHeaderRawPayloadLengths": [33],
          "textBoxListHeaderRawPayloadPrefixBytes": [],
          "textBoxListHeaderRawPayloadSuffixBytes": [[0, 0]],
          "rectangleCount": 1,
          "rectangleRawPayloadLengths": [33],
          "rectangleRawPayloadPrefixBytes": [[0, 152]],
          "rectangleRawPayloadSuffixBytes": [[207, 35]],
          "unknownChildCount": 0
        }
        """)

        expect(genShapeObjectHasTextBoxComponent(object)) == false
    }

    func testTextBoxGateRequiresRectangleSamplesToMatchRectangleCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611476835,
          "ctrlIdName": "rectangle",
          "textBoxListCount": 1,
          "textBoxParagraphCounts": [2],
          "textBoxVisibleTextContains": ["inside box"],
          "textBoxListHeaderRawPayloadLengths": [33],
          "textBoxListHeaderRawPayloadPrefixBytes": [[2, 0]],
          "textBoxListHeaderRawPayloadSuffixBytes": [[0, 0]],
          "rectangleCount": 1,
          "rectangleRawPayloadLengths": [33],
          "rectangleRawPayloadPrefixBytes": [[0, 152]],
          "rectangleRawPayloadSuffixBytes": [],
          "unknownChildCount": 0
        }
        """)

        expect(genShapeObjectHasTextBoxComponent(object)) == false
    }

    func testTextBoxGateRejectsListHeaderSamplesLongerThanDeclaredPayload() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611476835,
          "ctrlIdName": "rectangle",
          "textBoxListCount": 1,
          "textBoxParagraphCounts": [2],
          "textBoxVisibleTextContains": ["inside box"],
          "textBoxListHeaderRawPayloadLengths": [1],
          "textBoxListHeaderRawPayloadPrefixBytes": [[2, 0]],
          "textBoxListHeaderRawPayloadSuffixBytes": [[0]],
          "rectangleCount": 1,
          "rectangleRawPayloadLengths": [33],
          "rectangleRawPayloadPrefixBytes": [[0, 152]],
          "rectangleRawPayloadSuffixBytes": [[207, 35]],
          "unknownChildCount": 0
        }
        """)

        expect(genShapeObjectHasTextBoxComponent(object)) == false
    }

    func testChartGateAcceptsAlignedOleComponentSamples() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611282021,
          "ctrlIdName": "ole",
          "oleCount": 1,
          "olePayloadLengths": [30],
          "olePayloadPrefixBytes": [[1, 0]],
          "olePayloadSuffixBytes": [[0, 0]],
          "oleRawTrailingLengths": [26],
          "oleRawTrailingPrefixBytes": [[32, 28]],
          "oleRawTrailingSuffixBytes": [[0, 0]],
          "oleBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasOleComponent(object)) == true
    }

    func testChartGateRequiresOlePayloadSamplesToMatchOleCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611282021,
          "ctrlIdName": "ole",
          "oleCount": 1,
          "olePayloadLengths": [30],
          "olePayloadPrefixBytes": [],
          "olePayloadSuffixBytes": [[0, 0]],
          "oleBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasOleComponent(object)) == false
    }

    func testChartGateRequiresOleRawTrailingSamplesToMatchOleCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611282021,
          "ctrlIdName": "ole",
          "oleCount": 1,
          "olePayloadLengths": [30],
          "olePayloadPrefixBytes": [[1, 0]],
          "olePayloadSuffixBytes": [[0, 0]],
          "oleRawTrailingLengths": [],
          "oleRawTrailingPrefixBytes": [],
          "oleRawTrailingSuffixBytes": [],
          "oleBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasOleComponent(object)) == false
    }

    func testChartGateRequiresOleBinaryDataIdsToMatchOleCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611282021,
          "ctrlIdName": "ole",
          "oleCount": 1,
          "olePayloadLengths": [30],
          "olePayloadPrefixBytes": [[1, 0]],
          "olePayloadSuffixBytes": [[0, 0]],
          "oleBinaryDataIds": []
        }
        """)

        expect(genShapeObjectHasOleComponent(object)) == false
    }

    func testLegacyPolygonGateAcceptsAlignedPolygonComponentSamples() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611348332,
          "ctrlIdName": "polygon",
          "polygonCount": 1,
          "polygonRawPayloadLengths": [24],
          "polygonRawPayloadPrefixBytes": [[2, 0]],
          "polygonRawPayloadSuffixBytes": [[0, 0]]
        }
        """)

        expect(genShapeObjectHasLegacyPolygonComponent(object)) == true
    }

    func testLegacyPolygonGateRequiresPolygonPayloadSamplesToMatchCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611348332,
          "ctrlIdName": "polygon",
          "polygonCount": 1,
          "polygonRawPayloadLengths": [24],
          "polygonRawPayloadPrefixBytes": [[2, 0]],
          "polygonRawPayloadSuffixBytes": []
        }
        """)

        expect(genShapeObjectHasLegacyPolygonComponent(object)) == false
    }

    func testChartFeatureGateAcceptsOleReferenceWithBinaryDataSamples() throws {
        let expectations = try decodeChartFeatureExpectations()

        expect(chartFeatureHasOleAndBinaryDataSamples(expectations)) == true
    }

    func testChartFeatureGateRequiresBinaryDataPayloadSamples() throws {
        let expectations = try decodeChartFeatureExpectations(
            binaryDataPayloadPrefixBytes: "[]"
        )

        expect(chartFeatureHasOleAndBinaryDataSamples(expectations)) == false
    }

    func testChartFeatureGateRequiresOleReference() throws {
        let expectations = try decodeChartFeatureExpectations(shapeComponents: "[]")

        expect(chartFeatureHasOleAndBinaryDataSamples(expectations)) == false
    }

    func testEmbeddedImageGateAcceptsAlignedPictureComponentSamples() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611346787,
          "ctrlIdName": "picture",
          "pictureCount": 1,
          "pictureRawPayloadLengths": [91],
          "pictureRawPayloadPrefixBytes": [[0, 0]],
          "pictureRawPayloadSuffixBytes": [[50, 2]],
          "pictureRawTrailingLengths": [18],
          "pictureRawTrailingPrefixBytes": [[0, 120]],
          "pictureRawTrailingSuffixBytes": [[50, 2]],
          "pictureBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasPictureComponent(object)) == true
    }

    func testEmbeddedImageGateRequiresPicturePayloadSamplesToMatchPictureCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611346787,
          "ctrlIdName": "picture",
          "pictureCount": 1,
          "pictureRawPayloadLengths": [91],
          "pictureRawPayloadPrefixBytes": [[0, 0]],
          "pictureRawPayloadSuffixBytes": [],
          "pictureBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasPictureComponent(object)) == false
    }

    func testEmbeddedImageGateRequiresPictureRawTrailingSamplesToMatchPictureCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611346787,
          "ctrlIdName": "picture",
          "pictureCount": 1,
          "pictureRawPayloadLengths": [91],
          "pictureRawPayloadPrefixBytes": [[0, 0]],
          "pictureRawPayloadSuffixBytes": [[50, 2]],
          "pictureRawTrailingLengths": [],
          "pictureRawTrailingPrefixBytes": [],
          "pictureRawTrailingSuffixBytes": [],
          "pictureBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasPictureComponent(object)) == false
    }

    func testEmbeddedImageGateRejectsPictureSamplesLongerThanDeclaredPayload() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611346787,
          "ctrlIdName": "picture",
          "pictureCount": 1,
          "pictureRawPayloadLengths": [1],
          "pictureRawPayloadPrefixBytes": [[0, 0]],
          "pictureRawPayloadSuffixBytes": [[2]],
          "pictureBinaryDataIds": [1]
        }
        """)

        expect(genShapeObjectHasPictureComponent(object)) == false
    }

    func testEmbeddedImageGateRequiresPictureBinaryDataIdsToMatchPictureCount() throws {
        let object = try decodeGenShapeObject("""
        {
          "ctrlId": 611346787,
          "ctrlIdName": "picture",
          "pictureCount": 1,
          "pictureRawPayloadLengths": [91],
          "pictureRawPayloadPrefixBytes": [[0, 0]],
          "pictureRawPayloadSuffixBytes": [[50, 2]],
          "pictureBinaryDataIds": []
        }
        """)

        expect(genShapeObjectHasPictureComponent(object)) == false
    }

    func testImageGateAcceptsObjectReferenceWithBinaryDataSamples() throws {
        let expectations = try decodeImageFeatureExpectations()

        expect(imageFeatureHasObjectAndBinaryDataSamples(expectations)) == true
    }

    func testImageGateRequiresBinaryDataPayloadSamples() throws {
        let expectations = try decodeImageFeatureExpectations(
            binaryDataPayloadPrefixBytes: "[]"
        )

        expect(imageFeatureHasObjectAndBinaryDataSamples(expectations)) == false
    }

    func testImageGateRequiresObjectImageReference() throws {
        let expectations = try decodeImageFeatureExpectations(shapeComponents: "[]")

        expect(imageFeatureHasObjectAndBinaryDataSamples(expectations)) == false
    }
}

private func decodeGenShapeObject(_ json: String) throws -> FixtureGenShapeObjectExpectations {
    let data = Data("""
    {
      "id": "synthetic-object-feature-gate",
      "generationTool": "synthetic",
      "hwpVersion": "5.0.3.2",
      "source": "synthetic",
      "features": ["shape-object"],
      "expectations": {
        "genShapeObjects": [
          {
            "shapeComponents": [
              \(json)
            ]
          }
        ]
      }
    }
    """.utf8)
    let manifest = try JSONDecoder().decode(FixtureManifest.self, from: data)
    guard let object = manifest.expectations.genShapeObjects?.first else {
        throw FixtureObjectFeatureGateError.missingGenShapeObject
    }
    return object
}

private func decodeChartFeatureExpectations(
    binaryDataPayloadPrefixBytes: String = "[[79, 76]]",
    shapeComponents: String = "[\(chartFeatureOleComponentJSON)]"
) throws -> FixtureExpectations {
    let data = Data("""
    {
      "id": "synthetic-chart-feature-gate",
      "generationTool": "synthetic",
      "hwpVersion": "5.0.3.2",
      "source": "synthetic",
      "features": ["chart"],
      "expectations": {
        "allControlTypeCounts": {"genShapeObject": 1},
        "binaryDataCount": 1,
        "binaryDataNames": ["BIN0001.bin"],
        "binaryDataEntryNames": ["BIN0001.bin"],
        "binaryDataStreamIds": [1],
        "binaryDataExtensionNames": ["bin"],
        "binaryDataPayloadLengths": [4],
        "binaryDataPayloadPrefixBytes": \(binaryDataPayloadPrefixBytes),
        "binaryDataPayloadSuffixBytes": [[69, 0]],
        "binaryDataTotalByteCount": 4,
        "docInfoBinData": [
          {
            "type": "embedding",
            "compressType": "compress",
            "state": "success",
            "streamId": 1,
            "extensionName": "bin",
            "rawPayloadLength": 12,
            "rawPayloadPrefixBytes": [1, 0],
            "rawPayloadSuffixBytes": [98, 0]
          }
        ],
        "genShapeObjects": [
          {
            "ctrlId": 1735618336,
            "ctrlIdName": "genShapeObject",
            "commonCtrlPropertyRawPayloadLength": 8,
            "commonCtrlPropertyRawPayloadPrefixBytes": [32, 111],
            "commonCtrlPropertyRawPayloadSuffixBytes": [10, 4],
            "rawPayloadLength": 8,
            "rawPayloadPrefixBytes": [32, 111],
            "rawPayloadSuffixBytes": [10, 4],
            "rawTrailingLength": 0,
            "rawTrailingPrefixBytes": [],
            "rawTrailingSuffixBytes": [],
            "shapeComponents": \(shapeComponents)
          }
        ]
      }
    }
    """.utf8)
    return try JSONDecoder().decode(FixtureManifest.self, from: data).expectations
}

private func decodeImageFeatureExpectations(
    binaryDataPayloadPrefixBytes: String = "[[137, 80]]",
    shapeComponents: String = "[\(imageFeaturePictureComponentJSON)]"
) throws -> FixtureExpectations {
    let data = Data("""
    {
      "id": "synthetic-image-feature-gate",
      "generationTool": "synthetic",
      "hwpVersion": "5.0.3.2",
      "source": "synthetic",
      "features": ["image"],
      "expectations": {
        "binaryDataCount": 1,
        "binaryDataNames": ["BIN0001.png"],
        "binaryDataEntryNames": ["BIN0001.png"],
        "binaryDataStreamIds": [1],
        "binaryDataExtensionNames": ["png"],
        "binaryDataPayloadLengths": [4],
        "binaryDataPayloadPrefixBytes": \(binaryDataPayloadPrefixBytes),
        "binaryDataPayloadSuffixBytes": [[78, 71]],
        "binaryDataTotalByteCount": 4,
        "docInfoBinData": [
          {
            "type": "embedding",
            "compressType": "compress",
            "state": "success",
            "streamId": 1,
            "extensionName": "png",
            "rawPayloadLength": 12,
            "rawPayloadPrefixBytes": [1, 0],
            "rawPayloadSuffixBytes": [112, 0]
          }
        ],
        "genShapeObjects": [
          {
            "ctrlId": 1735618336,
            "ctrlIdName": "genShapeObject",
            "commonCtrlPropertyRawPayloadLength": 8,
            "commonCtrlPropertyRawPayloadPrefixBytes": [32, 111],
            "commonCtrlPropertyRawPayloadSuffixBytes": [10, 4],
            "rawPayloadLength": 8,
            "rawPayloadPrefixBytes": [32, 111],
            "rawPayloadSuffixBytes": [10, 4],
            "rawTrailingLength": 0,
            "rawTrailingPrefixBytes": [],
            "rawTrailingSuffixBytes": [],
            "shapeComponents": \(shapeComponents)
          }
        ]
      }
    }
    """.utf8)
    return try JSONDecoder().decode(FixtureManifest.self, from: data).expectations
}

private let chartFeatureOleComponentJSON = """
{
  "ctrlId": 611282021, "ctrlIdName": "ole", "rawPayloadLength": 8,
  "rawPayloadPrefixBytes": [101, 108], "rawPayloadSuffixBytes": [108, 111],
  "oleCount": 1, "olePayloadLengths": [4],
  "olePayloadPrefixBytes": [[1, 0]], "olePayloadSuffixBytes": [[0, 0]],
  "oleRawTrailingLengths": [0], "oleRawTrailingPrefixBytes": [[]],
  "oleRawTrailingSuffixBytes": [[]],
  "oleBinaryDataIds": [1]
}
"""

private let imageFeaturePictureComponentJSON = """
{
  "ctrlId": 611346787, "ctrlIdName": "picture", "rawPayloadLength": 8,
  "rawPayloadPrefixBytes": [99, 105], "rawPayloadSuffixBytes": [112, 36],
  "pictureCount": 1, "pictureRawPayloadLengths": [4],
  "pictureRawPayloadPrefixBytes": [[0, 0]], "pictureRawPayloadSuffixBytes": [[50, 2]],
  "pictureRawTrailingLengths": [0], "pictureRawTrailingPrefixBytes": [[]],
  "pictureRawTrailingSuffixBytes": [[]],
  "pictureBinaryDataIds": [1]
}
"""

private enum FixtureObjectFeatureGateError: Error {
    case missingGenShapeObject
}
