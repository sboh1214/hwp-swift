@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeComponentKindDetailDecodeTests: XCTestCase {
    func testLineDetailDecodesEndpointsAndOptionalAttribute() {
        var payload = int32Payload([10, -20, 30, -40])

        let bare = HwpShapeComponentLine(rawPayload: payload, unknownChildren: [])
        expect(bare.lineDetail?.start) == HwpShapePoint(x: 10, y: -20)
        expect(bare.lineDetail?.end) == HwpShapePoint(x: 30, y: -40)
        expect(bare.lineDetail?.attribute).to(beNil())

        payload.append(littleEndianData(UInt16(1)))
        let full = HwpShapeComponentLine(rawPayload: payload, unknownChildren: [])
        expect(full.lineDetail?.attribute) == 1

        let short = HwpShapeComponentLine(
            rawPayload: Data(repeating: 0, count: 15),
            unknownChildren: []
        )
        expect(short.lineDetail).to(beNil())
    }

    func testRectangleDetailReadsInterleavedCornerPairs() {
        var payload = Data([20]) // 모서리 곡률 %
        payload.append(int32Payload([0, 0, 100, 0, 100, 50, 0, 50])) // (x,y) 쌍 4개

        let rectangle = HwpShapeComponentRectangle(rawPayload: payload, unknownChildren: [])
        let detail = rectangle.rectangleDetail

        expect(detail?.cornerRoundness) == 20
        expect(detail?.corners) == [
            HwpShapePoint(x: 0, y: 0),
            HwpShapePoint(x: 100, y: 0),
            HwpShapePoint(x: 100, y: 50),
            HwpShapePoint(x: 0, y: 50),
        ]

        let truncated = HwpShapeComponentRectangle(
            rawPayload: Data(payload.dropLast()),
            unknownChildren: []
        )
        expect(truncated.rectangleDetail).to(beNil())
    }

    func testPolygonDetailReadsInterleavedPointPairs() {
        var payload = littleEndianData(Int16(3))
        payload.append(int32Payload([1, -1, 2, -2, 3, -3])) // (x,y) 쌍 3개

        let polygon = HwpShapeComponentPolygon(rawPayload: payload, unknownChildren: [])

        expect(polygon.polygonDetail?.points) == [
            HwpShapePoint(x: 1, y: -1),
            HwpShapePoint(x: 2, y: -2),
            HwpShapePoint(x: 3, y: -3),
        ]
    }

    func testPolygonDetailIsNilForZeroCountOrTruncatedPoints() {
        expect(HwpShapePolygonDetail.decode(from: littleEndianData(Int16(0)))).to(beNil())

        var truncated = littleEndianData(Int16(2))
        truncated.append(Data(repeating: 0, count: 15)) // 좌표에는 16 byte 필요
        expect(HwpShapePolygonDetail.decode(from: truncated)).to(beNil())
    }

    func testCurveDetailReadsPointsAndSegmentTypes() {
        var payload = littleEndianData(Int16(3))
        payload.append(int32Payload([0, 5, 10, 15, 20, 25])) // (x,y) 쌍 3개
        payload.append(contentsOf: [1, 0]) // segment types: curve, line

        let curve = HwpShapeComponentCurve(rawPayload: payload, unknownChildren: [])

        expect(curve.curveDetail?.points) == [
            HwpShapePoint(x: 0, y: 5),
            HwpShapePoint(x: 10, y: 15),
            HwpShapePoint(x: 20, y: 25),
        ]
        expect(curve.curveDetail?.segmentTypes) == [1, 0]
    }

    func testCurveDetailIsNilWhenSegmentTypesAreMissing() {
        var payload = littleEndianData(Int16(2))
        payload.append(Data(repeating: 0, count: 16)) // 좌표만 있고 구간 종류 byte 없음

        expect(HwpShapeCurveDetail.decode(from: payload)).to(beNil())
    }

    func testEllipseDetailReadsPropertyCenterAndAxes() {
        var payload = littleEndianData(UInt32(0b10)) // 호로 바뀜 flag
        payload.append(int32Payload([50, 60, 70, 80, 90, 100]))

        let ellipse = HwpShapeComponentEllipse(rawPayload: payload, unknownChildren: [])
        let detail = ellipse.ellipseDetail

        expect(detail?.property) == 2
        expect(detail?.isArc) == true
        expect(detail?.center) == HwpShapePoint(x: 50, y: 60)
        expect(detail?.firstAxis) == HwpShapePoint(x: 70, y: 80)
        expect(detail?.secondAxis) == HwpShapePoint(x: 90, y: 100)

        let arc = HwpShapeComponentArc(rawPayload: payload, unknownChildren: [])
        expect(arc.arcDetail) == detail
    }
}

private func int32Payload(_ values: [Int32]) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(littleEndianData(value))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
