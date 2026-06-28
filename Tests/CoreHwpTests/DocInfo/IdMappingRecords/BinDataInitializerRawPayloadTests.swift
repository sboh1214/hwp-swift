@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BinDataInitializerRawPayloadTests: XCTestCase {
    func testLinkBinDataInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = binDataInitializerLittleEndianData(UInt16(0))
            + binDataInitializerUTF16LengthPrefixedString("/tmp/image.png")
            + binDataInitializerUTF16LengthPrefixedString("image.png")
        let slicedPayload = (Data([0xFF, 0xEE]) + payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let binData = try HwpBinData(&reader)

        expect(binData.rawPayload) == slicedPayload
        expect(binData.absolutePathRawPayload) ==
            binDataInitializerUTF16StringPayload("/tmp/image.png")
        expect(binData.relativePathRawPayload) == binDataInitializerUTF16StringPayload("image.png")
        expect(reader.isEOF) == true
    }

    func testEmbeddedBinDataInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = embeddedBinDataInitializerPayload()
        let slicedPayload = (Data([0xFF, 0xEE]) + payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let binData = try HwpBinData(&reader)

        expect(binData.rawPayload) == slicedPayload
        expect(binData.streamId) == 42
        expect(binData.extensionNameRawPayload) == binDataInitializerUTF16StringPayload("jpg")
        expect(reader.isEOF) == true
    }
}

private func embeddedBinDataInitializerPayload() -> Data {
    let property = UInt16(HwpBinDataType.embedding.rawValue)
        | UInt16(HwpBinDataCompressType.never.rawValue << 4)
        | UInt16(HwpBinDataState.successed.rawValue << 6)
    return binDataInitializerLittleEndianData(property)
        + binDataInitializerLittleEndianData(UInt16(42))
        + binDataInitializerUTF16LengthPrefixedString("jpg")
}

private func binDataInitializerUTF16LengthPrefixedString(_ string: String) -> Data {
    var data = Data()
    data.append(binDataInitializerLittleEndianData(UInt16(string.utf16.count)))
    data.append(binDataInitializerUTF16StringPayload(string))
    return data
}

private func binDataInitializerUTF16StringPayload(_ string: String) -> Data {
    var data = Data()
    for codeUnit in string.utf16 {
        data.append(binDataInitializerLittleEndianData(UInt16(codeUnit)))
    }
    return data
}

private func binDataInitializerLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
