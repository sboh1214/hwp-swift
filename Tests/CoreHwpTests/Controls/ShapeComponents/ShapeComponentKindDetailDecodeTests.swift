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

    /// 점 개수는 4 byte다 (실제 저장본·hwplib) — 스펙 표 99의 INT16 표기와 다르다.
    func testPolygonDetailReadsInterleavedPointPairs() {
        var payload = littleEndianData(Int32(3))
        payload.append(int32Payload([1, -1, 2, -2, 3, -3])) // (x,y) 쌍 3개

        let polygon = HwpShapeComponentPolygon(rawPayload: payload, unknownChildren: [])

        expect(polygon.polygonDetail?.points) == [
            HwpShapePoint(x: 1, y: -1),
            HwpShapePoint(x: 2, y: -2),
            HwpShapePoint(x: 3, y: -3),
        ]
    }

    /// 헌법주석 픽스처의 유일한 다각형 레코드 (24 byte) — 4 byte 개수로 읽어야 283×283 상자
    /// 안의 대각선이다. 2 byte로 읽으면 둘째 점이 0x011B0000이 돼 쪽을 가로지르는 선이 된다.
    func testPolygonDetailReadsTheFixtureRecordAsADiagonalInsideItsBox() {
        let payload = Data([
            0x02, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x1B, 0x01, 0x00, 0x00, 0x1B, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ])
        expect(HwpShapePolygonDetail.decode(from: payload)?.points) == [
            HwpShapePoint(x: 0, y: 0),
            HwpShapePoint(x: 283, y: 283),
        ]
    }

    /// 2 byte 개수로는 읽지 않는다 — 두 해석은 구조로 가를 수 없어 (첫 x의 아래 16 bit가 0이면
    /// 앞 4 byte가 같은 개수다) 폴백이 있으면 좌표가 이웃 필드의 반쪽끼리 붙는다. 4 byte
    /// 레이아웃에 안 맞는 레코드는 nil이다.
    func testPolygonDetailDoesNotFallBackToANarrowCount() {
        var narrow = littleEndianData(Int16(2))
        narrow.append(int32Payload([7, 8, 9, 10]))
        expect(HwpShapePolygonDetail.decode(from: narrow)).to(beNil())
        // x = 0으로 시작하는 2 byte 레코드에 꼬리 2 byte가 있으면 4 byte로도 "읽히지만" 좌표가
        // 어긋난다 — 그런 표본이 없어 4 byte 하나로 읽는다 (hwplib과 같다).
        var ambiguous = littleEndianData(Int16(1))
        ambiguous.append(int32Payload([0, 5]))
        ambiguous.append(littleEndianData(Int16(0)))
        expect(HwpShapePolygonDetail.decode(from: ambiguous)?.points) == [HwpShapePoint(x: 327_680, y: 0)]
    }

    func testPolygonDetailIsNilForZeroCountOrTruncatedPoints() {
        expect(HwpShapePolygonDetail.decode(from: littleEndianData(Int32(0)))).to(beNil())
        expect(HwpShapePolygonDetail.decode(from: littleEndianData(Int16(0)))).to(beNil())

        // 좌표 두 쌍엔 16 byte가 필요하다.
        var truncated = littleEndianData(Int32(2))
        truncated.append(Data(repeating: 0, count: 15))
        expect(HwpShapePolygonDetail.decode(from: truncated)).to(beNil())
    }

    func testCurveDetailReadsPointsAndSegmentTypes() {
        var payload = littleEndianData(Int32(3))
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
        // 좌표 두 쌍(16)에 구간 종류 1 byte가 더 필요하다.
        var payload = littleEndianData(Int32(2))
        payload.append(Data(repeating: 0, count: 16))

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
        // 28바이트 레코드에는 호 끝점 필드가 없다 (60바이트 타원에만 존재).
        expect(detail?.arcStart).to(beNil())
        expect(detail?.arcEnd).to(beNil())

        let arc = HwpShapeComponentArc(rawPayload: payload, unknownChildren: [])
        expect(arc.arcDetail) == detail
    }

    func testEllipseDetailReadsArcEndpointsFrom60BytePayload() {
        // 60바이트 타원: property + center + axis1 + axis2 + start1 + end1 + start2 + end2.
        // 호 변환 시 start1(offset 28)/end1(offset 36)이 호 시작/끝점이다 (R45 #2).
        var payload = littleEndianData(UInt32(0b10)) // isArc
        payload.append(int32Payload([0, 0, 100, 0, 0, 50, 100, 0, 0, 50, 7, 7, 8, 8]))
        expect(payload.count) == 60

        let ellipse = HwpShapeComponentEllipse(rawPayload: payload, unknownChildren: [])
        let detail = ellipse.ellipseDetail

        expect(detail?.arcStart) == HwpShapePoint(x: 100, y: 0)
        expect(detail?.arcEnd) == HwpShapePoint(x: 0, y: 50)
    }

    func testEllipseDetailDecodesArcKindFromPropertyBits() {
        /// bits 2-9: 0 open, 1 pie, 2 chord (hwp-rs ArcKind·hwplib ArcType 실측).
        func arcKind(property: UInt32) -> HwpShapeArcKind? {
            var payload = littleEndianData(property)
            payload.append(int32Payload([0, 0, 0, 0, 0, 0]))
            return HwpShapeComponentEllipse(rawPayload: payload, unknownChildren: [])
                .ellipseDetail?.arcKind
        }

        expect(arcKind(property: 0)) == .open
        expect(arcKind(property: 1 << 2)) == .pie
        expect(arcKind(property: 2 << 2)) == .chord
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
