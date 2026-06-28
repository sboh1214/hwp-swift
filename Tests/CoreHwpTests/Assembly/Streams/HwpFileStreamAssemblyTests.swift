@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class HwpFileStreamAssemblyTests: XCTestCase {
    func testDecodedStreamsUseDefaultModelsForMissingOptionalStreams() throws {
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: minimalDocInfoData(sectionSize: 1),
            sectionDataArray: [minimalSectionData()]
        )

        expect(hwp.sectionArray.count) == 1
        expect(hwp.summary.rawPayload).to(beEmpty())
        expect(hwp.previewText.text) == "\r\n"
        expect(hwp.previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
        expect(hwp.previewImage.rawPayload).to(beEmpty())
        expect(hwp.previewImage.image).to(beEmpty())
        expect(hwp.previewImage.format) == HwpPreviewImageFormat.none
        expect(hwp.binaryDataArray).to(beEmpty())
    }

    func testDecodedStreamsAcceptPreparsedDocInfoForSectionValidation() throws {
        let fileHeader = HwpFileHeader()
        let docInfoData = minimalDocInfoData(sectionSize: 1)
        let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)

        let hwp = try HwpFile(
            fileHeader: fileHeader,
            docInfo: docInfo,
            sectionDataArray: [minimalSectionData()]
        )

        expect(hwp.docInfo.rawPayload) == docInfoData
        expect(hwp.sectionArray.count) == 1
        expect(hwp.sectionArray.map(\.rawPayload)) == [minimalSectionData()]
    }

    func testDecodedStreamsPreserveMultipleSectionsInInputOrder() throws {
        let firstSectionData = minimalSectionData()
        let secondUnknownPayload = Data([0xCA, 0xFE])
        let secondSectionData = fixtureRecordData(
            tagId: 0x2FE,
            level: 0,
            payload: secondUnknownPayload
        ) + minimalSectionData()

        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: minimalDocInfoData(sectionSize: 2),
            sectionDataArray: [firstSectionData, secondSectionData]
        )

        expect(hwp.sectionArray.count) == 2
        expect(hwp.sectionArray.map(\.rawPayload)) == [firstSectionData, secondSectionData]
        expect(hwp.sectionArray.first?.unknownRecords).to(beEmpty())
        expect(hwp.sectionArray.last?.unknownRecords) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 0, payload: secondUnknownPayload),
        ]
    }

    func testDecodedStreamsPreserveProvidedOptionalStreams() throws {
        let summaryData = Data([0xAA, 0xBB])
        let previewTextData = Data([0x41, 0x00, 0x0D, 0x00, 0x0A, 0x00])
        let previewImageData = Data([0x47, 0x49, 0x46, 0x38, 0x01])
        let binaryPayload = Data([0xCA, 0xFE])

        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: minimalDocInfoData(sectionSize: 1),
            sectionDataArray: [minimalSectionData()],
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: [("BIN0007.gif", binaryPayload)]
        )

        expect(hwp.summary.rawPayload) == summaryData
        expect(hwp.previewText.text) == "A\r\n"
        expect(hwp.previewText.rawPayload) == previewTextData
        expect(hwp.previewImage.rawPayload) == previewImageData
        expect(hwp.previewImage.image) == previewImageData
        expect(hwp.previewImage.format) == .gif
        expect(hwp.binaryDataArray.map(\.name)) == ["BIN0007.gif"]
        expect(hwp.binaryDataArray.map(\.streamId)) == [7]
        expect(hwp.binaryDataArray.map(\.extensionName)) == ["gif"]
        expect(hwp.binaryDataArray.map(\.data)) == [binaryPayload]
    }

    func testDecodedStreamsPreserveNonCanonicalBinaryDataNamesAndPayloads() throws {
        let binaryData = [
            ("BIN0001.png", Data([0x01])),
            ("BIN0002", Data([0x02])),
            ("BIN0003.", Data([0x03])),
            ("BIN000X.dat", Data([0x04])),
            ("ObjectPool", Data([0x05])),
        ]

        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: minimalDocInfoData(sectionSize: 1),
            sectionDataArray: [minimalSectionData()],
            binaryData: binaryData
        )

        let expectedStreamIds: [UInt16?] = [1, nil, nil, nil, nil]
        let expectedExtensionNames: [String?] = ["png", nil, nil, nil, nil]

        expect(hwp.binaryDataArray.map(\.name)) == binaryData.map(\.0)
        expect(hwp.binaryDataArray.map(\.streamId)) == expectedStreamIds
        expect(hwp.binaryDataArray.map(\.extensionName)) == expectedExtensionNames
        expect(hwp.binaryDataArray.map(\.data)) == binaryData.map(\.1)

        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expect(decoded.binaryDataArray.map(\.name)) == binaryData.map(\.0)
        expect(decoded.binaryDataArray.map(\.streamId)) == expectedStreamIds
        expect(decoded.binaryDataArray.map(\.extensionName)) == expectedExtensionNames
        expect(decoded.binaryDataArray.map(\.data)) == binaryData.map(\.1)
    }

    func testDecodedFilePreservesRawPayloadsThroughCodableRoundTrip() throws {
        let docInfoData = minimalDocInfoData(sectionSize: 1)
        let sectionData = minimalSectionData()
        let summaryData = Data([0xAA, 0xBB])
        let previewTextData = Data([0x41, 0x00, 0x0D, 0x00, 0x0A, 0x00])
        let previewImageData = Data([0x47, 0x49, 0x46, 0x38, 0x01])
        let binaryPayload = Data([0xCA, 0xFE])
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: docInfoData,
            sectionDataArray: [sectionData],
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: [("BIN0007.gif", binaryPayload)]
        )

        let encoded = try JSONEncoder().encode(hwp)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

        expect(decoded.docInfo.rawPayload) == docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == [sectionData]
        expect(decoded.summary.rawPayload) == summaryData
        expect(decoded.previewText.rawPayload) == previewTextData
        expect(decoded.previewImage.rawPayload) == previewImageData
        expect(decoded.previewImage.image) == previewImageData
        expect(decoded.binaryDataArray.map(\.name)) == ["BIN0007.gif"]
        expect(decoded.binaryDataArray.map(\.data)) == [binaryPayload]
    }

    func testDecodedStreamsRejectInvalidPreviewTextWithTypedError() {
        let invalidPreviewTextData = Data([0x00, 0xD8])

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 1),
                sectionDataArray: [minimalSectionData()],
                previewTextData: invalidPreviewTextData
            )
        }.to(throwError { error in
            guard case let HwpError.invalidDataForString(data, name) = error else {
                return fail("Expected invalidDataForString, got \(error)")
            }
            expect(data) == invalidPreviewTextData
            expect(name) == "PreviewText"
        })
    }

    func testDecodedStreamsRejectMalformedDocInfoRecordWithTypedError() {
        let malformedDocInfoData = Data([0x00, 0x01, 0x02])

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: malformedDocInfoData,
                sectionDataArray: [minimalSectionData()]
            )
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == malformedDocInfoData.count
        })
    }

    func testDecodedStreamsRejectInvalidDocInfoRecordTreeWithTypedError() {
        let invalidDocInfoData = fixtureRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 1,
            payload: fixtureDocumentPropertiesPayload(sectionSize: 1)
        )

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: invalidDocInfoData,
                sectionDataArray: [minimalSectionData()]
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "record level 1 has no parent"
        })
    }

    func testDecodedStreamsRejectMalformedBodyTextSectionRecordWithTypedError() {
        let malformedSectionData = Data([0x00, 0x01, 0x02])

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 1),
                sectionDataArray: [malformedSectionData]
            )
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == malformedSectionData.count
        })
    }

    func testDecodedStreamsRejectInvalidBodyTextRecordTreeWithTypedError() {
        let invalidSectionData = fixtureRecordData(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 1,
            payload: fixtureParaHeaderPayload()
        )

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 1),
                sectionDataArray: [invalidSectionData]
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "record level 1 has no parent"
        })
    }

    func testDecodedStreamsRejectMissingBodyTextSections() {
        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 1),
                sectionDataArray: []
            )
        }.to(throwError { error in
            guard case let HwpError.streamDoesNotExist(name) = error else {
                return fail("Expected streamDoesNotExist, got \(error)")
            }
            expect(name) == .bodyText
        })
    }

    func testDecodedStreamsRejectZeroSectionSizeBeforeMissingBodyText() {
        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 0),
                sectionDataArray: []
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "BodyText sectionSize 0 is invalid"
        })
    }

    func testDecodedStreamsRejectSectionCountMismatch() {
        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: minimalDocInfoData(sectionSize: 2),
                sectionDataArray: [minimalSectionData()]
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText section count 1 != sectionSize 2"))
        })
    }

    func testDecodedStreamsRejectPreparsedDocInfoSectionCountMismatch() throws {
        let fileHeader = HwpFileHeader()
        let docInfo = try HwpDocInfo.load(
            minimalDocInfoData(sectionSize: 2),
            fileHeader.version
        )

        expect {
            _ = try HwpFile(
                fileHeader: fileHeader,
                docInfo: docInfo,
                sectionDataArray: [minimalSectionData()]
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText section count 1 != sectionSize 2"))
        })
    }

    func testDecodedStreamsRejectUnsupportedPreparsedDocInfoBeforeParsingSections() throws {
        let cases: [(configure: (inout HwpFileHeader) -> Void, expected: HwpUnsupportedFeature)] = [
            ({ $0.fileProperty.isEncrypted = true }, .encryptedDocument),
            ({ $0.fileProperty.isDeploymentDocument = true }, .deploymentDocument),
            ({ $0.fileProperty.isDRMDocument = true }, .drmDocument),
            ({ $0.fileProperty.doesEncryptAccreditedCertificate = true }, .encryptedDocument),
            ({ $0.fileProperty.isAccreditedCertificateDRMDocument = true }, .drmDocument),
        ]

        for testCase in cases {
            var fileHeader = HwpFileHeader()
            testCase.configure(&fileHeader)
            let docInfo = try HwpDocInfo.load(
                minimalDocInfoData(sectionSize: 1),
                fileHeader.version
            )
            let malformedSectionData = Data([0x00, 0x01, 0x02])

            expect {
                _ = try HwpFile(
                    fileHeader: fileHeader,
                    docInfo: docInfo,
                    sectionDataArray: [malformedSectionData]
                )
            }.to(throwError { error in
                guard case let HwpError.unsupportedFeature(feature) = error else {
                    return fail("Expected unsupportedFeature, got \(error)")
                }
                expect(feature) == testCase.expected
            })
        }
    }

    func testDecodedStreamsRejectUnsupportedFileHeaderBeforeParsingStreams() {
        var fileHeader = HwpFileHeader()
        fileHeader.fileProperty.isDRMDocument = true

        assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
            fileHeader,
            expectedFeature: .drmDocument
        )
    }

    func testDecodedStreamsRejectEncryptedFileHeaderBeforeParsingStreams() {
        var fileHeader = HwpFileHeader()
        fileHeader.fileProperty.isEncrypted = true

        assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
            fileHeader,
            expectedFeature: .encryptedDocument
        )
    }

    func testDecodedStreamsRejectDeploymentFileHeaderBeforeParsingStreams() {
        var fileHeader = HwpFileHeader()
        fileHeader.fileProperty.isDeploymentDocument = true

        assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
            fileHeader,
            expectedFeature: .deploymentDocument
        )
    }

    func testDecodedStreamsRejectAccreditedCertificateEncryptedFileHeaderBeforeParsingStreams() {
        var fileHeader = HwpFileHeader()
        fileHeader.fileProperty.doesEncryptAccreditedCertificate = true

        assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
            fileHeader,
            expectedFeature: .encryptedDocument
        )
    }

    func testDecodedStreamsRejectAccreditedCertificateDRMFileHeaderBeforeParsingStreams() {
        var fileHeader = HwpFileHeader()
        fileHeader.fileProperty.isAccreditedCertificateDRMDocument = true

        assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
            fileHeader,
            expectedFeature: .drmDocument
        )
    }
}

private func assertUnsupportedFeatureIsRejectedBeforeParsingStreams(
    _ fileHeader: HwpFileHeader,
    expectedFeature: HwpUnsupportedFeature
) {
    expect {
        _ = try HwpFile(
            fileHeader: fileHeader,
            docInfoData: Data(),
            sectionDataArray: []
        )
    }.to(throwError { error in
        guard case let HwpError.unsupportedFeature(feature) = error else {
            return fail("Expected unsupportedFeature, got \(error)")
        }
        expect(feature) == expectedFeature
    })
}

private func minimalDocInfoData(sectionSize: UInt16) -> Data {
    fixtureRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: fixtureDocumentPropertiesPayload(sectionSize: sectionSize)
    )
        + fixtureRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: fixtureIdMappingsPayload()
        )
}

private func minimalSectionData() -> Data {
    fixtureRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: fixtureParaHeaderPayload()
    )
        + fixtureRecordData(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: fixtureParaCharShapePayload()
        )
}

private func fixtureDocumentPropertiesPayload(sectionSize: UInt16) -> Data {
    fixtureLittleEndianData(sectionSize) + Data(repeating: 0, count: 24)
}

private func fixtureIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(fixtureLittleEndianData(count))
    }
}

private func fixtureParaHeaderPayload() -> Data {
    fixtureLittleEndianData(UInt32(0x8000_0000))
        + fixtureLittleEndianData(UInt32(0))
        + fixtureLittleEndianData(UInt16(0))
        + Data([0, 0])
        + fixtureLittleEndianData(UInt16(1))
        + fixtureLittleEndianData(UInt16(0))
        + fixtureLittleEndianData(UInt16(0))
        + fixtureLittleEndianData(UInt32(0))
        + fixtureLittleEndianData(UInt16(0))
}

private func fixtureParaCharShapePayload() -> Data {
    fixtureLittleEndianData(UInt32(0)) + fixtureLittleEndianData(UInt32(0))
}

private func fixtureRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = fixtureLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func fixtureLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
