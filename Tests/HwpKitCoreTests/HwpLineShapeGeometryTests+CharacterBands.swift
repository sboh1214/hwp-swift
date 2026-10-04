import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 한글 문서 글자선의 여러 줄·물결 장치 단위 기하 (#252) — 기대값은 전부 한컴오피스 한글 12.30.0
/// (build 6523, macOS) PDF가 그린 값이다 (2026-10-03, `probes/252`): 글자 아래 밑줄 1~100pt의 부속선
/// 두께와 부속선 중심 사이(u = 0.12pt, 첫 부속선 기준), 물결의 대각선 가로 폭·반주기·획. 띠는 2중선·
/// 물결이 0.113em, 가는+굵은 선·3중선이 0.198em을 HWPUNIT과 장치 단위로 차례로 반올림한 것이다
/// (`HwpLineShapeGeometry+CharacterBands.swift`). 크기는 0.2~4pt의 작은 크기 갈림(2중선·물결의 1u 한
/// 줄, 가는+굵은 선의 굵은 선 하한 3u, 3중선의 굵은 선 0·1·2u와 띠 1u 이하의 1u 한 줄 — 1pt 미만은
/// HWPX로만 저작되지만 한글이 그대로 그린다)과 1u 경계를 지나는 큰 크기를 고른다.
/// 자리는 한글이 쪽 절대 600dpi 격자에서 세어 줄마다 ±1u 흔들리므로 여기서는 띠 안 구성만 본다 — 띠
/// 가운데는 `HwpLineShapeGeometryTests`의 40pt 핀과 홀수 띠 핀(`testOddBandCenterUsesTheFloorHalf`)이
/// 잡는다.
extension HwpLineShapeGeometryTests {
    struct StripeSample {
        let shape: HwpBorderType
        let hwpUnits: CGFloat
        /// 위에서 아래로 부속선 두께 (u)
        let widths: [CGFloat]
        /// 첫 부속선 중심에서 각 부속선 중심까지 (u, 아래가 +)
        let offsets: [CGFloat]

        init(
            _ shape: HwpBorderType, _ hwpUnits: CGFloat, _ widths: [CGFloat], _ offsets: [CGFloat]
        ) {
            self.shape = shape
            self.hwpUnits = hwpUnits
            self.widths = widths
            self.offsets = offsets
        }
    }

    struct WaveSample {
        let hwpUnits: CGFloat
        /// 대각선 가로 폭 = 세로 폭 (u) — nil이면 물결 없이 가로 선 하나
        let run: CGFloat?
        let halfPeriod: CGFloat?
        let stroke: CGFloat

        init(_ hwpUnits: CGFloat, _ run: CGFloat?, _ halfPeriod: CGFloat?, _ stroke: CGFloat) {
            self.hwpUnits = hwpUnits
            self.run = run
            self.halfPeriod = halfPeriod
            self.stroke = stroke
        }
    }

    private static let stripeSamples: [StripeSample] = [
        StripeSample(.doubleLine, 20, [1], [0]),
        StripeSample(.doubleLine, 50, [1], [0]),
        StripeSample(.doubleLine, 90, [1], [0]),
        StripeSample(.doubleLine, 100, [1], [0]),
        StripeSample(.doubleLine, 140, [1], [0]),
        StripeSample(.doubleLine, 149, [1], [0]),
        StripeSample(.doubleLine, 150, [1], [0]),
        StripeSample(.doubleLine, 155, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 200, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 210, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 250, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 300, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 330, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 340, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 400, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 500, [1, 1], [0, 3]),
        StripeSample(.doubleLine, 600, [2, 2], [0, 6]),
        StripeSample(.doubleLine, 700, [2, 2], [0, 6]),
        StripeSample(.doubleLine, 1000, [2, 2], [0, 6]),
        StripeSample(.doubleLine, 1400, [3, 3], [0, 9]),
        StripeSample(.doubleLine, 2000, [5, 5], [0, 15]),
        StripeSample(.doubleLine, 2800, [7, 7], [0, 21]),
        StripeSample(.doubleLine, 4000, [10, 10], [0, 30]),
        StripeSample(.doubleLine, 5600, [13, 13], [0, 39]),
        StripeSample(.doubleLine, 6300, [15, 15], [0, 45]),
        StripeSample(.doubleLine, 8000, [19, 19], [0, 57]),
        StripeSample(.doubleLine, 9900, [23, 23], [0, 69]),
        StripeSample(.doubleLine, 10000, [24, 24], [0, 72]),
        StripeSample(.thinThickDoubleLine, 20, [1], [0]),
        StripeSample(.thinThickDoubleLine, 50, [1], [0]),
        StripeSample(.thinThickDoubleLine, 90, [2], [0]),
        StripeSample(.thinThickDoubleLine, 100, [2], [0]),
        StripeSample(.thinThickDoubleLine, 140, [2], [0]),
        StripeSample(.thinThickDoubleLine, 149, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 150, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 155, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 200, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 210, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 250, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 300, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 330, [1, 3], [0, 3]),
        StripeSample(.thinThickDoubleLine, 340, [1, 4], [0, 4]),
        StripeSample(.thinThickDoubleLine, 400, [1, 5], [0, 4]),
        StripeSample(.thinThickDoubleLine, 500, [2, 4], [0, 5]),
        StripeSample(.thinThickDoubleLine, 600, [2, 6], [0, 6]),
        StripeSample(.thinThickDoubleLine, 700, [3, 6], [0, 8]),
        StripeSample(.thinThickDoubleLine, 1000, [4, 9], [0, 10]),
        StripeSample(.thinThickDoubleLine, 1400, [5, 13], [0, 14]),
        StripeSample(.thinThickDoubleLine, 2000, [8, 17], [0, 20]),
        StripeSample(.thinThickDoubleLine, 2800, [11, 24], [0, 29]),
        StripeSample(.thinThickDoubleLine, 4000, [16, 34], [0, 41]),
        StripeSample(.thinThickDoubleLine, 5600, [23, 46], [0, 58]),
        StripeSample(.thinThickDoubleLine, 6300, [26, 52], [0, 65]),
        StripeSample(.thinThickDoubleLine, 8000, [33, 66], [0, 83]),
        StripeSample(.thinThickDoubleLine, 9900, [40, 83], [0, 101]),
        StripeSample(.thinThickDoubleLine, 10000, [41, 83], [0, 103]),
        StripeSample(.thickThinDoubleLine, 20, [1], [0]),
        StripeSample(.thickThinDoubleLine, 50, [1], [0]),
        StripeSample(.thickThinDoubleLine, 90, [2], [0]),
        StripeSample(.thickThinDoubleLine, 100, [2], [0]),
        StripeSample(.thickThinDoubleLine, 140, [2], [0]),
        StripeSample(.thickThinDoubleLine, 149, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 150, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 155, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 200, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 210, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 250, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 300, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 330, [3, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 340, [4, 1], [0, 3]),
        StripeSample(.thickThinDoubleLine, 400, [5, 1], [0, 4]),
        StripeSample(.thickThinDoubleLine, 500, [4, 2], [0, 5]),
        StripeSample(.thickThinDoubleLine, 600, [6, 2], [0, 6]),
        StripeSample(.thickThinDoubleLine, 700, [6, 3], [0, 7]),
        StripeSample(.thickThinDoubleLine, 1000, [9, 4], [0, 11]),
        StripeSample(.thickThinDoubleLine, 1400, [13, 5], [0, 14]),
        StripeSample(.thickThinDoubleLine, 2000, [17, 8], [0, 21]),
        StripeSample(.thickThinDoubleLine, 2800, [24, 11], [0, 28]),
        StripeSample(.thickThinDoubleLine, 4000, [34, 16], [0, 41]),
        StripeSample(.thickThinDoubleLine, 5600, [46, 23], [0, 57]),
        StripeSample(.thickThinDoubleLine, 6300, [52, 26], [0, 65]),
        StripeSample(.thickThinDoubleLine, 8000, [66, 33], [0, 82]),
        StripeSample(.thickThinDoubleLine, 9900, [83, 40], [0, 102]),
        StripeSample(.thickThinDoubleLine, 10000, [83, 41], [0, 103]),
        StripeSample(.thinThickThinTripleLine, 20, [1], [0]),
        StripeSample(.thinThickThinTripleLine, 50, [1], [0]),
        StripeSample(.thinThickThinTripleLine, 80, [1], [0]),
        StripeSample(.thinThickThinTripleLine, 90, [1, 1], [0, 3]),
        StripeSample(.thinThickThinTripleLine, 100, [1, 1], [0, 3]),
        StripeSample(.thinThickThinTripleLine, 140, [1, 1], [0, 3]),
        StripeSample(.thinThickThinTripleLine, 149, [1, 1, 1], [0, 2, 4]),
        StripeSample(.thinThickThinTripleLine, 150, [1, 1, 1], [0, 2, 4]),
        StripeSample(.thinThickThinTripleLine, 155, [1, 1, 1], [0, 2, 4]),
        StripeSample(.thinThickThinTripleLine, 200, [1, 1, 1], [0, 2, 4]),
        StripeSample(.thinThickThinTripleLine, 210, [1, 2, 1], [0, 3, 5]),
        StripeSample(.thinThickThinTripleLine, 250, [1, 2, 1], [0, 3, 5]),
        StripeSample(.thinThickThinTripleLine, 300, [1, 2, 1], [0, 3, 5]),
        StripeSample(.thinThickThinTripleLine, 330, [1, 2, 1], [0, 3, 5]),
        StripeSample(.thinThickThinTripleLine, 340, [1, 2, 1], [0, 3, 5]),
        StripeSample(.thinThickThinTripleLine, 400, [1, 3, 1], [0, 3, 6]),
        StripeSample(.thinThickThinTripleLine, 500, [1, 4, 1], [0, 4, 7]),
        StripeSample(.thinThickThinTripleLine, 600, [1, 6, 1], [0, 5, 9]),
        StripeSample(.thinThickThinTripleLine, 700, [2, 4, 2], [0, 5, 10]),
        StripeSample(.thinThickThinTripleLine, 1000, [2, 9, 2], [0, 7, 15]),
        StripeSample(.thinThickThinTripleLine, 1400, [3, 11, 3], [0, 10, 20]),
        StripeSample(.thinThickThinTripleLine, 2000, [5, 13, 5], [0, 14, 28]),
        StripeSample(.thinThickThinTripleLine, 2800, [7, 18, 7], [0, 20, 39]),
        StripeSample(.thinThickThinTripleLine, 4000, [11, 22, 11], [0, 28, 55]),
        StripeSample(.thinThickThinTripleLine, 5600, [15, 32, 15], [0, 39, 77]),
        StripeSample(.thinThickThinTripleLine, 6300, [17, 36, 17], [0, 44, 87]),
        StripeSample(.thinThickThinTripleLine, 8000, [22, 44, 22], [0, 55, 110]),
        StripeSample(.thinThickThinTripleLine, 9900, [27, 55, 27], [0, 68, 136]),
        StripeSample(.thinThickThinTripleLine, 10000, [27, 57, 27], [0, 69, 138]),
    ]
    private static let waveSamples: [WaveSample] = [
        WaveSample(20, nil, nil, 1),
        WaveSample(50, nil, nil, 1),
        WaveSample(90, nil, nil, 1),
        WaveSample(100, nil, nil, 1),
        WaveSample(140, nil, nil, 1),
        WaveSample(149, nil, nil, 1),
        WaveSample(150, nil, nil, 1),
        WaveSample(155, 2, 3, 1),
        WaveSample(200, 2, 3, 1),
        WaveSample(210, 2, 3, 1),
        WaveSample(250, 2, 3, 1),
        WaveSample(300, 3, 4, 1),
        WaveSample(330, 3, 4, 1),
        WaveSample(340, 3, 4, 1),
        WaveSample(400, 4, 5, 1),
        WaveSample(500, 5, 6, 1),
        WaveSample(600, 6, 7, 2),
        WaveSample(700, 7, 8, 2),
        WaveSample(1000, 9, 10, 2),
        WaveSample(1400, 13, 14, 3),
        WaveSample(2000, 19, 20, 5),
        WaveSample(2800, 26, 27, 7),
        WaveSample(4000, 38, 39, 10),
        WaveSample(5600, 53, 54, 13),
        WaveSample(6300, 59, 60, 15),
        WaveSample(8000, 75, 76, 19),
        WaveSample(9900, 93, 94, 23),
        WaveSample(10000, 94, 95, 24),
    ]

    /// 글자선 2중선은 장치 단위 정수다 (#252) — 40pt: 띠 round(4000 × 0.113) = 452HWPUNIT → r =
    /// round(452 ÷ 12) = 38u → 획 round(38 ÷ 4) = 10u = 1.2pt 두 줄, 중심 사이 3 × 10u = 3.6pt (한글
    /// 40pt 10u·30u). 띠 가운데는 줄 상자 바닥(단선 위 가장자리 −0.78)에서 ⌊452/2⌋ = 226HWPUNIT 아래
    /// 1.48이고 두 줄은 그 위 ⌈15⌉u·아래 ⌊15⌋u다 — 한글 40pt 아래 밑줄 −6.48/−10.08pt(베이스라인 기준)는
    /// 단선 중심 −6.78에 이 −0.32/3.28을 더한 −6.46/−10.06과 0.02pt 안이다.
    func testCharacterDoubleLineIsInDeviceUnits() {
        let line = Self.characterLine(.doubleLine)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        expect(pieces.count) == 2
        expect(pieces[0].height).to(beCloseTo(1.2, within: 1e-9))
        expect(pieces[1].height).to(beCloseTo(1.2, within: 1e-9))
        expect(pieces[0].midY).to(beCloseTo(1.48 - 1.8, within: 1e-9))
        expect(pieces[1].midY).to(beCloseTo(1.48 + 1.8, within: 1e-9))
        // 홀수 획은 가운데가 반 단위 위로 — 20pt: 띠 226 → r 19u → 획 5u, 줄 −⌈7.5⌉ = −8u·+7u
        let small = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .doubleLine, fontSize: 20, placement: .strikethrough
        )))
        expect(small.map(\.midY)).to(beCloseTo([-0.96, 0.84], within: 1e-9))
        expect(small.map(\.height)).to(beCloseTo([0.6, 0.6], within: 1e-9))
        // 획이 0이 되는 1.54pt 이하는 1u 줄 하나다 (한글 1~1.54pt 실측)
        let tiny = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .doubleLine, fontSize: 1.5, placement: .strikethrough
        )))
        expect(tiny.map(\.height)).to(beCloseTo([0.12], within: 1e-9))
    }

    /// 가는+굵은·굵은+가는·3중선은 띠 0.198em의 장치 단위 정수다 (#252) — 40pt: 띠 792HWPUNIT → E =
    /// 66u, 가는+굵은 [16u, 공백 16u, 34u] = [1.92, 1.92, 4.08], 3중선 [11, 11, 22, 11, 11]u (한글 40pt
    /// 1.92·4.08, 1.32·2.64 — 종전 비례 0.2em은 [2, 2, 4]·[4/3, 8/3]). 작은 크기는 굵은 선에 하한이 있다
    /// (한글 1.49~4pt 0.1pt 간격 실측: 가는+굵은 E = 3·4u → 1/1/3u, 3중선 E = 2·3·4·5u → 굵은 선 0·1·2·2u).
    func testCharacterThickBandsAreInDeviceUnits() {
        let thinThick = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thinThickDoubleLine))
        )
        expect(thinThick.map(\.height)).to(beCloseTo([1.92, 4.08], within: 1e-9))
        expect(thinThick[1].minY - thinThick[0].maxY).to(beCloseTo(1.92, within: 1e-9))
        // 띠 가운데가 줄 상자 바닥 + ⌊792/2⌋HWPUNIT = −0.78 + 3.96, 띠 위 끝이 그 위 33u — 줄 상자 바닥
        expect(thinThick[0].minY).to(beCloseTo(-0.78, within: 1e-9))
        let thickThin = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thickThinDoubleLine))
        )
        expect(thickThin.map(\.height)).to(beCloseTo([4.08, 1.92], within: 1e-9))
        let triple = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thinThickThinTripleLine))
        )
        expect(triple.map(\.height)).to(beCloseTo([1.32, 2.64, 1.32], within: 1e-9))
        expect(triple[2].maxY - triple[0].minY).to(beCloseTo(66 * 0.12, within: 1e-9))
        // 작은 크기 — 2.5pt(E = 4u): 가는+굵은 1/1/3u, 3중선 1/1/2/1/1u
        let smallThin = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickDoubleLine, fontSize: 2.5
        )))
        expect(smallThin.map(\.height)).to(beCloseTo([0.12, 0.36], within: 1e-9))
        let smallTriple = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickThinTripleLine, fontSize: 2.5
        )))
        expect(smallTriple.map(\.height)).to(beCloseTo([0.12, 0.24, 0.12], within: 1e-9))
        // E = 2u(1.4pt)면 3중선은 굵은 선 없이 가는 선 둘, 가는+굵은 선은 2u 한 줄
        let tinyTriple = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickThinTripleLine, fontSize: 1.4
        )))
        expect(tinyTriple.map(\.height)).to(beCloseTo([0.12, 0.12], within: 1e-9))
        let tinyThin = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickDoubleLine, fontSize: 1.4
        )))
        expect(tinyThin.map(\.height)).to(beCloseTo([0.24], within: 1e-9))
    }

    func testCharacterStripesMatchHangul() {
        for sample in Self.stripeSamples {
            let label = "\(sample.shape) \(sample.hwpUnits)"
            let stripes = HwpLineShapeGeometry.stripes(for: Self.characterLine(
                sample.shape, fontSize: sample.hwpUnits / 100, placement: .strikethrough
            ))
            expect(stripes.map { $0.height / 0.12 })
                .to(beCloseTo(sample.widths, within: 1e-6), description: label)
            guard let first = stripes.first else { continue }
            expect(stripes.map { ($0.midY - first.midY) / 0.12 })
                .to(beCloseTo(sample.offsets, within: 1e-6), description: label)
        }
    }

    /// 2중 물결도 같은 물결이다 (한글: 단일 물결이 2중 물결의 위 파와 같다) — 둘째 파는 3 × 획 아래
    func testCharacterWavesMatchHangul() {
        for sample in Self.waveSamples {
            for shape in [HwpBorderType.wave, .doubleWave] {
                let label = "\(shape) \(sample.hwpUnits)"
                let line = Self.characterLine(
                    shape, fontSize: sample.hwpUnits / 100, placement: .strikethrough
                )
                let wave = HwpLineShapeGeometry.wave(for: line)
                expect(wave.stroke / 0.12)
                    .to(beCloseTo(sample.stroke, within: 1e-6), description: label)
                guard let run = sample.run, let halfPeriod = sample.halfPeriod else {
                    expect(wave.straight).to(beTrue(), description: label)
                    let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
                    expect(pieces.count).to(equal(1), description: label)
                    continue
                }
                expect(wave.straight).to(beFalse(), description: label)
                expect(wave.run / 0.12).to(beCloseTo(run, within: 1e-6), description: label)
                expect(wave.halfPeriod / 0.12)
                    .to(beCloseTo(halfPeriod, within: 1e-6), description: label)
                expect(wave.levelGap / 0.12)
                    .to(beCloseTo(2 * (run / 2).rounded(.down), within: 1e-6), description: label)
                expect(wave.secondOffset.y / 0.12)
                    .to(beCloseTo(3 * sample.stroke, within: 1e-6), description: label)
            }
        }
    }

    /// 띠 HWPUNIT이 홀수면 띠 가운데는 ⌊띠/2⌋만큼 줄 상자 바깥이다 — 10pt: 띠 113HWPUNIT → r 9u·획
    /// 2u, 단선 획 3u(0.36pt). 아래 밑줄 M = −0.18 + ⌊113/2⌋/100 = 0.38에서 두 줄이 위 ⌈3⌉u·아래
    /// ⌊3⌋u라 [0.02, 0.74], 위 밑줄은 거울 [−0.74, −0.02], 물결 위 평탄은 M − (⌊9/2⌋ + ⌈3⌉)u = −0.46이다
    /// (⌈띠/2⌉로 두면 0.01pt씩 밀린다 — 한글이 줄마다 ±1u 흔들려 실측으로는 못 가르는 크기라 규칙 핀이다).
    func testOddBandCenterUsesTheFloorHalf() {
        let below = HwpLineShapeGeometry.stripes(for: Self.characterLine(.doubleLine, fontSize: 10))
        expect(below.map(\.midY)).to(beCloseTo([0.02, 0.74], within: 1e-9))
        let above = HwpLineShapeGeometry.stripes(for: Self.characterLine(
            .doubleLine, fontSize: 10, placement: .underlineAbove
        ))
        expect(above.map(\.midY)).to(beCloseTo([-0.74, -0.02], within: 1e-9))
        let wave = HwpLineShapeGeometry.wave(for: Self.characterLine(.wave, fontSize: 10))
        expect(wave.top).to(beCloseTo(-0.46, within: 1e-9))
    }

    /// 무늬 두께가 장치 단위 반올림 상한 밖인 거대한 크기는 반올림 없이 같은 비율이다 — 2중선 띠
    /// 0.113em을 1/4·1/2·1/4로, 물결은 대각선 0.113em·획 그 1/4. 유한하고 순서가 지켜진다.
    func testHugeCharacterBandsFallBackToProportions() {
        let size: CGFloat = 1e14
        let stripes = HwpLineShapeGeometry.stripes(for: Self.characterLine(
            .doubleLine, fontSize: size, length: 100, placement: .strikethrough
        ))
        expect(stripes.count) == 2
        expect(stripes.first?.height).to(beCloseTo(size * 0.113 / 4, within: size * 1e-9))
        expect(stripes.allSatisfy { $0.minY.isFinite && $0.maxY.isFinite }) == true
        let wave = HwpLineShapeGeometry.wave(for: Self.characterLine(
            .wave, fontSize: size, length: 100, placement: .strikethrough
        ))
        expect(wave.run).to(beCloseTo(size * 0.113, within: size * 1e-9))
        expect(wave.stroke).to(beCloseTo(size * 0.113 / 4, within: size * 1e-9))
        expect(wave.straight) == false
        let largest = HwpLineShapeGeometry.stripes(for: Self.characterLine(
            .thinThickThinTripleLine, fontSize: .greatestFiniteMagnitude, length: 100,
            placement: .strikethrough
        ))
        expect(largest.allSatisfy { $0.height.isFinite && $0.midY.isFinite }) == true
    }
}
