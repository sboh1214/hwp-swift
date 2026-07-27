import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpShapeGeometryTests: XCTestCase {
    func testBuildWithNoDetailRecordsFallsBackToBoundingRect() throws {
        let geometry = HwpShapeGeometry.build(
            component: emptyComponent(),
            size: CGSize(width: 120, height: 60)
        )
        let unwrapped = try XCTUnwrap(geometry)
        let bounds = unwrapped.path.boundingBox
        expect(bounds.origin.x).to(beCloseTo(0, within: 0.01))
        expect(bounds.origin.y).to(beCloseTo(0, within: 0.01))
        expect(bounds.width).to(beCloseTo(120, within: 0.01))
        expect(bounds.height).to(beCloseTo(60, within: 0.01))
        expect(unwrapped.fillColor).to(beNil())
        expect(unwrapped.strokeColor).toNot(beNil())
        expect(unwrapped.strokeWidth) == 1
    }

    func testBuildWithNoDetailRecordsAndZeroSizeReturnsNil() {
        let geometry = HwpShapeGeometry.build(
            component: emptyComponent(),
            size: CGSize(width: 0, height: 0)
        )
        expect(geometry).to(beNil())
    }

    private func emptyComponent() -> CoreHwp.HwpShapeComponent {
        CoreHwp.HwpShapeComponent(
            rawCtrlId: nil,
            ctrlId: nil,
            rawPayload: Data(),
            rawTrailing: nil,
            pictureArray: [],
            oleArray: [],
            oleRecords: [],
            ctrlDataRecords: [],
            textBoxListArray: [],
            unknownChildren: []
        )
    }

    func testRectanglePathBounds() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let path = HwpShapeGeometry.rectanglePath(from: rect)
        expect(path.isEmpty) == false
        let bounds = path.boundingBox
        expect(bounds.origin.x).to(beCloseTo(10, within: 0.01))
        expect(bounds.origin.y).to(beCloseTo(20, within: 0.01))
        expect(bounds.width).to(beCloseTo(100, within: 0.01))
        expect(bounds.height).to(beCloseTo(50, within: 0.01))
    }

    func testEllipsePathBounds() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = HwpShapeGeometry.ellipsePath(from: rect)
        expect(path.isEmpty) == false
        let bounds = path.boundingBox
        expect(bounds.width).to(beCloseTo(200, within: 0.01))
        expect(bounds.height).to(beCloseTo(100, within: 0.01))
    }

    func testLinePathBounds() {
        let path = HwpShapeGeometry.linePath(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 50)
        )
        expect(path.isEmpty) == false
        let bounds = path.boundingBox
        expect(bounds.width).to(beCloseTo(100, within: 0.01))
        expect(bounds.height).to(beCloseTo(50, within: 0.01))
    }

    func testPolygonPathTriangle() throws {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 50, y: 100),
        ]
        let path = HwpShapeGeometry.polygonPath(from: points)
        expect(path).toNot(beNil())
        expect(try XCTUnwrap(path?.isEmpty)) == false
        let bounds = try XCTUnwrap(path?.boundingBox)
        expect(bounds.width).to(beCloseTo(100, within: 0.01))
        expect(bounds.height).to(beCloseTo(100, within: 0.01))
    }

    func testPolygonPathTwoPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let path = HwpShapeGeometry.polygonPath(from: points)
        expect(path).toNot(beNil())
    }

    func testPolygonPathOnePointReturnsNil() {
        let path = HwpShapeGeometry.polygonPath(from: [CGPoint(x: 0, y: 0)])
        expect(path).to(beNil())
    }

    func testPolygonPathEmptyReturnsNil() {
        let path = HwpShapeGeometry.polygonPath(from: [])
        expect(path).to(beNil())
    }

    func testEllipseArcPathDrawsPartialArcNotFullEllipse() {
        // 중심(0,0)·반지름 100×50 타원의 (100,0)→(0,50) 1사분면 호. 완전 타원이면
        // bounds가 (-100,-50,200,100)이지만 부분 호는 (0,0,100,50)이다 (R45 #2).
        let ellipse = CoreHwp.HwpShapeEllipseDetail(
            property: 0b10,
            center: CoreHwp.HwpShapePoint(x: 0, y: 0),
            firstAxis: CoreHwp.HwpShapePoint(x: 100, y: 0),
            secondAxis: CoreHwp.HwpShapePoint(x: 0, y: 50)
        )
        let path = HwpShapeGeometry.ellipseArcPath(
            of: ellipse,
            start: CoreHwp.HwpShapePoint(x: 100, y: 0),
            end: CoreHwp.HwpShapePoint(x: 0, y: 50),
            transform: .identity
        )
        let bounds = path.boundingBox
        expect(bounds.minX).to(beCloseTo(0, within: 0.5))
        expect(bounds.minY).to(beCloseTo(0, within: 0.5))
        expect(bounds.maxX).to(beCloseTo(100, within: 0.5))
        expect(bounds.maxY).to(beCloseTo(50, within: 0.5))
    }

    func testEllipseArcPathPieClosesThroughCenter() {
        // 오른쪽 호(-45°~45°, 중심 0,0·반지름 100): 부채꼴은 중심까지 닫으므로
        // bounds minX가 호만(70.71)이 아니라 중심(0)까지 내려온다 (R46 #2).
        let path = arcPath(arcKind: 1)
        expect(path.boundingBox.minX).to(beCloseTo(0, within: 0.5))
        expect(self.isClosed(path)) == true
    }

    func testEllipseArcPathChordClosesWithoutCenter() {
        // 활은 두 끝점을 현으로 닫되 중심은 포함하지 않는다 — 닫혀 있지만
        // bounds minX는 호만(≈70.71) (R46 #2).
        let path = arcPath(arcKind: 2)
        expect(path.boundingBox.minX).to(beCloseTo(70.71, within: 1))
        expect(self.isClosed(path)) == true
    }

    func testEllipseArcPathOpenStaysOpen() {
        // 호는 닫지 않아 stroke가 호 구간만 그린다 (R46 #2).
        let path = arcPath(arcKind: 0)
        expect(path.boundingBox.minX).to(beCloseTo(70.71, within: 1))
        expect(self.isClosed(path)) == false
    }

    private func arcPath(arcKind: UInt32) -> CGPath {
        // property: bit1 = 호 변환, bits 2-9 = 닫힘 종류
        let ellipse = CoreHwp.HwpShapeEllipseDetail(
            property: 0b10 | (arcKind << 2),
            center: CoreHwp.HwpShapePoint(x: 0, y: 0),
            firstAxis: CoreHwp.HwpShapePoint(x: 100, y: 0),
            secondAxis: CoreHwp.HwpShapePoint(x: 0, y: 100)
        )
        return HwpShapeGeometry.ellipseArcPath(
            of: ellipse,
            start: CoreHwp.HwpShapePoint(x: 70, y: -70),
            end: CoreHwp.HwpShapePoint(x: 70, y: 70),
            transform: .identity
        )
    }

    private func isClosed(_ path: CGPath) -> Bool {
        var closed = false
        path.applyWithBlock { element in
            if element.pointee.type == .closeSubpath {
                closed = true
            }
        }
        return closed
    }
}
