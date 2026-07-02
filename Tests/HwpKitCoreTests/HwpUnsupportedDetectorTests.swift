@testable import CoreHwp
import Foundation
import HwpKitCore
import Nimble
import XCTest

final class HwpUnsupportedDetectorTests: XCTestCase {
    let detector = HwpUnsupportedDetector()

    // MARK: - Unsupported (V1 OUT) Tests

    func testEquationControlReturnsPlaceholder() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x6465_7165, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .equation(shapeControl), page: 1)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.page) == 1
        expect(element?.hint).to(contain("수식"))
    }

    func testEquationLegacyControlReturnsPlaceholder() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x6465_7165, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .equationLegacy(shapeControl), page: 2)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.page) == 2
        expect(element?.hint).to(contain("수식"))
    }

    func testOleControlReturnsPlaceholder() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x246F_6C65, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .ole(shapeControl), page: 3)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.page) == 3
        expect(element?.hint).to(contain("OLE"))
    }

    func testFormControlReturnsPlaceholder() {
        let otherControl = HwpOtherControl(
            header: HwpCtrlHeader(ctrlId: 0x6D72_6F66, rawPayload: Data()),
            rawPayload: Data()
        )
        let element = detector.classify(ctrl: .form(otherControl), page: 4)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.hint).to(contain("알 수 없음"))
    }

    func testNotImplementedControlReturnsPlaceholder() {
        let header = HwpCtrlHeader(ctrlId: 0x1234_5678, rawPayload: Data())
        let element = detector.classify(ctrl: .notImplemented(header), page: 5)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.hint).to(contain("알 수 없음"))
    }

    func testUnknownControlReturnsPlaceholder() {
        let header = HwpCtrlHeader(ctrlId: 0x9ABC_DEF0, rawPayload: Data())
        let element = detector.classify(ctrl: .unknown(header), page: 6)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
        expect(element?.hint).to(contain("알 수 없음"))
    }

    // MARK: - Supported (V1 IN) Tests

    func testTableControlReturnsNil() {
        let table = HwpTable(
            property: HwpTableProperty(),
            cellArray: []
        )
        let element = detector.classify(ctrl: .table(table), page: 1)

        expect(element).to(beNil())
    }

    func testPictureControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2463_6970, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .picture(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testLineControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x246E_696C, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .line(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testRectangleControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2472_6563, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .rectangle(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testEllipseControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2465_6C6C, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .ellipse(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testArcControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2461_7263, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .arc(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testPolygonControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2470_6F6C, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .polygon(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testCurveControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2463_7572, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .curve(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testGenShapeObjectControlReturnsNil() {
        let genShapeObject = HwpGenShapeObject(
            header: HwpCtrlHeader(ctrlId: 0x2467_736F, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentId: 0,
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .genShapeObject(genShapeObject), page: 1)

        expect(element).to(beNil())
    }

    func testSectionControlReturnsNil() {
        let sectionDef = HwpSectionDef()
        let element = detector.classify(ctrl: .section(sectionDef), page: 1)

        expect(element).to(beNil())
    }

    func testColumnControlReturnsNil() {
        let column = HwpColumn()
        let element = detector.classify(ctrl: .column(column), page: 1)

        expect(element).to(beNil())
    }

    func testPageNumberPositionControlReturnsNil() {
        let pageNumberPosition = HwpPageNumberPosition()
        let element = detector.classify(ctrl: .pageNumberPosition(pageNumberPosition), page: 1)

        expect(element).to(beNil())
    }

    func testHeaderControlReturnsNil() {
        let listControl = HwpListControl()
        let element = detector.classify(ctrl: .header(listControl), page: 1)

        expect(element).to(beNil())
    }

    func testFooterControlReturnsNil() {
        let listControl = HwpListControl()
        let element = detector.classify(ctrl: .footer(listControl), page: 1)

        expect(element).to(beNil())
    }

    func testFootnoteControlReturnsNil() {
        let listControl = HwpListControl()
        let element = detector.classify(ctrl: .footnote(listControl), page: 1)

        expect(element).to(beNil())
    }

    func testEndnoteControlReturnsNil() {
        let listControl = HwpListControl()
        let element = detector.classify(ctrl: .endnote(listControl), page: 1)

        expect(element).to(beNil())
    }

    func testHyperlinkControlReturnsNil() {
        let hyperlink = HwpHyperlink()
        let element = detector.classify(ctrl: .hyperLink(hyperlink), page: 1)

        expect(element).to(beNil())
    }

    func testShapeControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2473_6861, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .shape(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    func testContainerControlReturnsNil() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x2463_6F6E, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .container(shapeControl), page: 1)

        expect(element).to(beNil())
    }

    // MARK: - Page Number Tracking

    func testPageNumberIsPreserved() {
        let shapeControl = HwpShapeControl(
            header: HwpCtrlHeader(ctrlId: 0x6465_7165, rawPayload: Data()),
            commonProperty: HwpCommonCtrlProperty(),
            shapeComponentArray: [],
            ctrlDataArray: []
        )
        let element = detector.classify(ctrl: .equation(shapeControl), page: 42)

        expect(element?.page) == 42
    }

    // MARK: - Placeholder Render Command

    func testPlaceholderRenderCommandCreation() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let text = "[수식]"
        let color = CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)

        let command = HwpPlaceholderRenderCommand(frame: frame, text: text, color: color)

        expect(command.frame) == frame
        expect(command.text) == text
    }

    func testPlaceholderRenderCommandDefaultColor() {
        let frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        let text = "[차트]"

        let command = HwpPlaceholderRenderCommand(frame: frame, text: text)

        expect(command.frame) == frame
        expect(command.text) == text
        // Verify default grey color is set
        expect(command.color).notTo(beNil())
    }

    func testPlaceholderRenderCommandHashable() {
        let frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        let command1 = HwpPlaceholderRenderCommand(frame: frame, text: "[수식]")
        let command2 = HwpPlaceholderRenderCommand(frame: frame, text: "[수식]")

        // Both should be hashable (no crash)
        let set = Set([command1, command2])
        expect(set.count) >= 1
    }

    // MARK: - Additional Unsupported Controls

    func testAutoNumberControlReturnsPlaceholder() {
        let otherControl = HwpOtherControl(
            header: HwpCtrlHeader(ctrlId: 0x6F6E_7461, rawPayload: Data()),
            rawPayload: Data()
        )
        let element = detector.classify(ctrl: .autoNumber(otherControl), page: 7)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
    }

    func testMemoControlReturnsPlaceholder() {
        let fieldControl = HwpFieldControl()
        let element = detector.classify(ctrl: .memo(fieldControl), page: 8)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
    }

    func testCommentControlReturnsPlaceholder() {
        let otherControl = HwpOtherControl(
            header: HwpCtrlHeader(ctrlId: 0x6D6D_6F63, rawPayload: Data()),
            rawPayload: Data()
        )
        let element = detector.classify(ctrl: .comment(otherControl), page: 9)

        expect(element).notTo(beNil())
        expect(element?.kind) == .placeholder
    }
}
