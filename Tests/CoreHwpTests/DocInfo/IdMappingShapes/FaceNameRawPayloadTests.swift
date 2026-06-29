@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FaceNameRawPayloadTests: XCTestCase {
    func testFaceNameInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = faceNamePayload()
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let faceName = try HwpFaceName(&reader)

        expect(faceName.rawPayload) == slicedPayload
        expect(faceName.faceNameRawPayload) == utf16Data("Base")
        expect(faceName.alternativeFaceNameRawPayload) == utf16Data("Alt")
        expect(faceName.defaultFaceNameRawPayload) == utf16Data("Default")
        expect(reader.isEOF) == true
    }

    func testFaceNamePreservesRawPayloadWithoutChangingEquality() throws {
        let payload = faceNamePayload()

        let faceName = try HwpFaceName.load(payload)
        var sameFaceName = faceName
        sameFaceName.rawPayload = Data([0xCA, 0xFE])
        sameFaceName.faceNameRawPayload = Data([0xCA])
        sameFaceName.alternativeFaceNameRawPayload = Data([0xFE])
        sameFaceName.defaultFaceNameRawPayload = Data([0xED])

        expect(faceName.rawPayload) == payload
        expect(faceName.property) == 0xE0
        expect(faceName.faceNameLength) == 4
        expect(faceName.faceName) == "Base"
        expect(faceName.faceNameRawPayload) == utf16Data("Base")
        expect(faceName.alternativeFaceType) == 1
        expect(faceName.alternativeFaceNameLength) == 3
        expect(faceName.alternativeFaceName) == "Alt"
        expect(faceName.alternativeFaceNameRawPayload) == utf16Data("Alt")
        expect(faceName.faceTypeInfo) == Array(0 ..< 10)
        expect(faceName.defaultFaceNameLength) == 7
        expect(faceName.defaultFaceName) == "Default"
        expect(faceName.defaultFaceNameRawPayload) == utf16Data("Default")
        expect(sameFaceName) == faceName
    }

    func testFaceNameRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(faceNamePayload(), Data([0xFF]))

        expect {
            _ = try HwpFaceName.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpFaceName"
            expect(remain) == 1
        })
    }

    func testFaceNameConvenienceInitUsesEmptyRawPayload() {
        let faceName = HwpFaceName("Base", [1, 2, 3], "Default")

        expect(faceName.rawPayload).to(beEmpty())
        expect(faceName.faceName) == "Base"
        expect(faceName.faceNameRawPayload) == utf16Data("Base")
        expect(faceName.defaultFaceName) == "Default"
        expect(faceName.defaultFaceNameRawPayload) == utf16Data("Default")
    }

    func testFaceNameDecodesNonBMPNamesAsUTF16() throws {
        let payload = concatenatedData(
            Data([0x20]),
            utf16LengthPrefixedString("Base😀"),
            utf16LengthPrefixedString("Default🚀")
        )
        let faceName = try HwpFaceName.load(payload)
        let initializedFaceName = HwpFaceName("Base😀", [1, 2, 3], "Default🚀")

        expect(faceName.rawPayload) == payload
        expect(faceName.faceNameLength) == UInt16("Base😀".utf16.count)
        expect(faceName.faceName) == "Base😀"
        expect(faceName.faceNameRawPayload) == utf16Data("Base😀")
        expect(faceName.defaultFaceNameLength) == UInt16("Default🚀".utf16.count)
        expect(faceName.defaultFaceName) == "Default🚀"
        expect(faceName.defaultFaceNameRawPayload) == utf16Data("Default🚀")
        expect(initializedFaceName.faceNameLength) == UInt16("Base😀".utf16.count)
        expect(initializedFaceName.faceNameRawPayload) == utf16Data("Base😀")
        expect(initializedFaceName.defaultFaceNameLength) == UInt16("Default🚀".utf16.count)
        expect(initializedFaceName.defaultFaceNameRawPayload) == utf16Data("Default🚀")
    }

    func testFaceNameWithNonZeroStartIndexPayloadPreservesNameRawPayloads() throws {
        let payload = faceNamePayload()
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let faceName = try HwpFaceName.load(slicedPayload)

        expect(faceName.rawPayload) == payload
        expect(faceName.faceNameRawPayload) == utf16Data("Base")
        expect(faceName.alternativeFaceNameRawPayload) == utf16Data("Alt")
        expect(faceName.defaultFaceNameRawPayload) == utf16Data("Default")
    }

    func testFaceNameDefaultInitUsesEmptyValues() {
        let faceName = HwpFaceName()

        expect(faceName.rawPayload).to(beEmpty())
        expect(faceName.property) == 0
        expect(faceName.faceNameLength) == 0
        expect(faceName.faceName) == ""
        expect(faceName.faceNameRawPayload).to(beEmpty())
        expect(faceName.alternativeFaceName).to(beNil())
        expect(faceName.alternativeFaceNameRawPayload).to(beNil())
        expect(faceName.faceTypeInfo).to(beNil())
        expect(faceName.defaultFaceName).to(beNil())
        expect(faceName.defaultFaceNameRawPayload).to(beNil())
    }

    func testFaceNameRawPayloadsSurviveCodableRoundTrip() throws {
        let payload = faceNamePayload()

        let decodedFaceName = try decodeRoundTrip(HwpFaceName.load(payload))

        expect(decodedFaceName.rawPayload) == payload
        expect(decodedFaceName.faceNameRawPayload) == utf16Data("Base")
        expect(decodedFaceName.alternativeFaceNameRawPayload) == utf16Data("Alt")
        expect(decodedFaceName.defaultFaceNameRawPayload) == utf16Data("Default")
    }
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func faceNamePayload() -> Data {
    var data = Data([0xE0])
    data.append(utf16LengthPrefixedString("Base"))
    data.append(1)
    data.append(utf16LengthPrefixedString("Alt"))
    data.append(Data(0 ..< 10))
    data.append(utf16LengthPrefixedString("Default"))
    return data
}

private func utf16LengthPrefixedString(_ string: String) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt16(string.utf16.count)))
    data.append(utf16Data(string))
    return data
}

private func utf16Data(_ string: String) -> Data {
    var data = Data()
    for codeUnit in string.utf16 {
        data.append(littleEndianData(UInt16(codeUnit)))
    }
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
