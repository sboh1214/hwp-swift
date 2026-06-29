import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertFileHeader(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertFileHeader(expectations, hwp.fileHeader)
    }

    static func assertFileHeader(_ expectations: FixtureExpectations, _ fileHeader: HwpFileHeader) {
        assertFileHeaderRawPayload(expectations, fileHeader)
        if let fileHeaderVersionRawBytes = expectations.fileHeaderVersionRawBytes {
            expect(Array(fileHeader.version.rawPayload)) == fileHeaderVersionRawBytes
        }
        if let fileProperty = expectations.fileProperty {
            assertFileProperty(fileProperty, fileHeader.fileProperty)
        }
        if let fileLicense = expectations.fileLicense {
            assertFileLicense(fileLicense, fileHeader.fileLicense)
        }
        if let encryptVersion = expectations.encryptVersion {
            expect(fileHeader.encryptVersion) == encryptVersion
        }
        if let koreaOpenLicense = expectations.koreaOpenLicense {
            expect(fileHeader.koreaOpenLicense) == koreaOpenLicense
        }
    }

    static func assertFileProperty(
        _ expectations: FixtureFilePropertyExpectations,
        _ actual: HwpFileProperty
    ) {
        if let rawValue = expectations.rawValue {
            expect(actual.rawValue) == rawValue
        }
        if let isCompressed = expectations.isCompressed {
            expect(actual.isCompressed) == isCompressed
        }
        assertFilePropertySecurityBits(expectations, actual)
        if let doesHaveDocumentHistory = expectations.doesHaveDocumentHistory {
            expect(actual.doesHaveDocumentHistory) == doesHaveDocumentHistory
        }
        if let isCCLDocument = expectations.isCCLDocument {
            expect(actual.isCCLDocument) == isCCLDocument
        }
        if let isTracingChange = expectations.isTracingChange {
            expect(actual.isTracingChange) == isTracingChange
        }
        if let isKOGLDocument = expectations.isKOGLDocument {
            expect(actual.isKOGLDocument) == isKOGLDocument
        }
    }

    static func assertFilePropertySecurityBits(
        _ expectations: FixtureFilePropertyExpectations,
        _ actual: HwpFileProperty
    ) {
        if let isEncrypted = expectations.isEncrypted {
            expect(actual.isEncrypted) == isEncrypted
        }
        if let isDeploymentDocument = expectations.isDeploymentDocument {
            expect(actual.isDeploymentDocument) == isDeploymentDocument
        }
        if let isDRMDocument = expectations.isDRMDocument {
            expect(actual.isDRMDocument) == isDRMDocument
        }
        if let doesEncryptAccreditedCertificate = expectations.doesEncryptAccreditedCertificate {
            expect(actual.doesEncryptAccreditedCertificate) == doesEncryptAccreditedCertificate
        }
        if let isAccreditedCertificateDRMDocument =
            expectations.isAccreditedCertificateDRMDocument
        {
            expect(actual.isAccreditedCertificateDRMDocument) ==
                isAccreditedCertificateDRMDocument
        }
    }

    static func assertFileLicense(
        _ expectations: FixtureFileLicenseExpectations,
        _ actual: HwpFileLicense
    ) {
        if let rawValue = expectations.rawValue {
            expect(actual.rawValue) == rawValue
        }
        if let doesHaveKoreaOpenLicense = expectations.doesHaveKoreaOpenLicense {
            expect(actual.doesHaveKoreaOpenLicense) == doesHaveKoreaOpenLicense
        }
        if let doesLimitReplication = expectations.doesLimitReplication {
            expect(actual.doesLimitReplication) == doesLimitReplication
        }
        if let doesHavePermission = expectations.doesHavePermission {
            expect(actual.doesHavePermission) == doesHavePermission
        }
    }

    static func assertFileHeaderRawPayload(
        _ expectations: FixtureExpectations,
        _ fileHeader: HwpFileHeader
    ) {
        assertPayloadSample(
            fileHeader.rawPayload,
            length: expectations.fileHeaderRawPayloadLength,
            prefix: expectations.fileHeaderRawPayloadPrefixBytes,
            suffix: expectations.fileHeaderRawPayloadSuffixBytes
        )
        assertPayloadSample(
            fileHeader.reserved,
            length: expectations.fileHeaderReservedLength,
            prefix: expectations.fileHeaderReservedPrefixBytes,
            suffix: expectations.fileHeaderReservedSuffixBytes
        )
    }
}
