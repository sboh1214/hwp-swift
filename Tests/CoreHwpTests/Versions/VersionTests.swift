@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class VersionTests: XCTestCase {
    func test2007() throws {
        let hwp = try openHwp(#file, "2007")
        expect(hwp.fileHeader.version) == HwpVersion(5, 0, 2, 2)
    }

    func test2014VP() throws {
        let hwp = try openHwp(#file, "2014VP")
        expect(hwp.fileHeader.version) == HwpVersion(5, 0, 5, 0)
    }

    func testManualVersionInitializerDoesNotTrapForOutOfRangeInts() {
        let version = HwpVersion(-1, 256, 300, Int.max)

        expect(version.major) == 0
        expect(version.minor) == 255
        expect(version.build) == 255
        expect(version.revision) == 255
        expect(version.rawPayload) == Data([255, 255, 255, 0])
        expect(version.rawValue) == 0x00FF_FFFF
    }

    func testVersionPreservesRawPayloadAndRawValue() throws {
        let payload = Data([0x02, 0x03, 0x04, 0x05])
        let version = try HwpVersion.load(payload)

        expect(version.revision) == 2
        expect(version.build) == 3
        expect(version.minor) == 4
        expect(version.major) == 5
        expect(version.rawPayload) == payload
        expect(version.rawValue) == 0x0504_0302
    }

    func testVersionRawPayloadSurvivesCodableRoundTrip() throws {
        let version = try HwpVersion.load(Data([0x01, 0x02, 0x03, 0x04]))

        let decoded = try JSONDecoder().decode(
            HwpVersion.self,
            from: JSONEncoder().encode(version)
        )

        expect(decoded) == version
        expect(decoded.rawPayload) == version.rawPayload
        expect(decoded.rawValue) == version.rawValue
    }

    func testVersionComparisonOrdersEveryComponent() {
        let orderedVersions = [
            HwpVersion(4, 255, 255, 255),
            HwpVersion(5, 0, 1, 0),
            HwpVersion(5, 0, 2, 0),
            HwpVersion(5, 0, 2, 1),
            HwpVersion(5, 1, 0, 0),
        ]

        expect(orderedVersions.sorted()) == orderedVersions
        expect(HwpVersion(5, 0, 2, 1)) > HwpVersion(5, 0, 2, 0)
        expect(HwpVersion(5, 0, 2, 1)) >= HwpVersion(5, 0, 2, 1)
        expect(HwpVersion(5, 0, 2, 1) < HwpVersion(5, 0, 2, 1)) == false
    }

    func testVersionComparisonHandlesMajorDifferencesDirectly() {
        expect(HwpVersion(4, 255, 255, 255) < HwpVersion(5, 0, 0, 0)) == true
        expect(HwpVersion(6, 0, 0, 0) < HwpVersion(5, 255, 255, 255)) == false
    }

    func testVersionLoadRejectsTruncatedPayloadWithTypedError() {
        expect {
            _ = try HwpVersion.load(Data([0x01, 0x00, 0x05]))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 1
            expect(actual) == 0
        })
    }
}
