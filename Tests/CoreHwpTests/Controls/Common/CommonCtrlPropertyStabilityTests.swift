@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class CommonCtrlPropertyStabilityTests: XCTestCase {
    func testCommonControlPropertyInfoDecodesErrataCommonObjectBits() throws {
        let restrictInPageInfo = try HwpCommonCtrlPropertyInfo.load(0x002A_2210)
        let unrestrictedInfo = try HwpCommonCtrlPropertyInfo.load(0x002A_0210)

        expect(restrictInPageInfo.restrictInPage) == true
        expect(restrictInPageInfo.allowOverlap) == false
        expect(restrictInPageInfo.effectiveAllowOverlap) == false
        expect(restrictInPageInfo.widthRelativeTo) == .absolute
        expect(restrictInPageInfo.heightRelativeTo) == .absolute
        expect(restrictInPageInfo.textWrap) == .topAndBottom

        expect(unrestrictedInfo.restrictInPage) == false
        expect(unrestrictedInfo.widthRelativeTo) == .absolute
        expect(unrestrictedInfo.heightRelativeTo) == .absolute
        expect(unrestrictedInfo.textWrap) == .topAndBottom
    }

    func testCommonControlPropertyDecodesPropertyInfoFromPayload() throws {
        let payload = commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue,
            property: 0x046A_4000
        )
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)

        expect(property.propertyInfo.rawValue) == 0x046A_4000
        expect(property.propertyInfo.restrictInPage) == false
        expect(property.propertyInfo.allowOverlap) == true
        expect(property.propertyInfo.effectiveAllowOverlap) == true
        expect(property.propertyInfo.widthRelativeTo) == .absolute
        expect(property.propertyInfo.heightRelativeTo) == .absolute
        expect(property.propertyInfo.textWrap) == .inFrontOfText
        expect(property.propertyInfo.numberingCategory) == .figure
    }

    func testCommonControlPropertyAcceptsLegacyPayloadWithoutObjectDescription() throws {
        var payload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        payload.removeLast(MemoryLayout<WORD>.size)
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)

        expect(property.rawPayload) == payload
        expect(property.commonCtrlId) == .genShapeObject
        expect(property.isDividablePage) == false
        expect(property.objectDescriptionLength).to(beNil())
        expect(property.objectDescription) == ""
        expect(property.objectDescriptionRawPayload).to(beEmpty())
        expect(reader.isEOF) == true
    }

    func testCommonControlPropertyAcceptsLegacyPayloadWithoutDividablePageFlag() throws {
        var payload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        payload.removeLast(MemoryLayout<WORD>.size + MemoryLayout<Int32>.size)
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)

        expect(property.rawPayload) == payload
        expect(property.commonCtrlId) == .genShapeObject
        expect(property.isDividablePage) == false
        expect(property.objectDescriptionLength).to(beNil())
        expect(property.objectDescription) == ""
        expect(property.objectDescriptionRawPayload).to(beEmpty())
        expect(reader.isEOF) == true
    }

    func testCommonControlPropertyPreservesObjectDescriptionRawPayload() throws {
        let description = "설명😀"
        let payload = commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue,
            objectDescription: description
        )
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)
        var sameProperty = property
        sameProperty.rawPayload = Data([0xCA])
        sameProperty.objectDescriptionRawPayload = Data([0xFE])

        expect(property.rawPayload) == payload
        expect(property.objectDescriptionLength) == WORD(description.utf16.count)
        expect(property.objectDescription) == description
        expect(property.objectDescriptionRawPayload) == wcharPayload(description)
        expect(sameProperty) == property
        expect(reader.isEOF) == true
    }

    func testCommonControlPropertyObjectDescriptionRawPayloadSurvivesCodableRoundTrip() throws {
        let description = "설명😀"
        let payload = commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue,
            objectDescription: description
        )
        var reader = DataReader(payload)

        let decoded = try decodeRoundTrip(HwpCommonCtrlProperty(&reader))

        expect(decoded.rawPayload) == payload
        expect(decoded.objectDescriptionLength) == WORD(description.utf16.count)
        expect(decoded.objectDescription) == description
        expect(decoded.objectDescriptionRawPayload) == wcharPayload(description)
    }

    func testCommonControlPropertyPreservesEmptyObjectDescriptionLength() throws {
        let payload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)

        expect(property.rawPayload) == payload
        expect(property.objectDescriptionLength) == 0
        expect(property.objectDescription) == ""
        expect(property.objectDescriptionRawPayload).to(beEmpty())
        expect(reader.isEOF) == true
    }

    func testCommonControlPropertyRejectsInvalidObjectDescriptionWithTypedError() {
        let payload = commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue,
            objectDescriptionPayload: littleEndianData(WCHAR(0xD800))
        )

        expect {
            var reader = DataReader(payload)
            _ = try HwpCommonCtrlProperty(&reader)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }

    func testCommonControlPropertyTruncatedObjectDescriptionThrowsTypedError() {
        var payload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        payload.removeLast(MemoryLayout<WORD>.size)
        payload.append(littleEndianData(WORD(1)))

        expect {
            var reader = DataReader(payload)
            _ = try HwpCommonCtrlProperty(&reader)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == MemoryLayout<WCHAR>.size
            expect(actual) == 0
        })
    }

    func testCommonControlPropertyTruncatedDividablePageFlagThrowsTypedError() {
        var payload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        payload.removeLast(MemoryLayout<WORD>.size + MemoryLayout<Int32>.size)
        payload.append(Data([0x01, 0x00]))

        expect {
            var reader = DataReader(payload)
            _ = try HwpCommonCtrlProperty(&reader)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == MemoryLayout<Int32>.size
            expect(actual) == 2
        })
    }

    func testGenShapeObjectAcceptsLegacyCommonPropertyWithoutObjectDescription() throws {
        var ctrlPayload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        ctrlPayload.removeLast(MemoryLayout<WORD>.size)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )

        let object = try HwpGenShapeObject.load(record)

        expect(object.rawPayload) == ctrlPayload
        expect(object.commonCtrlProperty.rawPayload) == ctrlPayload
        expect(object.rawTrailing).to(beEmpty())
        expect(object.commonCtrlProperty.isDividablePage) == false
        expect(object.commonCtrlProperty.objectDescriptionLength).to(beNil())
        expect(object.commonCtrlProperty.objectDescription) == ""
        expect(object.commonCtrlProperty.objectDescriptionRawPayload).to(beEmpty())
    }

    func testCommonControlPropertyPreservesConsumedSliceBeforeTrailingBytes() throws {
        let propertyPayload = commonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
        )
        let rawTrailing = Data([0xCA, 0xFE])
        var payload = propertyPayload
        payload.append(rawTrailing)
        var reader = DataReader(payload)

        let property = try HwpCommonCtrlProperty(&reader)

        expect(property.rawPayload) == propertyPayload
        expect(try reader.readToEnd()) == rawTrailing
    }

    func testCommonControlPropertyRejectsUnknownControlIdWithTypedError() {
        let invalidCtrlId = UInt32(0x1234_5678)
        let payload = commonCtrlPropertyPayload(ctrlId: invalidCtrlId)

        expect {
            var reader = DataReader(payload)
            _ = try HwpCommonCtrlProperty(&reader)
        }.to(throwError { error in
            guard case let HwpError.invalidCtrlId(ctrlId) = error else {
                return fail("Expected invalidCtrlId, got \(error)")
            }
            expect(ctrlId) == invalidCtrlId
        })
    }
}

private func commonCtrlPropertyPayload(
    ctrlId: UInt32,
    property: UInt32 = 0,
    objectDescription: String = ""
) -> Data {
    commonCtrlPropertyPayload(
        ctrlId: ctrlId,
        property: property,
        objectDescriptionPayload: wcharPayload(objectDescription)
    )
}

private func commonCtrlPropertyPayload(
    ctrlId: UInt32,
    property: UInt32 = 0,
    objectDescriptionPayload: Data
) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(property))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(WORD(objectDescriptionPayload.count / MemoryLayout<WCHAR>.size)))
    data.append(objectDescriptionPayload)
    return data
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func wcharPayload(_ string: String) -> Data {
    var data = Data()
    for value in string.utf16 {
        data.append(littleEndianData(value))
    }
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
