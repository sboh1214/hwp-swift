@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class StyleRawPayloadTests: XCTestCase {
    func testStyleInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let style = try HwpStyle(&reader)

        expect(style.rawPayload) == slicedPayload
        expect(style.styleLocalNameRawPayload) == wcharPayload("Local")
        expect(style.styleEnglishNameRawPayload) == wcharPayload("English")
        expect(reader.isEOF) == true
    }

    func testStylePreservesRawPayloadWithoutChangingEquality() throws {
        let payload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )

        let style = try HwpStyle.load(payload)
        var sameStyle = style
        sameStyle.rawPayload = Data([0xCA])
        sameStyle.styleLocalNameRawPayload = Data([0xFE])
        sameStyle.styleEnglishNameRawPayload = Data([0xED])

        expect(style.rawPayload) == payload
        expect(style.styleLocalNameRawPayload) == wcharPayload("Local")
        expect(style.styleEnglishNameRawPayload) == wcharPayload("English")
        expect(style.undocumentedTrailing) == [0, 0]
        expect(style) == HwpStyle("Local", "English", nextId: 1, paraShapeId: 2, charShapeId: 3)
        expect(sameStyle) == style
    }

    func testStyleDecodesNonBMPNamesAsUTF16() throws {
        let payload = stylePayload(
            localName: "Local😀",
            englishName: "English🚀",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )

        let style = try HwpStyle.load(payload)

        expect(style.rawPayload) == payload
        expect(style.length1) == UInt16("Local😀".utf16.count)
        expect(style.length2) == UInt16("English🚀".utf16.count)
        expect(style.styleLocalNameRawPayload) == wcharPayload("Local😀")
        expect(style.styleEnglishNameRawPayload) == wcharPayload("English🚀")
        expect(style) == HwpStyle("Local😀", "English🚀", nextId: 1, paraShapeId: 2, charShapeId: 3)
    }

    func testStyleWithNonZeroStartIndexPayloadPreservesNameRawPayloads() throws {
        let payload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let style = try HwpStyle.load(slicedPayload)

        expect(style.rawPayload) == payload
        expect(style.styleLocalNameRawPayload) == wcharPayload("Local")
        expect(style.styleEnglishNameRawPayload) == wcharPayload("English")
    }

    func testStyleRejectsTruncatedUndocumentedTrailingBytesWithTypedError() {
        var payload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )
        payload.removeLast()

        expect {
            _ = try HwpStyle.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })
    }

    func testStyleRejectsExtraTrailingBytesWithTypedError() {
        let payload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )
        let payloadWithTrailing = concatenatedData(payload, Data([0xFF]))

        expect {
            _ = try HwpStyle.load(payloadWithTrailing)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpStyle"
            expect(remain) == 1
        })
    }

    func testStyleRejectsInvalidUnicodeNameWithTypedError() {
        let payload = stylePayloadWithInvalidLocalName()

        expect {
            _ = try HwpStyle.load(payload)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }

    func testBulletPreservesRawPayloadAndUndocumentedTrailingBytes() throws {
        let payload = bulletPayload(undocumentedTrailing: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE])

        let bullet = try HwpBullet.load(payload)
        var sameBullet = bullet
        sameBullet.rawPayload = Data([0xCA])
        sameBullet.charRawPayload = Data([0xFE])
        sameBullet.checkCharRawPayload = Data([0xED])

        expect(bullet.rawPayload) == payload
        expect(bullet.info) == [1, 2, 3, 4, 5, 6, 7, 8]
        expect(bullet.char) == "\u{2022}"
        expect(bullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(bullet.imageId) == 42
        expect(bullet.imageProperty) == [9, 10, 11, 12]
        expect(bullet.checkChar) == "\u{2611}"
        expect(bullet.checkCharRawPayload) == wcharPayload("\u{2611}")
        expect(bullet.undocumentedTrailing) == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        expect(sameBullet) == bullet
    }

    func testBulletPreservesShortUndocumentedTrailingBytes() throws {
        let payload = bulletPayload(undocumentedTrailing: [0xAA, 0xBB, 0xCC, 0xDD])

        let bullet = try HwpBullet.load(payload)

        expect(bullet.rawPayload) == payload
        expect(bullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(bullet.checkCharRawPayload) == wcharPayload("\u{2611}")
        expect(bullet.undocumentedTrailing) == [0xAA, 0xBB, 0xCC, 0xDD]
    }

    func testBulletPreservesExtraUndocumentedTrailingBytes() throws {
        let payload = bulletPayload(
            undocumentedTrailing: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        )
        let payloadWithTrailing = concatenatedData(payload, Data([0xFF]))

        let bullet = try HwpBullet.load(payloadWithTrailing)

        expect(bullet.rawPayload) == payloadWithTrailing
        expect(bullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(bullet.checkCharRawPayload) == wcharPayload("\u{2611}")
        expect(bullet.undocumentedTrailing) == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
    }

    func testBulletWithNonZeroStartIndexPayloadPreservesCharRawPayloads() throws {
        let payload = bulletPayload(undocumentedTrailing: [0xAA, 0xBB])
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let bullet = try HwpBullet.load(slicedPayload)

        expect(bullet.rawPayload) == payload
        expect(bullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(bullet.checkCharRawPayload) == wcharPayload("\u{2611}")
    }

    func testBulletInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = bulletPayload(undocumentedTrailing: [0xAA, 0xBB])
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let bullet = try HwpBullet(&reader)

        expect(bullet.rawPayload) == slicedPayload
        expect(bullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(bullet.checkCharRawPayload) == wcharPayload("\u{2611}")
        expect(reader.isEOF) == true
    }

    func testBulletRejectsTruncatedRequiredCheckCharWithTypedError() {
        let payload = truncatedBulletPayloadBeforeCheckChar()

        expect {
            _ = try HwpBullet.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })
    }

    func testNumberingPreservesRawPayloadWithoutChangingEquality() throws {
        let payload = numberingPayload()

        let numbering = try HwpNumbering.load(payload, HwpVersion())
        var sameNumbering = numbering
        sameNumbering.rawPayload = Data([0xCA, 0xFE])
        sameNumbering.formatArray[0].formatRawPayload = Data([0xCA])
        sameNumbering.extendedFormatArray?[0].formatRawPayload = Data([0xFE])

        expect(numbering.rawPayload) == payload
        expect(numbering.formatArray.count) == 7
        expect(numbering.formatArray.map(\.formatRawPayload)) ==
            (1 ... 7).map { wcharPayload("^\($0)") }
        expect(numbering.startingIndexArray) == [1, 2, 3, 4, 5, 6, 7]
        expect(numbering.extendedFormatArray?.count) == 3
        expect(numbering.extendedFormatArray?.map(\.formatRawPayload)) ==
            (8 ... 10).map { wcharPayload("^\($0)") }
        expect(numbering.extendedStartingIndexArray) == [8, 9, 10]
        expect(sameNumbering) == numbering
    }

    func testNumberingFormatRawPayloadsPreserveSurrogatePairsAndNonZeroStartIndex() throws {
        let payload = numberingPayload(formatForIndex: { index in
            switch index {
            case 1:
                "^😀"
            case 8:
                "^🚀"
            default:
                "^\(index)"
            }
        })
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)

        let numbering = try HwpNumbering.load(slicedPayload, HwpVersion())

        expect(numbering.rawPayload) == payload
        expect(numbering.formatArray[0].format) == "^😀"
        expect(numbering.formatArray[0].formatRawPayload) == wcharPayload("^😀")
        expect(numbering.extendedFormatArray?[0].format) == "^🚀"
        expect(numbering.extendedFormatArray?[0].formatRawPayload) == wcharPayload("^🚀")
    }

    func testNumberingInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = numberingPayload()
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let numbering = try HwpNumbering(&reader, HwpVersion())

        expect(numbering.rawPayload) == slicedPayload
        expect(numbering.formatArray[0].formatRawPayload) == wcharPayload("^1")
        expect(numbering.extendedFormatArray?[0].formatRawPayload) == wcharPayload("^8")
        expect(reader.isEOF) == true
    }

    func testNumberingRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(numberingPayload(), Data([0xFF]))

        expect {
            _ = try HwpNumbering.load(payload, HwpVersion())
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpNumbering"
            expect(remain) == 1
        })
    }

    func testNumberingAcceptsLegacyShortStartingIndexArray() throws {
        let payload = numberingPayload(
            startingIndexArray: [1, 2, 3, 4, 5, 6],
            includesExtendedLevels: false
        )

        let numbering = try HwpNumbering.load(payload, HwpVersion(5, 0, 3, 0))

        expect(numbering.rawPayload) == payload
        expect(numbering.startingIndexArray) == [1, 2, 3, 4, 5, 6]
        expect(numbering.extendedFormatArray).to(beNil())
        expect(numbering.extendedStartingIndexArray).to(beNil())
    }

    func testNumberingRejectsPartialLegacyStartingIndexWithTypedError() {
        let payload = numberingPayload(
            startingIndexArray: [1, 2, 3, 4, 5, 6],
            includesExtendedLevels: false
        )
        let payloadWithTrailing = concatenatedData(payload, Data([0xFF]))

        expect {
            _ = try HwpNumbering.load(payloadWithTrailing, HwpVersion(5, 0, 3, 0))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 1
        })
    }

    func testStyleBulletAndNumberingRawPayloadsSurviveCodableRoundTrip() throws {
        let stylePayload = stylePayload(
            localName: "Local",
            englishName: "English",
            nextId: 1,
            paraShapeId: 2,
            charShapeId: 3
        )
        let bulletPayload = bulletPayload(
            undocumentedTrailing: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        )
        let numberingPayload = numberingPayload()

        let decodedStyle = try decodeRoundTrip(HwpStyle.load(stylePayload))
        let decodedBullet = try decodeRoundTrip(HwpBullet.load(bulletPayload))
        let decodedNumbering = try decodeRoundTrip(
            HwpNumbering.load(numberingPayload, HwpVersion())
        )

        expect(decodedStyle.rawPayload) == stylePayload
        expect(decodedStyle.styleLocalNameRawPayload) == wcharPayload("Local")
        expect(decodedStyle.styleEnglishNameRawPayload) == wcharPayload("English")
        expect(decodedStyle.unknown) == [0, 0]
        expect(decodedStyle.undocumentedTrailing) == [0, 0]
        expect(decodedBullet.rawPayload) == bulletPayload
        expect(decodedBullet.charRawPayload) == wcharPayload("\u{2022}")
        expect(decodedBullet.checkCharRawPayload) == wcharPayload("\u{2611}")
        expect(decodedBullet.undocumentedTrailing) == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        expect(decodedNumbering.rawPayload) == numberingPayload
        expect(decodedNumbering.formatArray[0].formatRawPayload) == wcharPayload("^1")
        expect(decodedNumbering.extendedFormatArray?[0].formatRawPayload) == wcharPayload("^8")
        expect(decodedNumbering.extendedStartingIndexArray) == [8, 9, 10]
    }
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func stylePayload(
    localName: String,
    englishName: String,
    property: BYTE = 0,
    nextId: BYTE,
    paraShapeId: UInt16,
    charShapeId: UInt16
) -> Data {
    var data = wcharStringData(localName)
    data.append(wcharStringData(englishName))
    data.append(littleEndianData(property))
    data.append(littleEndianData(nextId))
    data.append(littleEndianData(Int16(1042)))
    data.append(littleEndianData(paraShapeId))
    data.append(littleEndianData(charShapeId))
    data.append(contentsOf: [0, 0])
    return data
}

private func wcharStringData(_ string: String) -> Data {
    var data = littleEndianData(UInt16(string.utf16.count))
    data.append(wcharPayload(string))
    return data
}

private func wcharPayload(_ string: String) -> Data {
    var data = Data()
    for value in string.utf16 {
        data.append(littleEndianData(value))
    }
    return data
}

private func stylePayloadWithInvalidLocalName() -> Data {
    var data = littleEndianData(UInt16(1))
    data.append(littleEndianData(WCHAR(0xD800)))
    data.append(wcharStringData("English"))
    data.append(littleEndianData(BYTE(0)))
    data.append(littleEndianData(BYTE(1)))
    data.append(littleEndianData(Int16(1042)))
    data.append(littleEndianData(UInt16(2)))
    data.append(littleEndianData(UInt16(3)))
    data.append(contentsOf: [0, 0])
    return data
}

private func bulletPayload(undocumentedTrailing: [BYTE]) -> Data {
    concatenatedData(
        Data([1, 2, 3, 4, 5, 6, 7, 8]),
        littleEndianData(WCHAR(0x2022)),
        littleEndianData(Int32(42)),
        Data([9, 10, 11, 12]),
        littleEndianData(WCHAR(0x2611)),
        Data(undocumentedTrailing)
    )
}

private func truncatedBulletPayloadBeforeCheckChar() -> Data {
    concatenatedData(
        Data([1, 2, 3, 4, 5, 6, 7, 8]),
        littleEndianData(WCHAR(0x2022)),
        littleEndianData(Int32(42)),
        Data([9, 10, 11, 12]),
        Data([0x11])
    )
}

private func numberingPayload(
    formatForIndex: (Int) -> String = { "^\($0)" },
    startingIndexArray: [UInt32] = Array(1 ... 7),
    includesExtendedLevels: Bool = true
) -> Data {
    var data = Data()
    for index in 1 ... 7 {
        data.append(numberingFormatPayload(index: index, format: formatForIndex(index)))
    }
    data.append(littleEndianData(UInt16(0)))
    for startingIndex in startingIndexArray {
        data.append(littleEndianData(startingIndex))
    }
    guard includesExtendedLevels else {
        return data
    }
    for index in 8 ... 10 {
        data.append(numberingFormatPayload(index: index, format: formatForIndex(index)))
    }
    for index in 8 ... 10 {
        data.append(littleEndianData(UInt32(index)))
    }
    return data
}

private func numberingFormatPayload(index: Int, format: String) -> Data {
    var data = Data(repeating: UInt8(index), count: 12)
    data.append(littleEndianData(UInt16(format.utf16.count)))
    for value in format.utf16 {
        data.append(littleEndianData(value))
    }
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
