@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SummaryStreamPresenceStabilityTests: XCTestCase {
    func testSummaryDirectoryEntryMustBeStreamWhenPresent() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: HwpStreamName.summary.rawValue,
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("HwpSummaryInformation"))
            expect(reason).to(contain("expected stream"))
        })

        let data = try Data(contentsOf: url)
        expect {
            _ = try HwpFile(fromData: data)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("HwpSummaryInformation"))
            expect(reason).to(contain("expected stream"))
        })
    }

    func testMissingOptionalSummaryStreamUsesEmptySummary() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: HwpStreamName.summary.rawValue,
            to: "\u{5}XwpSummaryInformation",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.summary.rawPayload).to(beEmpty())
        expect(hwp.previewText.text).to(contain("Hello CoreHwp plain text fixture."))
        expect(hwp.previewImage.format) == HwpPreviewImageFormat.png

        let dataHwp = try HwpFile(fromData: Data(contentsOf: url))

        expect(dataHwp.summary.rawPayload).to(beEmpty())
        expect(dataHwp.previewText.text).to(contain("Hello CoreHwp plain text fixture."))
        expect(dataHwp.previewImage.format) == HwpPreviewImageFormat.png
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testFileWrapperEntrypointValidatesSummaryDirectoryEntryType() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: HwpStreamName.summary.rawValue,
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])

            expect {
                _ = try HwpFile(fromWrapper: wrapper)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("HwpSummaryInformation"))
                expect(reason).to(contain("expected stream"))
            })
        }

        func testMissingOptionalSummaryStreamFromFileWrapperUsesEmptySummary() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: HwpStreamName.summary.rawValue,
                to: "\u{5}XwpSummaryInformation",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])
            let hwp = try HwpFile(fromWrapper: wrapper)

            expect(hwp.summary.rawPayload).to(beEmpty())
            expect(hwp.previewText.text).to(contain("Hello CoreHwp plain text fixture."))
            expect(hwp.previewImage.format) == HwpPreviewImageFormat.png
        }
    #endif
}
