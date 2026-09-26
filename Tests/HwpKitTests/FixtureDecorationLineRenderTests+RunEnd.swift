import CoreGraphics
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// 원형 점선·물결의 **run 끝** 실물 핀 (#235) — 한글은 자리(원 중심·물결 대각선 시작)가 run
/// 끝보다 앞인 요소를 끝을 넘어도 온전히 그린다.
///
/// `hwp2007-decorations` 2쪽 끝의 R1~R4는 라벨(장식 없음) 뒤 Menlo 10pt 'A' run 하나에 선 모양을
/// 싣는다. 한글 2007 호환 문서라 무늬가 고정 pt(원 간격 3.0·물결 반주기 3.0·2중 물결 1.56)이고
/// run 폭이 한글과 결정론 resolver에서 거의 같아(Menlo 10pt 'A' — 한글 6.04pt, 우리 6.02pt)
/// **run 끝의 원·대각선 개수를 한글 PDF와 그대로 맞댈 수 있다**. 오라클은 한글.app 12.30.0 build
/// 6446의 PDF 내보내기(2026-09-27, 벡터 좌표):
///
/// | 문단 | 모양 | 'A' 수 | 한글 요소 수 · 마지막 자리 (run 시작 기준) | 종전 규칙 |
/// |---|---|---:|---|---|
/// | R1 | 원형 점선 아래 밑줄 | 15 | 원 31 · 중심 90.0 (run 90.61) | 원 30 |
/// | R2 | 원형 점선 취소선 | 24 | 원 49 · 중심 144.0 (run 144.97) | 원 48 |
/// | R3 | 물결 아래 밑줄 | 15 | 대각선 31 · 시작 90.0 → 92.88까지 | 같음 |
/// | R4 | 2중 물결 취소선 | 13 | 파마다 대각선 51 · 시작 78.0 | 같음 |
///
/// 우리 run은 R1 90.31·R2 144.49·R4 78.27pt라 마지막 원(중심 90.0·144.0)이 run 끝보다 반지름
/// 0.66 안쪽 앞에 있다 — 원이 끝 안에 온전히 들 때만 그리던 종전 규칙은 그 원을 빼 개수가 하나
/// 모자랐다. 물결은 종전에도 시작이 끝 앞인 대각선을 끝까지 그렸고, 그 넘침(R3 +2.6pt)을 함께 잠근다.
extension FixtureDecorationLineRenderTests {
    /// `y`(pt) ± `halfBand` 안에서 조건 픽셀이 가장 많은 행의, `x` 구간 안 가로 잉크 조각 (시작,
    /// 끝, pt) 목록 — #235 run 끝 핀(`FixtureLineShapeRenderTests+RunEnd`도 쓴다)
    static func rowRuns(
        _ raster: Raster, near y: CGFloat, halfBand: CGFloat, x: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> [(start: CGFloat, end: CGFloat)] {
        let columns = Int(x.lowerBound * scale) ... Int(x.upperBound * scale)
        func ink(_ row: Int, _ column: Int) -> Bool {
            let offset = row * raster.bytesPerRow + column * 4
            return match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
        }
        let rows = Int((y - halfBand) * scale) ... Int((y + halfBand) * scale)
        guard let row = rows.max(by: { lhs, rhs in
            columns.filter { ink(lhs, $0) }.count < columns.filter { ink(rhs, $0) }.count
        }) else { return [] }
        var runs: [(start: CGFloat, end: CGFloat)] = []
        var start: Int?
        for column in columns.lowerBound ... columns.upperBound + 1 {
            let isInk = column <= columns.upperBound && ink(row, column)
            if isInk, start == nil {
                start = column
            } else if !isInk, let first = start {
                runs.append((CGFloat(first) / scale, CGFloat(column) / scale))
                start = nil
            }
        }
        return runs
    }

    /// 띠(`y`·`x` 구간) 안 조건 픽셀의 가장 오른쪽 끝 (pt)
    static func inkRightEdge(
        _ raster: Raster, y: ClosedRange<CGFloat>, x: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> CGFloat? {
        let rows = Int(y.lowerBound * scale) ... Int(y.upperBound * scale)
        let columns = Int(x.lowerBound * scale) ... Int(x.upperBound * scale)
        for column in columns.reversed() {
            let hit = rows.contains { row in
                let offset = row * raster.bytesPerRow + column * 4
                return match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
            }
            if hit {
                return CGFloat(column + 1) / scale
            }
        }
        return nil
    }

    /// Menlo `size`pt 'A' `count`자의 진행 폭 — 결정론 resolver의 run 폭
    static func menloRunWidth(size: CGFloat, count: Int) -> CGFloat {
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        var character: UniChar = 0x41
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
        return CGFloat(advance) * CGFloat(count)
    }

    private static func isRunEndMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    func testHwp2007RunEndCirclesAndWavesMatchHangulCounts() async throws {
        let magenta = Self.isRunEndMagenta
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page = try await Self.raster("hwp2007-decorations", hwpx: hwpx, pageIndex: 1)
            func runs(near y: CGFloat, halfBand: CGFloat) -> [(start: CGFloat, end: CGFloat)] {
                Self.rowRuns(page, near: y, halfBand: halfBand, x: 90 ... 290, where: magenta)
            }
            // R1 (베이스라인 367.80): 원 중심 = 단선 중심(1.68 아래) + 띠 쪽 0.24 — 우리 369.62
            let circleUnderline = runs(near: 369.62, halfBand: 0.3)
            expect(circleUnderline.count).to(equal(31), description: "\(format) R1 원 수")
            if let first = circleUnderline.first, let last = circleUnderline.last {
                // 마지막 원(중심 90.0)은 run 끝(90.31)에 걸쳐 90.66까지 칠한다
                expect((last.start + last.end) / 2 - (first.start + first.end) / 2)
                    .to(beCloseTo(90.0, within: 0.3), description: "\(format) R1 마지막 중심")
            }
            // R2 (베이스라인 380.76): 취소선 중심 0.35em 위 — 우리 377.20
            let circleStrikeout = runs(near: 377.20, halfBand: 0.3)
            expect(circleStrikeout.count).to(equal(49), description: "\(format) R2 원 수")
            if let first = circleStrikeout.first, let last = circleStrikeout.last {
                expect((last.start + last.end) / 2 - (first.start + first.end) / 2)
                    .to(beCloseTo(144.0, within: 0.3), description: "\(format) R2 마지막 중심")
            }
            // R3 (베이스라인 393.72): 물결 꼭짓점 394.08 ~ 396.96, 가운데 행에서 대각선마다 한 조각
            let waveUnderline = runs(near: 395.52, halfBand: 0.2)
            expect(waveUnderline.count).to(equal(31), description: "\(format) R3 대각선 수")
            if let first = waveUnderline.first,
               let right = Self.inkRightEdge(
                   page, y: 393.8 ... 397.3, x: 90 ... 230, where: magenta
               )
            {
                // 첫 대각선이 가운데 행을 지나는 자리 = run 시작 + 진폭/2 — 마지막 대각선(90.0 시작)은
                // run 끝(90.31)을 넘어 92.88 + 획 모서리까지 칠한다
                let start = (first.start + first.end) / 2 - 1.44
                let runWidth = Self.menloRunWidth(size: 10, count: 15)
                expect(right - start)
                    .to(beGreaterThan(runWidth + 2), description: "\(format) R3 끝 넘침")
                expect(right - start)
                    .to(beLessThan(92.88 + 0.6), description: "\(format) R3 끝")
            }
            // R4 (베이스라인 406.80): 첫 파(꼭짓점 402.04 ~ 403.48)의 위쪽 행 — 둘째 파는 1.08 아래
            // (위 꼭짓점 획이 402.84부터)라 402.75 행부터 섞인다. 획이 0.36pt라 4px/pt에서 한
            // 대각선이 임계 아래 픽셀로 갈라지지 않게 옅은 자홍까지 센다
            let doubleWave = Self.rowRuns(page, near: 402.4, halfBand: 0.12, x: 90 ... 220) {
                $0 > 200 && $2 > 200 && $1 < 200
            }
            expect(doubleWave.count).to(equal(51), description: "\(format) R4 대각선 수")
        }
    }
}
