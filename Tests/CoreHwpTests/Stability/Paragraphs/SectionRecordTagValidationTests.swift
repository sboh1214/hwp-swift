@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SectionRecordTagValidationTests: XCTestCase {
    func testCtrlHeaderModelsRejectMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.listHeader.rawValue
        let version = HwpVersion(5, 0, 1, 1)
        let loaders: [(String, () throws -> Void)] = [
            ("HwpCtrlHeader", {
                _ = try HwpCtrlHeader.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpColumn", {
                _ = try HwpColumn.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpFieldControl", {
                _ = try HwpFieldControl.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpGenShapeObject", {
                _ = try HwpGenShapeObject.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpGenShapeObjectWithVersion", {
                _ = try HwpGenShapeObject.load(sectionTagValidationRecord(tagId: wrongTag), version)
            }),
            ("HwpHyperlink", {
                _ = try HwpHyperlink.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpListControl", {
                _ = try HwpListControl.load(sectionTagValidationRecord(tagId: wrongTag), version)
            }),
            ("HwpOtherControl", {
                _ = try HwpOtherControl.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpPageNumberPosition", {
                _ = try HwpPageNumberPosition.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpSectionDef", {
                _ = try HwpSectionDef.load(sectionTagValidationRecord(tagId: wrongTag), version)
            }),
            ("HwpShapeControl", {
                _ = try HwpShapeControl.load(sectionTagValidationRecord(tagId: wrongTag))
            }),
            ("HwpShapeControlWithVersion", {
                _ = try HwpShapeControl.load(sectionTagValidationRecord(tagId: wrongTag), version)
            }),
            ("HwpTable", {
                _ = try HwpTable.load(sectionTagValidationRecord(tagId: wrongTag), version)
            }),
        ]

        for loader in loaders {
            expectMismatchedSectionTag(expected: .ctrlHeader, got: wrongTag, loader.0) {
                try loader.1()
            }
        }
    }

    func testParagraphRejectsMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.ctrlHeader.rawValue

        expectMismatchedSectionTag(expected: .paraHeader, got: wrongTag, "HwpParagraph") {
            _ = try HwpParagraph.load(sectionTagValidationRecord(tagId: wrongTag), testVersion)
        }
    }

    func testCtrlDataRejectsMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.listHeader.rawValue

        expectMismatchedSectionTag(expected: .ctrlData, got: wrongTag, "HwpCtrlData") {
            _ = try HwpCtrlData.load(sectionTagValidationRecord(
                tagId: wrongTag,
                payload: Data([0xAA])
            ))
        }
    }

    func testTableCellHeaderRejectsMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.ctrlData.rawValue

        expectMismatchedSectionTag(expected: .listHeader, got: wrongTag, "HwpTableCellHeader") {
            _ = try HwpTableCellHeader.load(sectionTagValidationRecord(
                tagId: wrongTag,
                payload: Data([0xAA])
            ))
        }
    }

    func testShapeComponentRejectsMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.ctrlHeader.rawValue

        expectMismatchedSectionTag(expected: .shapeComponent, got: wrongTag, "HwpShapeComponent") {
            _ = try HwpShapeComponent.load(sectionTagValidationRecord(tagId: wrongTag))
        }
        expectMismatchedSectionTag(
            expected: .shapeComponent,
            got: wrongTag,
            "HwpShapeComponentWithVersion"
        ) {
            _ = try HwpShapeComponent.load(sectionTagValidationRecord(tagId: wrongTag), testVersion)
        }
    }

    func testShapeComponentDetailModelsRejectMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.shapeComponent.rawValue
        let loaders = [
            SectionTagValidationLoader(.shapeComponentLine, "HwpShapeComponentLine") {
                _ = try HwpShapeComponentLine.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentRectangle, "HwpShapeComponentRectangle") {
                _ = try HwpShapeComponentRectangle.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentEllipse, "HwpShapeComponentEllipse") {
                _ = try HwpShapeComponentEllipse.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentArc, "HwpShapeComponentArc") {
                _ = try HwpShapeComponentArc.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentPolygon, "HwpShapeComponentPolygon") {
                _ = try HwpShapeComponentPolygon.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentCurve, "HwpShapeComponentCurve") {
                _ = try HwpShapeComponentCurve.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentOle, "HwpShapeComponentOLE") {
                _ = try HwpShapeComponentOLE.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentPicture, "HwpShapeComponentPicture") {
                _ = try HwpShapeComponentPicture.load(sectionTagValidationRecord(tagId: wrongTag))
            },
            SectionTagValidationLoader(.shapeComponentContainer, "HwpShapeComponentContainer") {
                _ = try HwpShapeComponentContainer.load(sectionTagValidationRecord(
                    tagId: wrongTag
                ))
            },
            SectionTagValidationLoader(.chartData, "HwpShapeComponentChartData") {
                _ = try HwpShapeComponentChartData.load(sectionTagValidationRecord(
                    tagId: wrongTag
                ))
            },
        ]

        for loader in loaders {
            expectMismatchedSectionTag(expected: loader.expectedTag, got: wrongTag, loader.label) {
                try loader.expression()
            }
        }
    }

    func testEquationEditRejectsMismatchedSectionTagWithTypedError() {
        let wrongTag = HwpSectionTag.ctrlHeader.rawValue

        expectMismatchedSectionTag(expected: .eqEdit, got: wrongTag, "HwpEquationEdit") {
            _ = try HwpEquationEdit.load(sectionTagValidationRecord(tagId: wrongTag))
        }
    }
}

private let testVersion = HwpVersion(5, 0, 1, 1)

private struct SectionTagValidationLoader {
    let expectedTag: HwpSectionTag
    let label: String
    let expression: () throws -> Void

    init(
        _ expectedTag: HwpSectionTag,
        _ label: String,
        _ expression: @escaping () throws -> Void
    ) {
        self.expectedTag = expectedTag
        self.label = label
        self.expression = expression
    }
}

private func sectionTagValidationRecord(
    tagId: UInt32,
    payload: Data = Data([0xAA])
) -> HwpRecord {
    HwpRecord(tagId: tagId, level: 0, payload: payload)
}

private func expectMismatchedSectionTag(
    expected: HwpSectionTag,
    got actualTag: UInt32,
    _ label: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("\(label): expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("expected Section tag \(expected.rawValue)"))
        expect(reason).to(contain("got \(actualTag)"))
    })
}
