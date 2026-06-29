@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixtureCorruptionStabilityTests: XCTestCase {
    func testNonOLEInputThrowsInvalidOLEFileFromPathEntrypoints() throws {
        let url = try writeCorruptFixture(Data("not an OLE HWP".utf8), suffix: "non-ole")
        defer { removeCorruptFixture(url) }

        expectInvalidOLEFile("HwpFile non-OLE path") {
            _ = try HwpFile(fromPath: url.path)
        }
        expectInvalidOLEFile("HwpFileHeader non-OLE path") {
            _ = try HwpFileHeader.load(fromPath: url.path)
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testNonOLEInputThrowsInvalidOLEFileFromFileWrapperEntrypoints() {
            let wrapper = FileWrapper(regularFileWithContents: Data("not an OLE HWP".utf8))

            expectInvalidOLEFile("HwpFile non-OLE wrapper") {
                _ = try HwpFile(fromWrapper: wrapper)
            }
            expectInvalidOLEFile("HwpFileHeader non-OLE wrapper") {
                _ = try HwpFileHeader.load(fromWrapper: wrapper)
            }
        }
    #endif

    func testTruncatedRepresentativeFixturesThrowTypedErrorsFromPathEntrypoints() throws {
        for fixture in try representativeFixtures() {
            let data = try Data(contentsOf: fixture.documentURL)
            for length in truncationLengths(for: data) {
                let url = try writeCorruptFixture(
                    data.prefix(length),
                    suffix: "truncated-\(length)"
                )
                defer { removeCorruptFixture(url) }

                expectTypedHwpError("\(fixture.manifest.id) HwpFile prefix \(length)") {
                    _ = try HwpFile(fromPath: url.path)
                }
            }
            for length in headerTruncationLengths(for: data) {
                let url = try writeCorruptFixture(
                    data.prefix(length),
                    suffix: "truncated-\(length)"
                )
                defer { removeCorruptFixture(url) }

                expectTypedHwpError("\(fixture.manifest.id) HwpFileHeader prefix \(length)") {
                    _ = try HwpFileHeader.load(fromPath: url.path)
                }
            }
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testTruncatedRepresentativeFixturesThrowTypedErrorsFromDataEntrypoints() throws {
            for fixture in try representativeFixtures() {
                let data = try Data(contentsOf: fixture.documentURL)
                for length in truncationLengths(for: data) {
                    let truncatedData = Data(data.prefix(length))

                    expectTypedHwpError("\(fixture.manifest.id) data HwpFile prefix \(length)") {
                        _ = try HwpFile(fromData: truncatedData)
                    }
                }
                for length in headerTruncationLengths(for: data) {
                    let truncatedData = Data(data.prefix(length))

                    expectTypedHwpError(
                        "\(fixture.manifest.id) data HwpFileHeader prefix \(length)"
                    ) {
                        _ = try HwpFileHeader.load(fromData: truncatedData)
                    }
                }
            }
        }

        func testTruncatedRepresentativeFixturesThrowTypedErrorsFromFileWrapper() throws {
            for fixture in try representativeFixtures() {
                let data = try Data(contentsOf: fixture.documentURL)
                for length in truncationLengths(for: data) {
                    let wrapper = FileWrapper(
                        regularFileWithContents: Data(data.prefix(length))
                    )

                    expectTypedHwpError("\(fixture.manifest.id) wrapper HwpFile prefix \(length)") {
                        _ = try HwpFile(fromWrapper: wrapper)
                    }
                }
                for length in headerTruncationLengths(for: data) {
                    let wrapper = FileWrapper(
                        regularFileWithContents: Data(data.prefix(length))
                    )

                    expectTypedHwpError(
                        "\(fixture.manifest.id) wrapper HwpFileHeader prefix \(length)"
                    ) {
                        _ = try HwpFileHeader.load(fromWrapper: wrapper)
                    }
                }
            }
        }
    #endif

    func testRepresentativeCorruptionFixturesCoverCurrentFixtureClasses() throws {
        let fixtures = try representativeFixtures()
        let fixtureIds = Set(fixtures.map(\.manifest.id))
        let features = fixtures.reduce(into: Set<String>()) { result, fixture in
            result.formUnion(fixture.manifest.features)
        }

        expect(fixtureIds).to(contain("plain-text-hancom-mac2026"))
        expect(features).to(contain("encrypted"))
        expect(features).to(contain("deployment-document"))
        expect(features).to(contain("derived-drm"))
        expect(features).to(contain("multi-section"))
        expect(features).to(contain("large-document"))
        expect(features).to(contain("other-controls"))
        expect(features).to(contain("bin-data"))
        expect(features).to(contain("chart"))
        expect(features).to(contain("track-changes"))
    }
}

private func representativeFixtures() throws -> [LoadedFixture] {
    let fixtureIds = [
        "plain-text-minimal",
        "plain-text-hancom-mac2026",
        "multi-section",
        "legacy-common-control-property",
        "BinData",
        "chart",
        "track-changes",
        "문서암호설정-보안수준높음",
        "배포용문서",
        "drm-unsupported-derived",
    ]
    return try fixtureIds.map(FixtureLoader.load(id:))
}

private func truncationLengths(for data: Data) -> [Int] {
    Set([
        0,
        1,
        min(512, data.count - 1),
        data.count / 2,
    ])
    .filter { $0 >= 0 && $0 < data.count }
    .sorted()
}

private func headerTruncationLengths(for data: Data) -> [Int] {
    Set([
        0,
        1,
        min(512, data.count - 1),
    ])
    .filter { $0 >= 0 && $0 < data.count }
    .sorted()
}

private func writeCorruptFixture(_ data: some DataProtocol, suffix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreHwp-\(suffix)-\(UUID().uuidString).hwp")
    try Data(data).write(to: url, options: .atomic)
    return url
}

private func removeCorruptFixture(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("Failed to remove corrupt fixture: \(error)")
    }
}

private func expectInvalidOLEFile(
    _ context: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile for \(context), got \(error)")
        }
        expect(reason).notTo(beEmpty())
    })
}

private func expectTypedHwpError(
    _ context: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard error is HwpError else {
            return fail("Expected typed HwpError for \(context), got \(error)")
        }
    })
}
