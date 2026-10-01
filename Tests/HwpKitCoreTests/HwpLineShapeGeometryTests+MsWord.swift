import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// MS 워드 호환 문서의 글자선 모양 (#244) — 그 문서의 밑줄은 **선 두께와 무늬의 기준이 갈린다**.
/// 두께는 글꼴 기준 상자의 0.05배(#187, `HwpDecorationLineGeometry.msWordUnderlineBelow`)이고
/// 무늬(원·대시·여러 줄 띠·물결)는 줄 글자 상자의 높이 X를 글자 크기 자리에 넣은 축척이다. 한글
/// 문서에서는 두께가 늘 그 축척의 0.04배라 두 값이 같았고, 물결 꼭짓점 계단을 두께로 재도
/// 틀리지 않았다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-30, 글꼴 5종 × 10·20·40·
/// 80pt × 선 모양 12종). Menlo 20pt 밑줄은 줄 캐시 `vertsize` 30.29pt(우리 상자 30.27pt)이고
/// 실선 두께는 10u(1.2pt, 기준 상자 23.28pt × 0.05 = 1.164pt), 물결 위 꼭짓점은 실선 중심 위
/// 3.04pt(= 2.5 × 0.04 × 30.27 = 3.03), 2중선 두 줄은 실선 중심 ±1.26pt에 가운데로 놓인다.
/// 렌더러가 어느 축척·자리를 고르는지는 `HwpDecorationLineGeometryTests+MsWordShape`
/// (HwpKitNative)가 잡는다. 이 파일에서 #244의 변경을 가르는 것은 물결 계단 테스트 하나이고
/// (종전 계산이면 −2.91pt), 나머지 셋은 축척·자리를 입력으로 넣고 한글 값과 대는 **기하 특성화**다 —
/// 렌더러가 고른 축척·자리가 한글 값을 낸다는 사슬의 뒤 절반을 적어 둔다.
extension HwpLineShapeGeometryTests {
    /// Menlo 20pt MS 워드 호환 밑줄 — 축척은 줄 글자 상자 30.27pt, 두께는 기준 상자의 0.05배
    static let msWordBoxHeight: CGFloat = 1.513_3 * 20
    static let msWordUnderlineThickness: CGFloat = 1.513_3 * 20 / 1.3 * 0.05

    static func msWordUnderline(
        _ shape: HwpBorderType, length: CGFloat = 200
    ) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: length, thickness: msWordUnderlineThickness,
            scale: .characterLine(fontSize: msWordBoxHeight), placement: .strikethrough
        )
    }

    /// 물결 꼭짓점 계단은 선 두께가 아니라 **축척의 0.04배**다 — 취소선 자리(계단 둘)의 위
    /// 꼭짓점이 단선 중심 위 2.5 × 0.04 × X = 3.027pt (한글 3.04pt). 두께(1.164pt)로 재면
    /// 2.5 × 1.164 = 2.91pt라 한글보다 낮고, 글꼴 5종 80pt에서는 그 차가 0.36~0.54pt다.
    func testWaveStepsFollowTheScaleNotTheLineThickness() {
        let line = Self.msWordUnderline(.wave)
        let stroke = Self.msWordBoxHeight * HwpRenderTuning.LineShape.characterWaveStrokeEmRatio
        let top = -2.5 * HwpRenderTuning.Text.decorationLineThicknessRatio * Self.msWordBoxHeight
        let extent = HwpLineShapeGeometry.crossExtent(of: line)
        expect(extent?.lowerBound).to(beCloseTo(top - stroke / 2, within: 0.001))
        expect(top).to(beCloseTo(-3.04, within: 0.05))
        // 대조군 — 두께가 축척의 0.04배인 한글 문서 선에서는 두 셈이 같다
        let native = Self.characterLine(.wave, fontSize: 20, placement: .strikethrough)
        expect(HwpLineShapeGeometry.waveTopVertex(for: native))
            .to(beCloseTo(-2.5 * native.thickness, within: 0.001))
        expect(HwpLineShapeGeometry.wavePatternThickness(for: native))
            .to(beCloseTo(native.thickness, within: 0.000_1))
        // 테두리 축척을 글자선 자리에 쓴 선은 종전대로 두께다
        let border = HwpLineShapeGeometry.Line(
            shape: .wave, length: 40, thickness: 3, scale: .border, placement: .strikethrough
        )
        expect(HwpLineShapeGeometry.wavePatternThickness(for: border)) == 3
    }

    /// 2중 물결도 같은 위 꼭짓점에서 시작하고 둘째 파는 진폭의 0.8배 아래다 (축척 X 기준)
    func testDoubleWaveSharesTheScaledTopVertex() {
        let single = HwpLineShapeGeometry.waveTopVertex(for: Self.msWordUnderline(.wave))
        let double = HwpLineShapeGeometry.waveTopVertex(for: Self.msWordUnderline(.doubleWave))
        expect(double).to(beCloseTo(single, within: 0.000_1))
        let amplitude = Self.msWordBoxHeight
            * HwpRenderTuning.LineShape.characterWaveAmplitudeEmRatio
        expect(HwpLineShapeGeometry.doubleWaveOffset(for: Self.msWordUnderline(.doubleWave)).y)
            .to(beCloseTo(amplitude * 0.8, within: 0.001))
    }

    /// 대시는 무늬가 축척을, 획 두께가 선 두께를 따른다 — Menlo 20pt 긴 점선 밑줄은 무늬 두께
    /// round(3027 × 0.039) = 118HWPUNIT의 긴 선 round(144.2) = 144u의 절반 72u = 8.64pt(한글 72u, #245)에
    /// 두께 1.164pt(한글 10u = 1.2pt — 글자선 획 두께는 반올림하지 않는다)
    func testDashesScaleWithTheBoxAndKeepTheLineThickness() {
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.msWordUnderline(.longDotLine)))
        expect(pieces.count) > 4
        guard let first = pieces.first else { return }
        expect(first.width).to(beCloseTo(72 * 0.12, within: 1e-9))
        expect(first.height).to(beCloseTo(Self.msWordUnderlineThickness, within: 0.001))
    }

    /// 여러 줄 띠는 취소선 자리 — 단선 중심에 가운데. 2중선 띠 0.12 × 30.27 = 3.63pt의 두 줄이
    /// 중심 ±1.36pt에 놓인다 (한글 ±1.26pt·두께 0.84pt — 한글은 줄 두께를 장치 단위로 내려
    /// 반올림해 띠가 0.2pt 좁다, 한글 문서에도 있는 기존 격차).
    func testMultiLineBandsAreCenteredOnTheSingleLine() {
        let stripes = HwpLineShapeGeometry.stripes(for: Self.msWordUnderline(.doubleLine))
        expect(stripes.count) == 2
        guard stripes.count == 2 else { return }
        expect(stripes[0].minY).to(beCloseTo(-stripes[1].maxY, within: 0.000_1))
        let band = 0.12 * Self.msWordBoxHeight
        expect(stripes[1].maxY - stripes[0].minY).to(beCloseTo(band, within: 0.001))
        expect(stripes[1].midY).to(beCloseTo(1.26, within: 0.15))
    }
}
