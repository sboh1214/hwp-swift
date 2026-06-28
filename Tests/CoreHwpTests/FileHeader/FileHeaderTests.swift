@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FileHeaderTests: XCTestCase {
    func testDoesHaveDocumentHistory() throws {
        let hwp = try openHwp(#file, "문서이력관리")
        expect(hwp.fileHeader.fileProperty.doesHaveDocumentHistory) == true
    }

    func testDocumentHistoryFixtureSurvivesHwpFileCodableRoundTrip() throws {
        let roundTrip = try LegacyHeaderFixtureRoundTrip(id: "문서이력관리")

        try FixtureAssertions.assertReadableFixture(roundTrip.fixture, roundTrip.decoded)
        expect(roundTrip.decoded.fileHeader.fileProperty.doesHaveDocumentHistory) == true
        assertTopLevelRawPayloadsMatch(roundTrip.decoded, roundTrip.original)
    }

    func testLegacyTrackChangesFlagFixtureKeepsFileHeaderTracingBitFalse() throws {
        let hwp = try openHwp(#file, "변경내용추적")
        expect(hwp.fileHeader.fileProperty.rawValue) == 1
        expect(hwp.fileHeader.fileProperty.isCompressed) == true
        expect(hwp.fileHeader.fileProperty.isTracingChange) == false
    }

    func testLegacyTrackChangesFlagFixtureSurvivesHwpFileCodableRoundTrip() throws {
        let roundTrip = try LegacyHeaderFixtureRoundTrip(id: "변경내용추적")

        try FixtureAssertions.assertReadableFixture(roundTrip.fixture, roundTrip.decoded)
        expect(roundTrip.decoded.fileHeader.fileProperty.rawValue) == 1
        expect(roundTrip.decoded.fileHeader.fileProperty.isTracingChange) == false
        assertTopLevelRawPayloadsMatch(roundTrip.decoded, roundTrip.original)
    }

    func testIsKOGLDocument() throws {
        let hwp = try openHwp(#file, "공공누리")
        expect(hwp.fileHeader.fileProperty.isKOGLDocument) == true
    }

    func testCCLFixtureUsesFilePropertyFlagWithoutLicenseBits() throws {
        let hwp = try openHwp(#file, "CCL")
        expect(hwp.fileHeader.fileProperty.rawValue) == 2049
        expect(hwp.fileHeader.fileProperty.isCCLDocument) == true
        expect(hwp.fileHeader.fileProperty.isKOGLDocument) == false
        expect(hwp.fileHeader.fileLicense.rawValue) == 0
        expect(hwp.fileHeader.fileLicense.doesHaveKoreaOpenLicense) == false
    }

    func testTruncatedFileHeaderThrowsTypedError() {
        expect {
            _ = try HwpFileHeader.load(Data([0x48, 0x57, 0x50]))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 32
            expect(actual) == 3
        })
    }

    func testTruncatedFilePropertyThrowsTypedError() {
        let payload = validHwpSignatureData() + Data([1, 0, 1, 5])

        expect {
            _ = try HwpFileHeader.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 0
        })
    }

    func testTruncatedFixedWidthFileHeaderFieldsThrowTypedError() {
        let signatureAndVersion = validHwpSignatureData() + Data([1, 0, 1, 5])
        let fileProperty = littleEndianData(UInt32(0))
        let fileLicense = littleEndianData(UInt32(0))
        let encryptVersion = littleEndianData(UInt32(4))
        let scenarios = [
            FileHeaderTruncationScenario(
                name: "version",
                payload: validHwpSignatureData() + Data([1, 0]),
                expected: 4,
                actual: 2
            ),
            FileHeaderTruncationScenario(
                name: "fileLicense",
                payload: signatureAndVersion + fileProperty + Data([0xAA, 0xBB]),
                expected: 4,
                actual: 2
            ),
            FileHeaderTruncationScenario(
                name: "encryptVersion",
                payload: signatureAndVersion + fileProperty + fileLicense + Data([0xAA]),
                expected: 4,
                actual: 1
            ),
            FileHeaderTruncationScenario(
                name: "koreaOpenLicense",
                payload: signatureAndVersion + fileProperty + fileLicense + encryptVersion,
                expected: 1,
                actual: 0
            ),
        ]

        for scenario in scenarios {
            expect {
                _ = try HwpFileHeader.load(scenario.payload)
            }.to(throwError { error in
                guard case let HwpError.truncatedData(expected, actual) = error else {
                    return fail("Expected truncatedData for \(scenario.name), got \(error)")
                }
                expect(expected) == scenario.expected
                expect(actual) == scenario.actual
            })
        }
    }

    func testNonASCIISignatureThrowsTypedError() {
        let signature = Data([0xFF]) + Data(repeating: 0, count: 31)

        expect {
            _ = try HwpFileHeader.load(fileHeaderPayload(signature: signature))
        }.to(throwError { error in
            guard case let HwpError.invalidDataForString(data, name) = error else {
                return fail("Expected invalidDataForString, got \(error)")
            }
            expect(data) == signature
            expect(name) == "signature"
        })
    }

    func testInvalidOLEFileHeaderPathThrowsTypedError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-file-header-\(UUID().uuidString).hwp")
        try Data("not an OLE file".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        expect {
            _ = try HwpFileHeader.load(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).notTo(beEmpty())
        })
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testInvalidOLEFileHeaderWrapperThrowsTypedError() {
            let wrapper = FileWrapper(regularFileWithContents: Data("not an OLE file".utf8))

            expect {
                _ = try HwpFileHeader.load(fromWrapper: wrapper)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).notTo(beEmpty())
            })
        }
    #endif

    func testInvalidFileHeaderSignatureThrowsTypedError() {
        expect {
            _ = try HwpFileHeader.load(fileHeaderPayload(
                signature: Data(repeating: 0x20, count: 32)
            ))
        }.to(throwError { error in
            guard case let HwpError.invalidFileHeaderSignature(signature) = error else {
                return fail("Expected invalidFileHeaderSignature, got \(error)")
            }
            expect(signature) == String(repeating: " ", count: 32)
        })
    }

    func testUnsupportedFeatureBitsAreDecodedFromFileProperty() throws {
        let fileProperty = UInt32(1 << 1) | UInt32(1 << 2) | UInt32(1 << 4)

        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(fileProperty: fileProperty))

        expect(fileHeader.fileProperty.rawValue) == fileProperty
        expect(fileHeader.fileProperty.isEncrypted) == true
        expect(fileHeader.fileProperty.isDeploymentDocument) == true
        expect(fileHeader.fileProperty.isDRMDocument) == true
        expect(fileHeader.fileProperty.unsupportedFeature) == .encryptedDocument
    }

    func testFilePropertyDecodesEveryKnownFlagAndPreservesUnusedBits() throws {
        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(fileProperty: UInt32.max))
        let property = fileHeader.fileProperty

        expect(property.rawValue) == UInt32.max
        expect(property.isCompressed) == true
        expect(property.isEncrypted) == true
        expect(property.isDeploymentDocument) == true
        expect(property.doesSaveScript) == true
        expect(property.isDRMDocument) == true
        expect(property.doesHaveXMLTemplate) == true
        expect(property.doesHaveDocumentHistory) == true
        expect(property.doesHaveSignature) == true
        expect(property.doesEncryptAccreditedCertificate) == true
        expect(property.doesSaveSpareSignature) == true
        expect(property.isAccreditedCertificateDRMDocument) == true
        expect(property.isCCLDocument) == true
        expect(property.doesOptimizeMobile) == true
        expect(property.isPersonalInformationSecurityDocument) == true
        expect(property.isTracingChange) == true
        expect(property.isKOGLDocument) == true
        expect(property.doesHaveVideoControl) == true
        expect(property.doesHaveTOCFieldControl) == true
        expect(property.unused) == Array(repeating: true, count: 14)
        expect(property.unsupportedFeature) == .encryptedDocument
    }

    func testDeploymentDocumentTakesPrecedenceOverDRMDocument() throws {
        let fileProperty = UInt32(1 << 2) | UInt32(1 << 4) | UInt32(1 << 10)

        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(fileProperty: fileProperty))

        expect(fileHeader.fileProperty.isDeploymentDocument) == true
        expect(fileHeader.fileProperty.isDRMDocument) == true
        expect(fileHeader.fileProperty.isAccreditedCertificateDRMDocument) == true
        expect(fileHeader.fileProperty.unsupportedFeature) == .deploymentDocument
    }

    func testAccreditedCertificateSecurityBitsMapToUnsupportedFeatures() throws {
        let encryptedHeader = try HwpFileHeader.load(
            fileHeaderPayload(fileProperty: UInt32(1 << 8))
        )
        let drmHeader = try HwpFileHeader.load(fileHeaderPayload(fileProperty: UInt32(1 << 10)))

        expect(encryptedHeader.fileProperty.doesEncryptAccreditedCertificate) == true
        expect(encryptedHeader.fileProperty.unsupportedFeature) == .encryptedDocument
        expect(drmHeader.fileProperty.isAccreditedCertificateDRMDocment) == true
        expect(drmHeader.fileProperty.isAccreditedCertificateDRMDocument) == true
        expect(drmHeader.fileProperty.unsupportedFeature) == .drmDocument
    }

    func testAccreditedCertificateDRMAliasUpdatesStoredFlag() {
        var fileProperty = HwpFileProperty()

        fileProperty.isAccreditedCertificateDRMDocument = true

        expect(fileProperty.isAccreditedCertificateDRMDocment) == true
        expect(fileProperty.isAccreditedCertificateDRMDocument) == true
        expect(fileProperty.unsupportedFeature) == .drmDocument
    }

    func testFileLicenseBitsAreDecoded() throws {
        let rawLicense = UInt32(0b111)
        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(fileLicense: rawLicense))
        let allBitsLicense = try fileLicense(UInt32.max)

        expect(fileHeader.fileLicense.rawValue) == rawLicense
        expect(fileHeader.fileLicense.doesHaveKoreaOpenLicense) == true
        expect(fileHeader.fileLicense.doesLimitReplication) == true
        expect(fileHeader.fileLicense.doesHavePermission) == true
        expect(allBitsLicense.rawValue) == UInt32.max
        expect(allBitsLicense.doesHaveKoreaOpenLicense) == true
        expect(allBitsLicense.doesLimitReplication) == true
        expect(allBitsLicense.doesHavePermission) == true
        expect(allBitsLicense.unused) == Array(repeating: true, count: 29)
    }

    func testFileLicensePreservesUnusedBitsAsRawValue() throws {
        let rawLicense = UInt32(0xFFFF_FFF8)

        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(fileLicense: rawLicense))

        expect(fileHeader.fileLicense.rawValue) == rawLicense
        expect(fileHeader.fileLicense.doesHaveKoreaOpenLicense) == false
        expect(fileHeader.fileLicense.doesLimitReplication) == false
        expect(fileHeader.fileLicense.doesHavePermission) == false
        expect(fileHeader.fileLicense.unused) == Array(repeating: true, count: 29)
    }

    func testDefaultFileLicenseUsesEmptyRawValueAndFlags() {
        let license = HwpFileLicense()

        expect(license.rawValue) == 0
        expect(license.doesHaveKoreaOpenLicense) == false
        expect(license.doesLimitReplication) == false
        expect(license.doesHavePermission) == false
    }

    func testFilePropertyAndLicenseRawValuesSurviveCodableRoundTrip() throws {
        let property = UInt32(1 << 0) | UInt32(1 << 6) | UInt32(1 << 15)
        let license = UInt32(0b101)
        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(
            fileProperty: property,
            fileLicense: license
        ))

        let decoded = try JSONDecoder().decode(
            HwpFileHeader.self,
            from: JSONEncoder().encode(fileHeader)
        )

        expect(decoded.fileProperty.rawValue) == property
        expect(decoded.fileLicense.rawValue) == license
        expect(decoded) == fileHeader
    }

    func testReservedBytesArePreserved() throws {
        let reserved = Data((0 ..< 207).map { UInt8($0 % 256) })
        let payload = fileHeaderPayload(reserved: reserved)

        let fileHeader = try HwpFileHeader.load(payload)

        expect(fileHeader.rawPayload) == payload
        expect(fileHeader.reserved) == reserved
    }

    func testTrailingFileHeaderBytesThrowTypedEOFError() {
        let payload = fileHeaderPayload() + Data([0xAA, 0xBB])

        expect {
            _ = try HwpFileHeader.load(payload)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpFileHeader"
            expect(remain) == 2
        })
    }

    func testReservedBytesSurviveCodableRoundTrip() throws {
        let reserved = Data((0 ..< 207).map { UInt8(($0 * 3) % 256) })
        let fileHeader = try HwpFileHeader.load(fileHeaderPayload(reserved: reserved))

        let decoded = try JSONDecoder().decode(
            HwpFileHeader.self,
            from: JSONEncoder().encode(fileHeader)
        )

        expect(decoded.rawPayload) == fileHeader.rawPayload
        expect(decoded.reserved) == reserved
        expect(decoded) == fileHeader
    }

    func testTruncatedReservedBytesThrowsTypedError() {
        expect {
            _ = try HwpFileHeader.load(fileHeaderPayload(reserved: Data([0xAA, 0xBB, 0xCC])))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 207
            expect(actual) == 3
        })
    }
}

private struct FileHeaderTruncationScenario {
    let name: String
    let payload: Data
    let expected: Int
    let actual: Int
}

private struct LegacyHeaderFixtureRoundTrip {
    let fixture: LoadedFixture
    let original: HwpFile
    let decoded: HwpFile

    init(id: String) throws {
        fixture = try FixtureLoader.load(id: id)
        original = try HwpFile(fromPath: fixture.documentURL.path)
        decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(original)
        )
    }
}

private func assertTopLevelRawPayloadsMatch(_ decoded: HwpFile, _ original: HwpFile) {
    expect(decoded.fileHeader.rawPayload) == original.fileHeader.rawPayload
    expect(decoded.fileHeader.version.rawPayload) == original.fileHeader.version.rawPayload
    expect(decoded.fileHeader.reserved) == original.fileHeader.reserved
    expect(decoded.fileHeader.fileProperty.rawValue) == original.fileHeader.fileProperty.rawValue
    expect(decoded.fileHeader.fileLicense.rawValue) == original.fileHeader.fileLicense.rawValue
    expect(decoded.summary.rawPayload) == original.summary.rawPayload
    expect(decoded.previewText.rawPayload) == original.previewText.rawPayload
    expect(decoded.previewText.text) == original.previewText.text
    expect(decoded.previewImage.rawPayload) == original.previewImage.rawPayload
    expect(decoded.previewImage.image) == original.previewImage.image
    expect(decoded.previewImage.format) == original.previewImage.format
    expect(decoded.docInfo.rawPayload) == original.docInfo.rawPayload
    expect(decoded.docInfo.documentProperties.rawPayload) ==
        original.docInfo.documentProperties.rawPayload
    expect(decoded.docInfo.documentProperties.startingIndex.rawPayload) ==
        original.docInfo.documentProperties.startingIndex.rawPayload
    expect(decoded.docInfo.documentProperties.caratLocation.rawPayload) ==
        original.docInfo.documentProperties.caratLocation.rawPayload
    expect(decoded.sectionArray.map(\.rawPayload)) == original.sectionArray.map(\.rawPayload)
    expect(decoded.binaryDataArray.map(\.data)) == original.binaryDataArray.map(\.data)
}

private func fileHeaderPayload(
    signature: Data = validHwpSignatureData(),
    fileProperty: UInt32 = 0,
    fileLicense: UInt32 = 0,
    encryptVersion: UInt32 = 4,
    koreaOpenLicense: UInt8 = 0,
    reserved: Data = Data(repeating: 0, count: 207)
) -> Data {
    var data = Data()
    data.append(signature)
    data.append(Data([1, 0, 1, 5]))
    data.append(littleEndianData(fileProperty))
    data.append(littleEndianData(fileLicense))
    data.append(littleEndianData(encryptVersion))
    data.append(koreaOpenLicense)
    data.append(reserved)
    return data
}

private func fileLicense(_ rawValue: UInt32) throws -> HwpFileLicense {
    try HwpFileHeader.load(fileHeaderPayload(fileLicense: rawValue)).fileLicense
}

private func validHwpSignatureData() -> Data {
    Data("HWP Document File".utf8) + Data(repeating: 0, count: 15)
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
