@testable import CoreHwp
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(SwiftUI)
    import SwiftUI
#endif
import Foundation
import Nimble
import XCTest

final class ModelPrimitiveTests: XCTestCase {
    func testDefaultPrimitiveValues() {
        let hwp = HwpFile()
        expect(hwp.fileHeader.rawPayload).to(beEmpty())
        expect(hwp.summary.rawPayload).to(beEmpty())
        expect(hwp.previewImage.rawPayload).to(beEmpty())
        expect(hwp.previewImage.image).to(beEmpty())
        expect(hwp.previewImage.format) == HwpPreviewImageFormat.none
        expect(hwp.binaryDataArray).to(beEmpty())

        expect(HwpFileHeader().rawPayload).to(beEmpty())
        expect(HwpSummary().rawPayload).to(beEmpty())
        expect(HwpPreviewImage().rawPayload).to(beEmpty())
        expect(HwpPreviewImage().image).to(beEmpty())
        expect(HwpPreviewImage().format) == HwpPreviewImageFormat.none
        expect(HwpPreviewText().text) == "\r\n"
        expect(HwpPreviewText().rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])

        let listHeader = HwpListHeader()
        expect(listHeader.rawPayload).to(beEmpty())
        expect(listHeader.paragraphCount) == 0
        expect(listHeader.property) == 0
        expect(listHeader.rawTrailing).to(beEmpty())

        let rangeTag = HwpParaRangeTag()
        expect(rangeTag.start) == 0
        expect(rangeTag.end) == 0
        expect(rangeTag.tag) == 0

        let binData = HwpBinData()
        expect(binData.property.type) == .link
        expect(binData.property.compressType) == .followStorage
        expect(binData.property.state) == .never
        expect(binData.absolutePath).to(beNil())
        expect(binData.relativePath).to(beNil())
        expect(binData.streamId).to(beNil())
        expect(binData.extensionName).to(beNil())
    }

    func testBinaryDataPreservesNameAndPayload() {
        let data = Data([1, 2, 3])
        let binaryData = HwpBinaryData(name: "BIN0001.png", data: data)

        expect(HwpBinaryData().name) == ""
        expect(HwpBinaryData().data).to(beEmpty())
        expect(binaryData.name) == "BIN0001.png"
        expect(binaryData.data) == data
    }

    func testParaRangeTagLoad() throws {
        let tag = try HwpParaRangeTag.load(
            littleEndianData(UInt32(1))
                + littleEndianData(UInt32(9))
                + littleEndianData(UInt32(0xABCD_EF01))
        )

        expect(tag.start) == 1
        expect(tag.end) == 9
        expect(tag.tag) == 0xABCD_EF01
    }

    func testListHeaderLoad() throws {
        let payload = littleEndianData(Int32(3))
            + littleEndianData(UInt32(0x0102_0304))
            + Data([0xAA, 0xBB])
        let header = try HwpListHeader.load(payload)

        expect(header.rawPayload) == payload
        expect(header.paragraphCount) == 3
        expect(header.property) == 0x0102_0304
        expect(header.rawTrailing) == Data([0xAA, 0xBB])
    }

    func testZonePropertyLoad() throws {
        let property = try HwpZoneProperty.load(
            littleEndianData(UInt16(1))
                + littleEndianData(UInt16(2))
                + littleEndianData(UInt16(3))
                + littleEndianData(UInt16(4))
                + littleEndianData(UInt16(5))
        )

        expect(property.startColumnIndex) == 1
        expect(property.startRowIndex) == 2
        expect(property.endColumnIndex) == 3
        expect(property.endRowIndex) == 4
        expect(property.borderFillId) == 5
    }

    func testTablePropertyLoadWithZoneInfo() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        var data = Data()
        data.append(littleEndianData(UInt32(0)))
        data.append(littleEndianData(UInt16(0)))
        data.append(littleEndianData(UInt16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(UInt16(7)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt16(2)))
        data.append(littleEndianData(UInt16(3)))
        data.append(littleEndianData(UInt16(4)))
        data.append(littleEndianData(UInt16(5)))
        data.append(rawTrailing)
        let tableProperty = try HwpTableProperty.load(data, HwpVersion(5, 0, 1, 0))

        expect(tableProperty.rawPayload) == data
        expect(tableProperty.rawTrailing) == rawTrailing
        expect(tableProperty.borderFillId) == 7
        expect(tableProperty.validZoneInfoSize) == 1
        expect(tableProperty.zonePropertyArray?.first?.borderFillId) == 5
    }

    func testTablePropertyLargeRowCountThrowsTypedError() {
        let rowCount = UInt16.max
        var data = Data()
        data.append(littleEndianData(UInt32(0)))
        data.append(littleEndianData(rowCount))
        data.append(littleEndianData(UInt16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))
        data.append(littleEndianData(HWPUNIT16(0)))

        expect {
            _ = try HwpTableProperty.load(data, HwpVersion(5, 0, 0, 0))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == Int(rowCount) * MemoryLayout<UInt16>.size
            expect(actual) == 0
        })
    }

    func testHwpColorFromColorRef() {
        let color = HwpColor(0x0033_2211)

        expect(color.red) == 0x11
        expect(color.green) == 0x22
        expect(color.blue) == 0x33
    }

    #if os(macOS)
        func testHwpColorPlatformConversions() {
            let color = HwpColor(255, 127, 0)

            expect(color.cgColor.alpha) == 1
            expect(color.nsColor.cgColor.alpha) == 1
            #if canImport(SwiftUI)
                _ = color.color()
            #endif
        }
    #endif

    func testBinDataLinkLoad() throws {
        let binData = try HwpBinData.load(
            littleEndianData(UInt16(0))
                + wcharStringData("/tmp/image.png")
                + wcharStringData("image.png")
        )

        expect(binData.property.type) == .link
        expect(binData.absolutePath) == "/tmp/image.png"
        expect(binData.relativePath) == "image.png"
        expect(binData.streamId).to(beNil())
        expect(binData.extensionName).to(beNil())
    }

    func testBinDataStorageLoad() throws {
        let property = UInt16(HwpBinDataType.storage.rawValue)
            | UInt16(HwpBinDataCompressType.always.rawValue << 4)
            | UInt16(HwpBinDataState.failed.rawValue << 6)
        let binData = try HwpBinData.load(
            littleEndianData(property)
                + littleEndianData(UInt16(42))
                + wcharStringData("ole")
        )

        expect(binData.property.type) == .storage
        expect(binData.property.compressType) == .always
        expect(binData.property.state) == .failed
        expect(binData.streamId) == 42
        expect(binData.extensionName) == "ole"
    }

    func testBinDataPropertyLoadsIgnoredState() throws {
        let property = try HwpBinDataProperty.load(
            UInt16(HwpBinDataType.link.rawValue)
                | UInt16(HwpBinDataCompressType.followStorage.rawValue << 4)
                | UInt16(HwpBinDataState.ignored.rawValue << 6)
        )

        expect(property.type) == .link
        expect(property.compressType) == .followStorage
        expect(property.state) == .ignored
    }

    func testBinDataPropertyInvalidRawValuesThrow() {
        expect {
            _ = try HwpBinDataProperty.load(UInt16(0x000F))
        }.to(throwError { error in
            guard case let HwpError.invalidRawValueForEnum(_, rawValue) = error else {
                return fail("Expected invalidRawValueForEnum, got \(error)")
            }
            expect(rawValue) == 15
        })

        expect {
            _ = try HwpBinDataProperty.load(UInt16(0x0030))
        }.to(throwError { error in
            guard case let HwpError.invalidRawValueForEnum(_, rawValue) = error else {
                return fail("Expected invalidRawValueForEnum, got \(error)")
            }
            expect(rawValue) == 3
        })
    }

    func testColumnPropertyInvalidRawValuesThrow() {
        expect {
            _ = try HwpColumnProperty.load(UInt16(3))
        }.to(throwError { error in
            guard case let HwpError.invalidRawValueForEnum(_, rawValue) = error else {
                return fail("Expected invalidRawValueForEnum, got \(error)")
            }
            expect(rawValue) == 3
        })

        expect {
            _ = try HwpColumnProperty.load(UInt16(3 << 10))
        }.to(throwError { error in
            guard case let HwpError.invalidRawValueForEnum(_, rawValue) = error else {
                return fail("Expected invalidRawValueForEnum, got \(error)")
            }
            expect(rawValue) == 3
        })
    }

    func testCharShapePropertyInvalidRawValuesThrow() {
        for value in [UInt32(3 << 2), UInt32(7 << 8), UInt32(3 << 11), UInt32(7 << 21)] {
            expect {
                _ = try HwpCharShapeProperty.load(value)
            }.to(throwError { error in
                guard case HwpError.invalidRawValueForEnum = error else {
                    return fail("Expected invalidRawValueForEnum, got \(error)")
                }
            })
        }
    }

    func testFaceNameLoadWithOptionalFields() throws {
        let faceTypeInfo = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let faceName = try HwpFaceName.load(
            Data([0xE0])
                + wcharStringData("Base")
                + Data([1])
                + wcharStringData("Alt")
                + faceTypeInfo
                + wcharStringData("Default")
        )

        expect(faceName.property) == 0xE0
        expect(faceName.faceName) == "Base"
        expect(faceName.alternativeFaceType) == 1
        expect(faceName.alternativeFaceNameLength) == 3
        expect(faceName.alternativeFaceName) == "Alt"
        expect(faceName.faceTypeInfo) == Array(faceTypeInfo)
        expect(faceName.defaultFaceNameLength) == 7
        expect(faceName.defaultFaceName) == "Default"
    }

    func testFaceNameConvenienceInit() {
        let faceName = HwpFaceName("Base", [1, 2, 3], "Default")

        expect(faceName.property) == 97
        expect(faceName.faceNameLength) == 4
        expect(faceName.faceName) == "Base"
        expect(faceName.faceTypeInfo) == [1, 2, 3]
        expect(faceName.defaultFaceNameLength) == 7
        expect(faceName.defaultFaceName) == "Default"
    }

    func testDataExtensions() throws {
        let data = Data([0b0000_0011, 0b1000_0000])

        expect(data.bytes) == [3, 128]
        expect(data.bits.count) == 16
        expect(Data("HWP".utf8).stringASCII) == "HWP"

        var values = [1, 2, 3, 4]
        expect(try values.pop(2)) == [1, 2]
        expect(values) == [3, 4]
        expect([UInt8(1), UInt8(2)].data) == Data([1, 2])
    }

    func testArrayPopRejectsUnavailableCount() {
        expect {
            var values = [1]
            _ = try values.pop(2)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds available child records"))
        })
    }

    func testCharacterCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Character("한"))
        let decoded = try JSONDecoder().decode(Character.self, from: data)

        expect(decoded) == "한"
    }

    func testCharacterDecodeRejectsEmptyAndLongStrings() {
        expect {
            _ = try JSONDecoder().decode(Character.self, from: Data("[\"\"]".utf8))
        }.to(throwError())
        expect {
            _ = try JSONDecoder().decode(Character.self, from: Data("[\"ab\"]".utf8))
        }.to(throwError())
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func wcharStringData(_ string: String) -> Data {
    var data = littleEndianData(UInt16(string.utf16.count))
    for value in string.utf16 {
        data.append(littleEndianData(value))
    }
    return data
}
