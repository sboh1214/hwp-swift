@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpPageGeometryTests: XCTestCase {
    func testA4PageSize() {
        var pageDef = HwpPageDef()
        pageDef.width = 59528
        pageDef.height = 84189
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.pageSize.width).to(beCloseTo(595.28, within: 0.5))
        expect(geo.pageSize.height).to(beCloseTo(841.89, within: 0.5))
    }

    func testLetterPageSize() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.pageSize.width) == 612.0
        expect(geo.pageSize.height) == 792.0
    }

    func testCustomMargins() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.contentFrame.origin.x) == 72.0
        expect(geo.contentFrame.origin.y) == 72.0
        expect(geo.contentFrame.size.width) == geo.pageSize.width - 144.0
        expect(geo.contentFrame.size.height) == geo.pageSize.height - 144.0
    }

    func testTwoColumn() {
        // 단 컨트롤 없이 계산하면 1단 (contentFrame) 폴백이다.
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        var sectionDef = HwpSectionDef()
        sectionDef.columnSpacing = 1440

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: sectionDef)

        expect(geo.columnFrames.count) == 1
        expect(geo.columnFrames.first) == geo.contentFrame
    }

    // MARK: - 단 정의 (표 138/139) → columnFrames

    private func column(
        count: Int,
        spacing: Int16? = nil,
        widths: [UInt16]? = nil,
        gaps: [UInt16]? = nil,
        direction: HwpColumnDirection = .left
    ) -> HwpColumn {
        var column = HwpColumn()
        column.property = HwpColumnProperty(
            rawValue: 0,
            type: .general,
            count: count,
            direction: direction,
            isSameWidth: widths == nil
        )
        column.spacing = spacing
        column.widthArray = widths
        column.gapArray = gaps
        return column
    }

    func testEqualWidthColumnsSplitAreaWithSpacing() {
        let area = CGRect(x: 100, y: 50, width: 430, height: 600)
        // 2단, 간격 2268 HWPUNIT = 22.68pt (Column 픽스처 값)
        let frames = HwpPageGeometry.columnFrames(
            in: area,
            column: column(count: 2, spacing: 2268)
        )

        expect(frames.count) == 2
        let expectedWidth = (430.0 - 22.68) / 2
        expect(frames[0].minX).to(beCloseTo(100, within: 0.01))
        expect(frames[0].width).to(beCloseTo(expectedWidth, within: 0.01))
        expect(frames[1].minX).to(beCloseTo(100 + expectedWidth + 22.68, within: 0.01))
        expect(frames[1].maxX).to(beCloseTo(area.maxX, within: 0.01))
        for frame in frames {
            expect(frame.minY) == area.minY
            expect(frame.height) == area.height
        }
    }

    func testProportionalColumnWidthsScaleToArea() {
        let area = CGRect(x: 85, y: 56, width: 425.2, height: 600)
        // Column 픽스처 p3: 폭 [10339, 20682] + 간격 [1747, 0], 합 32768 비례값
        let frames = HwpPageGeometry.columnFrames(
            in: area,
            column: column(count: 2, widths: [10339, 20682], gaps: [1747, 0])
        )

        expect(frames.count) == 2
        let scale = 425.2 / 32768.0
        expect(frames[0].width).to(beCloseTo(10339 * scale, within: 0.05))
        expect(frames[1].width).to(beCloseTo(20682 * scale, within: 0.05))
        expect(frames[1].minX).to(beCloseTo(85 + (10339 + 1747) * scale, within: 0.05))
        expect(frames[1].maxX).to(beCloseTo(area.maxX, within: 0.05))
    }

    func testRightDirectionReversesColumnOrder() {
        let area = CGRect(x: 0, y: 0, width: 400, height: 500)
        let frames = HwpPageGeometry.columnFrames(
            in: area,
            column: column(count: 2, spacing: 0, direction: .right)
        )

        expect(frames.count) == 2
        // 오른쪽부터: 첫 채움 단이 오른쪽 프레임이다.
        expect(frames[0].minX) > frames[1].minX
    }

    func testComputeWithColumnControlFillsColumnFrames() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200

        var sectionDef = HwpSectionDef()
        sectionDef.columnSpacing = 1440

        let geo = HwpPageGeometry.compute(
            pageDef: pageDef,
            sectionDef: sectionDef,
            column: column(count: 2)
        )

        expect(geo.columnFrames.count) == 2
        // 단 간격이 nil이면 구역의 columnSpacing (1440 = 14.4pt)을 쓴다.
        expect(geo.columnFrames[1].minX - geo.columnFrames[0].maxX)
            .to(beCloseTo(14.4, within: 0.01))
    }
}
