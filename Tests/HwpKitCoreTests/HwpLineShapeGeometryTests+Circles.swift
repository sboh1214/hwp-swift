import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 원형 점선의 원 크기·간격 (#239) — 한글 12.30.0 build 6446의 PDF 내보내기(2026-09-27,
/// `probes/239`)에서 읽은 값을 고정한다. 한글은 원을 600dpi 장치 단위(u = 0.12pt)의 정수로 그리고,
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
    /// 20·40·80pt). 밑줄도 같은 크기에서 같다 (줄 글자 기본 크기, 217표본).
    static let characterCircleSamples: [CircleSample] = [
        .init(100, 5, 2), .init(320, 5, 2), .init(322, 6, 2), .init(500, 6, 2),
        .init(524, 6, 2), .init(526, 8, 4), .init(700, 8, 4), .init(730, 8, 4),
        .init(731, 10, 4), .init(935, 10, 4), .init(936, 13, 6), .init(1000, 13, 6),
        .init(1141, 13, 6), .init(1142, 15, 6), .init(1200, 15, 6), .init(1371, 15, 6),
        .init(1372, 18, 8), .init(1576, 18, 8), .init(1577, 20, 8), .init(1600, 20, 8),
        .init(2000, 25, 10), .init(2192, 25, 10), .init(2193, 28, 12), .init(2423, 28, 12),
        .init(2424, 30, 12), .init(4000, 48, 20), .init(4088, 48, 20), .init(4090, 50, 20),
        .init(4730, 55, 22), .init(4732, 58, 24), .init(6602, 78, 32), .init(6604, 80, 32),
        .init(8000, 95, 38), .init(8704, 103, 42), .init(8706, 105, 42), .init(10000, 120, 48),
    ]

    /// 단 구분선 원형 점선의 표 26 굵기 index별 간격·경로 지름 (0.1~5mm) — 점 무늬다
    static let dividerCircleSamples: [CircleSample] = [
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
    /// 0u(글자 1.14pt 이하, 두께 0HWPUNIT)에서도 간격 5u·칠 지름 3u(한글 1pt 실측과 같다), 격자는
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
    }

    /// 한글 2007 호환 문서의 글자선 원은 장치 단위 반올림 밖의 고정 pt 그대로다 (#227)
    func testHwp2007CirclesKeepTheirFixedSize() {
        let line = Self.hwp2007Line(.circle)
        expect(HwpLineShapeGeometry.circlePitch(for: line)) == 3.0
        expect(HwpLineShapeGeometry.circleDiameter(for: line)) == 1.32
    }
}
