@testable import CoreHwp
import Foundation
import Nimble
import OLEKit

extension FixtureAssertions {
    static func assertUnsupportedFeatureBit(
        _ expectedError: FixtureExpectedError,
        _ fileProperty: HwpFileProperty
    ) {
        switch expectedError.code {
        case "unsupportedFeature.encryptedDocument":
            expect(fileProperty.unsupportedFeature) == .encryptedDocument
        case "unsupportedFeature.deploymentDocument":
            expect(fileProperty.unsupportedFeature) == .deploymentDocument
        case "unsupportedFeature.drmDocument":
            expect(fileProperty.unsupportedFeature) == .drmDocument
        default:
            fail("Unsupported fixture expected unknown error code: \(expectedError.code)")
        }
    }

    static func assertError(_ expectedError: FixtureExpectedError, _ url: URL) {
        expect { try HwpFile(fromPath: url.path) }.to(throwError { error in
            assertExpectedError(expectedError, error)
        })

        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            expect {
                _ = try HwpFile(fromData: Data(contentsOf: url))
            }.to(throwError { error in
                assertExpectedError(expectedError, error)
            })

            expect {
                _ = try HwpFile(fromWrapper: FileWrapper(url: url, options: []))
            }.to(throwError { error in
                assertExpectedError(expectedError, error)
            })
        #endif
    }

    private static func assertExpectedError(
        _ expectedError: FixtureExpectedError,
        _ error: Error
    ) {
        switch (expectedError.code, error) {
        case (
            "unsupportedFeature.encryptedDocument",
            HwpError.unsupportedFeature(.encryptedDocument)
        ),
        (
            "unsupportedFeature.deploymentDocument",
            HwpError.unsupportedFeature(.deploymentDocument)
        ),
        ("unsupportedFeature.drmDocument", HwpError.unsupportedFeature(.drmDocument)):
            guard let description = expectedError.description else {
                return fail("Expected \(expectedError.code) description to be declared")
            }
            expect(error.localizedDescription) == description
            expect(String(describing: error)) == description
        default:
            fail("Expected \(expectedError.code), got \(error)")
        }
    }

    static func assertUnsupportedDocInfoRawRecords(
        _ expectations: FixtureExpectations,
        _ url: URL,
        _ fileHeader: HwpFileHeader
    ) throws {
        guard expectations.docInfoRawRecordCount != nil || expectations.docInfoRawRecords != nil
        else {
            return
        }

        let docInfo = try unsupportedDocInfo(from: url, fileHeader)
        if let expectedCount = expectations.docInfoRawRecordCount {
            expect(rawDocInfoRecordCount(docInfo)) == expectedCount
        }
        assertDocInfoRawRecords(expectations, docInfo)
    }
}

private func unsupportedDocInfo(from url: URL, _ fileHeader: HwpFileHeader) throws -> HwpDocInfo {
    let ole: OLEFile
    do {
        ole = try OLEFile(url.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
    let streams = try StreamReader.rootStreams(from: ole.root.children)
    let reader = StreamReader(ole, streams)
    let data = try reader.getDataFromStream(.docInfo, fileHeader.fileProperty.isCompressed)
    return try HwpDocInfo.load(data, fileHeader.version)
}
