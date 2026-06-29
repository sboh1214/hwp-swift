@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BinDataRawPayloadTests: XCTestCase {
    func testLinkBinDataPreservesRawPayloadWithoutChangingEquality() throws {
        let absolutePath = "/tmp/image.png"
        let relativePath = "image.png"
        let payload = concatenatedData(
            littleEndianData(UInt16(0)),
            utf16LengthPrefixedString(absolutePath),
            utf16LengthPrefixedString(relativePath)
        )

        let binData = try HwpBinData.load(payload)
        var sameBinData = binData
        sameBinData.rawPayload = Data([0xCA, 0xFE])
        sameBinData.absolutePathRawPayload = Data([0xCA])
        sameBinData.relativePathRawPayload = Data([0xFE])

        expect(binData.rawPayload) == payload
        expect(binData.property.rawValue) == 0
        expect(binData.property.type) == .link
        expect(binData.absolutePath) == absolutePath
        expect(binData.absolutePathRawPayload) == utf16StringPayload(absolutePath)
        expect(binData.relativePath) == relativePath
        expect(binData.relativePathRawPayload) == utf16StringPayload(relativePath)
        expect(binData.streamId).to(beNil())
        expect(binData.extensionName).to(beNil())
        expect(binData.extensionNameRawPayload).to(beNil())
        expect(sameBinData) == binData
    }

    func testEmbeddedBinDataPreservesRawPayloadWithoutChangingEquality() throws {
        let payload = embeddedBinDataPayload()

        let binData = try HwpBinData.load(payload)
        var sameBinData = binData
        sameBinData.rawPayload = Data([0xCA, 0xFE])
        sameBinData.extensionNameRawPayload = Data([0xCA])

        expect(binData.rawPayload) == payload
        expect(binData.property.rawValue) == UInt16(HwpBinDataType.embedding.rawValue)
            | UInt16(HwpBinDataCompressType.never.rawValue << 4)
            | UInt16(HwpBinDataState.successed.rawValue << 6)
        expect(binData.property.type) == .embedding
        expect(binData.property.compressType) == .never
        expect(binData.property.state) == .successed
        expect(binData.absolutePathRawPayload).to(beNil())
        expect(binData.relativePathRawPayload).to(beNil())
        expect(binData.streamId) == 42
        expect(binData.extensionName) == "jpg"
        expect(binData.extensionNameRawPayload) == utf16StringPayload("jpg")
        expect(sameBinData) == binData
    }

    func testLinkBinDataWithNonZeroStartIndexPayloadPreservesPaths() throws {
        let payload = concatenatedData(
            littleEndianData(UInt16(0)),
            utf16LengthPrefixedString("/tmp/image.png"),
            utf16LengthPrefixedString("image.png")
        )
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let binData = try HwpBinData.load(slicedPayload)

        expect(binData.rawPayload) == payload
        expect(binData.property.type) == .link
        expect(binData.absolutePath) == "/tmp/image.png"
        expect(binData.absolutePathRawPayload) == utf16StringPayload("/tmp/image.png")
        expect(binData.relativePath) == "image.png"
        expect(binData.relativePathRawPayload) == utf16StringPayload("image.png")
        expect(binData.streamId).to(beNil())
        expect(binData.extensionName).to(beNil())
        expect(binData.extensionNameRawPayload).to(beNil())
    }

    func testEmbeddedBinDataWithNonZeroStartIndexPayloadPreservesMetadata() throws {
        let payload = embeddedBinDataPayload()
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let binData = try HwpBinData.load(slicedPayload)

        expect(binData.rawPayload) == payload
        expect(binData.property.type) == .embedding
        expect(binData.property.compressType) == .never
        expect(binData.property.state) == .successed
        expect(binData.absolutePathRawPayload).to(beNil())
        expect(binData.relativePathRawPayload).to(beNil())
        expect(binData.streamId) == 42
        expect(binData.extensionName) == "jpg"
        expect(binData.extensionNameRawPayload) == utf16StringPayload("jpg")
    }

    func testStorageBinDataPreservesRawPayloadAndMetadata() throws {
        let property = UInt16(HwpBinDataType.storage.rawValue)
            | UInt16(HwpBinDataCompressType.always.rawValue << 4)
            | UInt16(HwpBinDataState.ignored.rawValue << 6)
        let payload = concatenatedData(
            littleEndianData(property),
            littleEndianData(UInt16(7)),
            utf16LengthPrefixedString("OLE")
        )

        let binData = try HwpBinData.load(payload)

        expect(binData.rawPayload) == payload
        expect(binData.property.rawValue) == property
        expect(binData.property.type) == .storage
        expect(binData.property.compressType) == .always
        expect(binData.property.state) == .ignored
        expect(binData.absolutePath).to(beNil())
        expect(binData.absolutePathRawPayload).to(beNil())
        expect(binData.relativePath).to(beNil())
        expect(binData.relativePathRawPayload).to(beNil())
        expect(binData.streamId) == 7
        expect(binData.extensionName) == "OLE"
        expect(binData.extensionNameRawPayload) == utf16StringPayload("OLE")
    }

    func testBinDataStringRawPayloadsPreserveSurrogatePairs() throws {
        let supplementaryScalar = String(decoding: [UInt16(0xD83E), UInt16(0xDDEA)], as: UTF16.self)
        let absolutePath = "/tmp/" + supplementaryScalar + ".png"
        let relativePath = supplementaryScalar + ".png"
        let extensionName = "jp" + supplementaryScalar
        let linkPayload = concatenatedData(
            littleEndianData(UInt16(HwpBinDataType.link.rawValue)),
            utf16LengthPrefixedString(absolutePath),
            utf16LengthPrefixedString(relativePath)
        )
        let embeddedProperty = UInt16(HwpBinDataType.embedding.rawValue)
            | UInt16(HwpBinDataCompressType.never.rawValue << 4)
            | UInt16(HwpBinDataState.successed.rawValue << 6)
        let embeddedPayload = concatenatedData(
            littleEndianData(embeddedProperty),
            littleEndianData(UInt16(42)),
            utf16LengthPrefixedString(extensionName)
        )

        let linkBinData = try HwpBinData.load(linkPayload)
        let embeddedBinData = try HwpBinData.load(embeddedPayload)

        expect(linkBinData.absolutePath) == absolutePath
        expect(linkBinData.absolutePathRawPayload) == utf16StringPayload(absolutePath)
        expect(linkBinData.relativePath) == relativePath
        expect(linkBinData.relativePathRawPayload) == utf16StringPayload(relativePath)
        expect(embeddedBinData.extensionName) == extensionName
        expect(embeddedBinData.extensionNameRawPayload) == utf16StringPayload(extensionName)
    }

    func testBinDataPropertyLoadsAllValidBitFieldCombinations() throws {
        let types: [HwpBinDataType] = [.link, .embedding, .storage]
        let compressTypes: [HwpBinDataCompressType] = [.followStorage, .always, .never]
        let states: [HwpBinDataState] = [.never, .successed, .failed, .ignored]

        for type in types {
            for compressType in compressTypes {
                for state in states {
                    let raw = UInt16(type.rawValue)
                        | UInt16(compressType.rawValue << 4)
                        | UInt16(state.rawValue << 6)
                        | UInt16(0xAB00)

                    let property = try HwpBinDataProperty.load(raw)

                    expect(property.rawValue) == raw
                    expect(property.type) == type
                    expect(property.compressType) == compressType
                    expect(property.state) == state
                }
            }
        }
    }

    func testBinDataPropertyRawValueSurvivesCodableRoundTrip() throws {
        let raw = UInt16(HwpBinDataType.storage.rawValue)
            | UInt16(HwpBinDataCompressType.always.rawValue << 4)
            | UInt16(HwpBinDataState.ignored.rawValue << 6)
            | UInt16(0xAB00)
        let property = try HwpBinDataProperty.load(raw)

        let decoded = try JSONDecoder().decode(
            HwpBinDataProperty.self,
            from: JSONEncoder().encode(property)
        )

        expect(decoded.rawValue) == raw
        expect(decoded) == property
    }

    func testBinDataRejectsInvalidPropertyEnumValuesWithTypedError() {
        expectInvalidRawValue(model: HwpBinDataType.self, rawValue: 3) {
            _ = try HwpBinData.load(littleEndianData(UInt16(3)))
        }

        let invalidCompressType = UInt16(HwpBinDataType.embedding.rawValue)
            | UInt16(3 << 4)
        expectInvalidRawValue(model: HwpBinDataCompressType.self, rawValue: 3) {
            _ = try HwpBinData.load(littleEndianData(invalidCompressType))
        }
    }

    func testBinDataRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(embeddedBinDataPayload(), Data([0xFF]))

        expect {
            _ = try HwpBinData.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpBinData"
            expect(remain) == 1
        })
    }

    func testBinDataRejectsTruncatedLinkPayloadsWithTypedError() {
        let linkProperty = littleEndianData(UInt16(HwpBinDataType.link.rawValue))
        let scenarios = [
            BinDataTruncationScenario(
                name: "property",
                payload: Data([0x00]),
                expected: 2,
                actual: 1
            ),
            BinDataTruncationScenario(
                name: "absolutePath",
                payload: concatenatedData(
                    linkProperty,
                    littleEndianData(UInt16(2)),
                    littleEndianData(WCHAR(0x0041))
                ),
                expected: 4,
                actual: 2
            ),
            BinDataTruncationScenario(
                name: "relativePathLength",
                payload: concatenatedData(
                    linkProperty,
                    utf16LengthPrefixedString("/tmp/image.png")
                ),
                expected: 2,
                actual: 0
            ),
        ]

        for scenario in scenarios {
            expectTruncatedBinDataPayload(scenario)
        }
    }

    func testBinDataRejectsTruncatedEmbeddedOrStoragePayloadsWithTypedError() {
        let embeddedProperty = UInt16(HwpBinDataType.embedding.rawValue)
            | UInt16(HwpBinDataCompressType.never.rawValue << 4)
            | UInt16(HwpBinDataState.successed.rawValue << 6)
        let storageProperty = UInt16(HwpBinDataType.storage.rawValue)
            | UInt16(HwpBinDataCompressType.always.rawValue << 4)
            | UInt16(HwpBinDataState.ignored.rawValue << 6)
        let scenarios = [
            BinDataTruncationScenario(
                name: "streamId",
                payload: littleEndianData(embeddedProperty),
                expected: 2,
                actual: 0
            ),
            BinDataTruncationScenario(
                name: "extensionName",
                payload: concatenatedData(
                    littleEndianData(embeddedProperty),
                    littleEndianData(UInt16(42)),
                    littleEndianData(UInt16(2)),
                    littleEndianData(WCHAR(0x006A))
                ),
                expected: 4,
                actual: 2
            ),
            BinDataTruncationScenario(
                name: "storageExtensionName",
                payload: concatenatedData(
                    littleEndianData(storageProperty),
                    littleEndianData(UInt16(7)),
                    littleEndianData(UInt16(3)),
                    littleEndianData(WCHAR(0x004F))
                ),
                expected: 6,
                actual: 2
            ),
        ]

        for scenario in scenarios {
            expectTruncatedBinDataPayload(scenario)
        }
    }

    func testLinkBinDataRejectsInvalidPathUnicodeScalarWithTypedError() {
        let payload = concatenatedData(
            littleEndianData(UInt16(HwpBinDataType.link.rawValue)),
            invalidUTF16LengthPrefixedString(),
            utf16LengthPrefixedString("image.png")
        )

        expectInvalidUnicodeScalar {
            _ = try HwpBinData.load(payload)
        }
    }

    func testLinkBinDataRejectsInvalidRelativePathUnicodeScalarWithTypedError() {
        let payload = concatenatedData(
            littleEndianData(UInt16(HwpBinDataType.link.rawValue)),
            utf16LengthPrefixedString("/tmp/image.png"),
            invalidUTF16LengthPrefixedString()
        )

        expectInvalidUnicodeScalar {
            _ = try HwpBinData.load(payload)
        }
    }

    func testEmbeddedBinDataRejectsInvalidExtensionUnicodeScalarWithTypedError() {
        let property = UInt16(HwpBinDataType.embedding.rawValue)
            | UInt16(HwpBinDataCompressType.never.rawValue << 4)
            | UInt16(HwpBinDataState.successed.rawValue << 6)
        let payload = concatenatedData(
            littleEndianData(property),
            littleEndianData(UInt16(42)),
            invalidUTF16LengthPrefixedString()
        )

        expectInvalidUnicodeScalar {
            _ = try HwpBinData.load(payload)
        }
    }

    func testStorageBinDataRejectsInvalidExtensionUnicodeScalarWithTypedError() {
        let property = UInt16(HwpBinDataType.storage.rawValue)
            | UInt16(HwpBinDataCompressType.always.rawValue << 4)
            | UInt16(HwpBinDataState.ignored.rawValue << 6)
        let payload = concatenatedData(
            littleEndianData(property),
            littleEndianData(UInt16(7)),
            invalidUTF16LengthPrefixedString()
        )

        expectInvalidUnicodeScalar {
            _ = try HwpBinData.load(payload)
        }
    }

    func testBinaryDataAndDocInfoBinDataSurviveCodableRoundTrip() throws {
        let binaryPayload = Data([0xCA, 0xFE])
        let binaryData = HwpBinaryData(name: "BIN0042.JPG", data: binaryPayload)
        let binDataPayload = embeddedBinDataPayload()

        let decodedBinaryData = try decodeRoundTrip(binaryData)
        let decodedBinData = try decodeRoundTrip(HwpBinData.load(binDataPayload))

        expect(decodedBinaryData.name) == "BIN0042.JPG"
        expect(decodedBinaryData.streamId) == 42
        expect(decodedBinaryData.extensionName) == "JPG"
        expect(decodedBinaryData.data) == binaryPayload
        expect(decodedBinData.rawPayload) == binDataPayload
        expect(decodedBinData.property.type) == .embedding
        expect(decodedBinData.property.compressType) == .never
        expect(decodedBinData.property.state) == .successed
        expect(decodedBinData.streamId) == 42
        expect(decodedBinData.extensionName) == "jpg"
        expect(decodedBinData.extensionNameRawPayload) == utf16StringPayload("jpg")
    }
}

private struct BinDataTruncationScenario {
    let name: String
    let payload: Data
    let expected: Int
    let actual: Int
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func embeddedBinDataPayload() -> Data {
    let property = UInt16(HwpBinDataType.embedding.rawValue)
        | UInt16(HwpBinDataCompressType.never.rawValue << 4)
        | UInt16(HwpBinDataState.successed.rawValue << 6)
    return concatenatedData(
        littleEndianData(property),
        littleEndianData(UInt16(42)),
        utf16LengthPrefixedString("jpg")
    )
}

private func utf16LengthPrefixedString(_ string: String) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt16(string.utf16.count)))
    data.append(utf16StringPayload(string))
    return data
}

private func utf16StringPayload(_ string: String) -> Data {
    var data = Data()
    for codeUnit in string.utf16 {
        data.append(littleEndianData(UInt16(codeUnit)))
    }
    return data
}

private func invalidUTF16LengthPrefixedString() -> Data {
    concatenatedData(littleEndianData(UInt16(1)), littleEndianData(UInt16(0xD800)))
}

private func expectInvalidUnicodeScalar(_ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidUnicodeScalar(value) = error else {
            return fail("Expected invalidUnicodeScalar, got \(error)")
        }
        expect(value) == 0xD800
    })
}

private func expectInvalidRawValue(
    model expectedModel: Any.Type,
    rawValue expectedRawValue: Int,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRawValueForEnum(model, rawValue) = error else {
            return fail("Expected invalidRawValueForEnum, got \(error)")
        }
        expect(String(describing: model)) == String(describing: expectedModel)
        expect(rawValue) == expectedRawValue
    })
}

private func expectTruncatedBinDataPayload(_ scenario: BinDataTruncationScenario) {
    expect {
        _ = try HwpBinData.load(scenario.payload)
    }.to(throwError { error in
        guard case let HwpError.truncatedData(expected, actual) = error else {
            return fail("Expected truncatedData for \(scenario.name), got \(error)")
        }
        expect(expected) == scenario.expected
        expect(actual) == scenario.actual
    })
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
