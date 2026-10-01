import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 대시(긴 점선·점선·일점쇄선·이점쇄선·긴 파선)의 장치 단위 무늬 (#245) — 기대값은 식이 아니라
/// 한글 12.30.0(build 6446, macOS) PDF 내보내기의 벡터 좌표에서 읽은 선·공백 길이(u = 0.12pt)다
/// (2026-10-01 `probes/245`: 표 셀 테두리 대시 5종 × 표 26 굵기 16단 × 셀 간격 0·283HWPUNIT,
/// 한글 문서 취소선 대시 5종 × 무늬 두께 4~390). 식은 `HwpLineShapeGeometry+Dashes.swift`.
extension HwpLineShapeGeometryTests {
    /// 한 맥락의 대시 세 모양 (선, 공백, u) — 쇄선은 긴 파선의 선·공백과 점선의 점으로 짜인다
    struct DashSample {
        let dotLine: [CGFloat]
        let longDotLine: [CGFloat]
        let longDash: [CGFloat]

        /// 일점쇄선 [긴 선, 공백, 점, 공백]
        var dashDot: [CGFloat] {
            [longDash[0], longDash[1], dotLine[0], longDash[1]]
        }

        /// 이점쇄선 [긴 선, 공백, 점, 공백, 점, 공백]
        var dashDotDot: [CGFloat] {
            dashDot + [dotLine[0], longDash[1]]
        }
    }

    /// 표 26 굵기 하나의 셀 테두리 대시 — 셀 간격이 없는 표(격자)와 있는 표(점 무늬)
    struct BorderDashSample {
        let index: UInt8
        let grid: DashSample
        let dot: DashSample
    }

    /// 글자 크기(HWPUNIT) 하나의 한글 문서 취소선 대시
    struct CharacterDashSample {
        let size: CGFloat
        let dashes: DashSample
    }

    // swiftlint:disable line_length
    /// 한글 PDF의 위 변 대시 (u) — 쇄선 둘도 측정했고 긴 파선·점선에서 짜인 값과 같다
    static let hangulBorderDashes: [BorderDashSample] = [
        BorderDashSample(index: 0, grid: DashSample(dotLine: [3, 4], longDotLine: [17, 9], longDash: [34, 9]), dot: DashSample(dotLine: [3, 5], longDotLine: [17, 10], longDash: [34, 10])),
        BorderDashSample(index: 1, grid: DashSample(dotLine: [4, 6], longDotLine: [20, 12], longDash: [40, 12]), dot: DashSample(dotLine: [4, 6], longDotLine: [20, 12], longDash: [40, 12])),
        BorderDashSample(index: 2, grid: DashSample(dotLine: [5, 7], longDotLine: [26, 14], longDash: [51, 15]), dot: DashSample(dotLine: [5, 8], longDotLine: [25, 16], longDash: [51, 16])),
        BorderDashSample(index: 3, grid: DashSample(dotLine: [7, 10], longDotLine: [34, 21], longDash: [68, 21]), dot: DashSample(dotLine: [7, 11], longDotLine: [34, 20], longDash: [68, 20])),
        BorderDashSample(index: 4, grid: DashSample(dotLine: [9, 13], longDotLine: [43, 27], longDash: [86, 27]), dot: DashSample(dotLine: [9, 14], longDotLine: [43, 26], longDash: [86, 26])),
        BorderDashSample(index: 5, grid: DashSample(dotLine: [10, 15], longDotLine: [52, 29], longDash: [103, 30]), dot: DashSample(dotLine: [10, 15], longDotLine: [51, 30], longDash: [103, 30])),
        BorderDashSample(index: 6, grid: DashSample(dotLine: [14, 21], longDotLine: [69, 42], longDash: [138, 42]), dot: DashSample(dotLine: [14, 21], longDotLine: [69, 42], longDash: [138, 42])),
        BorderDashSample(index: 7, grid: DashSample(dotLine: [17, 25], longDotLine: [86, 51], longDash: [172, 51]), dot: DashSample(dotLine: [17, 26], longDotLine: [86, 52], longDash: [172, 52])),
        BorderDashSample(index: 8, grid: DashSample(dotLine: [21, 31], longDotLine: [104, 62], longDash: [207, 63]), dot: DashSample(dotLine: [21, 32], longDotLine: [103, 62], longDash: [207, 62])),
        BorderDashSample(index: 9, grid: DashSample(dotLine: [24, 36], longDotLine: [121, 72], longDash: [242, 72]), dot: DashSample(dotLine: [24, 36], longDotLine: [121, 72], longDash: [242, 72])),
        BorderDashSample(index: 10, grid: DashSample(dotLine: [35, 52], longDotLine: [173, 105], longDash: [346, 105]), dot: DashSample(dotLine: [35, 53], longDotLine: [173, 104], longDash: [346, 104])),
        BorderDashSample(index: 11, grid: DashSample(dotLine: [52, 78], longDotLine: [259, 156], longDash: [518, 156]), dot: DashSample(dotLine: [52, 78], longDotLine: [259, 156], longDash: [518, 156])),
        BorderDashSample(index: 12, grid: DashSample(dotLine: [69, 103], longDotLine: [347, 206], longDash: [693, 207]), dot: DashSample(dotLine: [69, 104], longDotLine: [346, 208], longDash: [693, 208])),
        BorderDashSample(index: 13, grid: DashSample(dotLine: [104, 156], longDotLine: [520, 311], longDash: [1039, 312]), dot: DashSample(dotLine: [104, 156], longDotLine: [519, 312], longDash: [1039, 312])),
        BorderDashSample(index: 14, grid: DashSample(dotLine: [139, 208], longDotLine: [693, 417], longDash: [1386, 417]), dot: DashSample(dotLine: [139, 209], longDotLine: [693, 416], longDash: [1386, 416])),
        BorderDashSample(index: 15, grid: DashSample(dotLine: [173, 259], longDotLine: [866, 519], longDash: [1732, 519]), dot: DashSample(dotLine: [173, 260], longDotLine: [866, 520], longDash: [1732, 520])),
    ]

    /// 한글 문서 취소선 대시 (u) — 크기는 무늬 두께 T = round(크기 × 0.039)가 4·5·7·8·12·13·20·21·
    /// 28·30·39·45·52·60·78·90·99·113·118·132·156·170·198·230·264·284·312·340·370·390인 글자 크기다.
    /// T 30은 1.5b = 5.5u, T 45는 b = 5.5u인 동점이고(둘 다 올린다), T 20 이하는 하한이 걸린다.
    static let hangulCharacterDashes: [CharacterDashSample] = [
        CharacterDashSample(size: 102, dashes: DashSample(dotLine: [1, 4], longDotLine: [5, 2], longDash: [10, 2])),
        CharacterDashSample(size: 128, dashes: DashSample(dotLine: [1, 4], longDotLine: [5, 2], longDash: [10, 2])),
        CharacterDashSample(size: 179, dashes: DashSample(dotLine: [1, 4], longDotLine: [5, 2], longDash: [10, 2])),
        CharacterDashSample(size: 205, dashes: DashSample(dotLine: [1, 4], longDotLine: [5, 2], longDash: [10, 2])),
        CharacterDashSample(size: 307, dashes: DashSample(dotLine: [1, 4], longDotLine: [7, 4], longDash: [15, 4])),
        CharacterDashSample(size: 333, dashes: DashSample(dotLine: [2, 4], longDotLine: [8, 4], longDash: [16, 4])),
        CharacterDashSample(size: 512, dashes: DashSample(dotLine: [2, 4], longDotLine: [12, 8], longDash: [24, 8])),
        CharacterDashSample(size: 538, dashes: DashSample(dotLine: [3, 5], longDotLine: [13, 8], longDash: [26, 8])),
        CharacterDashSample(size: 718, dashes: DashSample(dotLine: [3, 5], longDotLine: [17, 10], longDash: [34, 10])),
        CharacterDashSample(size: 769, dashes: DashSample(dotLine: [4, 6], longDotLine: [18, 12], longDash: [37, 12])),
        CharacterDashSample(size: 1000, dashes: DashSample(dotLine: [5, 8], longDotLine: [24, 14], longDash: [48, 14])),
        CharacterDashSample(size: 1154, dashes: DashSample(dotLine: [6, 9], longDotLine: [27, 16], longDash: [55, 16])),
        CharacterDashSample(size: 1333, dashes: DashSample(dotLine: [6, 9], longDotLine: [32, 20], longDash: [64, 20])),
        CharacterDashSample(size: 1538, dashes: DashSample(dotLine: [7, 11], longDotLine: [36, 22], longDash: [73, 22])),
        CharacterDashSample(size: 2000, dashes: DashSample(dotLine: [10, 15], longDotLine: [47, 28], longDash: [95, 28])),
        CharacterDashSample(size: 2307, dashes: DashSample(dotLine: [11, 17], longDotLine: [55, 34], longDash: [110, 34])),
        CharacterDashSample(size: 2538, dashes: DashSample(dotLine: [12, 18], longDotLine: [60, 36], longDash: [121, 36])),
        CharacterDashSample(size: 2897, dashes: DashSample(dotLine: [14, 21], longDotLine: [69, 42], longDash: [138, 42])),
        CharacterDashSample(size: 3025, dashes: DashSample(dotLine: [14, 21], longDotLine: [72, 44], longDash: [144, 44])),
        CharacterDashSample(size: 3384, dashes: DashSample(dotLine: [16, 24], longDotLine: [80, 48], longDash: [161, 48])),
        CharacterDashSample(size: 4000, dashes: DashSample(dotLine: [19, 29], longDotLine: [95, 58], longDash: [191, 58])),
        CharacterDashSample(size: 4359, dashes: DashSample(dotLine: [21, 32], longDotLine: [104, 62], longDash: [208, 62])),
        CharacterDashSample(size: 5077, dashes: DashSample(dotLine: [24, 36], longDotLine: [121, 72], longDash: [242, 72])),
        CharacterDashSample(size: 5897, dashes: DashSample(dotLine: [28, 42], longDotLine: [140, 84], longDash: [281, 84])),
        CharacterDashSample(size: 6769, dashes: DashSample(dotLine: [32, 48], longDotLine: [161, 96], longDash: [323, 96])),
        CharacterDashSample(size: 7282, dashes: DashSample(dotLine: [35, 53], longDotLine: [173, 104], longDash: [347, 104])),
        CharacterDashSample(size: 8000, dashes: DashSample(dotLine: [38, 57], longDotLine: [190, 114], longDash: [381, 114])),
        CharacterDashSample(size: 8718, dashes: DashSample(dotLine: [42, 63], longDotLine: [208, 124], longDash: [416, 124])),
        CharacterDashSample(size: 9487, dashes: DashSample(dotLine: [45, 68], longDotLine: [226, 136], longDash: [452, 136])),
        CharacterDashSample(size: 10000, dashes: DashSample(dotLine: [48, 72], longDotLine: [238, 144], longDash: [477, 144])),
    ]
    // swiftlint:enable line_length

    /// 대시 무늬를 장치 단위로 — 요소가 모두 정수 장치 단위인지도 본다
    static func deviceUnits(_ line: HwpLineShapeGeometry.Line) -> [CGFloat] {
        HwpLineShapeGeometry.dashPattern(for: line).map { length in
            let units = length / 0.12
            expect(abs(units - units.rounded())).to(beLessThan(1e-9))
            return units.rounded()
        }
    }

    static func expectDashes(
        _ line: (HwpBorderType) -> HwpLineShapeGeometry.Line, match sample: DashSample,
        _ label: String
    ) {
        let expectations: [(HwpBorderType, [CGFloat])] = [
            (.dotLine, sample.dotLine), (.longDotLine, sample.longDotLine),
            (.longDash, sample.longDash), (.dashDot, sample.dashDot),
            (.dashDotDot, sample.dashDotDot),
        ]
        for (shape, units) in expectations {
            let actual = Self.deviceUnits(line(shape))
            expect(actual).to(equal(units), description: "\(label) \(shape)")
        }
    }

    /// 40pt 글자선(무늬 두께 156HWPUNIT, 단위 19.07u) — 점 19u·공백 round(28.5) = 29u, 긴 선 191u·
    /// 공백 2·round(28.6) = 58u (한글 12.30 PDF 그대로, #245). 반올림 전 비례(0.057em = 19u, 긴
    /// 선 190u·공백 57u)와 갈린다.
    func testCharacterDashPatternsFollowTheDeviceUnitTable() {
        let expectations: [(HwpBorderType, [CGFloat])] = [
            (.dotLine, [19, 29]),
            (.dashDot, [191, 58, 19, 58]),
            (.dashDotDot, [191, 58, 19, 58, 19, 58]),
            (.longDash, [191, 58]),
        ]
        for (shape, units) in expectations {
            let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(shape)))
            var x: CGFloat = 0
            for (index, length) in units.enumerated() {
                if index % 2 == 0 {
                    let piece = pieces[index / 2]
                    expect(piece.minX).to(beCloseTo(x, within: 1e-9), description: "\(shape)")
                    expect(piece.width).to(beCloseTo(length * 0.12, within: 1e-9))
                }
                x += length * 0.12
            }
        }
    }

    /// 셀 간격이 없는 표의 5mm 테두리(무늬 두께 1417HWPUNIT, 단위 173.19u): 점선 173u·⌊259.5⌋ =
    /// 259u, 긴 점선 ⌈1732/2⌉ = 866u·3 × 173 = 519u, 획 두께 round(118.08) = 118u (한글 그대로,
    /// #245 — 반올림 전 비례는 20.79pt = 173.2u 단위라 주기마다 밀린다).
    func testBorderDashesRoundTheTwentyTwoFifteenthsUnitToDeviceUnits() {
        let thickness = 5 * 72 / 25.4
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .dotLine, thickness: thickness, length: 300
        )))
        expect(pieces[0].width).to(beCloseTo(173 * 0.12, within: 1e-9))
        expect(pieces[1].minX).to(beCloseTo(432 * 0.12, within: 1e-9))
        expect(pieces[0].minY).to(beCloseTo(-118 * 0.12 / 2, within: 1e-9))
        expect(pieces[0].height).to(beCloseTo(118 * 0.12, within: 1e-9))
        let long = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .longDotLine, thickness: thickness, length: 300
        )))
        expect(long[0].width).to(beCloseTo(866 * 0.12, within: 1e-9))
        expect(long[1].minX).to(beCloseTo(1385 * 0.12, within: 1e-9))
    }

    /// 표 셀 테두리 대시 5종 × 굵기 16단 × 셀 간격 0·있음 — 한글 PDF와 요소마다 같다. 단 구분선은
    /// 셀 간격이 있는 표와 같은 점 무늬다 (한글 단 구분선 68표본 모두).
    func testBorderDashesMatchHangulForEveryThickness() {
        expect(Self.hangulBorderDashes.count) == 16
        for sample in Self.hangulBorderDashes {
            let thickness = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: sample.index))
            let label = "\(CoreHwp.HwpBorderFill.borderThicknessMillimeters[Int(sample.index)])mm"
            func line(
                _ shape: HwpBorderType, spaced: Bool, divider: Bool
            ) -> HwpLineShapeGeometry.Line {
                HwpLineShapeGeometry.Line(
                    shape: shape, length: 400, thickness: thickness, scale: .border,
                    placement: divider ? .divider : .border, inSpacedTable: spaced
                )
            }
            let grid = { line($0, spaced: false, divider: false) }
            let spaced = { line($0, spaced: true, divider: false) }
            let divider = { line($0, spaced: false, divider: true) }
            Self.expectDashes(grid, match: sample.grid, label)
            Self.expectDashes(spaced, match: sample.dot, label)
            Self.expectDashes(divider, match: sample.dot, label)
        }
    }

    /// 표 셀 테두리·단 구분선의 실선·대시 획은 장치 단위로 반올림한 두께다 — 한글 PDF의 획 폭이 굵기
    /// 16단에서 2·3·4·5·6·7·9·12·14·17·24·35·47·71·95·118u (가로·세로 변·단 구분선 모두). 글자선의
    /// 획은 반올림하지 않는다.
    func testBorderStrokesRoundToDeviceUnits() {
        let hangul: [CGFloat] = [2, 3, 4, 5, 6, 7, 9, 12, 14, 17, 24, 35, 47, 71, 95, 118]
        for (index, units) in hangul.enumerated() {
            let thickness = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: UInt8(index)))
            for shape: HwpBorderType in [.line, .longDash, .single3D] {
                let line = Self.borderLine(shape, thickness: thickness)
                let band = HwpLineShapeGeometry.crossExtent(of: line)
                expect(band?.lowerBound).to(beCloseTo(-units * 0.12 / 2, within: 1e-9))
                expect(band?.upperBound).to(beCloseTo(units * 0.12 / 2, within: 1e-9))
            }
            expect(HwpLineShapeGeometry.borderStrokeThickness(thickness))
                .to(beCloseTo(units * 0.12, within: 1e-9), description: "index \(index)")
        }
        let character = Self.characterLine(.longDash, fontSize: 10)
        expect(HwpLineShapeGeometry.crossExtent(of: character)?.upperBound)
            .to(beCloseTo(0.2, within: 1e-9))
    }

    /// 한글 문서 글자선 대시는 무늬 두께 T = round(글자 크기 HWPUNIT × 39/1000)의 식이다 — 하한(점 1u,
    /// 긴 선 10u, 점선 공백 4u)과 0.5u 동점(T 30·45)까지 한글 PDF와 같다. 쇄선 둘은 T 4·9·14·39 표본.
    func testCharacterDashesMatchHangulAcrossSizes() {
        for sample in Self.hangulCharacterDashes {
            Self.expectDashes(
                { Self.characterLine($0, fontSize: sample.size / 100, placement: .strikethrough) },
                match: sample.dashes, "\(sample.size)HU"
            )
        }
        for (size, dashDot) in [
            (CGFloat(102), [CGFloat(10), 2, 1, 2]), (230, [11, 4, 1, 4]), (359, [17, 6, 2, 6]),
            (1000, [48, 14, 5, 14]),
        ] {
            let line = Self.characterLine(.dashDot, fontSize: size / 100)
            expect(Self.deviceUnits(line)).to(equal(dashDot), description: "\(size)HU")
        }
    }

    /// 0.5u 동점은 올린다 — b의 배수를 정수 두께 × (22 × 배수) ÷ 180 한 번의 나눗셈으로 셈해 동점을
    /// 정확히 가른다. T 30(1.5b = 5.5u → 공백 12u)·T 45(b = 5.5u → 점 6u)는 반올림 방향을 잠그고,
    /// T 315(b = 38.5u)·T 330(1.5b = 60.5u)은 22/15를 이진 소수로 곱하면 38.4999…·60.4999…로 내려가
    /// 점 38u·공백 120u가 되는 자리다 — 한글 12.30 PDF는 쇄선 385·116·39·116u(8077HU)와 긴 파선
    /// 403·122u·점선 40·60u·긴 점선 201·122u(8461HU)로 올린다 (2026-10-01 `probes/245`).
    func testDashUnitTiesRoundUp() {
        expect(HwpLineShapeGeometry.dashDeviceUnits(for: .longDash, hwpUnits: 30, grid: false))
            == [37, 12]
        expect(HwpLineShapeGeometry.dashDeviceUnits(for: .dotLine, hwpUnits: 45, grid: false))
            == [6, 9]
        expect(HwpLineShapeGeometry.dashDeviceUnits(for: .dotLine, hwpUnits: 45, grid: true))
            == [6, 9]
        expect(HwpLineShapeGeometry.dashDeviceUnits(for: .dashDot, hwpUnits: 315, grid: false))
            == [385, 116, 39, 116]
        expect(HwpLineShapeGeometry.dashDeviceUnits(for: .longDash, hwpUnits: 330, grid: false))
            == [403, 122]
        // 글자선 경로도 같은 자리에서 — 한글 실측 글자 크기 80.77pt·84.61pt
        for (size, shape, units) in [
            (CGFloat(8077), HwpBorderType.dashDotDot, [CGFloat(385), 116, 39, 116, 39, 116]),
            (8461, .dotLine, [40, 60]), (8461, .longDotLine, [201, 122]),
        ] {
            let line = Self.characterLine(shape, fontSize: size / 100, placement: .strikethrough)
            expect(Self.deviceUnits(line)).to(equal(units), description: "\(size)HU \(shape)")
        }
    }

    /// 표 26 굵기가 아닌 두께(테두리 정보가 없는 표의 0.5pt 등)는 HWPUNIT으로 반올림한 두께로 푼다 —
    /// 0.5pt = 50HWPUNIT: 단위 6.11u → 격자 점선 6·9u, 획 round(4.17) = 4u
    func testNonTableThicknessUsesItsOwnHwpUnits() {
        expect(HwpLineShapeGeometry.borderPatternHwpUnits(thickness: 0.5)) == 50
        expect(Self.deviceUnits(Self.borderLine(.dotLine, thickness: 0.5))) == [6, 9]
        expect(HwpLineShapeGeometry.borderStrokeThickness(0.5)).to(beCloseTo(0.48, within: 1e-9))
        // 표 26 굵기는 한글의 표 값 — 0.12mm는 반올림한 34가 아니라 33HWPUNIT이다
        let twelve = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: 1))
        expect(HwpLineShapeGeometry.borderPatternHwpUnits(thickness: twelve)) == 33
        expect((twelve * 100).rounded()) == 34
    }

    /// 장치 단위 반올림 상한(`deviceRoundingLimit`) 밖 두께는 반올림 전 비율(두께 × 22/15의 배수)이고
    /// 획도 그대로다 — 곱이 넘치지 않는다
    func testHugeThicknessFallsBackToProportionalDashes() {
        let thickness: CGFloat = 3e12
        let line = Self.borderLine(.longDotLine, thickness: thickness, length: 1e15)
        let unit = thickness / 15 * 22
        let pattern = HwpLineShapeGeometry.dashPattern(for: line)
        expect(pattern.count) == 2
        expect(pattern.first).to(beCloseTo(unit * 5, within: unit * 1e-12))
        expect(pattern.last).to(beCloseTo(unit * 3, within: unit * 1e-12))
        expect(HwpLineShapeGeometry.strokeThickness(for: line)) == thickness
    }
}
