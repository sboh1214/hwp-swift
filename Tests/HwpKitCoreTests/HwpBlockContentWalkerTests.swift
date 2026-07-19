import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpBlockContentWalkerTests: XCTestCase {
    private let black = HwpRGBColor(red: 0, green: 0, blue: 0)

    private func paragraph(_ text: String) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: text),
            frame: HwpParagraphFrame(totalHeight: 10, lines: []),
            rect: CGRect(x: 0, y: 0, width: 100, height: 10),
            paragraphId: 0,
            hyperlinkURL: nil
        )
    }

    private func image(binItemId: UInt32, behind: Bool = false, zOrder: Int32) -> HwpCellImage {
        HwpCellImage(
            rect: CGRect(x: 0, y: 0, width: 10, height: 10),
            binItemId: binItemId,
            style: nil,
            paintsBehindText: behind,
            zOrder: zOrder,
            controlInstanceId: binItemId
        )
    }

    private func shape(zOrder: Int32) -> HwpCellShape {
        HwpCellShape(
            rect: CGRect(x: 0, y: 0, width: 10, height: 10),
            geometry: HwpShapeGeometry(
                path: CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil),
                fillColor: nil, strokeColor: nil, strokeWidth: 1
            ),
            zOrder: zOrder,
            controlInstanceId: 3
        )
    }

    private func table(cells: [HwpTableCellFrame]) -> HwpTableFrame {
        HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
            rows: [HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
                cells: cells
            )],
            borderColor: black,
            borderWidth: 1
        )
    }

    /// 셀 개체 방출 순서: 글 뒤로 개체 → 문단 텍스트 → 나머지 개체
    /// (각 평면 안은 zOrder 오름차순) (R30 #2).
    func testWalkTableEmitsBehindObjectsBeforeTextAndSortsByZOrder() {
        let cell = HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: [paragraph("셀")],
            borders: HwpBorderSet.uniform(width: 0.5, color: black),
            fillColor: nil,
            images: [
                image(binItemId: 1, behind: true, zOrder: 0),
                image(binItemId: 2, zOrder: 2),
            ],
            shapes: [shape(zOrder: 1)]
        )

        var events: [String] = []
        HwpBlockContentWalker.walkTable(
            table(cells: [cell]),
            origin: .zero,
            onParagraphText: { _, _, _ in events.append("text") },
            onCellImage: { image, _ in events.append("image\(image.binItemId)") },
            onCellShape: { _, _ in events.append("shape") }
        )

        expect(events) == ["image1", "text", "shape", "image2"]
    }
}
