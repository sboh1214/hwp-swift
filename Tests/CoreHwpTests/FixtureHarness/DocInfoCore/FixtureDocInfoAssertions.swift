import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertDocInfoIdMappings(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expected = expectations.docInfoIdMappings else {
            return
        }

        let mappings = hwp.docInfo.idMappings
        assertDocInfoIdMappings(expected, mappings)
    }

    static func assertDocInfoIdMappings(
        _ expected: FixtureDocInfoIdMappingsExpectations,
        _ mappings: HwpIdMappings
    ) {
        assertCount(expected.binDataCount, mappings.binDataArray.count)
        assertCount(expected.faceNameKoreanCount, mappings.faceNameKoreanArray.count)
        assertCount(expected.faceNameEnglishCount, mappings.faceNameEnglishArray.count)
        assertCount(expected.faceNameChineseCount, mappings.faceNameChineseArray.count)
        assertCount(expected.faceNameJapaneseCount, mappings.faceNameJapaneseArray.count)
        assertCount(expected.faceNameEtcCount, mappings.faceNameEtcArray.count)
        assertCount(expected.faceNameSymbolCount, mappings.faceNameSymbolArray.count)
        assertCount(expected.faceNameUserCount, mappings.faceNameUserArray.count)
        assertCount(expected.borderFillCount, mappings.borderFillArray.count)
        assertCount(expected.charShapeCount, mappings.charShapeArray.count)
        assertCount(expected.tabDefCount, mappings.tabDefArray.count)
        assertCount(expected.numberingCount, mappings.numberingArray.count)
        assertCount(expected.bulletCount, mappings.bulletArray.count)
        assertCount(expected.paraShapeCount, mappings.paraShapeArray.count)
        assertCount(expected.styleCount, mappings.styleArray.count)
        assertCount(expected.memoShapeCount, mappings.memoShapeArray.count)
        assertCount(expected.trackChangeCount, mappings.trackChangeArray.count)
        assertCount(expected.trackChangeContentCount, mappings.trackChangeContentArray.count)
        assertCount(expected.trackChangeAuthorCount, mappings.trackChangeAuthorArray.count)
        assertCount(expected.forbiddenCharCount, mappings.forbiddenCharArray.count)
        assertCount(expected.unknownChildCount, mappings.unknownChildren.count)
        if let charShapePropertyRawValues = expected.charShapePropertyRawValues {
            expect(mappings.charShapeArray.map(\.property.rawValue)) == charShapePropertyRawValues
        }
        assertDocInfoIdMappingUnknownChildren(expected, mappings)
        assertDocInfoMappingRawPayloadTotals(expected, mappings)
    }

    static func assertDocInfoBinData(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expectedEntries = expectations.docInfoBinData else {
            return
        }

        let actualEntries = hwp.docInfo.idMappings.binDataArray
        expect(actualEntries.count) == expectedEntries.count

        for (actual, expected) in zip(actualEntries, expectedEntries) {
            if let propertyRawValue = expected.propertyRawValue {
                expect(actual.property.rawValue) == propertyRawValue
            }
            if let type = expected.type {
                expect(String(describing: actual.property.type)) == type
            }
            if let compressType = expected.compressType {
                expect(String(describing: actual.property.compressType)) == compressType
            }
            if let state = expected.state {
                expect(String(describing: actual.property.state)) == state
            }
            if let streamId = expected.streamId {
                expect(actual.streamId) == streamId
            }
            if let extensionName = expected.extensionName {
                expect(actual.extensionName) == extensionName
            }
            assertRawPayloadSample(
                actual.absolutePathRawPayload,
                length: expected.absolutePathRawPayloadLength,
                prefix: expected.absolutePathRawPayloadPrefixBytes,
                suffix: expected.absolutePathRawPayloadSuffixBytes
            )
            assertRawPayloadSample(
                actual.relativePathRawPayload,
                length: expected.relativePathRawPayloadLength,
                prefix: expected.relativePathRawPayloadPrefixBytes,
                suffix: expected.relativePathRawPayloadSuffixBytes
            )
            assertRawPayloadSample(
                actual.extensionNameRawPayload,
                length: expected.extensionNameRawPayloadLength,
                prefix: expected.extensionNameRawPayloadPrefixBytes,
                suffix: expected.extensionNameRawPayloadSuffixBytes
            )
            assertRawPayloadSample(
                actual.rawPayload,
                length: expected.rawPayloadLength,
                prefix: expected.rawPayloadPrefixBytes,
                suffix: expected.rawPayloadSuffixBytes
            )
        }
    }

    static func assertDocInfoStyles(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expectedStyles = expectations.docInfoStyles else {
            return
        }

        let actualStyles = hwp.docInfo.idMappings.styleArray

        for expected in expectedStyles {
            expect(actualStyles.indices).to(contain(expected.index))
            guard actualStyles.indices.contains(expected.index) else {
                continue
            }
            assertDocInfoStyle(actualStyles[expected.index], expected)
        }
    }

    static func assertDocInfoBullets(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expectedBullets = expectations.docInfoBullets else {
            return
        }

        let actualBullets = hwp.docInfo.idMappings.bulletArray
        expect(actualBullets.count) == expectedBullets.count

        for (actual, expected) in zip(actualBullets, expectedBullets) {
            assertRawPayloadSample(
                actual.rawPayload,
                length: expected.rawPayloadLength,
                prefix: expected.rawPayloadPrefixBytes,
                suffix: expected.rawPayloadSuffixBytes
            )
            assertRawPayloadSample(
                actual.charRawPayload,
                length: expected.charRawPayloadLength,
                prefix: expected.charRawPayloadPrefixBytes,
                suffix: expected.charRawPayloadSuffixBytes
            )
            assertRawPayloadSample(
                actual.checkCharRawPayload,
                length: expected.checkCharRawPayloadLength,
                prefix: expected.checkCharRawPayloadPrefixBytes,
                suffix: expected.checkCharRawPayloadSuffixBytes
            )
            if let undocumentedTrailingLength = expected.undocumentedTrailingLength {
                expect(actual.undocumentedTrailing.count) == undocumentedTrailingLength
            }
            assertRawPayloadSample(
                Data(actual.undocumentedTrailing),
                length: expected.undocumentedTrailingLength,
                prefix: expected.undocumentedTrailingPrefixBytes,
                suffix: expected.undocumentedTrailingSuffixBytes
            )
        }
    }

    static func assertDocInfoNumberings(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expectedNumberings = expectations.docInfoNumberings else {
            return
        }

        let actualNumberings = hwp.docInfo.idMappings.numberingArray
        expect(actualNumberings.count) == expectedNumberings.count

        for (actual, expected) in zip(actualNumberings, expectedNumberings) {
            assertRawPayloadSample(
                actual.rawPayload,
                length: expected.rawPayloadLength,
                prefix: expected.rawPayloadPrefixBytes,
                suffix: expected.rawPayloadSuffixBytes
            )
        }
    }
}

private func assertRawPayloadSample(
    _ rawPayload: Data?,
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?
) {
    guard length != nil || prefix != nil || suffix != nil else {
        return
    }
    guard let rawPayload else {
        return fail("Expected raw payload sample")
    }
    assertRawPayloadSample(rawPayload, length: length, prefix: prefix, suffix: suffix)
}

private func assertRawPayloadSample(
    _ rawPayload: Data,
    length: Int?,
    prefix: [UInt8]?,
    suffix: [UInt8]?
) {
    if let length {
        expect(rawPayload.count) == length
    }
    if let prefix {
        expect(Array(rawPayload.prefix(prefix.count))) == prefix
    }
    if let suffix {
        expect(Array(rawPayload.suffix(suffix.count))) == suffix
    }
}

private func assertDocInfoStyle(_ actual: HwpStyle, _ expected: FixtureStyleExpectations) {
    assertDocInfoStyleMetadata(actual, expected)
    assertDocInfoStylePayload(actual, expected)
}

private func assertDocInfoStyleMetadata(
    _ actual: HwpStyle,
    _ expected: FixtureStyleExpectations
) {
    if let localName = expected.localName {
        expect(actual.styleLocalName) == localName
    }
    if let englishName = expected.englishName {
        expect(actual.styelEnglishName) == englishName
    }
    assertRawPayloadSample(
        actual.styleLocalNameRawPayload,
        length: expected.localNameRawPayloadLength,
        prefix: expected.localNameRawPayloadPrefixBytes,
        suffix: expected.localNameRawPayloadSuffixBytes
    )
    assertRawPayloadSample(
        actual.styleEnglishNameRawPayload,
        length: expected.englishNameRawPayloadLength,
        prefix: expected.englishNameRawPayloadPrefixBytes,
        suffix: expected.englishNameRawPayloadSuffixBytes
    )
    if let property = expected.property {
        expect(actual.property) == property
    }
    if let nextId = expected.nextId {
        expect(actual.nextId) == nextId
    }
    if let languageId = expected.languageId {
        expect(actual.languageId) == languageId
    }
    if let paraShapeId = expected.paraShapeId {
        expect(actual.paraShapeId) == paraShapeId
    }
    if let charShapeId = expected.charShapeId {
        expect(actual.charShapeId) == charShapeId
    }
    if let unknownBytes = expected.unknownBytes {
        expect(actual.unknown) == unknownBytes
    }
    if let undocumentedTrailingLength = expected.undocumentedTrailingLength {
        expect(actual.undocumentedTrailing.count) == undocumentedTrailingLength
    }
    assertRawPayloadSample(
        Data(actual.undocumentedTrailing),
        length: expected.undocumentedTrailingLength,
        prefix: expected.undocumentedTrailingPrefixBytes,
        suffix: expected.undocumentedTrailingSuffixBytes
    )
}

private func assertDocInfoStylePayload(
    _ actual: HwpStyle,
    _ expected: FixtureStyleExpectations
) {
    if let rawPayloadLength = expected.rawPayloadLength {
        expect(actual.rawPayload.count) == rawPayloadLength
    }
    if let rawPayloadPrefixBytes = expected.rawPayloadPrefixBytes {
        expect(Array(actual.rawPayload.prefix(rawPayloadPrefixBytes.count))) ==
            rawPayloadPrefixBytes
    }
    if let rawPayloadSuffixBytes = expected.rawPayloadSuffixBytes {
        expect(Array(actual.rawPayload.suffix(rawPayloadSuffixBytes.count))) ==
            rawPayloadSuffixBytes
    }
}

private func assertCount(_ expected: Int?, _ actual: Int) {
    if let expected {
        expect(actual) == expected
    }
}

private func assertDocInfoIdMappingUnknownChildren(
    _ expected: FixtureDocInfoIdMappingsExpectations,
    _ mappings: HwpIdMappings
) {
    FixtureAssertions.assertUnknownRecordSamples(
        mappings.unknownChildren,
        rootLevel: 1,
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

private func assertDocInfoMappingRawPayloadTotals(
    _ expected: FixtureDocInfoIdMappingsExpectations,
    _ mappings: HwpIdMappings
) {
    if let expectedBytes = expected.faceNameRawPayloadTotalByteCount {
        let actual = [
            mappings.faceNameKoreanArray,
            mappings.faceNameEnglishArray,
            mappings.faceNameChineseArray,
            mappings.faceNameJapaneseArray,
            mappings.faceNameEtcArray,
            mappings.faceNameSymbolArray,
            mappings.faceNameUserArray,
        ].flatMap { $0 }.reduce(0) { $0 + $1.rawPayload.count }
        expect(actual) == expectedBytes
    }
    assertRawPayloadTotal(
        expected.borderFillRawPayloadTotalByteCount,
        mappings.borderFillArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.charShapeRawPayloadTotalByteCount,
        mappings.charShapeArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.tabDefRawPayloadTotalByteCount,
        mappings.tabDefArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.tabInfoRawPayloadTotalByteCount,
        mappings.tabDefArray.flatMap(\.tabInfoArray)
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.paraShapeRawPayloadTotalByteCount,
        mappings.paraShapeArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.memoShapeRawPayloadTotalByteCount,
        mappings.memoShapeArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.trackChangeRawPayloadTotalByteCount,
        mappings.trackChangeArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.trackChangeContentRawPayloadBytes,
        mappings.trackChangeContentArray
    ) { $0.rawPayload.count }
    assertRawPayloadTotal(
        expected.trackChangeAuthorRawPayloadBytes,
        mappings.trackChangeAuthorArray
    ) { $0.rawPayload.count }
}

private func assertRawPayloadTotal<T>(
    _ expected: Int?,
    _ actualRecords: [T],
    payloadLength: (T) -> Int
) {
    if let expected {
        let actual = actualRecords.reduce(0) { $0 + payloadLength($1) }
        expect(actual) == expected
    }
}
