@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlBookmarkTests: XCTestCase {
    func testBookmarkControlExposesParsedBookmarkInfoFromCtrlData() throws {
        let name = "CoreHwpBookmark"
        let ctrlDataPayload = bookmarkCtrlDataPayload(name: name)
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.bookmark(control))
        )

        expect(control.ctrlId) == .bookmark
        expect(control.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(control.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(control.bookmarkInfo?.name) == name
        expect(control.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(control.bookmarkInfo?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing).to(beEmpty())
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]

        guard case let .bookmark(roundTripped) = decoded else {
            return fail("Expected bookmark after Codable round-trip")
        }
        expect(roundTripped.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(roundTripped.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(roundTripped.bookmarkInfo?.name) == name
        expect(roundTripped.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(roundTripped.bookmarkInfo?.rawTrailing) == Data()
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
    }

    func testBookmarkInfoPreservesRawTrailingAfterName() throws {
        let name = "CoreHwpBookmark"
        let rawTrailing = Data([0xAA, 0xBB])
        let ctrlDataPayload = bookmarkCtrlDataPayload(name: name, rawTrailing: rawTrailing)
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.bookmark(control))
        )

        expect(control.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(control.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(control.bookmarkInfo?.name) == name
        expect(control.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(control.bookmarkInfo?.rawTrailing) == rawTrailing
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]

        guard case let .bookmark(roundTripped) = decoded else {
            return fail("Expected bookmark after Codable round-trip")
        }
        expect(roundTripped.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(roundTripped.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(roundTripped.bookmarkInfo?.name) == name
        expect(roundTripped.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(roundTripped.bookmarkInfo?.rawTrailing) == rawTrailing
    }

    func testBookmarkControlDecodesUtf16SurrogatePairsFromCtrlData() throws {
        let name = "CoreHwp🔖"
        let ctrlDataPayload = bookmarkCtrlDataPayload(name: name)
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)

        expect(control.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(control.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(control.bookmarkInfo?.name) == name
        expect(control.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(control.bookmarkInfo?.rawTrailing) == Data()
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
    }

    func testMalformedBookmarkCtrlDataIsPreservedWithoutParsedBookmarkInfo() throws {
        let ctrlDataPayload = Data([
            0x1B, 0x02, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x40,
            0x01, 0x00, 0x05, 0x00,
            0x43, 0x00,
        ])
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.bookmark(control))
        )

        expect(control.bookmarkInfo).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]

        guard case let .bookmark(roundTripped) = decoded else {
            return fail("Expected bookmark after Codable round-trip")
        }
        expect(roundTripped.bookmarkInfo).to(beNil())
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
    }

    func testBookmarkControlSkipsMalformedCtrlDataAndPreservesAllCtrlDataRecords() throws {
        let name = "SecondBookmark"
        let malformedPayload = Data([
            0x1B, 0x02, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x40,
            0x01, 0x00, 0x05, 0x00,
            0x43, 0x00,
        ])
        let validPayload = bookmarkCtrlDataPayload(name: name)
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: malformedPayload),
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: validPayload),
        ]

        let control = try HwpOtherControl.load(record)

        expect(control.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(control.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(control.bookmarkInfo?.name) == name
        expect(control.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(control.bookmarkInfo?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [malformedPayload, validPayload]
    }

    func testBookmarkControlWithInvalidUtf16IsPreservedWithoutParsedBookmarkInfo() throws {
        var ctrlDataPayload = Data([
            0x1B, 0x02, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x40,
            0x01, 0x00,
        ])
        ctrlDataPayload.append(littleEndianData(UInt16(1)))
        ctrlDataPayload.append(littleEndianData(WCHAR(0xD800)))

        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.bookmark(control))
        )

        expect(control.bookmarkInfo).to(beNil())
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]

        guard case let .bookmark(roundTripped) = decoded else {
            return fail("Expected bookmark after Codable round-trip")
        }
        expect(roundTripped.bookmarkInfo).to(beNil())
        expect(roundTripped.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
    }

    func testBookmarkCtrlDataWithNonZeroDataStartIndexDoesNotTrap() throws {
        let name = "CoreHwpBookmark"
        let ctrlDataPayload = bookmarkCtrlDataPayload(name: name)
        let paddedPayload = Data([0xAA, 0xBB]) + ctrlDataPayload
        let slicedPayload = paddedPayload.dropFirst(2)
        let rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: slicedPayload),
        ]

        let control = try HwpOtherControl.load(record)

        expect(control.bookmarkInfo?.nameCharacterCount) == name.utf16.count
        expect(control.bookmarkInfo?.nameLengthRawPayload) ==
            littleEndianData(UInt16(name.utf16.count))
        expect(control.bookmarkInfo?.name) == name
        expect(control.bookmarkInfo?.nameRawPayload) == utf16LittleEndianData(name)
        expect(control.bookmarkInfo?.rawTrailing) == Data()
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [slicedPayload]
    }

    func testNonBookmarkControlDoesNotParseBookmarkInfoFromCtrlData() throws {
        let ctrlDataPayload = bookmarkCtrlDataPayload(name: "CoreHwpBookmark")
        let rawPayload = littleEndianData(HwpOtherCtrlId.indexmark.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: ctrlDataPayload),
        ]

        let control = try HwpOtherControl.load(record)

        expect(control.ctrlId) == .indexmark
        expect(control.bookmarkInfo).to(beNil())
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
    }
}

private func bookmarkCtrlDataPayload(name: String, rawTrailing: Data = Data()) -> Data {
    var payload = Data([
        0x1B, 0x02, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x40,
        0x01, 0x00,
    ])
    payload.append(littleEndianData(UInt16(name.utf16.count)))
    for character in name.utf16 {
        payload.append(littleEndianData(character))
    }
    payload.append(rawTrailing)
    return payload
}

private func utf16LittleEndianData(_ text: String) -> Data {
    text.utf16.reduce(into: Data()) { data, character in
        data.append(littleEndianData(character))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
