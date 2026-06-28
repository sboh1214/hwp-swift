import CoreHwp
import Foundation
import Nimble
import XCTest

class HwpErrorTests: XCTestCase {
    func test() {
        expect { try openHwp(#file, "") }.to(throwError())
    }

    func testInvalidOleFileThrowsTypedError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-\(UUID().uuidString).hwp")
        try Data("not an OLE file".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).notTo(beEmpty())
        })
    }

    func testMissingFileThrowsTypedError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).hwp")

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).notTo(beEmpty())
        })
    }

    func testTruncatedRealFixturePrefixesThrowTypedError() throws {
        let fixtureURL = hwpURL(#file, "plain-text-minimal")
        let fixtureData = try Data(contentsOf: fixtureURL)
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
            let truncatedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("truncated-\(length)-\(UUID().uuidString).hwp")
            try fixtureData.prefix(length).write(to: truncatedURL)
            defer {
                try? FileManager.default.removeItem(at: truncatedURL)
            }

            expect {
                _ = try HwpFile(fromPath: truncatedURL.path)
            }.to(throwError { error in
                assertHwpError(error)
            })
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testRealFixtureFileWrapperLoadsPublicEntrypoint() throws {
            let wrapper = try FileWrapper(
                url: hwpURL(#file, "plain-text-minimal"),
                options: []
            )

            let hwp = try HwpFile(fromWrapper: wrapper)

            expect(hwp.fileHeader.version) == HwpVersion(5, 1, 1, 0)
            expect(hwp.sectionArray.count) == 1
            expect(hwp.previewText.rawPayload).notTo(beEmpty())
            expect(hwp.previewImage.image).notTo(beEmpty())
        }

        func testInvalidFileWrapperThrowsTypedError() {
            let wrapper = FileWrapper(regularFileWithContents: Data("not an OLE file".utf8))

            expect {
                _ = try HwpFile(fromWrapper: wrapper)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).notTo(beEmpty())
            })
        }

        func testTruncatedRealFixtureFileWrapperThrowsTypedError() throws {
            let fixtureURL = hwpURL(#file, "plain-text-minimal")
            let fixtureData = try Data(contentsOf: fixtureURL)
            let wrapper = FileWrapper(
                regularFileWithContents: Data(fixtureData.prefix(fixtureData.count / 2))
            )

            expect {
                _ = try HwpFile(fromWrapper: wrapper)
            }.to(throwError { error in
                assertHwpError(error)
            })
        }
    #endif

    func testDescriptions() {
        let descriptions = [
            HwpError.streamDoesNotExist(name: .fileHeader).description,
            HwpError.streamDecompressFailed(name: .docInfo).description,
            HwpError.streamSizeLimitExceeded(name: .docInfo, limit: 1, actual: 2)
                .description,
            HwpError.invalidOLEFile(reason: "bad").description,
            HwpError.invalidDataForString(data: Data([0x00]), name: "test").description,
            HwpError.recordDoesNotExist(tag: 16).description,
            HwpError.invalidRecordTree(reason: "bad level").description,
            HwpError.invalidFileHeaderSignature(signature: "bad").description,
            HwpError.invalidUnicodeScalar(value: 0xD800).description,
            HwpError.unidentifiedTag(tagId: 999).description,
            HwpError.invalidCtrlId(ctrlId: 0).description,
            HwpError.truncatedData(expected: 4, actual: 1).description,
            HwpError.truncatedBits(expected: 4, actual: 1).description,
            HwpError.invalidDataLength(length: "-1").description,
            HwpError.unsupportedDataReadType(type: "UInt64").description,
            HwpError.unsupportedFeature(.encryptedDocument).description,
        ]

        for description in descriptions {
            expect(description).notTo(beEmpty())
        }
    }

    func testEOFDescriptionsUseModelTypeNames() {
        expect(HwpError.bytesAreNotEOF(modelName: "HwpFile", remain: 1).description) ==
            "Bytes are not EOF : 1 bytes remain in HwpFile"
        expect(HwpError.bitsAreNotEOF(modelName: "HwpFile", remain: 2).description) ==
            "Bits are not EOF : 2 bits remain in HwpFile"
        expect(HwpError.invalidRawValueForEnum(
            modelName: "HwpBinDataType",
            rawValue: 9
        ).description) ==
            "Invalid rawValue : 9 for initiating enum : HwpBinDataType"
    }

    func testEOFDescriptionsUseInstanceTypeNames() {
        expect(HwpError.bytesAreNotEOF(modelName: "HwpFile", remain: 1).description) ==
            "Bytes are not EOF : 1 bytes remain in HwpFile"
        expect(HwpError.bitsAreNotEOF(modelName: "HwpFile", remain: 2).description) ==
            "Bits are not EOF : 2 bits remain in HwpFile"
    }

    func testInvalidDataForStringDescriptionIsReadable() {
        let description = HwpError.invalidDataForString(
            data: Data([0x00]),
            name: "PreviewText"
        ).description

        expect(description).to(contain("Cannot convert data to utf16le string"))
        expect(description).to(contain("PreviewText"))
    }

    func testLocalizedDescriptionUsesTypedDescription() {
        let error = HwpError.unsupportedFeature(.encryptedDocument)

        expect(error.localizedDescription) == error.description
    }
}

private func assertHwpError(_ error: Error) {
    guard error is HwpError else {
        return fail("Expected HwpError, got \(error)")
    }
}
