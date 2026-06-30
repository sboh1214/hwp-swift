@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlRealFixturePreservationTests: XCTestCase {
    func testFootnoteEndnoteFixtureAutoNumberControlsSurviveCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "footnote-endnote")
        let autoNumbers = FixtureDerivedValues
            .otherControls(from: hwp)
            .filter { $0.ctrlId == .autoNumber }

        expect(autoNumbers.count) == 2
        guard autoNumbers.count == 2 else {
            return
        }

        assertFootnoteAutoNumberControl(autoNumbers[0], kind: 2)
        assertFootnoteAutoNumberControl(autoNumbers[1], kind: 1)
        assertFootnoteAutoNumberControl(try roundTrippedAutoNumber(autoNumbers[0]), kind: 2)
        assertFootnoteAutoNumberControl(try roundTrippedAutoNumber(autoNumbers[1]), kind: 1)
    }

    func testLegacyFixtureNumberingAndPageHideControlsSurviveCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let autoNumber = try otherControl(.autoNumber, in: hwp)
        let newNumber = try otherControl(.newNumber, in: hwp)
        let pageHide = try otherControl(.pageHide, in: hwp)

        assertLegacyAutoNumberControl(autoNumber)
        assertLegacyNewNumberControl(newNumber)
        assertLegacyPageHideControl(pageHide)

        assertLegacyAutoNumberControl(try roundTrippedAutoNumber(autoNumber))
        assertLegacyNewNumberControl(try roundTrippedNewNumber(newNumber))
        assertLegacyPageHideControl(try roundTrippedPageHide(pageHide))
    }

    func testLegacyFixtureIndexmarkControlSurvivesCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let indexmark = try otherControl(.indexmark, in: hwp)

        assertLegacyIndexmarkControl(indexmark)
        assertLegacyIndexmarkControl(try roundTrippedIndexmark(indexmark))
    }

    func testBookmarkFixtureCtrlDataNameSurvivesCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "bookmark")
        let bookmark = try bookmarkControl(in: hwp)
        let encoded = try JSONEncoder().encode(HwpCtrlId.bookmark(bookmark))
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        assertBookmarkFixtureControl(bookmark)

        guard case let .bookmark(roundTripped) = decoded else {
            return fail("Expected bookmark after Codable round-trip")
        }

        assertBookmarkFixtureControl(roundTripped)
    }

    func testBookmarkFixtureControlSurvivesHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "bookmark")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let originalBookmark = try bookmarkControl(in: hwp)
        let decodedBookmark = try bookmarkControl(in: decoded)

        FixtureAssertions.assertOtherControls(
            fixture.manifest.expectations.otherControls ?? [],
            decoded
        )
        assertBookmarkFixtureControl(decodedBookmark)
        assertBookmarkPayloadsMatch(decodedBookmark, originalBookmark)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testLegacyFixtureHiddenCommentPreservesUnknownChildrenAndGrandchildren() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let hiddenComment = try hiddenCommentControl(in: hwp)

        assertLegacyHiddenCommentUnknownChildren(hiddenComment)
    }

    func testLegacyFixtureHiddenCommentUnknownChildrenSurviveCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let hiddenComment = try hiddenCommentControl(in: hwp)
        let encoded = try JSONEncoder().encode(HwpCtrlId.hiddenComment(hiddenComment))
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        guard case let .hiddenComment(roundTripped) = decoded else {
            return fail("Expected hiddenComment after Codable round-trip")
        }

        assertLegacyHiddenCommentUnknownChildren(roundTripped)
    }

    func testLegacyFixtureOtherControlsSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "legacy-common-control-property")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let originalControls = FixtureDerivedValues.otherControls(from: hwp)
        let decodedControls = FixtureDerivedValues.otherControls(from: decoded)

        FixtureAssertions.assertOtherControlSamples(
            fixture.manifest.expectations.otherControlSamples ?? [],
            decoded
        )
        assertLegacyHiddenCommentUnknownChildren(try hiddenCommentControl(in: decoded))
        assertOtherControlPayloadsMatch(decodedControls, originalControls)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func bookmarkControl(in hwp: HwpFile) throws -> HwpOtherControl {
    try otherControl(.bookmark, in: hwp)
}

private func hiddenCommentControl(in hwp: HwpFile) throws -> HwpOtherControl {
    try otherControl(.hiddenComment, in: hwp)
}

private func otherControl(_ ctrlId: HwpOtherCtrlId, in hwp: HwpFile) throws -> HwpOtherControl {
    guard let control = FixtureDerivedValues
        .otherControls(from: hwp)
        .first(where: { $0.ctrlId == ctrlId })
    else {
        fail("Expected fixture to contain \(ctrlId) control")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    return control
}

private func roundTrippedAutoNumber(_ control: HwpOtherControl) throws -> HwpOtherControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(HwpCtrlId.autoNumber(control))
    )

    guard case let .autoNumber(roundTripped) = decoded else {
        fail("Expected autoNumber after Codable round-trip")
        throw HwpError.invalidCtrlId(ctrlId: HwpOtherCtrlId.autoNumber.rawValue)
    }

    return roundTripped
}

private func roundTrippedNewNumber(_ control: HwpOtherControl) throws -> HwpOtherControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(HwpCtrlId.newNumber(control))
    )

    guard case let .newNumber(roundTripped) = decoded else {
        fail("Expected newNumber after Codable round-trip")
        throw HwpError.invalidCtrlId(ctrlId: HwpOtherCtrlId.newNumber.rawValue)
    }

    return roundTripped
}

private func roundTrippedPageHide(_ control: HwpOtherControl) throws -> HwpOtherControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(HwpCtrlId.pageHide(control))
    )

    guard case let .pageHide(roundTripped) = decoded else {
        fail("Expected pageHide after Codable round-trip")
        throw HwpError.invalidCtrlId(ctrlId: HwpOtherCtrlId.pageHide.rawValue)
    }

    return roundTripped
}

private func roundTrippedIndexmark(_ control: HwpOtherControl) throws -> HwpOtherControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(HwpCtrlId.indexmark(control))
    )

    guard case let .indexmark(roundTripped) = decoded else {
        fail("Expected indexmark after Codable round-trip")
        throw HwpError.invalidCtrlId(ctrlId: HwpOtherCtrlId.indexmark.rawValue)
    }

    return roundTripped
}

private func assertFootnoteAutoNumberControl(_ control: HwpOtherControl, kind: UInt32) {
    let kindBytes = kind == 2 ? Data([2, 0, 0, 0]) : Data([1, 0, 0, 0])
    let rawTrailing = concatenatedData(kindBytes, Data([1, 0, 0, 0, 0, 0, 41, 0]))
    let rawPayload = concatenatedData(Data([111, 110, 116, 97]), rawTrailing)

    expect(control.ctrlId) == .autoNumber
    expect(control.numberingInfo?.kind) == kind
    expect(control.numberingInfo?.number) == 1
    expect(control.numberingInfo?.format) == 2_686_976
    expect(control.numberingInfo?.rawTrailing).to(beEmpty())
    expect(control.rawPayload) == rawPayload
    expect(control.rawTrailing) == rawTrailing
    expect(control.ctrlDataRecords).to(beEmpty())
    expect(control.unknownChildren).to(beEmpty())
}

private func assertLegacyAutoNumberControl(_ control: HwpOtherControl) {
    expect(control.ctrlId) == .autoNumber
    expect(control.numberingInfo?.kind) == 1
    expect(control.numberingInfo?.number) == 1
    expect(control.numberingInfo?.format) == 2_686_976
    expect(control.numberingInfo?.rawTrailing).to(beEmpty())
    expect(control.rawPayload) == Data([111, 110, 116, 97, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 41, 0])
    expect(control.rawTrailing) == Data([1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 41, 0])
    expect(control.ctrlDataRecords).to(beEmpty())
    expect(control.unknownChildren).to(beEmpty())
}

private func assertLegacyNewNumberControl(_ control: HwpOtherControl) {
    expect(control.ctrlId) == .newNumber
    expect(control.numberingInfo).to(beNil())
    expect(control.rawPayload) == Data([111, 110, 119, 110, 0, 0, 0, 0, 1, 0])
    expect(control.rawTrailing) == Data([0, 0, 0, 0, 1, 0])
    expect(control.ctrlDataRecords).to(beEmpty())
    expect(control.unknownChildren).to(beEmpty())
}

private func assertLegacyPageHideControl(_ control: HwpOtherControl) {
    expect(control.ctrlId) == .pageHide
    expect(control.pageHideInfo?.rawValue) == 32
    expect(control.pageHideInfo?.rawTrailing).to(beEmpty())
    expect(control.rawPayload) == Data([100, 104, 103, 112, 32, 0, 0, 0])
    expect(control.rawTrailing) == Data([32, 0, 0, 0])
    expect(control.ctrlDataRecords).to(beEmpty())
    expect(control.unknownChildren).to(beEmpty())
}

private func assertLegacyIndexmarkControl(_ control: HwpOtherControl) {
    let textRawPayload = Data([28, 172, 196, 188, 137, 213, 4, 199, 36, 193])
    let infoTrailing = Data([0, 0, 0, 0, 0, 0])
    let rawTrailing = concatenatedData(Data([5, 0]), textRawPayload, infoTrailing)
    let rawPayload = concatenatedData(Data([109, 120, 100, 105]), rawTrailing)

    expect(control.ctrlId) == .indexmark
    expect(control.indexmarkInfo?.textCharacterCount) == 5
    expect(control.indexmarkInfo?.textLengthRawPayload) == Data([5, 0])
    expect(control.indexmarkInfo?.text) == "\u{AC1C}\u{BCC4}\u{D589}\u{C704}\u{C124}"
    expect(control.indexmarkInfo?.textRawPayload) == textRawPayload
    expect(control.indexmarkInfo?.rawTrailing) == infoTrailing
    expect(control.rawPayload) == rawPayload
    expect(control.rawTrailing) == rawTrailing
    expect(control.ctrlDataRecords).to(beEmpty())
    expect(control.unknownChildren).to(beEmpty())
}

private func assertOtherControlPayloadsMatch(
    _ decoded: [HwpOtherControl],
    _ original: [HwpOtherControl]
) {
    expect(decoded.map(\.ctrlId)) == original.map(\.ctrlId)
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map { $0.ctrlDataRecords.map(\.rawPayload) }) ==
        original.map { $0.ctrlDataRecords.map(\.rawPayload) }
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
}

private func assertBookmarkPayloadsMatch(
    _ decoded: HwpOtherControl,
    _ original: HwpOtherControl
) {
    expect(decoded.rawPayload) == original.rawPayload
    expect(decoded.rawTrailing) == original.rawTrailing
    expect(decoded.ctrlDataRecords.map(\.rawPayload)) ==
        original.ctrlDataRecords.map(\.rawPayload)
    expect(decoded.ctrlDataRecords.map(\.parameterSet)) ==
        original.ctrlDataRecords.map(\.parameterSet)
    expect(decoded.bookmarkInfo?.nameCharacterCount) ==
        original.bookmarkInfo?.nameCharacterCount
    expect(decoded.bookmarkInfo?.nameLengthRawPayload) ==
        original.bookmarkInfo?.nameLengthRawPayload
    expect(decoded.bookmarkInfo?.name) == original.bookmarkInfo?.name
    expect(decoded.bookmarkInfo?.rawTrailing) == original.bookmarkInfo?.rawTrailing
    expect(decoded.unknownChildren) == original.unknownChildren
}

private func assertBookmarkFixtureControl(_ bookmark: HwpOtherControl) {
    expect(bookmark.ctrlId) == .bookmark
    expect(bookmark.bookmarkInfo?.nameCharacterCount) == 15
    expect(bookmark.bookmarkInfo?.nameLengthRawPayload) == Data([15, 0])
    expect(bookmark.bookmarkInfo?.name) == "CoreHwpBookmark"
    expect(bookmark.bookmarkInfo?.rawTrailing).to(beEmpty())
    expect(bookmark.rawPayload) == Data([109, 107, 111, 98])
    expect(bookmark.rawTrailing).to(beEmpty())
    expect(bookmark.ctrlDataRecords.map(\.rawPayload.count)) == [42]
    expect(bookmark.ctrlDataRecords.map { Array($0.rawPayload.prefix(16)) }) == [
        [27, 2, 1, 0, 0, 0, 0, 64, 1, 0, 15, 0, 67, 0, 111, 0],
    ]
    expect(bookmark.ctrlDataRecords.map { Array($0.rawPayload.suffix(16)) }) == [
        [66, 0, 111, 0, 111, 0, 107, 0, 109, 0, 97, 0, 114, 0, 107, 0],
    ]
    assertBookmarkFixtureCtrlDataParameterSet(bookmark.ctrlDataRecords.first)
    expect(bookmark.unknownChildren).to(beEmpty())
}

private func assertBookmarkFixtureCtrlDataParameterSet(_ ctrlData: HwpCtrlData?) {
    expect(ctrlData?.parameterSet?.parameterSetId) == 0x021B
    expect(ctrlData?.parameterSet?.parameterSetIdRawPayload) == Data([27, 2])
    expect(ctrlData?.parameterSet?.itemCount) == 1
    expect(ctrlData?.parameterSet?.itemCountRawPayload) == Data([1, 0])
    expect(ctrlData?.parameterSet?.stringItem.itemId) == 0x4000_0000
    expect(ctrlData?.parameterSet?.stringItem.itemIdRawPayload) == Data([0, 0, 0, 64])
    expect(ctrlData?.parameterSet?.stringItem.valueType) == 1
    expect(ctrlData?.parameterSet?.stringItem.valueTypeRawPayload) == Data([1, 0])
    expect(ctrlData?.parameterSet?.stringItem.valueCharacterCount) == 15
    expect(ctrlData?.parameterSet?.stringItem.valueLengthRawPayload) == Data([15, 0])
    expect(ctrlData?.parameterSet?.stringItem.value) == "CoreHwpBookmark"
    expect(ctrlData?.parameterSet?.stringItem.valueRawPayload.count) == 30
    expect(ctrlData?.parameterSet?.stringItem.valueRawPayload.prefix(2)) == Data([67, 0])
    expect(ctrlData?.parameterSet?.stringItem.valueRawPayload.suffix(2)) == Data([107, 0])
    expect(ctrlData?.parameterSet?.stringItem.rawTrailing).to(beEmpty())
}

private func assertLegacyHiddenCommentUnknownChildren(_ hiddenComment: HwpOtherControl) {
    expect(hiddenComment.ctrlId) == .hiddenComment
    expect(hiddenComment.rawPayload) == Data([116, 109, 99, 116])
    expect(hiddenComment.rawTrailing).to(beEmpty())
    FixtureAssertions.assertUnknownRecordSamples(
        hiddenComment.unknownChildren,
        rootLevel: 2,
        expectations: FixtureUnknownRecordSampleExpectations(
            tagIds: [72, 66],
            payloadLengths: [16, 22],
            payloadPrefixes: [
                [1, 0, 0, 0, 0, 0, 0, 0],
                [1, 0, 0, 128, 0, 0, 0, 0],
            ],
            payloadSuffixes: [
                [0, 0, 0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0, 0, 128],
            ],
            childTagIds: [
                [],
                [68],
            ],
            childPayloadLengths: [
                [],
                [8],
            ],
            childPayloadPrefixes: [
                [],
                [[0, 0, 0, 0, 17, 0, 0, 0]],
            ],
            childPayloadSuffixes: [
                [],
                [[0, 0, 0, 0, 17, 0, 0, 0]],
            ]
        )
    )
}
