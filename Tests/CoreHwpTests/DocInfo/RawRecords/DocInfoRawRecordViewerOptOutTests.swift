@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoRawRecordViewerOptOutTests: XCTestCase {
    func testViewerModeEmptiesDocDataNestedRawSlices() throws {
        let payload = Data([0x04, 0x03, 0x02, 0x01, 0xDD, 0xCC, 0xBB, 0xAA, 0xEE, 0xFF])
        let preserved = try HwpDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.docData.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.docData.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.docDataInfo?.values) == preserved.docDataInfo?.values
        expect(viewer.docDataInfo?.values).notTo(beNil())
        expectRawSliceEmptiedByViewer(
            preserved: preserved.docDataInfo?.valuesRawPayload,
            viewer: viewer.docDataInfo?.valuesRawPayload,
            "docData valuesRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.docDataInfo?.rawTrailing,
            viewer: viewer.docDataInfo?.rawTrailing,
            "docData rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }

    func testViewerModeEmptiesDistributeDocDataNestedRawSlices() throws {
        let payload = Data([0xD1, 0x57, 0x00, 0x01, 0xEE])
        let preserved = try HwpDistributeDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpDistributeDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.distributeDocDataInfo?.values) == preserved.distributeDocDataInfo?.values
        expect(viewer.distributeDocDataInfo?.values).notTo(beNil())
        expectRawSliceEmptiedByViewer(
            preserved: preserved.distributeDocDataInfo?.valuesRawPayload,
            viewer: viewer.distributeDocDataInfo?.valuesRawPayload,
            "distributeDocData valuesRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.distributeDocDataInfo?.rawTrailing,
            viewer: viewer.distributeDocDataInfo?.rawTrailing,
            "distributeDocData rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }

    func testViewerModeEmptiesTrackChangeNestedRawSlices() throws {
        let payload = Data([0x71, 0x72, 0x73, 0x74, 0xAA, 0xBB])
        let preserved = try HwpTrackChange.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpTrackChange.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.trackChangeInfo?.headerValue) == preserved.trackChangeInfo?.headerValue
        expect(viewer.trackChangeInfo?.headerValue).notTo(beNil())
        expectRawSliceEmptiedByViewer(
            preserved: preserved.trackChangeInfo?.headerRawPayload,
            viewer: viewer.trackChangeInfo?.headerRawPayload,
            "trackChange headerRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.trackChangeInfo?.rawTrailing,
            viewer: viewer.trackChangeInfo?.rawTrailing,
            "trackChange rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }

    func testViewerModeEmptiesTrackChangeContentNestedRawSlices() throws {
        let payload = Data([
            0x01, 0x00, 0x00, 0x00,
            0xE8, 0x07, 0x01, 0x00, 0x0F, 0x00, 0x09, 0x00, 0x1E, 0x00,
            0xEE, 0xFF,
        ])
        let preserved = try HwpTrackChangeContent.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpTrackChangeContent.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.contentInfo?.kind) == preserved.contentInfo?.kind
        expect(viewer.contentInfo?.timestamp) == preserved.contentInfo?.timestamp
        expect(viewer.contentInfo?.kind).notTo(beNil())
        expectRawSliceEmptiedByViewer(
            preserved: preserved.contentInfo?.kindRawPayload,
            viewer: viewer.contentInfo?.kindRawPayload,
            "trackChangeContent kindRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.contentInfo?.timestampRawPayload,
            viewer: viewer.contentInfo?.timestampRawPayload,
            "trackChangeContent timestampRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.contentInfo?.rawTrailing,
            viewer: viewer.contentInfo?.rawTrailing,
            "trackChangeContent rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }

    func testViewerModeEmptiesTrackChangeAuthorNestedRawSlices() throws {
        let payload = Data([
            0x03, 0x00, 0x00, 0x00,
            0x41, 0x00, 0x42, 0x00, 0x43, 0x00,
            0xEE, 0xFF,
        ])
        let preserved = try HwpTrackChangeAuthor.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpTrackChangeAuthor.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.authorInfo?.name) == preserved.authorInfo?.name
        expect(viewer.authorInfo?.name) == "ABC"
        expectRawSliceEmptiedByViewer(
            preserved: preserved.authorInfo?.nameLengthRawPayload,
            viewer: viewer.authorInfo?.nameLengthRawPayload,
            "trackChangeAuthor nameLengthRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.authorInfo?.nameRawPayload,
            viewer: viewer.authorInfo?.nameRawPayload,
            "trackChangeAuthor nameRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.authorInfo?.rawTrailing,
            viewer: viewer.authorInfo?.rawTrailing,
            "trackChangeAuthor rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }

    func testViewerModeEmptiesMemoShapeNestedRawSlices() throws {
        let payload = Data([
            0x64, 0x00, 0x00, 0x00,
            0x01,
            0x02,
            0x10, 0x20, 0x30, 0x00,
            0x40, 0x50, 0x60, 0x00,
            0x70, 0x80, 0x90, 0x00,
            0xEE, 0xFF,
        ])
        let preserved = try HwpMemoShape.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue, payload: payload, options: .default
        ))
        let viewer = try HwpMemoShape.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue, payload: payload, options: .viewer
        ))

        expect(viewer.shapeInfo?.width) == preserved.shapeInfo?.width
        expect(viewer.shapeInfo?.lineColor) == preserved.shapeInfo?.lineColor
        expect(viewer.shapeInfo?.width).notTo(beNil())
        expectRawSliceEmptiedByViewer(
            preserved: preserved.shapeInfo?.fixedFieldsRawPayload,
            viewer: viewer.shapeInfo?.fixedFieldsRawPayload,
            "memoShape fixedFieldsRawPayload"
        )
        expectRawSliceEmptiedByViewer(
            preserved: preserved.shapeInfo?.rawTrailing,
            viewer: viewer.shapeInfo?.rawTrailing,
            "memoShape rawTrailing"
        )
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }
}

private func rawDocInfoRecord(
    tagId: UInt32,
    payload: Data,
    options: HwpLoadOptions
) -> HwpRecord {
    HwpRecord(tagId: tagId, level: 0, payload: payload, options: options)
}

private func expectRawSliceEmptiedByViewer(preserved: Data?, viewer: Data?, _ label: String) {
    expect(preserved ?? Data()).notTo(beEmpty(), description: "\(label): default는 원문 보존")
    expect(viewer ?? Data()).to(beEmpty(), description: "\(label): viewer는 원문 제거")
}
