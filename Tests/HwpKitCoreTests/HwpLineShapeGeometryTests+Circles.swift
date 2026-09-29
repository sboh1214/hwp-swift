import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 원형 점선의 원 크기·간격 (#239·#243) — 한글 12.30.0 build 6446의 PDF 내보내기(2026-09-27~28,
/// `probes/239`·`probes/243`)에서 읽은 값을 고정한다. 한글은 원을 600dpi 장치 단위(u = 0.12pt)의 정수로 그리고,
/// 경로를 채운 뒤 1u 윤곽을 둘러 칠하므로 칠 지름 = 경로 지름 + 1u다. 아래 표의 간격·경로 지름은
/// PDF의 원 중심 차와 원 경로 상자 폭 그대로다 (윤곽 제외).
extension HwpLineShapeGeometryTests {
    /// 실측 한 점 — 입력(글자 크기 HWPUNIT 또는 표 26 굵기 index)과 한글의 간격·경로 지름 (u)
    struct CircleSample {
        let input: Int
        let pitch: Int
        let path: Int

        init(_ input: Int, _ pitch: Int, _ path: Int) {
            self.input = input
            self.pitch = pitch
            self.path = path
        }
    }

    /// 한글 문서 원형 점선 취소선의 크기별 간격·경로 지름 — 점 단위가 바뀌는 크기의 양쪽(1~100pt
    /// 1,010표본 가운데 전환점 둘레는 0.01~0.02pt 간격으로 쟀다)과 이슈의 표본 크기(5·7·10·12·16·
    /// 20·40·80pt). 밑줄도 7pt 이상에서 같은 크기면 같다 (줄 글자 기본 크기, 217표본 — 7pt 미만
    /// 표본은 한 줄의 7pt 꼬리표가 기준 크기라 7pt 값이었다). 8064/8065·14987/14988은
    /// 점 단위가 정확히 38.5u·71.5u가 되는 동점(두께 315·585HWPUNIT)이다 — 한글은 올리고, 22/15를
    /// 이진 소수로 곱하면 내려간다 (0.01pt 간격 42표본).
    static let characterCircleSamples: [CircleSample] = [
        .init(100, 5, 2), .init(320, 5, 2), .init(322, 6, 2), .init(500, 6, 2),
        .init(524, 6, 2), .init(526, 8, 4), .init(700, 8, 4), .init(730, 8, 4),
        .init(731, 10, 4), .init(935, 10, 4), .init(936, 13, 6), .init(1000, 13, 6),
        .init(1141, 13, 6), .init(1142, 15, 6), .init(1200, 15, 6), .init(1371, 15, 6),
        .init(1372, 18, 8), .init(1576, 18, 8), .init(1577, 20, 8), .init(1600, 20, 8),
        .init(2000, 25, 10), .init(2192, 25, 10), .init(2193, 28, 12), .init(2423, 28, 12),
        .init(2424, 30, 12), .init(4000, 48, 20), .init(4088, 48, 20), .init(4090, 50, 20),
        .init(4730, 55, 22), .init(4732, 58, 24), .init(6602, 78, 32), .init(6604, 80, 32),
        .init(8000, 95, 38), .init(8064, 95, 38), .init(8065, 98, 40), .init(8704, 103, 42),
        .init(8706, 105, 42), .init(10000, 120, 48), .init(14987, 178, 72), .init(14988, 180, 72),
    ]

    /// 단 구분선 원형 점선의 표 26 굵기 index별 간격·경로 지름 (0.1~5mm) — 점 무늬다
    static let dividerCircleSamples: [CircleSample] = [
        .init(0, 8, 4), .init(1, 10, 4), .init(2, 13, 6), .init(3, 18, 8),
        .init(4, 23, 10), .init(5, 25, 10), .init(6, 35, 14), .init(7, 43, 18),
        .init(8, 53, 22), .init(9, 60, 24), .init(10, 88, 36), .init(11, 130, 52),
        .init(12, 173, 70), .init(13, 260, 104), .init(14, 348, 140), .init(15, 433, 174),
    ]

    /// 셀 간격이 있는 표의 셀 테두리 원형 점선 굵기 index별 간격·경로 지름 (#243, `probes/243`
    /// `so243-widths`: 셀 간격 283HWPUNIT 가로 변 360pt, 셀 간격 1HWPUNIT 네 변) — 단 구분선과 같은
    /// 점 무늬다. 값이 `dividerCircleSamples`와 같은 것은 따로 잰 결과이지 옮겨 적은 것이 아니다.
    static let spacedCellCircleSamples: [CircleSample] = [
        .init(0, 8, 4), .init(1, 10, 4), .init(2, 13, 6), .init(3, 18, 8),
        .init(4, 23, 10), .init(5, 25, 10), .init(6, 35, 14), .init(7, 43, 18),
        .init(8, 53, 22), .init(9, 60, 24), .init(10, 88, 36), .init(11, 130, 52),
        .init(12, 173, 70), .init(13, 260, 104), .init(14, 348, 140), .init(15, 433, 174),
    ]

    /// 표 셀 테두리 원형 점선(가로 변 400pt·세로 변 250pt, 칸 간격 없음)의 굵기 index별 간격·경로
    /// 지름 — 두께를 장치 단위로 반올림한 격자다 (4mm는 1134HWPUNIT = 94.5u → 95u)
    static let cellCircleSamples: [CircleSample] = [
        .init(0, 4, 2), .init(1, 6, 4), .init(2, 8, 4), .init(3, 10, 6),
        .init(4, 12, 6), .init(5, 14, 8), .init(6, 18, 10), .init(7, 24, 12),
        .init(8, 28, 14), .init(9, 34, 18), .init(10, 48, 24), .init(11, 70, 36),
        .init(12, 94, 48), .init(13, 142, 72), .init(14, 190, 96), .init(15, 236, 118),
    ]

    static let deviceUnit = HwpRenderTuning.LineShape.deviceUnit

    func testCharacterCirclesFollowHangulDeviceRounding() {
        for sample in Self.characterCircleSamples {
            let line = Self.characterLine(
                .circle, fontSize: CGFloat(sample.input) / 100, length: 100,
                placement: .strikethrough
            )
            let label = "\(sample.input)HWPUNIT"
            expect(HwpLineShapeGeometry.circlePitch(for: line)).to(
                beCloseTo(CGFloat(sample.pitch) * Self.deviceUnit, within: 1e-9), description: label
            )
            expect(HwpLineShapeGeometry.circleDiameter(for: line)).to(
                beCloseTo(CGFloat(sample.path + 1) * Self.deviceUnit, within: 1e-9),
                description: label
            )
        }
    }

    /// 무늬 축척은 밑줄·취소선·글자 위 밑줄과 두께 입력에 기대지 않는다 — 글자 크기만 본다
    func testCharacterCirclesIgnorePlacementAndThickness() {
        let reference = Self.characterLine(.circle, fontSize: 12)
        for placement in [HwpLineShapeGeometry.Placement.strikethrough, .underlineAbove] {
            var line = reference
            line.placement = placement
            line.thickness = 5
            expect(HwpLineShapeGeometry.circlePitch(for: line))
                == HwpLineShapeGeometry.circlePitch(for: reference)
            expect(HwpLineShapeGeometry.circleDiameter(for: line))
                == HwpLineShapeGeometry.circleDiameter(for: reference)
        }
    }

    func testDividerCirclesUseTheDotPatternOfCharacterLines() {
        for sample in Self.dividerCircleSamples {
            let thickness = CoreHwp.HwpBorderFill.borderThicknessPoints(at: UInt8(sample.input))
            let line = HwpLineShapeGeometry.Line(
                shape: .circle, length: 100, thickness: CGFloat(thickness),
                scale: .border, placement: .divider
            )
            let label = "index \(sample.input)"
            expect(HwpLineShapeGeometry.circlePitch(for: line)).to(
                beCloseTo(CGFloat(sample.pitch) * Self.deviceUnit, within: 1e-9), description: label
            )
            expect(HwpLineShapeGeometry.circleDiameter(for: line)).to(
                beCloseTo(CGFloat(sample.path + 1) * Self.deviceUnit, within: 1e-9),
                description: label
            )
        }
    }

    func testCellCirclesRoundTheThicknessToAGrid() {
        for sample in Self.cellCircleSamples {
            let thickness = CoreHwp.HwpBorderFill.borderThicknessPoints(at: UInt8(sample.input))
            let line = Self.borderLine(.circle, thickness: CGFloat(thickness))
            let label = "index \(sample.input)"
            expect(HwpLineShapeGeometry.circlePitch(for: line)).to(
                beCloseTo(CGFloat(sample.pitch) * Self.deviceUnit, within: 1e-9), description: label
            )
            expect(HwpLineShapeGeometry.circleDiameter(for: line)).to(
                beCloseTo(CGFloat(sample.path + 1) * Self.deviceUnit, within: 1e-9),
                description: label
            )
        }
    }

    /// 셀 간격이 있는 표의 셀 테두리는 격자가 아니라 단 구분선의 점 무늬다 (#243) — 한글은 셀 간격
    /// 1HWPUNIT(0.01pt)부터 이 갈래다. 같은 두께의 셀 간격 없는 표 셀 테두리보다 원이 크고 성기다
    /// (1mm: 간격 88u·경로 36u vs 48u·24u).
    func testSpacedCellCirclesUseTheDotPatternOfDividers() {
        for sample in Self.spacedCellCircleSamples {
            let thickness = CoreHwp.HwpBorderFill.borderThicknessPoints(at: UInt8(sample.input))
            var line = Self.borderLine(.circle, thickness: CGFloat(thickness))
            line.inSpacedTable = true
            let label = "index \(sample.input)"
            expect(HwpLineShapeGeometry.circleUsesCellGrid(line)).to(beFalse(), description: label)
            expect(HwpLineShapeGeometry.circlePitch(for: line)).to(
                beCloseTo(CGFloat(sample.pitch) * Self.deviceUnit, within: 1e-9), description: label
            )
            expect(HwpLineShapeGeometry.circleDiameter(for: line)).to(
                beCloseTo(CGFloat(sample.path + 1) * Self.deviceUnit, within: 1e-9),
                description: label
            )
        }
        // 1mm 셀 간격 없는 표는 여전히 격자 — 같은 입력에서 셀 간격만 가른다
        let thickness = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: 10))
        let grid = Self.borderLine(.circle, thickness: thickness)
        expect(HwpLineShapeGeometry.circleUsesCellGrid(grid)) == true
        expect(HwpLineShapeGeometry.circlePitch(for: grid)).to(beCloseTo(5.76, within: 1e-9))
    }

    /// 셀 간격 표시는 표 셀 테두리의 원만 바꾼다 — 글자선·단 구분선 원과 대시·여러 줄·물결 경로는
    /// 그대로다 (한글 12.30 실측: 셀 간격 0·1·283 표의 여러 줄·물결·2중 물결 벡터가 같다; 대시는
    /// 한글이 장치 단위로 반올림하는 식이 셀 간격에 따라 한 주기에 1u쯤 갈리지만 여기서는 두 경우
    /// 모두 같은 비례 경로다 — `Sources/HwpKitCore/AGENTS.md`의 남은 격차)
    func testSpacedTableFlagLeavesOtherLinesAlone() {
        var character = Self.characterLine(.circle, fontSize: 12)
        let characterPitch = HwpLineShapeGeometry.circlePitch(for: character)
        character.inSpacedTable = true
        expect(HwpLineShapeGeometry.circlePitch(for: character)) == characterPitch
        var divider = HwpLineShapeGeometry.Line(
            shape: .circle, length: 100, thickness: 2.8346, scale: .border, placement: .divider
        )
        let dividerPitch = HwpLineShapeGeometry.circlePitch(for: divider)
        divider.inSpacedTable = true
        expect(HwpLineShapeGeometry.circlePitch(for: divider)) == dividerPitch
        let shapes = (0 ... 17).compactMap(HwpBorderType.init(rawValue:)).filter { $0 != .circle }
        expect(shapes.count) == 17
        for shape in shapes {
            let grid = Self.borderLine(shape, thickness: 2.8346)
            var spaced = grid
            spaced.inSpacedTable = true
            let gridPieces = Self.pieces(HwpLineShapeGeometry.path(for: grid))
            expect(Self.pieces(HwpLineShapeGeometry.path(for: spaced)))
                .to(equal(gridPieces), description: "\(shape)")
        }
    }

    /// `line-shapes` 픽스처의 run 끝 표본 R1(원형 점선 밑줄 'A' 5자)·R2(취소선 14자)를 한글 PDF의
    /// run 길이(함초롬바탕 10pt 'A' 진행 폭 7.0796pt × 글자 수)로 그리면 원의 개수·자리가 한글과
    /// 같다 — R1 원 23개(마지막 중심 34.32), R2 64개(98.28), 간격 1.56pt(13u). 반올림하지 않던 간격
    /// 1.425pt로는 25·70개였다. 글꼴 폭이 섞이지 않도록 한글의 run 길이를 그대로 넣는다.
    func testLineShapesRunEndSamplesMatchHangulAtItsRunLengths() {
        let advance: CGFloat = 7.0796
        for (count, placement, circles, last) in [
            (5, HwpLineShapeGeometry.Placement.underlineBelow, 23, 34.32),
            (14, .strikethrough, 64, 98.28),
        ] {
            let line = Self.characterLine(
                .circle, fontSize: 10, length: advance * CGFloat(count), placement: placement
            )
            let centers = Self.pieces(HwpLineShapeGeometry.path(for: line)).map(\.midX)
            expect(centers.count) == circles
            expect(centers.last).to(beCloseTo(last, within: 1e-9))
            for (index, center) in centers.enumerated() {
                expect(center).to(beCloseTo(CGFloat(index) * 1.56, within: 1e-9))
            }
        }
    }

    /// 아주 작은 입력도 원이 한 단위 윤곽보다 작아지거나 간격이 0이 되지 않는다 — 점 무늬는 점 단위
    /// 0u(글자 1.15pt 이하 — 1pt는 두께 4HWPUNIT, 0.001pt는 0HWPUNIT)에서도 간격 5u·칠 지름 3u(한글
    /// 1pt 실측과 같다), 격자는
    /// r 1u로 간격 2u·칠 지름 3u다 (표 26 최소 0.1mm는 r 2u라 문서에서는 닿지 않는다)
    func testTinyInputsKeepTheMinimumCircle() {
        for fontSize: CGFloat in [1, 0.001] {
            let line = Self.characterLine(.circle, fontSize: fontSize)
            expect(HwpLineShapeGeometry.circlePitch(for: line)).to(beCloseTo(0.6, within: 1e-9))
            expect(HwpLineShapeGeometry.circleDiameter(for: line)).to(beCloseTo(0.36, within: 1e-9))
        }
        let divider = HwpLineShapeGeometry.Line(
            shape: .circle, length: 10, thickness: 0.001, scale: .border, placement: .divider
        )
        expect(HwpLineShapeGeometry.circlePitch(for: divider)).to(beCloseTo(0.6, within: 1e-9))
        expect(HwpLineShapeGeometry.circleDiameter(for: divider)).to(beCloseTo(0.36, within: 1e-9))
        let cell = Self.borderLine(.circle, thickness: 0.001, length: 10)
        expect(HwpLineShapeGeometry.circlePitch(for: cell)).to(beCloseTo(0.24, within: 1e-9))
        expect(HwpLineShapeGeometry.circleDiameter(for: cell)).to(beCloseTo(0.36, within: 1e-9))
        expect(Self.pieces(HwpLineShapeGeometry.path(for: cell)).count) == 42
        // 셀 간격이 있는 표의 셀 테두리는 점 무늬의 최솟값 (#243)
        var spaced = cell
        spaced.inSpacedTable = true
        expect(HwpLineShapeGeometry.circlePitch(for: spaced)).to(beCloseTo(0.6, within: 1e-9))
        expect(HwpLineShapeGeometry.circleDiameter(for: spaced)).to(beCloseTo(0.36, within: 1e-9))
    }

    /// 한글 2007 호환 문서의 글자선 원은 장치 단위 반올림 밖의 고정 pt 그대로다 (#227)
    func testHwp2007CirclesKeepTheirFixedSize() {
        let line = Self.hwp2007Line(.circle)
        expect(HwpLineShapeGeometry.circlePitch(for: line)) == 3.0
        expect(HwpLineShapeGeometry.circleDiameter(for: line)) == 1.32
    }
}
