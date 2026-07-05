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
}
