@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TabDefRawPayloadTests: XCTestCase {
    func testTabDefInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), tabDefPayload()).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let tabDef = try HwpTabDef(&reader)

        expect(tabDef.rawPayload) == slicedPayload
        expect(tabDef.tabInfoArray.map(\.rawPayload)) == [tabInfoPayload()]
        expect(reader.isEOF) == true
    }

    func testTabDefPreservesRawPayloadWithoutChangingEquality() throws {
        let payload = tabDefPayload()

        let tabDef = try HwpTabDef.load(payload)
        var sameTabDef = tabDef
        sameTabDef.rawPayload = Data([0xCA, 0xFE])
        sameTabDef.tabInfoArray[0].rawPayload = Data([0xED])

        expect(tabDef.rawPayload) == payload
        expect(tabDef.property) == 0x0102_0304
        expect(tabDef.count) == 1
        expect(tabDef.tabInfoArray.count) == 1
        expect(tabDef.tabInfoArray.first?.rawPayload) == tabInfoPayload()
        expect(tabDef.tabInfoArray.first?.location) == 7200
        expect(tabDef.tabInfoArray.first?.type) == 2
        expect(tabDef.tabInfoArray.first?.fillType) == 3
        expect(tabDef.tabInfoArray.first?.reserved) == 0x0405
        expect(sameTabDef) == tabDef
    }

    func testTabInfoWithNonZeroStartIndexPayloadPreservesRawPayload() throws {
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), tabInfoPayload()).dropFirst(2)

        let tabInfo = try HwpTabInfo.load(slicedPayload)

        expect(tabInfo.rawPayload) == tabInfoPayload()
        expect(tabInfo.location) == 7200
        expect(tabInfo.type) == 2
        expect(tabInfo.fillType) == 3
        expect(tabInfo.reserved) == 0x0405
    }

    func testTabInfoInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), tabInfoPayload()).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let tabInfo = try HwpTabInfo(&reader)

        expect(tabInfo.rawPayload) == slicedPayload
        expect(tabInfo.location) == 7200
        expect(tabInfo.type) == 2
        expect(tabInfo.fillType) == 3
        expect(tabInfo.reserved) == 0x0405
        expect(reader.isEOF) == true
    }

    func testTabDefAndTabInfoRawPayloadsSurviveCodableRoundTrip() throws {
        let payload = tabDefPayload()

        let decoded = try decodeRoundTrip(HwpTabDef.load(payload))

        expect(decoded.rawPayload) == payload
        expect(decoded.tabInfoArray.map(\.rawPayload)) == [tabInfoPayload()]
    }

    func testTabDefRejectsNegativeCountWithTypedError() {
        var payload = Data()
        payload.append(littleEndianData(UInt32(0)))
        payload.append(littleEndianData(Int32(-1)))

        expect {
            _ = try HwpTabDef.load(payload)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })
    }

    func testTabDefRejectsTruncatedTabInfoWithTypedError() {
        let payload = tabDefPayload().dropLast()

        expect {
            _ = try HwpTabDef.load(Data(payload))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 8
            expect(actual) == 7
        })
    }

    func testTabDefRejectsTabInfoCountMismatchWithTypedError() {
        var payload = tabDefHeaderPayload(count: 2)
        payload.append(tabInfoPayload())

        expect {
            _ = try HwpTabDef.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 16
            expect(actual) == 8
        })
    }

    func testTabDefRejectsOversizedTabInfoCountBeforeIterating() {
        let payload = tabDefHeaderPayload(count: Int32.max)

        expect {
            _ = try HwpTabDef.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == Int(Int32.max) * 8
            expect(actual) == 0
        })
    }

    func testTabDefRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(tabDefPayload(), Data([0xFF]))

        expect {
            _ = try HwpTabDef.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpTabDef"
            expect(remain) == 1
        })
    }

    func testTabInfoRejectsTruncatedFixedFieldsWithTypedError() {
        let payload = Data(tabInfoPayload().dropLast())

        expect {
            _ = try HwpTabInfo.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })
    }

    func testTabInfoRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(tabInfoPayload(), Data([0xFF]))

        expect {
            _ = try HwpTabInfo.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpTabInfo"
            expect(remain) == 1
        })
    }
}

private func tabDefPayload() -> Data {
    var data = tabDefHeaderPayload(count: 1)
    data.append(tabInfoPayload())
    return data
}

private func tabDefHeaderPayload(count: Int32) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x0102_0304)))
    data.append(littleEndianData(count))
    return data
}

private func tabInfoPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(Int32(7200)))
    data.append(Data([2, 3]))
    data.append(littleEndianData(UInt16(0x0405)))
    return data
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
