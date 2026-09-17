import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `line-shapes` 픽스처 쌍의 선 모양 **실물 픽셀 핀** (#191) — 밑줄·취소선의 점선·원형
/// 점선·여러 줄·물결, 표 셀 테두리의 같은 모양, 2단 사이의 일점쇄선 구분선이 한글이 그린
/// 자리에 그려지고, HWP와 HWPX 저장본이 같은 픽셀을 내는지 잠근다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-17, 600dpi 벡터 좌표): 10pt 긴 점선
/// 밑줄은 선 2.88pt·공백 1.68pt, 점선은 0.6/0.96pt, 2중선은 0.24pt 두 줄(중심 간격 0.72),
/// 가는+굵은은 0.48 + 1.08pt, 물결은 진폭 1.08pt·획 0.24pt, 표 테두리(0.12mm)는 긴 점선
/// 2.4/1.44pt·2중선 0.12pt 두 줄, 단 구분선은 x 297.72에서 일점쇄선 4.8/1.44/0.48/1.44pt로
/// 쪽 본문 위(99.24)부터 첫 단 표 아래 여백(754.80)까지다. 쪽 좌표는 줄 캐시가 정하므로
/// 두 포맷·기기에서 같다 (`HwpFontResolver.testDeterministic`).
final class FixtureLineShapeRenderTests: XCTestCase {
    typealias Raster = FixtureDecorationLineRenderTests.Raster
    static let scale = FixtureDecorationLineRenderTests.scale

    static func isBlue(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 90 && green < 90 && blue > 130
    }

    /// 밑줄 문단(0 = SOLID … 12 = DOUBLEWAVE)의 베이스라인 (한글 줄 캐시, 위에서부터 pt)
    static func underlineBaseline(_ index: Int) -> CGFloat {
        123.72 + 15.96 * CGFloat(index)
    }

    /// 취소선 문단의 베이스라인
    static func strikeoutBaseline(_ index: Int) -> CGFloat {
        395.76 + 15.96 * CGFloat(index)
    }

    /// 첫 단 표 행(0 = SOLID … 6 = CIRCLE)의 위 모서리 y
    static func tableRowTop(_ row: Int) -> CGFloat {
        662.04 + 12.84 * CGFloat(row)
    }

    /// 띠(y 범위, x 범위 pt) 안에서 조건에 맞는 잉크가 있는 열들의 이어진 덩어리 수
    static func horizontalInkRuns(
        _ raster: Raster, y: ClosedRange<CGFloat>, x: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> Int {
        let rows = Int(y.lowerBound * scale) ... Int(y.upperBound * scale)
        var runs = 0
        var inRun = false
        for column in Int(x.lowerBound * scale) ... Int(x.upperBound * scale) {
            let ink = rows.contains { row in
                let offset = row * raster.bytesPerRow + column * 4
                return match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
            }
            if ink, !inRun {
                runs += 1
            }
            inRun = ink
        }
        return runs
    }

    /// 세로 띠 안의 잉크 덩어리 수와 위·아래 끝 (pt)
    struct VerticalInk {
        let runs: Int
        let top: CGFloat?
        let bottom: CGFloat?
    }

    /// 세로 띠(x 범위) 안에서 조건에 맞는 잉크가 있는 행들의 이어진 덩어리 수와 위·아래 끝 (pt)
    static func verticalInkRuns(
        _ raster: Raster, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> VerticalInk {
        let columns = Int(x.lowerBound * scale) ... Int(x.upperBound * scale)
        var runs = 0
        var inRun = false
        var top: CGFloat?
        var bottom: CGFloat?
        for row in Int(y.lowerBound * scale) ... Int(y.upperBound * scale) {
            let ink = columns.contains { column in
                let offset = row * raster.bytesPerRow + column * 4
                return match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
            }
            if ink {
                if top == nil {
                    top = CGFloat(row) / scale
                }
                bottom = CGFloat(row + 1) / scale
            }
            if ink, !inRun {
                runs += 1
            }
            inRun = ink
        }
        return VerticalInk(runs: runs, top: top, bottom: bottom)
    }

    /// 띠 안에서 조건에 맞는 픽셀이 있는 행들을 이어진 띠로 묶어 (위·아래 pt) 목록으로
    static func rowBands(
        _ raster: Raster, y: ClosedRange<CGFloat>, x: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> [(top: CGFloat, bottom: CGFloat)] {
        let columns = Int(x.lowerBound * scale) ... Int(x.upperBound * scale)
        var bands: [(top: CGFloat, bottom: CGFloat)] = []
        var previousInk = false
        for row in Int(y.lowerBound * scale) ... Int(y.upperBound * scale) {
            var count = 0
            for column in columns {
                let offset = row * raster.bytesPerRow + column * 4
                if match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]) {
                    count += 1
                }
            }
            let ink = count > 3
            if ink {
                if previousInk, let last = bands.popLast() {
                    bands.append((last.top, CGFloat(row + 1) / scale))
                } else {
                    bands.append((CGFloat(row) / scale, CGFloat(row + 1) / scale))
                }
            }
            previousInk = ink
        }
        return bands
    }

    static var hwp: Raster!
    static var hwpx: Raster!

    override static func setUp() {
        super.setUp()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            hwp = try? await FixtureDecorationLineRenderTests.raster("line-shapes", hwpx: false)
            hwpx = try? await FixtureDecorationLineRenderTests.raster("line-shapes", hwpx: true)
            semaphore.signal()
        }
        semaphore.wait()
    }

    func testHwpAndHwpxRenderTheSamePixels() throws {
        let hwp = try XCTUnwrap(Self.hwp)
        let hwpx = try XCTUnwrap(Self.hwpx)
        expect(hwp.data == hwpx.data) == true
    }

    /// 밑줄 13종: 실선은 한 덩어리, 긴 점선·점선·쇄선·원형 점선은 한글의 주기대로 조각난다
    /// (65pt 안에서 긴 점선 4.56pt 주기 14~15개, 점선 1.5pt 주기 40개쯤, 원형 점선 1.4pt
    /// 피치 45개쯤)
    func testUnderlineDashPatternsAreFragmented() throws {
        let raster = try XCTUnwrap(Self.hwp)
        func runs(_ index: Int) -> Double {
            let base = Self.underlineBaseline(index)
            return Double(Self.horizontalInkRuns(
                raster, y: (base + 1.2) ... (base + 2.2), x: 85 ... 150,
                where: FixtureDecorationLineRenderTests.isRed
            ))
        }
        expect(runs(0)) == 1 // SOLID
        expect(runs(1)).to(beCloseTo(15, within: 2)) // DOT(긴 점선) 2.88/1.68
        expect(runs(2)).to(beCloseTo(43, within: 5)) // DASH(점선) 0.6/0.96
        expect(runs(3)).to(beCloseTo(14, within: 2)) // DASH_DOT 5.76/1.68/0.6/1.68
        expect(runs(4)).to(beCloseTo(17, within: 3)) // DASH_DOT_DOT
        expect(runs(5)).to(beCloseTo(9, within: 2)) // LONG_DASH 5.76/1.68
        expect(runs(6)).to(beCloseTo(46, within: 5)) // CIRCLE 지름 0.57·피치 1.43
        expect(runs(7)) == 1 // DOUBLE_SLIM은 가로로는 이어진다
    }

    /// 여러 줄 밑줄: 2중선은 0.24pt 두 줄(중심 간격 0.72pt), 가는+굵은은 위가 가늘고 아래가
    /// 굵으며, 3중선은 세 띠 — 모두 단선 띠의 위 가장자리(베이스라인 아래 1.5pt)에서
    /// 아래로 자란다 (한글 실측 2026-09-17)
    func testMultiLineUnderlinesStackDownwardFromTheSingleLineTop() throws {
        let raster = try XCTUnwrap(Self.hwp)
        func bands(_ index: Int) -> [(top: CGFloat, bottom: CGFloat)] {
            let base = Self.underlineBaseline(index)
            return Self.rowBands(
                raster, y: (base + 0.9) ... (base + 5.5), x: 85 ... 150,
                where: FixtureDecorationLineRenderTests.isRed
            )
        }
        let double = bands(7)
        expect(double.count) == 2
        if double.count == 2 {
            let centers = double.map { ($0.top + $0.bottom) / 2 }
            expect(centers[1] - centers[0]).to(beCloseTo(0.72, within: 0.3))
            expect(double[0].top).to(beCloseTo(Self.underlineBaseline(7) + 1.5, within: 0.45))
        }
        let thinThick = bands(8)
        expect(thinThick.count) == 2
        if thinThick.count == 2 {
            expect(thinThick[1].bottom - thinThick[1].top) > thinThick[0].bottom - thinThick[0].top
            // 띠 0.2em = 2pt: 위 가장자리 +1.5 → 아래 가장자리 +3.5
            expect(thinThick[1].bottom).to(beCloseTo(Self.underlineBaseline(8) + 3.5, within: 0.45))
        }
        let thickThin = bands(9)
        expect(thickThin.count) == 2
        if thickThin.count == 2 {
            expect(thickThin[0].bottom - thickThin[0].top) > thickThin[1].bottom - thickThin[1].top
        }
        expect(bands(10).count) == 3
    }

    /// 물결 밑줄은 진폭 1.12pt(0.112em)의 지그재그, 2중 물결은 둘째 파가 0.8 진폭 아래 —
    /// 잉크 띠가 한 줄보다 훨씬 높다 (한글 실측: 10pt 꼭짓점 세로 1.08pt, 2중 1.68pt)
    func testWaveUnderlinesSpanTheirAmplitude() throws {
        let raster = try XCTUnwrap(Self.hwp)
        func span(_ index: Int) -> CGFloat {
            let base = Self.underlineBaseline(index)
            let result = Self.verticalInkRuns(
                raster, x: 90 ... 140, y: (base + 0.5) ... (base + 6),
                where: FixtureDecorationLineRenderTests.isRed
            )
            return (result.bottom ?? 0) - (result.top ?? 0)
        }
        expect(span(0)).to(beCloseTo(0.5, within: 0.3)) // 실선 0.4pt
        expect(span(11)).to(beCloseTo(1.12 + 0.3, within: 0.4)) // WAVE
        expect(span(12)).to(beCloseTo(1.12 * 1.8 + 0.3, within: 0.5)) // DOUBLEWAVE
    }

    /// 취소선도 같은 모양을 쓴다 — 긴 점선은 조각나고, 2중선은 단선 중심(베이스라인 위
    /// 3.48pt)에 가운데 맞춰 두 줄이다
    func testStrikeoutShapesFollowTheSameTable() throws {
        let raster = try XCTUnwrap(Self.hwp)
        let dotBase = Self.strikeoutBaseline(1)
        expect(Double(Self.horizontalInkRuns(
            raster, y: (dotBase - 4.2) ... (dotBase - 2.8), x: 85 ... 150,
            where: Self.isBlue
        ))).to(beCloseTo(15, within: 2))
        let doubleBase = Self.strikeoutBaseline(7)
        let bands = Self.rowBands(
            raster, y: (doubleBase - 6) ... (doubleBase - 1), x: 85 ... 150,
            where: Self.isBlue
        )
        expect(bands.count) == 2
        if bands.count == 2 {
            let center = (bands[0].top + bands[1].bottom) / 2
            expect(center).to(beCloseTo(doubleBase - 3.48, within: 0.3))
        }
    }

    /// 첫 단 표(0.12mm 테두리): 이웃 행과 공유하는 가로 변은 두 셀의 모양이 겹쳐 그려지므로
    /// (한글도 그렇다 — 실선 아래 변 + 긴 점선 위 변이 한 모서리에 둘 다 남는다) 표 맨 위
    /// 변과 행마다 하나뿐인 **왼 변**으로 잰다: 왼 변 10pt 안에서 긴 점선(2.4/1.44)은 3조각,
    /// 점선(0.48/0.72)은 8조각쯤, 긴 파선(4.8/1.44)은 2조각, 원형 점선(피치 0.68)은 8조각 넘게
    func testTableBordersFollowTheirShapes() throws {
        let raster = try XCTUnwrap(Self.hwp)
        let top = Self.tableRowTop(0)
        expect(Self.horizontalInkRuns(
            raster, y: (top - 0.6) ... (top + 0.6), x: 100 ... 280,
            where: FixtureDecorationLineRenderTests.isDark
        )) == 1
        // 표 왼 모서리 x (한글보다 2.83pt 왼쪽 — #161의 표 x 격차) — 실선 행에서 찾는다
        let solidRow = Self.tableRowTop(0)
        var edge: CGFloat?
        for column in Int(80 * Self.scale) ..< Int(95 * Self.scale) {
            let rows = Int((solidRow + 2) * Self.scale) ... Int((solidRow + 10) * Self.scale)
            let ink = rows.filter { row in
                let offset = row * raster.bytesPerRow + column * 4
                return FixtureDecorationLineRenderTests.isDark(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }.count
            if ink > rows.count * 8 / 10 {
                edge = CGFloat(column) / Self.scale
                break
            }
        }
        let left = try XCTUnwrap(edge, "표 왼 변을 못 찾았다")
        expect(left).to(beCloseTo(85.1, within: 0.6))
        func leftRuns(_ row: Int) -> Double {
            let y = Self.tableRowTop(row)
            return Double(Self.verticalInkRuns(
                raster, x: (left - 0.3) ... (left + 0.7), y: (y + 1.5) ... (y + 11.5),
                where: FixtureDecorationLineRenderTests.isDark
            ).runs)
        }
        expect(leftRuns(0)) == 1 // SOLID
        expect(leftRuns(1)).to(beCloseTo(3, within: 1)) // DOT
        expect(leftRuns(2)).to(beCloseTo(8, within: 2)) // DASH
        expect(leftRuns(5)).to(beCloseTo(2, within: 1)) // LONG_DASH
        // CIRCLE — 지름 0.34·간격 0.34pt 원 사이가 4px/pt에선 붙기도 해 하한만 둔다
        expect(leftRuns(6)) >= 8
    }

    /// 2단 사이 구분선(`DASH_DOT`, 0.12mm): 간격 중앙 x 297.72에 본문 위(99.24)부터 첫 단
    /// 표 아래 여백(754.80)까지 일점쇄선 4.8/1.44/0.48/1.44pt — 8.16pt 주기로 655pt 안에
    /// 조각 160개쯤
    func testColumnDividerIsDashDotBetweenTheColumns() throws {
        let raster = try XCTUnwrap(Self.hwp)
        let divider = Self.verticalInkRuns(
            raster, x: 297.0 ... 298.5, y: 95 ... 760,
            where: FixtureDecorationLineRenderTests.isDark
        )
        expect(Double(divider.runs)).to(beCloseTo(160, within: 12))
        expect(divider.top ?? -1).to(beCloseTo(99.24, within: 0.5))
        expect(divider.bottom ?? -1).to(beCloseTo(754.8, within: 1.0))
        // 간격의 다른 자리에는 잉크가 없다
        let beside = Self.verticalInkRuns(
            raster, x: 293.0 ... 295.0, y: 95 ... 760,
            where: FixtureDecorationLineRenderTests.isDark
        )
        expect(beside.runs) == 0
    }
}
