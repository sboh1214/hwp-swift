@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BinaryDataStorageNameTests: XCTestCase {
    func testBinaryDataParsesStorageNameMetadata() {
        // Stream 이름의 id는 16진수다 (BIN%04X): 0x42 = 66
        let binaryData = HwpBinaryData(name: "BIN0042.JPG", data: Data([0xCA, 0xFE]))

        expect(binaryData.name) == "BIN0042.JPG"
        expect(binaryData.streamId) == 0x42
        expect(binaryData.extensionName) == "JPG"
        expect(binaryData.data) == Data([0xCA, 0xFE])
    }

    func testBinaryDataParsesCanonicalStorageNameBoundaryIds() {
        let zeroIdData = HwpBinaryData(name: "BIN0000.bmp", data: Data([0x00]))
        let maxIdData = HwpBinaryData(name: "BINFFFF.OLE", data: Data([0x99]))
        let hexDigitsData = HwpBinaryData(name: "BIN00AB.jpg", data: Data([0xAB]))

        expect(zeroIdData.streamId) == 0
        expect(zeroIdData.extensionName) == "bmp"
        expect(zeroIdData.data) == Data([0x00])
        expect(maxIdData.streamId) == 0xFFFF
        expect(maxIdData.extensionName) == "OLE"
        expect(maxIdData.data) == Data([0x99])
        expect(hexDigitsData.streamId) == 0xAB
        expect(hexDigitsData.extensionName) == "jpg"
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
            "BINGHIJ.jpg",
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
