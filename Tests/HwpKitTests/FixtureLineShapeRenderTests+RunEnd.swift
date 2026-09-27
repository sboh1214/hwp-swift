import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `line-shapes`(한글 문서) 둘째 단 끝의 run 끝 표본 R1~R4 (#235) — 원형 점선·물결은 자리(원
/// 중심·대각선 시작)가 run 끝보다 앞인 요소를 끝을 넘어도 온전히 그린다.
///
/// 표본은 라벨 뒤 'A' run 하나에 기존 선 모양 글자 모양(10pt 함초롬바탕)을 싣고, 결정론
/// resolver에서 Menlo 10pt(6.02pt/자)로 조판된다. 10pt 원형 점선은 한글처럼 장치 단위로 반올림한
/// 간격 1.56pt(13u)·칠 지름 0.84pt(7u)다 (#239). R2 14자 84.29pt는 마지막 원 중심 84.24가 run 끝보다
/// 칠 반지름(0.42) 안쪽 앞이라 그 원이 끝을 넘는다 — 원이 끝 안에 온전히 들 때만 그리던 종전
/// 규칙은 54개였다. R1 5자 30.10pt의 마지막 원(29.64)은 끝 안에서 끝나 **개수 핀**이다 (#239 전의
/// 간격 1.425pt에서는 R1도 끝 규칙을 갈랐다). 간격이 한글과 같아졌으므로 한글 PDF와의 개수 대조는
/// 한글의 run 길이를 넣는 `HwpLineShapeGeometryTests+Circles`가 한다 (R1 23개·R2 64개 — 여기서는
/// 글꼴이 달라 run 길이가 다르다). R4는 마지막 대각선이 run 끝 안에서 끝나 끝 규칙을 가르지 않는
/// 개수 핀이다 (2중 물결의 끝은 `hwp2007-decorations` R4가 잠근다).
extension FixtureLineShapeRenderTests {
    func testRunEndCirclesAndWavesKeepElementsStartingBeforeTheEnd() throws {
        typealias Render = FixtureDecorationLineRenderTests
        let raster = try XCTUnwrap(Self.hwp)
        let red = FixtureDecorationLineRenderTests.isRed
        let columnTwo: ClosedRange<CGFloat> = 310 ... 425
        func runs(
            near y: CGFloat, where match: (UInt8, UInt8, UInt8) -> Bool
        ) -> [(start: CGFloat, end: CGFloat)] {
            Render.rowRuns(raster, near: y, halfBand: 0.2, x: columnTwo, where: match)
        }
        // R1 (베이스라인 257.64): 원형 점선 밑줄 — 원 20개, 마지막 중심 29.64 (= 19 × 1.56)
        let circleUnderline = runs(near: 259.26, where: red)
        expect(circleUnderline.count) == 20
        if let first = circleUnderline.first, let last = circleUnderline.last {
            expect((last.start + last.end) / 2 - (first.start + first.end) / 2)
                .to(beCloseTo(29.64, within: 0.3))
        }
        // R2 (베이스라인 273.60): 원형 점선 취소선 — 원 55개, 마지막 중심 84.24 (= 54 × 1.56)가 run
        // 끝 84.29 앞이라 끝을 넘어 그린다. 간격은 한글과 같은 1.56pt다
        let circleStrikeout = runs(near: 270.06, where: Self.isBlue)
        expect(circleStrikeout.count) == 55
        if let first = circleStrikeout.first, let last = circleStrikeout.last {
            let span = (last.start + last.end) / 2 - (first.start + first.end) / 2
            expect(span).to(beCloseTo(84.24, within: 0.3))
            expect(span / CGFloat(circleStrikeout.count - 1)).to(beCloseTo(1.56, within: 0.01))
        }
        // R3 (베이스라인 289.56): 물결 밑줄 — 반주기 1.24pt, 대각선 25개. 마지막 대각선(29.76
        // 시작)은 run 끝(30.10)을 넘어 30.88 + 획 모서리까지 칠한다
        // (가운데 행 둘레 띠에서 대각선마다 한 조각 — 10pt 획은 0.3pt라 한 행만 보면 놓친다)
        expect(Self.horizontalInkRuns(raster, y: 291.1 ... 291.34, x: columnTwo, where: red)) == 25
        if let first = circleUnderline.first,
           let right = Render.inkRightEdge(raster, y: 290.3 ... 292.1, x: columnTwo, where: red)
        {
            // R1과 같은 자리에서 시작하는 run — 첫 원 중심이 run 시작이다
            let start = (first.start + first.end) / 2
            let runWidth = Render.menloRunWidth(size: 10, count: 5)
            expect(right - start).to(beGreaterThan(runWidth + 0.3))
        }
        // R4 (베이스라인 305.64): 2중 물결 취소선 — 첫 파의 가운데 행 띠에서 대각선 68개 (둘째 파는
        // 0.9pt 아래에서 시작해 닿지 않는다). 마지막 대각선(83.08 → 84.20)이 run 끝(84.29) 안에서
        // 끝나 끝 규칙은 가르지 않는 개수 핀이다
        expect(Self.horizontalInkRuns(
            raster, y: 301.52 ... 301.72, x: columnTwo, where: Self.isBlue
        )) == 68
    }
}
