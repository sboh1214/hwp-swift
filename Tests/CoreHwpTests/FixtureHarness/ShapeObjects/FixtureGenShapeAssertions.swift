@testable import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertGenShapeObjects(
        _ expectations: [FixtureGenShapeObjectExpectations],
        _ hwp: HwpFile
    ) {
        let actualObjects = FixtureDerivedValues.genShapeObjects(from: hwp)
        expect(actualObjects.count) == expectations.count

        for (actual, expected) in zip(actualObjects, expectations) {
            assertGenShapeObjectGeometry(expected, actual)
            if let shapeComponents = expected.shapeComponents {
                assertShapeComponents(shapeComponents, actual)
            }
            assertGenShapeObjectChildren(expected, actual)
        }
    }

    static func assertGenShapeObjectGeometry(
        _ expected: FixtureGenShapeObjectExpectations,
        _ actual: HwpGenShapeObject
    ) {
        if let ctrlId = expected.ctrlId {
            expect(actual.commonCtrlProperty.commonCtrlId.rawValue) == ctrlId
        }
        if let ctrlIdName = expected.ctrlIdName {
            expect(String(describing: actual.commonCtrlProperty.commonCtrlId)) == ctrlIdName
        }
        if let width = expected.width {
            expect(actual.commonCtrlProperty.width) == width
        }
        if let height = expected.height {
            expect(actual.commonCtrlProperty.height) == height
        }
        if let rawPayloadLength = expected.commonCtrlPropertyRawPayloadLength {
            expect(actual.commonCtrlProperty.rawPayload.count) == rawPayloadLength
        }
        expectPayloadPrefix(
            actual.commonCtrlProperty.rawPayload,
            expected.commonCtrlPropertyRawPayloadPrefixBytes
        )
        expectPayloadSuffix(
            actual.commonCtrlProperty.rawPayload,
            expected.commonCtrlPropertyRawPayloadSuffixBytes
        )
        if let rawPayloadLength = expected.rawPayloadLength {
            expect(actual.rawPayload.count) == rawPayloadLength
        }
        expectPayloadPrefix(actual.rawPayload, expected.rawPayloadPrefixBytes)
        expectPayloadSuffix(actual.rawPayload, expected.rawPayloadSuffixBytes)
        if let rawTrailingLength = expected.rawTrailingLength {
            expect(actual.rawTrailing.count) == rawTrailingLength
        }
        expectPayloadPrefix(actual.rawTrailing, expected.rawTrailingPrefixBytes)
        expectPayloadSuffix(actual.rawTrailing, expected.rawTrailingSuffixBytes)
    }

    static func assertGenShapeObjectChildren(
        _ expected: FixtureGenShapeObjectExpectations,
        _ actual: HwpGenShapeObject
    ) {
        if let ctrlDataCount = expected.ctrlDataCount {
            expect(actual.ctrlDataRecords.count) == ctrlDataCount
        }
        if let ctrlDataPayloadLengths = expected.ctrlDataPayloadLengths {
            expect(actual.ctrlDataRecords.map(\.rawPayload.count)) == ctrlDataPayloadLengths
        }
        expectPayloadPrefixes(
            actual.ctrlDataRecords.map(\.rawPayload),
            expected.ctrlDataPayloadPrefixBytes
        )
        expectPayloadSuffixes(
            actual.ctrlDataRecords.map(\.rawPayload),
            expected.ctrlDataPayloadSuffixBytes
        )
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.unknownChildren.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
            actual.unknownChildren,
            rootLevel: 2,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expected.unknownChildTagIds,
                payloadLengths: expected.unknownChildPayloadLengths,
                payloadPrefixes: expected.unknownChildPayloadPrefixBytes,
                payloadSuffixes: expected.unknownChildPayloadSuffixBytes,
                childTagIds: expected.unknownChildChildTagIds,
                childPayloadLengths: expected.unknownChildChildPayloadLengths,
                childPayloadPrefixes: expected.unknownChildChildPayloadPrefixBytes,
                childPayloadSuffixes: expected.unknownChildChildPayloadSuffixBytes
            )
        )
    }

    static func assertShapeComponents(
        _ expectations: [FixtureShapeComponentExpectations],
        _ actualObject: HwpGenShapeObject
    ) {
        expect(actualObject.shapeComponentArray.count) == expectations.count

        for (actual, expected) in zip(actualObject.shapeComponentArray, expectations) {
            if let ctrlId = expected.ctrlId {
                expect(actual.rawCtrlId) == ctrlId
            }
            if let ctrlIdName = expected.ctrlIdName {
                expect(actual.ctrlIdName) == ctrlIdName
            }
            if let rawPayloadLength = expected.rawPayloadLength {
                expect(actual.rawPayload.count) == rawPayloadLength
            }
            expectPayloadPrefix(actual.rawPayload, expected.rawPayloadPrefixBytes)
            expectPayloadSuffix(actual.rawPayload, expected.rawPayloadSuffixBytes)
            assertShapeComponentPictures(expected, actual)
            if let rectangleCount = expected.rectangleCount {
                expect(actual.rectangleArray.count) == rectangleCount
            }
            assertShapeComponentRectangles(expected, actual)
            if let polygonCount = expected.polygonCount {
                expect(actual.polygonArray.count) == polygonCount
            }
            assertShapeComponentPolygons(expected, actual)
            assertShapeComponentOleRecords(expected, actual)
            if let ctrlDataCount = expected.ctrlDataCount {
                expect(actual.ctrlDataRecords.count) == ctrlDataCount
            }
            if let ctrlDataPayloadLengths = expected.ctrlDataPayloadLengths {
                expect(actual.ctrlDataRecords.map(\.rawPayload.count)) == ctrlDataPayloadLengths
            }
            expectPayloadPrefixes(
                actual.ctrlDataRecords.map(\.rawPayload),
                expected.ctrlDataPayloadPrefixBytes
            )
            expectPayloadSuffixes(
                actual.ctrlDataRecords.map(\.rawPayload),
                expected.ctrlDataPayloadSuffixBytes
            )
            assertShapeComponentTextBoxLists(expected, actual)
            assertShapeComponentRawChildren(expected, actual)
            assertShapeComponentUnknownChildren(expected, actual)
        }
    }

    static func assertShapeComponentPictures(
        _ expected: FixtureShapeComponentExpectations,
        _ actual: HwpShapeComponent
    ) {
        if let pictureCount = expected.pictureCount {
            expect(actual.pictureArray.count) == pictureCount
        }
        if let pictureRawPayloadLengths = expected.pictureRawPayloadLengths {
            expect(actual.pictureArray.map(\.rawPayload.count)) == pictureRawPayloadLengths
        }
        expectPayloadPrefixes(
            actual.pictureArray.map(\.rawPayload),
            expected.pictureRawPayloadPrefixBytes
        )
        expectPayloadSuffixes(
            actual.pictureArray.map(\.rawPayload),
            expected.pictureRawPayloadSuffixBytes
        )
        assertPayloadSamples(
            actual.pictureArray.compactMap(\.rawTrailing),
            lengths: expected.pictureRawTrailingLengths,
            prefixes: expected.pictureRawTrailingPrefixBytes,
            suffixes: expected.pictureRawTrailingSuffixBytes
        )
        if let pictureBinaryDataIds = expected.pictureBinaryDataIds {
            expect(actual.pictureArray.compactMap(\.binaryDataId)) == pictureBinaryDataIds
        }
    }

    static func assertShapeComponentRectangles(
        _ expected: FixtureShapeComponentExpectations,
        _ actual: HwpShapeComponent
    ) {
        if let rectangleRawPayloadLengths = expected.rectangleRawPayloadLengths {
            expect(actual.rectangleArray.map(\.rawPayload.count)) == rectangleRawPayloadLengths
        }
        assertPayloadSamples(
            actual.rectangleArray.map(\.rawPayload),
            lengths: nil,
            prefixes: expected.rectangleRawPayloadPrefixBytes,
            suffixes: expected.rectangleRawPayloadSuffixBytes
        )
    }

    static func assertShapeComponentPolygons(
        _ expected: FixtureShapeComponentExpectations,
        _ actual: HwpShapeComponent
    ) {
        if let polygonRawPayloadLengths = expected.polygonRawPayloadLengths {
            expect(actual.polygonArray.map(\.rawPayload.count)) == polygonRawPayloadLengths
        }
        assertPayloadSamples(
            actual.polygonArray.map(\.rawPayload),
            lengths: nil,
            prefixes: expected.polygonRawPayloadPrefixBytes,
            suffixes: expected.polygonRawPayloadSuffixBytes
        )
    }

    static func assertShapeComponentTextBoxLists(
        _ expected: FixtureShapeComponentExpectations,
        _ actual: HwpShapeComponent
    ) {
        if let textBoxListCount = expected.textBoxListCount {
            expect(actual.textBoxListArray.count) == textBoxListCount
        }
        if let textBoxParagraphCounts = expected.textBoxParagraphCounts {
            expect(actual.textBoxListArray.map(\.paragraphArray.count)) ==
                textBoxParagraphCounts
        }
        assertPayloadSamples(
            actual.textBoxListArray.map(\.headerRawPayload),
            lengths: expected.textBoxListHeaderRawPayloadLengths,
            prefixes: expected.textBoxListHeaderRawPayloadPrefixBytes,
            suffixes: expected.textBoxListHeaderRawPayloadSuffixBytes
        )
        if let textBoxVisibleTextContains = expected.textBoxVisibleTextContains {
            let text = visibleText(in: actual.textBoxListArray.flatMap(\.paragraphArray))
            for expectedText in textBoxVisibleTextContains {
                expect(text).to(contain(expectedText))
            }
        }
    }

    static func assertShapeComponentUnknownChildren(
        _ expected: FixtureShapeComponentExpectations,
        _ actual: HwpShapeComponent
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.unknownChildren.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
            actual.unknownChildren,
            rootLevel: 3,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expected.unknownChildTagIds,
                payloadLengths: expected.unknownChildPayloadLengths,
                payloadPrefixes: expected.unknownChildPayloadPrefixBytes,
                payloadSuffixes: expected.unknownChildPayloadSuffixBytes,
                childTagIds: expected.unknownChildChildTagIds,
                childPayloadLengths: expected.unknownChildChildPayloadLengths,
                childPayloadPrefixes: expected.unknownChildChildPayloadPrefixBytes,
                childPayloadSuffixes: expected.unknownChildChildPayloadSuffixBytes
            )
        )
    }
}

private func expectPayloadPrefix(_ actual: Data, _ expected: [UInt8]?) {
    guard let expected else {
        return
    }
    expect(Array(actual.prefix(expected.count))) == expected
}

private func expectPayloadSuffix(_ actual: Data, _ expected: [UInt8]?) {
    guard let expected else {
        return
    }
    expect(Array(actual.suffix(expected.count))) == expected
}

private func expectPayloadPrefixes(_ actual: [Data], _ expected: [[UInt8]]?) {
    guard let expected else {
        return
    }
    expect(actual.count) == expected.count
    let actualPrefixes = zip(actual, expected)
        .map { data, prefix in Array(data.prefix(prefix.count)) }
    expect(actualPrefixes) == expected
}

private func expectPayloadSuffixes(_ actual: [Data], _ expected: [[UInt8]]?) {
    guard let expected else {
        return
    }
    expect(actual.count) == expected.count
    let actualSuffixes = zip(actual, expected)
        .map { data, suffix in Array(data.suffix(suffix.count)) }
    expect(actualSuffixes) == expected
}

private func visibleText(in paragraphs: [HwpParagraph]) -> String {
    paragraphs
        .compactMap(\.paraText)
        .flatMap(\.charArray)
        .compactMap { char -> UnicodeScalar? in
            guard char.type == .char else {
                return nil
            }
            return UnicodeScalar(Int(char.value))
        }
        .map(String.init)
        .joined()
}
