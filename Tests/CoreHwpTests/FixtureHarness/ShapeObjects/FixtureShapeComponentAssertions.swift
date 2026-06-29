@testable import CoreHwp
import Foundation
import Nimble

func assertShapeComponentOleRecords(
    _ expected: FixtureShapeComponentExpectations,
    _ actual: HwpShapeComponent
) {
    if let oleCount = expected.oleCount {
        expect(actual.oleRecords.count) == oleCount
        expect(actual.oleArray.count) == oleCount
    }
    if let olePayloadLengths = expected.olePayloadLengths {
        expect(actual.oleRecords.map(\.payload.count)) == olePayloadLengths
        expect(actual.oleArray.map(\.rawPayload.count)) == olePayloadLengths
    }
    FixtureAssertions.assertPayloadSamples(
        actual.oleRecords.map(\.payload),
        lengths: nil,
        prefixes: expected.olePayloadPrefixBytes,
        suffixes: expected.olePayloadSuffixBytes
    )
    FixtureAssertions.assertPayloadSamples(
        actual.oleArray.map(\.rawPayload),
        lengths: nil,
        prefixes: expected.olePayloadPrefixBytes,
        suffixes: expected.olePayloadSuffixBytes
    )
    FixtureAssertions.assertPayloadSamples(
        actual.oleArray.compactMap(\.rawTrailing),
        lengths: expected.oleRawTrailingLengths,
        prefixes: expected.oleRawTrailingPrefixBytes,
        suffixes: expected.oleRawTrailingSuffixBytes
    )
    if let oleBinaryDataIds = expected.oleBinaryDataIds {
        expect(actual.oleArray.compactMap(\.binaryDataId)) == oleBinaryDataIds
    }
}

func assertShapeComponentRawChildren(
    _ expected: FixtureShapeComponentExpectations,
    _ actual: HwpShapeComponent
) {
    guard let rawChildren = expected.rawChildren else {
        return
    }

    for rawChild in rawChildren {
        assertShapeComponentRawChild(rawChild, actual)
    }
}

private func assertShapeComponentRawChild(
    _ expected: FixtureShapeRawChildExpectations,
    _ actual: HwpShapeComponent
) {
    guard let records = rawShapeComponentChildRecords(expected.kind, actual) else {
        fail("Unknown shape component raw child kind: \(expected.kind)")
        return
    }
    if let count = expected.count {
        expect(records.count) == count
    }
    FixtureAssertions.assertPayloadSamples(
        records.map(\.rawPayload),
        lengths: expected.payloadLengths,
        prefixes: expected.payloadPrefixBytes,
        suffixes: expected.payloadSuffixBytes
    )
    if let childCounts = expected.childCounts {
        expect(records.map(\.unknownChildren.count)) == childCounts
    }

    for index in records.indices {
        FixtureAssertions.assertUnknownRecordSamples(
            records[index].unknownChildren,
            rootLevel: 4,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: nestedExpectation(expected.childTagIds, at: index),
                payloadLengths: nestedExpectation(expected.childPayloadLengths, at: index),
                payloadPrefixes: nestedExpectation(expected.childPayloadPrefixBytes, at: index),
                payloadSuffixes: nestedExpectation(expected.childPayloadSuffixBytes, at: index),
                childTagIds: nil,
                childPayloadLengths: nil,
                childPayloadPrefixes: nil,
                childPayloadSuffixes: nil
            )
        )
    }
}

private struct ShapeComponentRawChildSnapshot {
    let rawPayload: Data
    let unknownChildren: [HwpUnknownRecord]
}

private typealias RawChildAccessor = (HwpShapeComponent) -> [ShapeComponentRawChildSnapshot]

private let rawShapeComponentChildAccessors: [String: RawChildAccessor] = [
    "line": { rawChildren($0.lineArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentLine": { rawChildren($0.lineArray, \.rawPayload, \.unknownChildren) },
    "rectangle": { rawChildren($0.rectangleArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentRectangle": {
        rawChildren($0.rectangleArray, \.rawPayload, \.unknownChildren)
    },
    "ellipse": { rawChildren($0.ellipseArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentEllipse": { rawChildren($0.ellipseArray, \.rawPayload, \.unknownChildren) },
    "arc": { rawChildren($0.arcArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentArc": { rawChildren($0.arcArray, \.rawPayload, \.unknownChildren) },
    "polygon": { rawChildren($0.polygonArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentPolygon": { rawChildren($0.polygonArray, \.rawPayload, \.unknownChildren) },
    "curve": { rawChildren($0.curveArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentCurve": { rawChildren($0.curveArray, \.rawPayload, \.unknownChildren) },
    "container": { rawChildren($0.containerArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentContainer": {
        rawChildren($0.containerArray, \.rawPayload, \.unknownChildren)
    },
    "chartData": { rawChildren($0.chartDataArray, \.rawPayload, \.unknownChildren) },
    "textart": { rawChildren($0.textartArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentTextart": { rawChildren($0.textartArray, \.rawPayload, \.unknownChildren) },
    "formObject": { rawChildren($0.formObjectArray, \.rawPayload, \.unknownChildren) },
    "memoShape": { rawChildren($0.memoShapeArray, \.rawPayload, \.unknownChildren) },
    "memoList": { rawChildren($0.memoListArray, \.rawPayload, \.unknownChildren) },
    "videoData": { rawChildren($0.videoDataArray, \.rawPayload, \.unknownChildren) },
    "unknown": { rawChildren($0.shapeComponentUnknownArray, \.rawPayload, \.unknownChildren) },
    "shapeComponentUnknown": {
        rawChildren($0.shapeComponentUnknownArray, \.rawPayload, \.unknownChildren)
    },
]

private func rawShapeComponentChildRecords(
    _ kind: String,
    _ actual: HwpShapeComponent
) -> [ShapeComponentRawChildSnapshot]? {
    rawShapeComponentChildAccessors[kind]?(actual)
}

private func rawChildren<Record>(
    _ records: [Record],
    _ rawPayload: KeyPath<Record, Data>,
    _ unknownChildren: KeyPath<Record, [HwpUnknownRecord]>
) -> [ShapeComponentRawChildSnapshot] {
    records.map {
        ShapeComponentRawChildSnapshot(
            rawPayload: $0[keyPath: rawPayload],
            unknownChildren: $0[keyPath: unknownChildren]
        )
    }
}

private func nestedExpectation<Element>(
    _ expectations: [[Element]]?,
    at index: Int
) -> [Element]? {
    guard let expectations, expectations.indices.contains(index) else {
        return nil
    }
    return expectations[index]
}
