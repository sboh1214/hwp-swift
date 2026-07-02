@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpTextboxLayoutTests: XCTestCase {
        func testNoShapeComponentsReturnsNil() {
            let textbox = HwpGenShapeObject(
                commonCtrlProperty: HwpCommonCtrlProperty(commonCtrlId: .genShapeObject),
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            let result = HwpTextboxLayout().layout(textbox: textbox, width: 300, index: emptyIndex())
            expect(result).to(beNil())
        }

        func testComponentWithNoTextboxListReturnsNil() {
            let component = HwpShapeComponent(
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
            let textbox = HwpGenShapeObject(
                commonCtrlProperty: HwpCommonCtrlProperty(commonCtrlId: .genShapeObject),
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [component],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            let result = HwpTextboxLayout().layout(textbox: textbox, width: 300, index: emptyIndex())
            expect(result).to(beNil())
        }

        func testEmptyParagraphListReturnsFrameWithNoParagraphFrames() {
            let list = HwpListControlList(
                header: HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: []
            )
            let component = HwpShapeComponent(
                rawCtrlId: nil,
                ctrlId: nil,
                rawPayload: Data(),
                rawTrailing: nil,
                pictureArray: [],
                oleArray: [],
                oleRecords: [],
                ctrlDataRecords: [],
                textBoxListArray: [list],
                unknownChildren: []
            )
            let textbox = HwpGenShapeObject(
                commonCtrlProperty: HwpCommonCtrlProperty(commonCtrlId: .genShapeObject),
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [component],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            let result = HwpTextboxLayout().layout(textbox: textbox, width: 300, index: emptyIndex())
            expect(result).toNot(beNil())
            expect(result?.paragraphFrames.count) == 0
        }

        func testOuterFrameUsesPassedWidthWhenCtrlPropertyWidthIsZero() {
            let list = HwpListControlList(
                header: HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: []
            )
            let component = HwpShapeComponent(
                rawCtrlId: nil,
                ctrlId: nil,
                rawPayload: Data(),
                rawTrailing: nil,
                pictureArray: [],
                oleArray: [],
                oleRecords: [],
                ctrlDataRecords: [],
                textBoxListArray: [list],
                unknownChildren: []
            )
            // HwpCommonCtrlProperty() has width = 0, so layout should fall back to passed width
            let textbox = HwpGenShapeObject(
                commonCtrlProperty: HwpCommonCtrlProperty(commonCtrlId: .genShapeObject),
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [component],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            let result = HwpTextboxLayout().layout(textbox: textbox, width: 200, index: emptyIndex())
            expect(result?.outerFrame.width) == 200
        }
    }

    private extension HwpTextboxLayoutTests {
        func emptyIndex() -> HwpIndex {
            HwpIndex(from: CoreHwp.HwpFile())
        }
    }
#endif
