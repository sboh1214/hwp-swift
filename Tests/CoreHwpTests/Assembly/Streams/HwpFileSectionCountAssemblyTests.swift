@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileSectionCountAssemblyTests: XCTestCase {
    func testActualMultiSectionAssemblyRejectsMissingSectionPayload() throws {
        let base = try openHwp(#file, "multi-section")
        let sectionPayloads = base.sectionArray.map(\.rawPayload)
        expect(sectionPayloads.count) == 2
        expect(base.docInfo.documentProperties.sectionSize) == 2

        expect {
            _ = try HwpFile(
                fileHeader: base.fileHeader,
                docInfo: base.docInfo,
                sectionDataArray: Array(sectionPayloads.dropLast())
            )
        }.to(throwError { error in
            assertActualSectionCountMismatch(error, actualCount: 1, expectedCount: 2)
        })
    }

    func testActualMultiSectionAssemblyRejectsExtraSectionPayloadThroughDocInfoData() throws {
        let base = try openHwp(#file, "multi-section")
        let sectionPayloads = base.sectionArray.map(\.rawPayload)
        expect(sectionPayloads.count) == 2
        expect(base.docInfo.documentProperties.sectionSize) == 2

        expect {
            _ = try HwpFile(
                fileHeader: base.fileHeader,
                docInfoData: base.docInfo.rawPayload,
                sectionDataArray: sectionPayloads + [sectionPayloads[0]]
            )
        }.to(throwError { error in
            assertActualSectionCountMismatch(error, actualCount: 3, expectedCount: 2)
        })
    }
}

private func assertActualSectionCountMismatch(
    _ error: Error,
    actualCount: Int,
    expectedCount: Int
) {
    guard case let HwpError.invalidRecordTree(reason) = error else {
        return fail("Expected invalidRecordTree, got \(error)")
    }
    expect(reason).to(contain(
        "BodyText section count \(actualCount) != sectionSize \(expectedCount)"
    ))
}
