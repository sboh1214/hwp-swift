@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileDataEntrypointTests: XCTestCase {
    func testReadableFixtureLoadsFromDataLikePathEntrypoint() throws {
        let url = hwpURL(#file, "plain-text-minimal")
        let data = try Data(contentsOf: url)

        let pathHwp = try HwpFile(fromPath: url.path)
        let dataHwp = try HwpFile(fromData: data)

        assertDataEntrypointRawPayloads(dataHwp, pathHwp)
    }

    func testReadableFixturesLoadFromDataLikePathEntrypoint() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let dataHwp = try HwpFile(fromData: Data(contentsOf: fixture.documentURL))
            let pathHwp = try HwpFile(fromPath: fixture.documentURL.path)

            expect(dataHwp) == pathHwp
            assertDataEntrypointRawPayloads(dataHwp, pathHwp)
            try FixtureAssertions.assertReadableFixture(fixture, dataHwp)
        }
    }

    func testUnsupportedFixtureFromDataReturnsTypedUnsupportedFeature() throws {
        let url = hwpURL(#file, "drm-unsupported-derived")
        let data = try Data(contentsOf: url)

        expect {
            _ = try HwpFile(fromData: data)
        }.to(throwError { error in
            guard case let HwpError.unsupportedFeature(feature) = error else {
                return fail("Expected unsupportedFeature, got \(error)")
            }
            expect(feature) == .drmDocument
        })
    }

    func testNonOLEDataFromDataThrowsTypedInvalidOLEFile() {
        expect {
            _ = try HwpFile(fromData: Data([0x00, 0x01, 0x02]))
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).toNot(beEmpty())
        })
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testDarwinFromDataUsesInMemoryOLEPathWithoutTemporaryFile() throws {
            let data = try Data(contentsOf: hwpURL(#file, "plain-text-minimal"))
            let before = try coreHwpTemporaryFileNames()

            _ = try coreHwpOLEFile(fromData: data)

            expect(try coreHwpTemporaryFileNames()) == before
        }

        func testDarwinFromWrapperUsesInMemoryOLEPathWithoutTemporaryFile() throws {
            let data = try Data(contentsOf: hwpURL(#file, "plain-text-minimal"))
            let wrapper = dataEntrypointFileWrapper(
                contents: data,
                preferredFilename: "plain-text-minimal.hwp"
            )
            let before = try coreHwpTemporaryFileNames()

            _ = try coreHwpOLEFile(fromWrapper: wrapper)

            expect(try coreHwpTemporaryFileNames()) == before
        }
    #endif

    #if os(Linux)
        func testLinuxTemporaryFileUsesPrivatePermissionsAndCleansUpOnSuccess() throws {
            var createdURLs = [URL]()
            var permissions = [Int]()
            coreHwpTemporaryFileDidCreate = { url in
                createdURLs.append(url)
                if let attributes = try? FileManager.default.attributesOfItem(
                    atPath: url.path
                ),
                    let value = attributes[.posixPermissions] as? NSNumber
                {
                    permissions.append(value.intValue & 0o777)
                }
            }
            defer {
                coreHwpTemporaryFileDidCreate = nil
            }
            let data = try Data(contentsOf: hwpURL(#file, "plain-text-minimal"))
            let before = try coreHwpTemporaryFileNames()

            _ = try coreHwpOLEFile(fromData: data)

            expect(try coreHwpTemporaryFileNames()) == before
            expect(createdURLs.count) == 1
            expect(permissions) == [0o600]
            expect(createdURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
                .to(beEmpty())
        }

        func testLinuxTemporaryFileCleansUpWhenOLEParsingFails() throws {
            var createdURLs = [URL]()
            var permissions = [Int]()
            coreHwpTemporaryFileDidCreate = { url in
                createdURLs.append(url)
                if let attributes = try? FileManager.default.attributesOfItem(
                    atPath: url.path
                ),
                    let value = attributes[.posixPermissions] as? NSNumber
                {
                    permissions.append(value.intValue & 0o777)
                }
            }
            defer {
                coreHwpTemporaryFileDidCreate = nil
            }
            let before = try coreHwpTemporaryFileNames()

            expect {
                _ = try coreHwpOLEFile(fromData: Data("not an OLE file".utf8))
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).notTo(beEmpty())
            })

            expect(try coreHwpTemporaryFileNames()) == before
            expect(createdURLs.count) == 1
            expect(permissions) == [0o600]
            expect(createdURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
                .to(beEmpty())
        }

        func testLinuxTemporaryFileWriteFailureThrowsTypedError() throws {
            let blockerURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CoreHwpBlocker-\(UUID().uuidString)")
            try Data([0x00]).write(to: blockerURL)
            defer {
                try? FileManager.default.removeItem(at: blockerURL)
            }

            coreHwpTemporaryDirectoryOverride = blockerURL
            defer {
                coreHwpTemporaryDirectoryOverride = nil
            }

            expect {
                _ = try coreHwpOLEFile(fromData: Data([0x00]))
            }.to(throwError { error in
                guard case let HwpError.temporaryFileWriteFailed(reason) = error else {
                    return fail("Expected temporaryFileWriteFailed, got \(error)")
                }
                expect(reason).notTo(beEmpty())
            })
        }
    #endif

    func testTruncatedRealFixturePrefixesFromInMemoryEntrypointsThrowTypedErrors() throws {
        let fixtureData = try Data(contentsOf: hwpURL(#file, "plain-text-minimal"))
        let prefixLengths = Set([
            0,
            1,
            min(512, fixtureData.count - 1),
            fixtureData.count / 4,
            fixtureData.count / 2,
        ])
        .filter { $0 >= 0 && $0 < fixtureData.count }
        .sorted()

        for length in prefixLengths {
            let truncatedData = Data(fixtureData.prefix(length))

            expect {
                _ = try HwpFile(fromData: truncatedData)
            }.to(throwError { error in
                assertDataEntrypointTypedHwpError(error)
            })
            expect {
                _ = try HwpFileHeader.load(fromData: truncatedData)
            }.to(throwError { error in
                assertDataEntrypointTypedHwpError(error)
            })

            let wrapper = dataEntrypointFileWrapper(
                contents: truncatedData,
                preferredFilename: "truncated-\(length).hwp"
            )
            expect {
                _ = try HwpFile(fromWrapper: wrapper)
            }.to(throwError { error in
                assertDataEntrypointTypedHwpError(error)
            })
            expect {
                _ = try HwpFileHeader.load(fromWrapper: wrapper)
            }.to(throwError { error in
                assertDataEntrypointTypedHwpError(error)
            })
        }
    }
}

private func assertDataEntrypointRawPayloads(_ hwp: HwpFile, _ pathHwp: HwpFile) {
    expect(hwp.fileHeader.rawPayload) == pathHwp.fileHeader.rawPayload
    expect(hwp.fileHeader.reserved) == pathHwp.fileHeader.reserved
    expect(hwp.docInfo.rawPayload) == pathHwp.docInfo.rawPayload
    expect(hwp.sectionArray.map(\.rawPayload)) == pathHwp.sectionArray.map(\.rawPayload)
    expect(hwp.summary.rawPayload) == pathHwp.summary.rawPayload
    expect(hwp.previewText.rawPayload) == pathHwp.previewText.rawPayload
    expect(hwp.previewImage.rawPayload) == pathHwp.previewImage.rawPayload
    expect(hwp.binaryDataArray.map(\.name)) == pathHwp.binaryDataArray.map(\.name)
    expect(hwp.binaryDataArray.map(\.streamId)) == pathHwp.binaryDataArray.map(\.streamId)
    expect(hwp.binaryDataArray.map(\.extensionName)) ==
        pathHwp.binaryDataArray.map(\.extensionName)
    expect(hwp.binaryDataArray.map(\.data)) == pathHwp.binaryDataArray.map(\.data)
}

private func assertDataEntrypointTypedHwpError(_ error: Error) {
    guard error is HwpError else {
        return fail("Expected HwpError, got \(error)")
    }
}

private func dataEntrypointFileWrapper(contents: Data, preferredFilename: String) -> FileWrapper {
    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        let wrapper = FileWrapper(regularFileWithContents: contents)
        wrapper.preferredFilename = preferredFilename
        return wrapper
    #else
        var wrapper = FileWrapper(regularFileWithContents: contents)
        wrapper.preferredFilename = preferredFilename
        return wrapper
    #endif
}

private func coreHwpTemporaryFileNames() throws -> Set<String> {
    let urls = try FileManager.default.contentsOfDirectory(
        at: FileManager.default.temporaryDirectory,
        includingPropertiesForKeys: nil
    )
    return Set(urls.map(\.lastPathComponent).filter { $0.hasPrefix("CoreHwp-") })
}
