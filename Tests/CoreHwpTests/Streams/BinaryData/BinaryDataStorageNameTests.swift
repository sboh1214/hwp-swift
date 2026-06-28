@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BinaryDataStorageNameTests: XCTestCase {
    func testBinaryDataParsesStorageNameMetadata() {
        let binaryData = HwpBinaryData(name: "BIN0042.JPG", data: Data([0xCA, 0xFE]))

        expect(binaryData.name) == "BIN0042.JPG"
        expect(binaryData.streamId) == 42
        expect(binaryData.extensionName) == "JPG"
        expect(binaryData.data) == Data([0xCA, 0xFE])
    }

    func testBinaryDataParsesCanonicalStorageNameBoundaryIds() {
        let zeroIdData = HwpBinaryData(name: "BIN0000.bmp", data: Data([0x00]))
        let maxFourDigitData = HwpBinaryData(name: "BIN9999.OLE", data: Data([0x99]))

        expect(zeroIdData.streamId) == 0
        expect(zeroIdData.extensionName) == "bmp"
        expect(zeroIdData.data) == Data([0x00])
        expect(maxFourDigitData.streamId) == 9999
        expect(maxFourDigitData.extensionName) == "OLE"
        expect(maxFourDigitData.data) == Data([0x99])
    }

    func testBinaryDataPreservesUnrecognizedStorageNameWithoutMetadata() {
        for name in [
            "bin0001.jpg",
            "BiN0001.jpg",
            "BIN42.jpg",
            "BIN10000.jpg",
            "BIN0001.",
            "BIN0001.jpg.extra",
            "OTHER0001.jpg",
            "BINABCD.jpg",
            "BIN１２３４.jpg",
            "BIN١٢٣٤.jpg",
        ] {
            let binaryData = HwpBinaryData(name: name, data: Data([0xAA]))

            expect(binaryData.name) == name
            expect(binaryData.streamId).to(beNil())
            expect(binaryData.extensionName).to(beNil())
            expect(binaryData.data) == Data([0xAA])
        }
    }
}
