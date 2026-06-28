@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixtureHeaderEntrypointTests: XCTestCase {
    func testFixtureHeadersLoadThroughPathEntrypoint() throws {
        let fixtures = try FixtureLoader.loadAll()

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let header = try HwpFileHeader.load(fromPath: fixture.documentURL.path)

            try assertHeader(header, matches: fixture)
            if fixture.manifest.expectedError == nil {
                let hwp = try HwpFile(fromPath: fixture.documentURL.path)
                expect(header) == hwp.fileHeader
                assertHeaderRawPayload(header, hwp.fileHeader)
            }
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testFixtureHeadersLoadThroughFileWrapperEntrypoint() throws {
            let fixtures = try FixtureLoader.loadAll()

            expect(fixtures).notTo(beEmpty())
            for fixture in fixtures {
                let wrapper = try FileWrapper(url: fixture.documentURL, options: [])
                let header = try HwpFileHeader.load(fromWrapper: wrapper)
                let pathHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)

                expect(header) == pathHeader
                assertHeaderRawPayload(header, pathHeader)
                try assertHeader(header, matches: fixture)
            }
        }

        func testFixtureHeadersLoadThroughDataEntrypoint() throws {
            let fixtures = try FixtureLoader.loadAll()

            expect(fixtures).notTo(beEmpty())
            for fixture in fixtures {
                let data = try Data(contentsOf: fixture.documentURL)
                let header = try HwpFileHeader.load(fromData: data)
                let pathHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)

                expect(header) == pathHeader
                assertHeaderRawPayload(header, pathHeader)
                try assertHeader(header, matches: fixture)
            }
        }

        func testInvalidOLEFileHeaderDataThrowsTypedError() {
            let data = Data("not an OLE file".utf8)

            expect {
                _ = try HwpFileHeader.load(fromData: data)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).notTo(beEmpty())
            })
        }
    #endif
}

private func assertHeader(_ header: HwpFileHeader, matches fixture: LoadedFixture) throws {
    let expectedVersion = try FixtureVersionParser.parse(fixture.manifest.hwpVersion)

    expect(header.version) == expectedVersion
    expect(header.rawPayload.count) == 256
    expect(header.reserved.count) == 207
    if let expectedError = fixture.manifest.expectedError {
        FixtureAssertions.assertUnsupportedFeatureBit(expectedError, header.fileProperty)
    } else {
        expect(header.fileProperty.unsupportedFeature).to(beNil())
    }
}

private func assertHeaderRawPayload(_ header: HwpFileHeader, _ other: HwpFileHeader) {
    expect(header.rawPayload) == other.rawPayload
    expect(header.reserved) == other.reserved
}
