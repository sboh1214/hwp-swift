@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoIdMappingFixtureTests: XCTestCase {
    func testNooriDocInfoIdMappingRawPayloadsSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "noori")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        FixtureAssertions.assertDocInfoIdMappings(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertDocInfoStyles(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertDocInfoNumberings(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertDocInfoBullets(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertDocInfoBinData(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertDocInfoRawRecords(fixture.manifest.expectations, decoded)
        assertDocInfoIdMappingPayloadsMatch(decoded.docInfo.idMappings, hwp.docInfo.idMappings)
        assertDocInfoRawRecordPayloadsMatch(decoded.docInfo, hwp.docInfo)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func assertDocInfoIdMappingPayloadsMatch(
    _ decoded: HwpIdMappings,
    _ original: HwpIdMappings
) {
    assertFaceNameArraysPayloadsMatch(decoded, original)
    assertCoreDocInfoIdMappingPayloadsMatch(decoded, original)
    assertStyleNumberingBulletPayloadsMatch(decoded, original)
    assertDocInfoIdMappingRawRecordPayloadsMatch(decoded, original)
    expect(decoded.unknownChildren) == original.unknownChildren
}

private func assertFaceNameArraysPayloadsMatch(
    _ decoded: HwpIdMappings,
    _ original: HwpIdMappings
) {
    assertFaceNamePayloadsMatch(decoded.faceNameKoreanArray, original.faceNameKoreanArray)
    assertFaceNamePayloadsMatch(decoded.faceNameEnglishArray, original.faceNameEnglishArray)
    assertFaceNamePayloadsMatch(decoded.faceNameChineseArray, original.faceNameChineseArray)
    assertFaceNamePayloadsMatch(decoded.faceNameJapaneseArray, original.faceNameJapaneseArray)
    assertFaceNamePayloadsMatch(decoded.faceNameEtcArray, original.faceNameEtcArray)
    assertFaceNamePayloadsMatch(decoded.faceNameSymbolArray, original.faceNameSymbolArray)
    assertFaceNamePayloadsMatch(decoded.faceNameUserArray, original.faceNameUserArray)
}

private func assertCoreDocInfoIdMappingPayloadsMatch(
    _ decoded: HwpIdMappings,
    _ original: HwpIdMappings
) {
    assertBinDataPayloadsMatch(decoded.binDataArray, original.binDataArray)
    expect(decoded.borderFillArray.map(\.rawPayload)) ==
        original.borderFillArray.map(\.rawPayload)
    expect(decoded.charShapeArray.map(\.rawPayload)) ==
        original.charShapeArray.map(\.rawPayload)
    expect(decoded.tabDefArray.map(\.rawPayload)) == original.tabDefArray.map(\.rawPayload)
    expect(decoded.tabDefArray.map { $0.tabInfoArray.map(\.rawPayload) }) ==
        original.tabDefArray.map { $0.tabInfoArray.map(\.rawPayload) }
    expect(decoded.paraShapeArray.map(\.rawPayload)) ==
        original.paraShapeArray.map(\.rawPayload)
}

private func assertStyleNumberingBulletPayloadsMatch(
    _ decoded: HwpIdMappings,
    _ original: HwpIdMappings
) {
    expect(decoded.styleArray.map(\.rawPayload)) == original.styleArray.map(\.rawPayload)
    expect(decoded.styleArray.map(\.styleLocalNameRawPayload)) ==
        original.styleArray.map(\.styleLocalNameRawPayload)
    expect(decoded.styleArray.map(\.styleEnglishNameRawPayload)) ==
        original.styleArray.map(\.styleEnglishNameRawPayload)
    expect(decoded.numberingArray.map(\.rawPayload)) == original.numberingArray.map(\.rawPayload)
    expect(decoded.numberingArray.map { $0.formatArray.map(\.formatRawPayload) }) ==
        original.numberingArray.map { $0.formatArray.map(\.formatRawPayload) }
    expect(decoded.numberingArray.map { $0.extendedFormatArray?.map(\.formatRawPayload) }) ==
        original.numberingArray.map { $0.extendedFormatArray?.map(\.formatRawPayload) }
    expect(decoded.bulletArray.map(\.rawPayload)) == original.bulletArray.map(\.rawPayload)
    expect(decoded.bulletArray.map(\.charRawPayload)) == original.bulletArray.map(\.charRawPayload)
    expect(decoded.bulletArray.map(\.checkCharRawPayload)) ==
        original.bulletArray.map(\.checkCharRawPayload)
    expect(decoded.bulletArray.map(\.undocumentedTrailing)) ==
        original.bulletArray.map(\.undocumentedTrailing)
}

private func assertDocInfoIdMappingRawRecordPayloadsMatch(
    _ decoded: HwpIdMappings,
    _ original: HwpIdMappings
) {
    expect(decoded.memoShapeArray.map(\.rawPayload)) == original.memoShapeArray.map(\.rawPayload)
    expect(decoded.memoShapeArray.map(\.shapeInfo?.rawTrailing)) ==
        original.memoShapeArray.map(\.shapeInfo?.rawTrailing)
    expect(decoded.trackChangeArray.map(\.rawPayload)) ==
        original.trackChangeArray.map(\.rawPayload)
    expect(decoded.trackChangeArray.map(\.unknownChildren)) ==
        original.trackChangeArray.map(\.unknownChildren)
    assertTrackChangeContentPayloadsMatch(
        decoded.trackChangeContentArray,
        original.trackChangeContentArray
    )
    assertTrackChangeAuthorPayloadsMatch(
        decoded.trackChangeAuthorArray,
        original.trackChangeAuthorArray
    )
    expect(decoded.forbiddenCharArray.map(\.rawPayload)) ==
        original.forbiddenCharArray.map(\.rawPayload)
    expect(decoded.forbiddenCharArray.map(\.data)) == original.forbiddenCharArray.map(\.data)
    expect(decoded.forbiddenCharArray.map(\.unknownChildren)) ==
        original.forbiddenCharArray.map(\.unknownChildren)
}

private func assertFaceNamePayloadsMatch(
    _ decoded: [HwpFaceName],
    _ original: [HwpFaceName]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.faceNameRawPayload)) == original.map(\.faceNameRawPayload)
    expect(decoded.map(\.alternativeFaceNameRawPayload)) ==
        original.map(\.alternativeFaceNameRawPayload)
    expect(decoded.map(\.defaultFaceNameRawPayload)) == original.map(\.defaultFaceNameRawPayload)
}

private func assertBinDataPayloadsMatch(_ decoded: [HwpBinData], _ original: [HwpBinData]) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.absolutePathRawPayload)) == original.map(\.absolutePathRawPayload)
    expect(decoded.map(\.relativePathRawPayload)) == original.map(\.relativePathRawPayload)
    expect(decoded.map(\.extensionNameRawPayload)) == original.map(\.extensionNameRawPayload)
}

private func assertTrackChangeContentPayloadsMatch(
    _ decoded: [HwpTrackChangeContent],
    _ original: [HwpTrackChangeContent]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.contentInfo?.rawTrailing)) ==
        original.map(\.contentInfo?.rawTrailing)
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
}

private func assertTrackChangeAuthorPayloadsMatch(
    _ decoded: [HwpTrackChangeAuthor],
    _ original: [HwpTrackChangeAuthor]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.authorInfo?.nameRawPayload)) ==
        original.map(\.authorInfo?.nameRawPayload)
    expect(decoded.map(\.authorInfo?.rawTrailing)) ==
        original.map(\.authorInfo?.rawTrailing)
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
}

private func assertDocInfoRawRecordPayloadsMatch(_ decoded: HwpDocInfo, _ original: HwpDocInfo) {
    expect(decoded.docData?.rawPayload) == original.docData?.rawPayload
    expect(decoded.docData?.forbiddenCharArray.map(\.rawPayload)) ==
        original.docData?.forbiddenCharArray.map(\.rawPayload)
    expect(decoded.docData?.forbiddenCharArray.map(\.data)) ==
        original.docData?.forbiddenCharArray.map(\.data)
    expect(decoded.docData?.forbiddenCharArray.map(\.unknownChildren)) ==
        original.docData?.forbiddenCharArray.map(\.unknownChildren)
    expect(decoded.docData?.unknownChildren) == original.docData?.unknownChildren
    expect(decoded.unknownRecords) == original.unknownRecords
}
