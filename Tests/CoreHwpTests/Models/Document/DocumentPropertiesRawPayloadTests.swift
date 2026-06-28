@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocumentPropertiesRawPayloadTests: XCTestCase {
    func testDocumentPropertiesInitializersPreserveRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = documentPropertiesPayload(
            sectionSize: 3,
            startingIndex: [1, 2, 3, 4, 5, 6],
            caratLocation: [7, 8, 9]
        )
        let slicedPayload = (Data([0xEF]) + payload).dropFirst()
        var reader = DataReader(slicedPayload)

        let properties = try HwpDocumentProperties(&reader)

        expect(properties.rawPayload) == slicedPayload
        expect(properties.startingIndex.rawPayload) == Data(slicedPayload.dropFirst(2).prefix(12))
        expect(properties.caratLocation.rawPayload) == Data(slicedPayload.dropFirst(14).prefix(12))
        expect(reader.isEOF) == true
    }

    func testStartingIndexInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = documentPropertiesPayload(
            sectionSize: 1,
            startingIndex: [10, 11, 12, 13, 14, 15],
            caratLocation: [0, 0, 0]
        ).dropFirst(2).prefix(12)
        let slicedPayload = (Data([0xEF]) + payload).dropFirst()
        var reader = DataReader(slicedPayload)

        let startingIndex = try HwpStartingIndex(&reader)

        expect(startingIndex.rawPayload) == slicedPayload
        expect(startingIndex.page) == 10
        expect(startingIndex.equation) == 15
        expect(reader.isEOF) == true
    }

    func testCaratLocationInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = documentPropertiesPayload(
            sectionSize: 1,
            startingIndex: [0, 0, 0, 0, 0, 0],
            caratLocation: [16, 17, 18]
        ).dropFirst(14).prefix(12)
        let slicedPayload = (Data([0xEF]) + payload).dropFirst()
        var reader = DataReader(slicedPayload)

        let caratLocation = try HwpCaratLocation(&reader)

        expect(caratLocation.rawPayload) == slicedPayload
        expect(caratLocation.listId) == 16
        expect(caratLocation.charIndex) == 18
        expect(reader.isEOF) == true
    }

    func testDocumentPropertiesPreserveRawPayloads() throws {
        let payload = documentPropertiesPayload(
            sectionSize: 2,
            startingIndex: [1, 2, 3, 4, 5, 6],
            caratLocation: [7, 8, 9]
        )

        let properties = try HwpDocumentProperties.load(payload)

        expect(properties.rawPayload) == payload
        expect(properties.sectionSize) == 2
        expect(properties.startingIndex.rawPayload) == Data(payload.dropFirst(2).prefix(12))
        expect(properties.startingIndex.page) == 1
        expect(properties.startingIndex.footnote) == 2
        expect(properties.startingIndex.endnote) == 3
        expect(properties.startingIndex.picture) == 4
        expect(properties.startingIndex.table) == 5
        expect(properties.startingIndex.equation) == 6
        expect(properties.caratLocation.rawPayload) == Data(payload.dropFirst(14).prefix(12))
        expect(properties.caratLocation.listId) == 7
        expect(properties.caratLocation.paragraphId) == 8
        expect(properties.caratLocation.charIndex) == 9
    }

    func testDocumentPropertiesRawPayloadsSurviveCodableRoundTrip() throws {
        let payload = documentPropertiesPayload(
            sectionSize: 1,
            startingIndex: [10, 11, 12, 13, 14, 15],
            caratLocation: [16, 17, 18]
        )
        let properties = try HwpDocumentProperties.load(payload)

        let decoded = try JSONDecoder().decode(
            HwpDocumentProperties.self,
            from: JSONEncoder().encode(properties)
        )

        expect(decoded.rawPayload) == payload
        expect(decoded.startingIndex.rawPayload) == properties.startingIndex.rawPayload
        expect(decoded.caratLocation.rawPayload) == properties.caratLocation.rawPayload
        expect(decoded) == properties
    }

    func testDocumentPropertiesRejectTruncatedFixedFieldsWithTypedError() {
        let sectionSize = documentPropertiesLittleEndianData(UInt16(1))
        let startingIndex = Data(repeating: 0, count: 12)
        let scenarios = [
            DocumentPropertiesTruncationScenario(
                name: "sectionSize",
                payload: Data([0x01]),
                expected: 2,
                actual: 1
            ),
            DocumentPropertiesTruncationScenario(
                name: "startingIndex",
                payload: sectionSize + Data(repeating: 0, count: 11),
                expected: 12,
                actual: 11
            ),
            DocumentPropertiesTruncationScenario(
                name: "caratLocation",
                payload: sectionSize + startingIndex + Data(repeating: 0, count: 11),
                expected: 12,
                actual: 11
            ),
        ]

        for scenario in scenarios {
            expect {
                _ = try HwpDocumentProperties.load(scenario.payload)
            }.to(throwError { error in
                guard case let HwpError.truncatedData(expected, actual) = error else {
                    return fail("Expected truncatedData for \(scenario.name), got \(error)")
                }
                expect(expected) == scenario.expected
                expect(actual) == scenario.actual
            })
        }
    }

    func testDocumentPropertiesRejectTrailingBytesWithTypedError() {
        let payload = documentPropertiesPayload(
            sectionSize: 1,
            startingIndex: [1, 2, 3, 4, 5, 6],
            caratLocation: [7, 8, 9]
        ) + Data([0xFF])

        expect {
            _ = try HwpDocumentProperties.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpDocumentProperties"
            expect(remain) == 1
        })
    }

    func testDocumentPropertySubrecordsRejectTrailingBytesWithTypedError() {
        let startingIndexPayload = Data(repeating: 0, count: 12) + Data([0xAA])
        let caratLocationPayload = Data(repeating: 0, count: 12) + Data([0xBB, 0xCC])
        let scenarios = [
            DocumentPropertiesTrailingScenario(
                name: "HwpStartingIndex",
                remain: 1,
                load: {
                    _ = try HwpStartingIndex.load(startingIndexPayload)
                }
            ),
            DocumentPropertiesTrailingScenario(
                name: "HwpCaratLocation",
                remain: 2,
                load: {
                    _ = try HwpCaratLocation.load(caratLocationPayload)
                }
            ),
        ]

        for scenario in scenarios {
            expect {
                try scenario.load()
            }.to(throwError { error in
                guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                    return fail("Expected bytesAreNotEOF for \(scenario.name), got \(error)")
                }
                expect(String(describing: model)) == scenario.name
                expect(remain) == scenario.remain
            })
        }
    }

    func testActualFixtureDocumentPropertiesPreserveRawPayloads() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "plain-text-minimal").path)
        let properties = hwp.docInfo.documentProperties

        expect(properties.rawPayload.count) == 26
        expect(properties.rawPayload.prefix(2)) == Data([0x01, 0x00])
        expect(properties.startingIndex.rawPayload) ==
            Data(properties.rawPayload.dropFirst(2).prefix(12))
        expect(properties.caratLocation.rawPayload) ==
            Data(properties.rawPayload.dropFirst(14).prefix(12))

        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expect(decoded.docInfo.documentProperties.rawPayload) == properties.rawPayload
        expect(decoded.docInfo.documentProperties.startingIndex.rawPayload) ==
            properties.startingIndex.rawPayload
        expect(decoded.docInfo.documentProperties.caratLocation.rawPayload) ==
            properties.caratLocation.rawPayload
    }
}

private struct DocumentPropertiesTruncationScenario {
    let name: String
    let payload: Data
    let expected: Int
    let actual: Int
}

private struct DocumentPropertiesTrailingScenario {
    let name: String
    let remain: Int
    let load: () throws -> Void
}

private func documentPropertiesPayload(
    sectionSize: UInt16,
    startingIndex: [UInt16],
    caratLocation: [UInt32]
) -> Data {
    var data = documentPropertiesLittleEndianData(sectionSize)
    for value in startingIndex {
        data.append(documentPropertiesLittleEndianData(value))
    }
    for value in caratLocation {
        data.append(documentPropertiesLittleEndianData(value))
    }
    return data
}

private func documentPropertiesLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
