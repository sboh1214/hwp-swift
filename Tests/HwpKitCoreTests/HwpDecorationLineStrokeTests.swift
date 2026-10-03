import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 장식선 획 두께의 장치 단위 규칙 (#252) — 한글은 실선·대시 장식선의 획을 기준 크기 X(HWPUNIT
/// 정수)에서 max(1, round(round(X × 39/1000) ÷ 12))u(u = 0.12pt, 0.5 올림)로 긋는다. 기대값은 전부
/// 한컴오피스 한글 12.30.0 (build 6523, macOS) PDF가 그린 획이다 (2026-10-03, `probes/252`).
final class HwpDecorationLineStrokeTests: XCTestCase {
    private struct MsWordSample {
        let face: String
        let size: CGFloat
        /// 한글 저장본 줄 캐시의 `vertsize` (HWPUNIT) — 줄 글자 상자의 높이
        let vertsize: CGFloat
        let units: Int
    }

    /// 한글 문서 실선 취소선 (글자 크기 HWPUNIT, 한글 획 u) — 1~3pt와, 무늬 두께 t가 12k + 5인
    /// 가장 큰 크기·12k + 6인 가장 작은 크기의 0.01pt 이웃 쌍 (k = 1…33). 쌍마다 획이 1u 갈린다:
    /// 무늬 두께를 HWPUNIT으로 반올림하지 않으면(t = 12k + 5.5 근처) 둘째 크기가 내려가고, 0.5를
    /// 짝수로 보내면 홀수 k의 둘째 크기가 내려간다. 같은 크기의 실선 아래·위 밑줄과 점선·긴 점선
    /// 취소선도 전부 같은 획이다 (각 79·79·158표본).
    private static let boundarySamples: [(hwpUnits: CGFloat, units: Int)] = [
        (100, 1), (120, 1), (140, 1), (141, 1), (142, 1), (160, 1), (180, 1), (200, 1), (220, 1),
        (240, 1), (260, 1), (280, 1), (300, 1), (448, 1), (449, 2), (756, 2), (757, 3), (1064, 3),
        (1065, 4), (1371, 4), (1372, 5), (1679, 5), (1680, 6), (1987, 6), (1988, 7), (2294, 7),
        (2295, 8), (2602, 8), (2603, 9), (2910, 9), (2911, 10), (3217, 10), (3218, 11), (3525, 11),
        (3526, 12), (3833, 12), (3834, 13), (4141, 13), (4142, 14), (4448, 14), (4449, 15),
        (4756, 15), (4757, 16), (5064, 16), (5065, 17), (5371, 17), (5372, 18), (5679, 18),
        (5680, 19), (5987, 19), (5988, 20), (6294, 20), (6295, 21), (6602, 21), (6603, 22),
        (6910, 22), (6911, 23), (7217, 23), (7218, 24), (7525, 24), (7526, 25), (7833, 25),
        (7834, 26), (8141, 26), (8142, 27), (8448, 27), (8449, 28), (8756, 28), (8757, 29),
        (9064, 29), (9065, 30), (9371, 30), (9372, 31), (9679, 31), (9680, 32), (9987, 32),
        (9988, 33), (10294, 33), (10295, 34),
    ]

    func testStrokeMatchesHangulAtEveryRoundingBoundary() {
        for sample in Self.boundarySamples {
            let size = sample.hwpUnits / 100
            let stroke = CGFloat(sample.units) * 0.12
            expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: size))
                .to(beCloseTo(stroke, within: 1e-9), description: "\(size)pt")
        }
    }

    /// 이슈의 대표 표본 — 종전 연속값(0.04em)과 #176이 읽은 `round(크기 ÷ 3)`u가 둘 다 틀리는 자리
    /// (56·80pt는 `round(크기 ÷ 3)`이면 19·27u, 0.04em이면 2.24·3.20pt). 1.02·1.28pt 취소선은 무늬
    /// 두께 4·5로 반올림하면 0u지만 한글은 1u를 긋는다.
    func testRepresentativeSizesFromTheIssue() {
        let samples: [(size: CGFloat, stroke: CGFloat)] = [
            (1.02, 0.12), (1.28, 0.12), (5, 0.24), (10, 0.36), (56, 2.16), (80, 3.12),
            (93.59, 3.60), (100, 3.96),
        ]
        for sample in samples {
            expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: sample.size))
                .to(beCloseTo(sample.stroke, within: 1e-9), description: "\(sample.size)pt")
        }
    }

    /// MS 워드 호환 문서의 밑줄은 줄 글자 상자의 높이(한글 줄 캐시 `vertsize`)가 기준이다 — 글꼴
    /// 11종의 5~100pt 아래 밑줄 193표본이 모두 그 높이에 같은 식을 넣은 값이다 (아래는 그 가운데
    /// 종전 0.05 cell을 반올림하면 갈리는 표본 위주). 상자는 높이가 그 `vertsize`가 되도록 짓는다.
    func testMsWordUnderlineUsesTheTextBoxHeight() {
        let samples = [
            MsWordSample(face: "함초롬바탕", size: 5, vertsize: 846, units: 3),
            MsWordSample(face: "함초롬바탕", size: 10, vertsize: 1692, units: 6),
            MsWordSample(face: "함초롬바탕", size: 36, vertsize: 6089, units: 20),
            MsWordSample(face: "함초롬바탕", size: 80, vertsize: 13531, units: 44),
            MsWordSample(face: "Apple SD 산돌고딕 Neo", size: 80, vertsize: 12477, units: 41),
            MsWordSample(face: "Times New Roman", size: 10, vertsize: 1152, units: 4),
            MsWordSample(face: "Times New Roman", size: 36, vertsize: 4144, units: 14),
            MsWordSample(face: "Helvetica", size: 80, vertsize: 9407, units: 31),
            MsWordSample(face: "Courier New", size: 10, vertsize: 1134, units: 4),
            MsWordSample(face: "Baskerville", size: 80, vertsize: 13586, units: 44),
            MsWordSample(face: "Menlo", size: 10, vertsize: 1515, units: 5),
            MsWordSample(face: "HY울릉도M", size: 5, vertsize: 650, units: 2),
        ]
        for sample in samples {
            let label = "\(sample.face) \(sample.size)pt"
            let height = sample.vertsize / 100
            let box = HwpMsWordLineBox(lineHeight: height, baseline: height * 0.8)
            expect(box.cellHeight * HwpRenderTuning.Text.msWordLineHeightCellRatio)
                .to(beCloseTo(height, within: 1e-9), description: label)
            let expected = CGFloat(sample.units) * 0.12
            expect(HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box).thickness)
                .to(beCloseTo(expected, within: 1e-9), description: label)
            expect(HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box).thickness)
                .to(beCloseTo(expected, within: 1e-9), description: label)
        }
    }

    /// MS 워드 호환 문서의 취소선은 글자 모양 기본 크기가 기준이다 — 상자(글꼴)와 무관하다
    /// (한글: 함초롬바탕·Times New Roman 취소선 80표본, 라틴 글꼴 5종 55표본 모두 크기의 식).
    func testMsWordStrikethroughUsesTheBaseSize() {
        for cell in [CGFloat(1.3), 1.15, 0.9] {
            let box = HwpMsWordLineBox(
                winAscent: cell * 0.8, winDescent: cell * 0.2, lineGap: 0, isCJK: true
            ).scaled(by: 80)
            let strike = HwpDecorationLineGeometry.msWordStrikethrough(
                runBox: box, thicknessFontSize: 80
            )
            expect(strike.thickness).to(beCloseTo(3.12, within: 1e-9), description: "cell \(cell)")
        }
    }

    /// 실선과 대시는 같은 크기에서 같은 획이다 — 대시 띠(`HwpLineShapeGeometry.solidBand`)가 장식선
    /// 기하가 낸 두께를 그대로 쓰므로 렌더러가 실선을 채우는 두께와 같다 (한글 12.30: 실선 + 대시 5종
    /// 크기 10단 60표본이 크기마다 한 값).
    func testDashBandsUseTheSameStrokeAsSolidLines() {
        for size in [CGFloat(5), 10, 20, 56, 80] {
            let line = HwpDecorationLineGeometry.strikethrough(
                fontSize: size, thicknessFontSize: size
            )
            let shapes: [HwpBorderType] = [.longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash]
            for shape in shapes {
                let band = HwpLineShapeGeometry.solidBand(for: HwpLineShapeGeometry.Line(
                    shape: shape, length: 100, thickness: line.thickness,
                    scale: .characterLine(fontSize: size), placement: .strikethrough
                ))
                expect(band.height)
                    .to(beCloseTo(line.thickness, within: 1e-12), description: "\(size)pt")
            }
        }
    }

    /// 0 이하·NaN은 선이 없고(0), 무늬 두께가 장치 단위 반올림 상한 밖이면 반올림 전 무늬 두께
    /// (글자 크기 × 0.039)다 — 무한대도 넘치지 않고 그대로 간다. 아주 작은 양수는 1u다.
    func testDegenerateSizes() {
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: 0)) == 0
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: -10)) == 0
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: .nan)) == 0
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: 1e-9))
            .to(beCloseTo(0.12, within: 1e-12))
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: .infinity)) == .infinity
        let huge: CGFloat = 1e15
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: huge))
            .to(beCloseTo(huge / 1000 * 39, within: huge * 1e-12))
        let largest = HwpDecorationLineGeometry.strokeThickness(
            referenceSize: .greatestFiniteMagnitude
        )
        expect(largest.isFinite) == true
    }
}
