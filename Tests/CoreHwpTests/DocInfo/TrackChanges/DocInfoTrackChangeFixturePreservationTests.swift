@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TrackChangeFixturePreservationTests: XCTestCase {
    func testTrackChangesFixtureDocInfoAndInlineControlsSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "track-changes")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        FixtureAssertions.assertDocInfoRawRecords(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertParaTextPayloads(fixture.manifest.expectations, decoded)
        assertTrackChangeRawRecordPayloadsPreserved(decoded.docInfo, hwp.docInfo)
        assertTrackChangeInlineControlsPreserved(decoded, hwp)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func assertTrackChangeRawRecordPayloadsPreserved(
    _ decoded: HwpDocInfo,
    _ original: HwpDocInfo
) {
    expect(decoded.trackChangeArray.map(\.rawPayload)) ==
        original.trackChangeArray.map(\.rawPayload)
    expect(decoded.trackChangeArray.map(\.unknownChildren)) ==
        original.trackChangeArray.map(\.unknownChildren)
    expect(decoded.trackChangeContentArray.map(\.rawPayload)) ==
        original.trackChangeContentArray.map(\.rawPayload)
    expect(decoded.trackChangeContentArray.map(\.contentInfo?.kind)) ==
        original.trackChangeContentArray.map(\.contentInfo?.kind)
    expect(decoded.trackChangeContentArray.map(\.contentInfo?.timestamp)) ==
        original.trackChangeContentArray.map(\.contentInfo?.timestamp)
    expect(decoded.trackChangeContentArray.map(\.contentInfo?.rawTrailing)) ==
        original.trackChangeContentArray.map(\.contentInfo?.rawTrailing)
    expect(decoded.trackChangeContentArray.map(\.unknownChildren)) ==
        original.trackChangeContentArray.map(\.unknownChildren)
    expect(decoded.trackChangeAuthorArray.map(\.rawPayload)) ==
        original.trackChangeAuthorArray.map(\.rawPayload)
    expect(decoded.trackChangeAuthorArray.map(\.authorInfo?.name)) ==
        original.trackChangeAuthorArray.map(\.authorInfo?.name)
    expect(decoded.trackChangeAuthorArray.map(\.authorInfo?.nameRawPayload)) ==
        original.trackChangeAuthorArray.map(\.authorInfo?.nameRawPayload)
    expect(decoded.trackChangeAuthorArray.map(\.authorInfo?.rawTrailing)) ==
        original.trackChangeAuthorArray.map(\.authorInfo?.rawTrailing)
    expect(decoded.trackChangeAuthorArray.map(\.unknownChildren)) ==
        original.trackChangeAuthorArray.map(\.unknownChildren)
}

private func assertTrackChangeInlineControlsPreserved(_ decoded: HwpFile, _ original: HwpFile) {
    let decodedControls = FixtureDerivedValues.paraTextInlineControls(from: decoded)
    let originalControls = FixtureDerivedValues.paraTextInlineControls(from: original)

    expect(decodedControls.map(\.rawControlId)) == originalControls.map(\.rawControlId)
    expect(decodedControls.map(\.ctrlIdName)) == originalControls.map(\.ctrlIdName)
    expect(decodedControls.map(\.rawPayload)) == originalControls.map(\.rawPayload)
    expect(decodedControls.map(\.rawTrailing)) == originalControls.map(\.rawTrailing)
}
