@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileAssemblyTruncationTests: XCTestCase {
    func testRepresentativeAssemblyTruncationFixturesCoverCurrentStreamClasses() {
        for fixtureId in [
            "plain-text-hancom-mac2026",
            "multi-section",
            "BinData",
            "chart",
            "header-footer",
            "text-box",
            "track-changes",
        ] {
            expect(representativeAssemblyFixtureIds).to(contain(fixtureId))
        }
    }

    func testRepresentativeFixtureAssemblyRejectsTruncatedInjectedDocInfoRecord() throws {
        for fixtureId in representativeAssemblyFixtureIds {
            let streams = try representativeAssemblyStreams(fromFixture: fixtureId)
            let docInfoData = concatenatedData(
                streams.docInfoData,
                representativeTruncatedExtendedRecordData(
                    tagId: HwpDocInfoTag.distributeDocData.rawValue,
                    declaredPayloadSize: 7,
                    actualPayload: Data([0xA1, 0xB2, 0xC3])
                )
            )

            expect {
                _ = try HwpFile(
                    fileHeader: streams.fileHeader,
                    docInfoData: docInfoData,
                    sectionDataArray: streams.sectionDataArray
                )
            }.to(throwError { error in
                assertRepresentativeTruncatedDataError(error, expected: 7, actual: 3)
            })
        }
    }

    func testRepresentativeFixtureAssemblyRejectsTruncatedInjectedSectionRecord() throws {
        for fixtureId in representativeAssemblyFixtureIds {
            let streams = try representativeAssemblyStreams(fromFixture: fixtureId)
            for sectionIndex in streams.sectionDataArray.indices {
                var sectionDataArray = streams.sectionDataArray
                sectionDataArray[sectionIndex].append(representativeTruncatedExtendedRecordData(
                    tagId: 0x2FE,
                    declaredPayloadSize: 8,
                    actualPayload: Data([0xD4, 0xE5])
                ))

                expect {
                    _ = try HwpFile(
                        fileHeader: streams.fileHeader,
                        docInfoData: streams.docInfoData,
                        sectionDataArray: sectionDataArray
                    )
                }.to(throwError { error in
                    assertRepresentativeTruncatedDataError(error, expected: 8, actual: 2)
                })
            }
        }
    }
}

private let representativeAssemblyFixtureIds = [
    "plain-text-hancom-mac2026",
    "multi-section",
    "BinData",
    "chart",
    "header-footer",
    "text-box",
    "track-changes",
]

private struct RepresentativeAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private func representativeAssemblyStreams(
    fromFixture id: String
) throws -> RepresentativeAssemblyStreams {
    let fixture = try FixtureLoader.load(id: id)
    let ole: OLEFile
    do {
        ole = try OLEFile(fixture.documentURL.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    let streams = try StreamReader.rootStreams(from: ole.root.children)
    let reader = StreamReader(ole, streams)
    let fileHeader = try HwpFileHeader.load(reader.getDataFromStream(.fileHeader, false))
    let docInfoData = try reader.getDataFromStream(
        .docInfo,
        fileHeader.fileProperty.isCompressed
    )
    let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)
    let sectionDataArray = try reader.getDataFromStorage(
        .bodyText,
        fileHeader.fileProperty.isCompressed,
        expectedCount: Int(docInfo.documentProperties.sectionSize)
    )

    return RepresentativeAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func representativeTruncatedExtendedRecordData(
    tagId: UInt32,
    declaredPayloadSize: UInt32,
    actualPayload: Data
) -> Data {
    var data = representativeLittleEndianData(tagId | (0xFFF << 20))
    data.append(representativeLittleEndianData(declaredPayloadSize))
    data.append(actualPayload)
    return data
}

private func assertRepresentativeTruncatedDataError(
    _ error: Error,
    expected: Int,
    actual: Int
) {
    guard case let HwpError.truncatedData(actualExpected, actualBytes) = error else {
        return fail("Expected truncatedData, got \(error)")
    }
    expect(actualExpected) == expected
    expect(actualBytes) == actual
}

private func representativeLittleEndianData(_ value: UInt32) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
