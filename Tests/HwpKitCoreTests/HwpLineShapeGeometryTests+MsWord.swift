import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// MS 워드 호환 문서의 글자선 모양 (#244·#252) — 그 문서의 밑줄은 무늬(원·대시·여러 줄 띠·물결)와
/// 획 두께가 모두 줄 글자 상자의 높이 X를 기준 크기로 쓴다. 획 두께는 장식선 기하가 같은 X의 장치
/// 단위 획으로 넘기고(`HwpDecorationLineGeometry.msWordUnderlineBelow`), 여러 줄·물결은 X에서 푼
/// 장치 단위 정수 기하를 **취소선 자리**(단선 중심에 가운데)에 놓는다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (build 6446 2026-09-30, 글꼴 5종 × 10·20·40·80pt ×
/// 선 모양 12종; build 6523 2026-10-03, 글꼴 4종 × 10·20·40·80pt × 여러 줄·물결 6종 × 세 종류 288표본 —
/// 부속선 두께·물결 가로 폭·반주기·획·둘째 파 이동이 모두 같다). Menlo 20pt 밑줄은 줄 캐시
/// `vertsize` 30.29pt(우리 상자 30.27pt — X = 3027HWPUNIT)이고 실선 두께는 10u(1.2pt), 물결 위
/// 꼭짓점은 실선 중심 위 3.04pt, 2중선 두 줄은 실선 중심 −1.32·+1.20pt(한글 ±1.26pt 평균)다.
/// 렌더러가 어느 축척·자리를 고르는지는 `HwpDecorationLineGeometryTests+MsWordShape`
/// (HwpKitNative)가 잡고, 이 파일은 축척·자리를 입력으로 넣고 한글 값과 대는 **기하 특성화**다.
extension HwpLineShapeGeometryTests {
    /// Menlo 20pt MS 워드 호환 밑줄 — 축척은 줄 글자 상자 30.27pt, 두께는 그 축척의 획 10u
    static let msWordBoxHeight: CGFloat = 1.513_3 * 20
    static let msWordUnderlineThickness: CGFloat = 1.2

    static func msWordUnderline(
        _ shape: HwpBorderType, length: CGFloat = 200
    ) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: length, thickness: msWordUnderlineThickness,
            scale: .characterLine(fontSize: msWordBoxHeight), placement: .strikethrough
        )
    }

    /// 물결은 X = 3027HWPUNIT의 장치 단위 기하다 (#252) — 띠 round(3027 × 0.113) = 342HWPUNIT, 대각선
    /// 가로·세로 r = round(342 ÷ 12) = 29u, 획 round(29 ÷ 4) = 7u, 반주기 30u, 두 평탄 사이 28u. 위
    /// 평탄은 단선 중심 위 ⌊29/2⌋ + ⌈3 × 7/2⌉ = 25u = 3.00pt다 (한글 위 꼭짓점 3.04pt). r이 홀수라 홀수
    /// 대각선은 위 평탄을 1u 넘는다.
    func testMsWordWaveUsesTheBoxDeviceGeometry() {
        let line = Self.msWordUnderline(.wave)
        let wave = HwpLineShapeGeometry.wave(for: line)
        expect(wave.run).to(beCloseTo(29 * 0.12, within: 1e-9))
        expect(wave.levelGap).to(beCloseTo(28 * 0.12, within: 1e-9))
        expect(wave.halfPeriod).to(beCloseTo(30 * 0.12, within: 1e-9))
        expect(wave.stroke).to(beCloseTo(7 * 0.12, within: 1e-9))
        expect(wave.top).to(beCloseTo(-25 * 0.12, within: 1e-9))
        let extent = HwpLineShapeGeometry.crossExtent(of: line)
        expect(extent?.lowerBound).to(beCloseTo(-26 * 0.12 - 0.42, within: 1e-9))
        expect(extent?.upperBound).to(beCloseTo(4 * 0.12 + 0.42, within: 1e-9))
    }

    /// 2중 물결은 같은 물결을 3w = 21u 아래에 한 번 더 긋는다 (한글: 단일 물결이 2중 물결의 위 파와 같다)
    func testDoubleWaveRepeatsTheWaveThreeStrokesLower() {
        let single = HwpLineShapeGeometry.wave(for: Self.msWordUnderline(.wave))
        let double = HwpLineShapeGeometry.wave(for: Self.msWordUnderline(.doubleWave))
        expect(double.top).to(beCloseTo(single.top, within: 1e-12))
        expect(double.secondOffset.y).to(beCloseTo(21 * 0.12, within: 1e-9))
        expect(double.secondOffset.x) == 0
    }

    /// 대시는 무늬와 획 두께가 같은 축척을 따른다 — Menlo 20pt 긴 점선 밑줄은 무늬 두께
    /// round(3027 × 0.039) = 118HWPUNIT의 긴 선 round(144.2) = 144u의 절반 72u = 8.64pt(한글 72u, #245)에
    /// 획 round(118 ÷ 12) = 10u = 1.2pt (한글 10u, #252)
    func testDashesScaleWithTheBoxAndKeepTheLineThickness() {
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.msWordUnderline(.longDotLine)))
        expect(pieces.count) > 4
        guard let first = pieces.first else { return }
        expect(first.width).to(beCloseTo(72 * 0.12, within: 1e-9))
        expect(first.height).to(beCloseTo(Self.msWordUnderlineThickness, within: 0.001))
    }

    /// 여러 줄은 취소선 자리 — 단선 중심에 가운데. 2중선은 획 7u 두 줄이 중심 사이 21u로 −⌈21/2⌉ =
    /// −11u·+10u에 놓인다 (한글 ±1.26pt·두께 0.84pt — 종전 비례 띠 0.12em은 ±1.36pt·0.91pt).
    func testMultiLineBandsAreCenteredOnTheSingleLine() {
        let stripes = HwpLineShapeGeometry.stripes(for: Self.msWordUnderline(.doubleLine))
        expect(stripes.count) == 2
        guard stripes.count == 2 else { return }
        expect(stripes[0].midY).to(beCloseTo(-11 * 0.12, within: 1e-9))
        expect(stripes[1].midY).to(beCloseTo(10 * 0.12, within: 1e-9))
        for stripe in stripes {
            expect(stripe.height).to(beCloseTo(7 * 0.12, within: 1e-9))
        }
        expect((stripes[0].midY + stripes[1].midY) / 2).to(beCloseTo(-0.06, within: 1e-9))
    }
}
