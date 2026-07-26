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

    /// 넓게(표 13 bit 0 = 1)로 선언된 구역은 축을 바꿔 배치한다 — 세로로 두면
    /// 본문 폭·줄바꿈·페이지 분할이 전부 어긋난다 (R69 #1).
    func testLandscapePropertySwapsAxesAndWidensContent() {
        var pageDef = HwpPageDef()
        pageDef.width = 59528
        pageDef.height = 84189
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0
        var landscape = pageDef
        landscape.property = 1

        let portraitGeometry = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)
        let landscapeGeometry = HwpPageGeometry.compute(pageDef: landscape, sectionDef: nil)

        expect(landscapeGeometry.pageSize.width).to(beCloseTo(841.89, within: 0.5))
        expect(landscapeGeometry.pageSize.height).to(beCloseTo(595.28, within: 0.5))
        expect(landscapeGeometry.contentFrame.width) > portraitGeometry.contentFrame.width
        expect(landscapeGeometry.columnFrames.first?.width)
            == landscapeGeometry.contentFrame.width
    }

    /// 저장 치수가 이미 가로 형태면 넓게 선언이어도 그대로 둔다 — 무조건 교환은
    /// 이중 회전이 된다. 방향 정규화는 멱등해야 한다 (R69 #1).
    func testLandscapePropertyKeepsAlreadyRotatedDimensions() {
        var pageDef = HwpPageDef()
        pageDef.width = 84189
        pageDef.height = 59528
        pageDef.property = 1

        let geometry = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geometry.pageSize.width).to(beCloseTo(841.89, within: 0.5))
        expect(geometry.pageSize.height).to(beCloseTo(595.28, within: 0.5))
        expect(HwpPageGeometry.orientedPageSize(geometry.pageSize, property: 1))
            == geometry.pageSize
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

    /// 제본 여백(gutter)은 제책 방향(property bit1~2)에 따라 해당 변에 더해진다
    /// — 한쪽(0)은 왼쪽, 위로(2)는 위쪽. 본문이 제본 스트립을 관통하지 않는다 (R42 #3).
    func testGutterAddedToBindingSide() {
        var oneSided = HwpPageDef()
        oneSided.width = 61200
        oneSided.height = 79200
        oneSided.marginTop = 7200
        oneSided.marginLeft = 7200
        oneSided.marginBottom = 7200
        oneSided.marginRight = 7200
        oneSided.marginHeader = 0
        oneSided.marginFootnote = 0
        oneSided.marginGutter = 3600
        oneSided.property = 0

        let left = HwpPageGeometry.compute(pageDef: oneSided, sectionDef: nil)
        // 왼쪽 여백 72 + gutter 36 = 108
        expect(left.contentFrame.origin.x) == 108.0
        expect(left.contentFrame.size.width) == left.pageSize.width - 108.0 - 72.0

        var topBound = oneSided
        topBound.property = 0b100 // makingBook = 2 (위로)
        let top = HwpPageGeometry.compute(pageDef: topBound, sectionDef: nil)
        expect(top.contentFrame.origin.x) == 72.0 // 왼쪽엔 gutter 없음
        expect(top.contentFrame.origin.y) == 108.0 // 위쪽 72 + gutter 36
    }

    /// 위로 제책 + 머리말: gutter가 머리말 앞에 와 머리말이 제본 영역에 놓이지
    /// 않는다 — 위 여백 → gutter → 머리말 → 본문 (R43 #2).
    func testTopGutterPushesHeaderBelowGutter() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200
        pageDef.marginHeader = 2400
        pageDef.marginFootnote = 0
        pageDef.marginGutter = 3600
        pageDef.property = 0b100 // 위로 제책

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        // 머리말 = 위 여백 72 + gutter 36 = 108 (제본 영역 아래)
        expect(geo.headerFrame?.minY) == 108.0
        // 본문 = 위 여백 72 + 머리말 24 + gutter 36 = 132
        expect(geo.contentFrame.minY) == 132.0
    }

    /// 한글의 세로 구성 (표 137): 위쪽 여백 → 머리말 영역 → 본문 → 꼬리말 영역
    /// → 아래쪽 여백. 본문 상단 = marginTop + marginHeader (BinData/plain-text
    /// 픽스처 PrvImage 실측: A4 기본 여백에서 본문 상단 99.2pt).
    func testContentFrameReservesHeaderAndFooterBands() {
        var pageDef = HwpPageDef()
        pageDef.width = 59528
        pageDef.height = 84186
        pageDef.marginLeft = 8504
        pageDef.marginRight = 8504
        pageDef.marginTop = 5668
        pageDef.marginBottom = 4252
        pageDef.marginHeader = 4252
        pageDef.marginFootnote = 4252

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.contentFrame.minY).to(beCloseTo(99.2, within: 0.05))
        expect(geo.headerFrame?.minY).to(beCloseTo(56.68, within: 0.05))
        expect(geo.headerFrame?.maxY).to(beCloseTo(geo.contentFrame.minY, within: 0.01))
        // 본문 하단 = 페이지 높이 − 아래 여백 − 꼬리말 여백
        expect(geo.contentFrame.maxY).to(beCloseTo(841.86 - 42.52 - 42.52, within: 0.1))
        expect(geo.footerFrame?.minY).to(beCloseTo(geo.contentFrame.maxY, within: 0.01))
        expect(geo.footerFrame?.maxY).to(beCloseTo(841.86 - 42.52, within: 0.1))
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
