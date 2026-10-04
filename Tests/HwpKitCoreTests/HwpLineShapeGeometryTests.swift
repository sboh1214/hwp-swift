import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 선 모양 기하(`HwpLineShapeGeometry`)를 한글 12.30.0 실측값에 고정한다 (#191). 값의
/// 근거는 `HwpRenderTuning.LineShape`의 doc-comment — 글자선은 5·10·20·40·80pt, 테두리는
/// 0.1~5mm 스윕을 PDF 벡터(0.12pt 단위)로 읽은 것이다. 여기서는 로컬 좌표(x = 선 방향,
/// y = 가로지르는 축, 0 = 단선 중심, 양수 = 아래)의 경로 조각 경계 상자로 잰다.
final class HwpLineShapeGeometryTests: XCTestCase {
    /// 경로의 닫힌 조각(사각형·평행사변형·원)마다 경계 상자 — x 순으로 정렬
    static func pieces(_ path: CGPath?) -> [CGRect] {
        guard let path else { return [] }
        var boxes: [CGRect] = []
        var points: [CGPoint] = []
        func flush() {
            guard let first = points.first else { return }
            var box = CGRect(origin: first, size: .zero)
            for point in points {
                box = box.union(CGRect(origin: point, size: .zero))
            }
            boxes.append(box)
            points = []
        }
        path.applyWithBlock { element in
            let kind = element.pointee.type
            let count = switch kind {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            case .closeSubpath: 0
            @unknown default: 0
            }
            if kind == .moveToPoint {
                flush()
            }
            for index in 0 ..< count {
                points.append(element.pointee.points[index])
            }
            if kind == .closeSubpath {
                flush()
            }
        }
        flush()
        return boxes.sorted { $0.minX < $1.minX || ($0.minX == $1.minX && $0.minY < $1.minY) }
    }

    static func characterLine(
        _ shape: HwpBorderType, fontSize: CGFloat = 40, length: CGFloat = 400,
        placement: HwpLineShapeGeometry.Placement = .underlineBelow
    ) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: length,
            thickness: HwpDecorationLineGeometry.strokeThickness(referenceSize: fontSize),
            scale: .characterLine(fontSize: fontSize), placement: placement
        )
    }

    static func borderLine(
        _ shape: HwpBorderType, thickness: CGFloat, length: CGFloat = 200
    ) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: length, thickness: thickness, scale: .border, placement: .border
        )
    }

    // MARK: - 실선·없음·3D

    func testSolidLineIsOneBandCenteredOnZero() {
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(.line)))
        expect(pieces.count) == 1
        // 40pt 획 13u = 1.56pt (#252)
        expect(pieces.first).to(equal(CGRect(x: 0, y: -0.78, width: 400, height: 1.56)))
    }

    func testNoneAndDegenerateLinesHaveNoPath() {
        expect(HwpLineShapeGeometry.path(for: Self.characterLine(.none))).to(beNil())
        expect(HwpLineShapeGeometry.path(for: Self.characterLine(.dotLine, length: 0))).to(beNil())
        expect(HwpLineShapeGeometry.path(for: Self.borderLine(.wave, thickness: 0))).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: Self.characterLine(.none))).to(beNil())
    }

    /// 3D 넷은 한글 macOS가 아무것도 그리지 않지만 실선으로 대체한다 (사라지는 것보다 낫다) —
    /// 테두리 실선처럼 획 두께를 장치 단위로 반올림한다 (2pt = 200HWPUNIT → 17u = 2.04pt, #245).
    func test3DShapesFallBackToSolid() {
        for shape in [HwpBorderType.thick3D, .thick3DReverse, .single3D, .single3DReverse] {
            let pieces = Self.pieces(
                HwpLineShapeGeometry.path(for: Self.borderLine(shape, thickness: 2))
            )
            expect(pieces.count) == 1
            expect(pieces.first?.minX) == 0
            expect(pieces.first?.width) == 200
            expect(pieces.first?.minY).to(beCloseTo(-1.02, within: 1e-9))
            expect(pieces.first?.height).to(beCloseTo(2.04, within: 1e-9))
        }
    }

    // MARK: - 대시 (실측: 80pt 긴 점선 190/114u, 5mm 테두리 점선 173/259u — 장치 단위 식은 `+Dashes`)

    func testCharacterLongDotDashesAreFiveAndThreeUnits() {
        // 80pt: 무늬 두께 312HWPUNIT → 단위 38.13u, 긴 선 381u → 선 ⌊381/2⌋ = 190u = 22.8,
        // 공백 2·round(57.2) = 114u = 13.68 (한글 190u/114u)
        let line = Self.characterLine(.longDotLine, fontSize: 80, length: 200)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        expect(pieces.count) == 6 // 36.48 주기 → 0, 36.48, …, 182.4 (마지막은 잘린다)
        expect(pieces[0].minX) == 0
        expect(pieces[0].width).to(beCloseTo(22.8, within: 0.001))
        expect(pieces[1].minX).to(beCloseTo(36.48, within: 0.001))
        expect(pieces[5].maxX).to(beCloseTo(200, within: 0.001))
        for piece in pieces {
            // 획 26u = 3.12pt (#252 — 한글 80pt 26u)
            expect(piece.minY).to(beCloseTo(-1.56, within: 0.001))
            expect(piece.height).to(beCloseTo(3.12, within: 0.001))
        }
    }

    // MARK: - 원형 점선

    func testCharacterCirclesRoundToDeviceUnits() {
        // 20pt: 두께 78HWPUNIT → 점 단위 10u, 칠 지름 = 경로 10u + 윤곽 1u = 1.32pt, 간격 10 + 15 =
        // 25u = 3.0pt, 첫 원 중심 = run 시작 (한글 PDF: 경로 10u·간격 25u, #239)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .circle, fontSize: 20, length: 99.12
        )))
        expect(pieces[0].width).to(beCloseTo(1.32, within: 0.001))
        expect(pieces[0].height).to(beCloseTo(1.32, within: 0.001))
        expect(pieces[0].midX).to(beCloseTo(0, within: 0.001))
        expect(pieces[0].midY).to(beCloseTo(0, within: 0.001))
        expect(pieces[1].midX).to(beCloseTo(3.0, within: 0.001))
        // 중심이 선 끝 앞인 마지막 원은 끝에 걸쳐도 온전히 그린다 (#235) — 0, 3.0, …, 99.0
        expect(pieces.count) == 34
        expect(pieces.last?.midX).to(beCloseTo(99.0, within: 0.001))
        expect(pieces.last?.maxX).to(beCloseTo(99.66, within: 0.001))
    }

    func testBorderCirclesRoundTheThicknessToDeviceUnits() {
        // 1mm(2.835pt = 283HWPUNIT → r 24u): 칠 지름 = 경로 24u + 윤곽 1u = 3.0, 간격 2r = 48u =
        // 5.76, 첫 중심 = 선 시작 (한글 PDF: 경로 24u·간격 48u)
        let thickness = 72 / 25.4
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .circle, thickness: thickness, length: 100
        )))
        expect(pieces[0].width).to(beCloseTo(3.0, within: 0.001))
        expect(pieces[0].midX).to(beCloseTo(0, within: 0.001))
        expect(pieces[1].midX).to(beCloseTo(5.76, within: 0.001))
        let cross = HwpLineShapeGeometry.crossExtent(
            of: Self.borderLine(.circle, thickness: thickness)
        )
        expect(cross?.lowerBound).to(beCloseTo(-1.5, within: 1e-9))
        expect(cross?.upperBound).to(beCloseTo(1.5, within: 1e-9))
    }

    // MARK: - 여러 줄

    /// 취소선은 띠 가운데가 단선 중심이고, 글자 위 밑줄은 띠 가운데가 줄 상자 상단(단선 띠의 아래
    /// 가장자리)에서 띠 절반 위다 (#252 — 40pt 가는+굵은 위 밑줄: 가운데 0.78 − 3.96 = −3.18, 띠 66u가
    /// [−7.14, 0.78] — 한글 40pt +41.04/+36.12pt 중심은 단선 중심 34.78에서 −6.26·−1.34라 모델의
    /// −6.18·−1.26과 쪽 격자 흔들림 1u 안이다).
    func testMultiLinePlacementFollowsTheDecorationKind() {
        let centered = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .doubleLine, placement: .strikethrough
        )))
        expect(centered[0].minY).to(beCloseTo(-2.4, within: 1e-9))
        expect(centered[1].maxY).to(beCloseTo(2.4, within: 1e-9))
        let above = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickDoubleLine, placement: .underlineAbove
        )))
        expect(above[1].maxY).to(beCloseTo(0.78, within: 1e-9))
        expect(above[0].minY).to(beCloseTo(-7.14, within: 1e-9))
        expect(above.map(\.midY)).to(beCloseTo([-6.18, -1.26], within: 1e-9))
    }

    /// 테두리 여러 줄은 두께 띠 안에 든다 — 4mm(11.34pt) 가는+굵은: 2.83 / 2.83 공백 / 5.67,
    /// 모서리(0)에 중심 (한글 23·23·49u, 띠 35.5~130.5u가 모서리 83u 중심)
    func testBorderMultiLineBandIsThicknessCenteredOnEdge() {
        let thickness = 4 * 72 / 25.4
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .thinThickDoubleLine, thickness: thickness
        )))
        expect(pieces.count) == 2
        expect(pieces[0].minY).to(beCloseTo(-thickness / 2, within: 0.001))
        expect(pieces[0].height).to(beCloseTo(thickness / 4, within: 0.001))
        expect(pieces[1].minY).to(beCloseTo(0, within: 0.001))
        expect(pieces[1].maxY).to(beCloseTo(thickness / 2, within: 0.001))
    }

    // MARK: - 물결

    /// 글자선 물결은 장치 단위 정수의 45° 지그재그다 (#252) — 40pt: 띠 452HWPUNIT → 대각선 가로·세로
    /// r = 38u = 4.56pt, 반주기 r + 1 = 39u = 4.68pt, 획 round(38 ÷ 4) = 10u = 1.2pt. 띠 가운데(줄 상자
    /// 바닥 + 226HWPUNIT = 1.48)에서 ⌊38/2⌋ + ⌈3 × 10/2⌉ = 34u 위가 위 평탄 −2.60이다 (한글 40pt 아래
    /// 밑줄: 위 평탄 베이스라인 아래 4.20pt = 단선 중심 −6.78 + 2.60 − 0.02, 대각선 38u·반주기 39u·획 10u).
    func testCharacterWaveIsFortyFiveDegreeZigzagAboveTheLine() {
        let line = Self.characterLine(.wave, length: 30)
        let extent = HwpLineShapeGeometry.crossExtent(of: line)
        expect(extent?.lowerBound).to(beCloseTo(-2.6 - 0.6, within: 1e-9))
        expect(extent?.upperBound).to(beCloseTo(-2.6 + 4.56 + 0.6, within: 1e-9))
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        // 첫 대각선: x 0~4.56, y −2.6~1.96 (획 반폭 0.6의 평행사변형이라 상자는 0.6/√2만큼 크다)
        let corner = 0.6 / 2.0.squareRoot()
        let first = try? XCTUnwrap(pieces.first)
        expect(first?.minX).to(beCloseTo(-corner, within: 1e-9))
        expect(first?.maxX).to(beCloseTo(4.56 + corner, within: 1e-9))
        expect(first?.minY).to(beCloseTo(-2.6 - corner, within: 1e-9))
        expect(first?.maxY).to(beCloseTo(1.96 + corner, within: 1e-9))
        // 반주기 = 대각선 + 1u 평탄 → 둘째 대각선은 4.68에서 시작한다
        let diagonals = pieces.filter { $0.height > 2 }
        expect(diagonals[1].minX).to(beCloseTo(4.68 - corner, within: 1e-9))
    }

    /// 물결 가운데도 여러 줄과 같은 자리다 — 취소선은 단선 중심, 글자 위 밑줄은 줄 상자 상단(+0.78)에서
    /// 226HWPUNIT 위인 −1.48에서 34u 위가 위 평탄이다 (#252 — 한글 build 6523 S·T 각 25크기 일치).
    func testWaveTopFollowsTheBandCenterByDecorationKind() {
        let strike = HwpLineShapeGeometry.crossExtent(
            of: Self.characterLine(.wave, placement: .strikethrough)
        )
        expect(strike?.lowerBound).to(beCloseTo(-4.08 - 0.6, within: 1e-9))
        let above = HwpLineShapeGeometry.crossExtent(
            of: Self.characterLine(.wave, placement: .underlineAbove)
        )
        expect(above?.lowerBound).to(beCloseTo(-1.48 - 4.08 - 0.6, within: 1e-9))
    }

    /// 2중 물결의 둘째 파는 같은 물결을 3 × 획 = 30u 아래에 긋는다 (한글 실측: 단일 물결은 2중 물결의 위
    /// 파와 같고 둘째 파는 3w 아래 — 149크기 모두). 홀수 r(20pt 19u)이면 홀수 대각선이 위 평탄을 1u
    /// 넘어 올라간다.
    func testCharacterDoubleWaveOffsetsTheSecondWaveDown() {
        let extent = HwpLineShapeGeometry.crossExtent(of: Self.characterLine(.doubleWave))
        expect(extent?.lowerBound).to(beCloseTo(-3.2, within: 1e-9))
        expect(extent?.upperBound).to(beCloseTo(-2.6 + 4.56 + 3.6 + 0.6, within: 1e-9))
        let odd = HwpLineShapeGeometry.wave(for: Self.characterLine(
            .wave, fontSize: 20, placement: .strikethrough
        ))
        expect(odd.run).to(beCloseTo(19 * 0.12, within: 1e-9))
        expect(odd.levelGap).to(beCloseTo(18 * 0.12, within: 1e-9))
        expect(odd.stroke).to(beCloseTo(5 * 0.12, within: 1e-9))
        expect(odd.top).to(beCloseTo(-(9 + 8) * 0.12, within: 1e-9))
        expect(odd.centerRange.lowerBound).to(beCloseTo(-(9 + 8 + 1) * 0.12, within: 1e-9))
    }

    /// 테두리 물결: 진폭·반주기 = 두께, 획 = 두께/4, 꼭짓점 띠 [−7/8, +1/8] 두께 (−y 쪽으로
    /// 3/8 치우침, 한글 4mm 실측 71~167u 대 모서리 83u); 2중 물결은 (3/4, 3/4) 옮긴 파를 더해
    /// [−7/8, +7/8] 대칭 — 둘째 파의 내려가는 획이 첫 파의 내려가는 획과 한 직선에 놓여
    /// 마름모 격자를 이룬다 (한글 4mm 실측: 둘째 파 첫 꼭짓점이 첫 파 시작 + 3t/4)
    func testBorderWaveShiftsTowardNegativeCross() {
        let thickness: CGFloat = 8
        let wave = HwpLineShapeGeometry.crossExtent(
            of: Self.borderLine(.wave, thickness: thickness)
        )
        expect(wave?.lowerBound).to(beCloseTo(-7 - 1, within: 0.001))
        expect(wave?.upperBound).to(beCloseTo(1 + 1, within: 0.001))
        let double = HwpLineShapeGeometry.crossExtent(
            of: Self.borderLine(.doubleWave, thickness: thickness)
        )
        expect(double?.lowerBound).to(beCloseTo(-8, within: 0.001))
        expect(double?.upperBound).to(beCloseTo(7 + 1, within: 0.001))
        let pieces = Self.pieces(HwpLineShapeGeometry.path(
            for: Self.borderLine(.doubleWave, thickness: thickness, length: 40)
        ))
        // 둘째 파의 첫 대각선은 x = 3/4 두께 = 6에서 시작한다 (45° 평행사변형이라 상자는 획
        // 반폭/√2만큼 왼쪽으로 나간다) — 첫 파의 **첫** 내려가는 획(x 0~8, y −7~1)과 같은
        // 직선 y − x = −7 위라 마름모 격자가 된다
        let diagonals = pieces.filter { $0.height > 4 }
        let corner = 1 / 2.0.squareRoot()
        let first = try? XCTUnwrap(diagonals.first { abs($0.minX + corner) < 0.01 })
        let second = try? XCTUnwrap(diagonals.first { abs($0.minX - (6 - corner)) < 0.01 })
        expect(first).toNot(beNil())
        expect(second).toNot(beNil())
        expect(second?.minY).to(beCloseTo(-7 + 6 - corner, within: 0.01))
        expect((second?.minY ?? 0) - (second?.minX ?? 0))
            .to(beCloseTo((first?.minY ?? 1) - (first?.minX ?? 1), within: 0.01))
        expect(diagonals.contains { abs($0.minX - (2 - corner)) < 0.01 }) == false
        // 둘째 파의 시작(3t/4)이 길이 밖이면 둘째 파는 그리지 않는다 (강제 대각선 없음)
        let short = Self.pieces(HwpLineShapeGeometry.path(
            for: Self.borderLine(.doubleWave, thickness: thickness, length: 5)
        )).filter { $0.height > 4 }
        expect(short.count) == 1
        expect(HwpLineShapeGeometry.alongExtent(
            of: Self.borderLine(.doubleWave, thickness: thickness, length: 5)
        )?.upperBound).to(beCloseTo(8 + corner, within: 0.001))
    }

    // MARK: - 글자 모양 값 변환

    func testCharacterLineShapeMapsToBorderTypeByPlusOne() {
        expect(HwpBorderType(characterLineShape: 0)) == .line
        expect(HwpBorderType(characterLineShape: 1)) == .longDotLine
        expect(HwpBorderType(characterLineShape: 11)) == .wave
        expect(HwpBorderType(characterLineShape: 15)) == .single3D
        expect(HwpBorderType(characterLineShape: 16)) == .line
        expect(HwpBorderType(characterLineShape: -1)) == .line
    }
}

// MARK: - 단 구분선·넘침·비정상 입력

extension HwpLineShapeGeometryTests {
    /// 단 구분선의 2중 물결은 둘째 파를 선 방향으로 옮기지 않는다 (한글 3mm 실측: 두 파의
    /// 꼭짓점이 같은 y에서 시작) — 가로지르는 축 이동은 테두리와 같은 3/4 두께
    func testDividerDoubleWaveKeepsBothWavesInPhase() {
        let line = HwpLineShapeGeometry.Line(
            shape: .doubleWave, length: 40, thickness: 8, scale: .border, placement: .divider
        )
        let offset = HwpLineShapeGeometry.doubleWaveOffset(for: line)
        expect(offset.x) == 0
        expect(offset.y).to(beCloseTo(6, within: 0.001))
        let starts = Self.pieces(HwpLineShapeGeometry.path(for: line))
            .filter { $0.height > 4 }.map(\.minX).filter { $0 < 0 }
        expect(starts.count) == 2
        expect(HwpLineShapeGeometry.crossExtent(of: line)?.upperBound)
            .to(beCloseTo(8, within: 0.001))
    }

    /// 물결은 `length` 앞에서 시작한 마지막 반주기를 자르지 않고 끝까지 그린다 (한글 실측:
    /// 40pt 밑줄 51.03반주기 → 대각선 52개, 3mm 구분선 → 4개) — `alongExtent`가 그 넘침을
    /// 보고하고, 대시는 종전대로 `length`에서 잘린다
    func testWaveCompletesTheLastHalfPeriodPastTheLength() {
        // 두께 8 → 반주기 8.12; 길이 20 → ceil(20 / 8.12) = 3개, 끝 = 3 × 8.12 − 0.12 = 24.24
        let border = Self.borderLine(.wave, thickness: 8, length: 20)
        let diagonals = Self.pieces(HwpLineShapeGeometry.path(for: border))
            .filter { $0.height > 4 }
        expect(diagonals.count) == 3
        expect(diagonals.last?.maxX).to(beCloseTo(24.24 + 1 / 2.0.squareRoot(), within: 0.01))
        expect(diagonals.last?.width).to(beCloseTo(8 + 2 / 2.0.squareRoot(), within: 0.01))
        // 선 방향 범위는 넘침에 획 모서리(1/√2)를 양 끝에 더한 것
        expect(HwpLineShapeGeometry.alongExtent(of: border)?.lowerBound)
            .to(beCloseTo(-1 / 2.0.squareRoot(), within: 0.001))
        expect(HwpLineShapeGeometry.alongExtent(of: border)?.upperBound)
            .to(beCloseTo(24.24 + 1 / 2.0.squareRoot(), within: 0.001))
        // 40pt 글자선 400pt: 반주기 4.68 → 400 / 4.68 = 85.47 → 86개, 끝 = 85 × 4.68 + 4.56 =
        // 402.36 (잘랐다면 400에서 멈춘다)
        let character = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(.wave)))
            .filter { $0.height > 2 }
        expect(character.count) == 86
        expect(character.last?.maxX).to(beCloseTo(402.36 + 0.6 / 2.0.squareRoot(), within: 0.01))
        // 대시·실선은 길이 그대로
        let dashed = Self.borderLine(.longDash, thickness: 8, length: 20)
        expect(HwpLineShapeGeometry.alongExtent(of: dashed)?.upperBound)
            .to(beCloseTo(20, within: 0.001))
        expect(Self.pieces(HwpLineShapeGeometry.path(for: dashed)).last?.maxX)
            .to(beCloseTo(20, within: 0.001))
    }

    /// 원형 점선은 첫 원의 중심이 선 시작이라 반지름만큼 앞으로 나간다 — `alongExtent`가 그
    /// 몫을 보고해야 히트 띠가 첫 원을 다 덮는다 (#191 리뷰). 첫 원의 중심 0은 어떤 양수 길이보다
    /// 앞이라 반지름보다 짧은 선도 그 원 하나는 그린다 — 글자선·단 구분선(#235)도, 표 셀
    /// 테두리(#238 — 이은 선의 끝 규칙)도.
    func testCircleAlongExtentStartsHalfADiameterBeforeTheLine() {
        // 표 셀 테두리 4pt(r 33u): 칠 지름 35u = 4.2 (반지름 2.1), 간격 66u = 7.92
        let border = Self.borderLine(.circle, thickness: 4, length: 196)
        let along = HwpLineShapeGeometry.alongExtent(of: border)
        expect(along?.lowerBound).to(beCloseTo(-2.1, within: 0.001))
        // 중심 0 … 190.08 (198.0은 끝 뒤) — 마지막 원이 192.18에서 끝나 뒤는 선 끝 그대로
        expect(along?.upperBound).to(beCloseTo(196, within: 0.001))
        expect(HwpLineShapeGeometry.path(for: border)?.boundingBoxOfPath.minX)
            .to(beCloseTo(-2.1, within: 0.001))
        expect(HwpLineShapeGeometry.path(for: border)?.boundingBoxOfPath.maxX)
            .to(beCloseTo(192.18, within: 0.001))
        let character = Self.characterLine(.circle, fontSize: 20)
        expect(HwpLineShapeGeometry.alongExtent(of: character)?.lowerBound)
            .to(beCloseTo(-0.66, within: 0.001))
        let short = Self.borderLine(.circle, thickness: 4, length: 1.5)
        expect(Self.pieces(HwpLineShapeGeometry.path(for: short)).count) == 1
        for extent in [
            HwpLineShapeGeometry.alongExtent(of: short),
            HwpLineShapeGeometry.crossExtent(of: short),
        ] {
            expect(extent?.lowerBound).to(beCloseTo(-2.1, within: 1e-9))
            expect(extent?.upperBound).to(beCloseTo(2.1, within: 1e-9))
        }
        // 반지름보다 짧은 길이도 원 하나
        let one = Self.borderLine(.circle, thickness: 4, length: 2)
        expect(Self.pieces(HwpLineShapeGeometry.path(for: one)).count) == 1
        // 단 구분선 4pt는 점 무늬 — 점 단위 49u, 칠 지름 51u = 6.12 (반지름 3.06)
        let shortDivider = HwpLineShapeGeometry.Line(
            shape: .circle, length: 1.5, thickness: 4, scale: .border, placement: .divider
        )
        let dividerPieces = Self.pieces(HwpLineShapeGeometry.path(for: shortDivider))
        expect(dividerPieces.count) == 1
        expect(dividerPieces.first?.minX).to(beCloseTo(-3.06, within: 1e-9))
        expect(dividerPieces.first?.width).to(beCloseTo(6.12, within: 1e-9))
        expect(dividerPieces.first?.height).to(beCloseTo(6.12, within: 1e-9))
        for extent in [
            HwpLineShapeGeometry.alongExtent(of: shortDivider),
            HwpLineShapeGeometry.crossExtent(of: shortDivider),
        ] {
            expect(extent?.lowerBound).to(beCloseTo(-3.06, within: 1e-9))
            expect(extent?.upperBound).to(beCloseTo(3.06, within: 1e-9))
        }
    }

    /// 물결의 대각선(평행사변형)과 꼭짓점 평탄 띠는 겹치는데, 부분 경로의 회전 방향이 다르면
    /// nonzero 채우기(`CGContext.fillPath`)에서 겹친 자리가 상쇄돼 꼭짓점에 구멍이 난다 (PR
    /// 리뷰) — 첫 대각선 끝(4.56, 1.96) 둘레의 겹침 점이 합친 경로에서도 안에 있어야 한다. 홀수 r이면
    /// 대각선 끝이 평탄보다 1u 아래지만(20pt: 끝 −2.04 + 2.28 = 0.24, 평탄 0.12) 획이 그보다 굵어 이어진다.
    func testWaveSubpathsShareWindingSoJunctionsStayFilled() throws {
        let line = Self.characterLine(.wave, length: 30)
        let path = try XCTUnwrap(HwpLineShapeGeometry.path(for: line))
        // 대각선 끝 (4.56, 1.96): 평탄 띠 [4.56, 4.68] × [1.36, 2.56]과 butt cap 모서리가 겹친다
        let junction = [
            CGPoint(x: 4.58, y: 1.9), CGPoint(x: 4.58, y: 2.1), CGPoint(x: 4.62, y: 1.96),
        ]
        for point in junction {
            expect(path.contains(point, using: .winding)) == true
        }
        let odd = try XCTUnwrap(HwpLineShapeGeometry.path(for: Self.characterLine(
            .wave, fontSize: 20, length: 30, placement: .strikethrough
        )))
        // 20pt: 위 평탄 −2.04, 첫 대각선 끝 (2.28, 0.24), 평탄 [2.28, 2.4] × [−0.18, 0.42]
        for point in [CGPoint(x: 2.3, y: 0.12), CGPoint(x: 2.3, y: 0.3), CGPoint(x: 2.38, y: 0.0)] {
            expect(odd.contains(point, using: .winding)) == true
        }
        let border = try XCTUnwrap(
            HwpLineShapeGeometry.path(for: Self.borderLine(.wave, thickness: 8))
        )
        // 테두리 8pt: 첫 대각선 끝 (8, 1), 평탄 [8, 8.12] × [0, 2]
        expect(border.contains(CGPoint(x: 8.02, y: 1), using: .winding)) == true
        expect(border.contains(CGPoint(x: 8.06, y: 0.5), using: .winding)) == true
    }

    /// 유한하지 않은 입력은 경로가 없고, 패턴이 10만 번 넘게 되풀이될 길이·축척은 실선 띠로
    /// 떨어진다 (손상 문서가 수십만 부분 경로를 만들지 않게)
    func testDegenerateInputsHaveNoPathOrFallBackToSolid() {
        expect(HwpLineShapeGeometry.path(
            for: Self.borderLine(.wave, thickness: 8, length: .infinity)
        )).to(beNil())
        expect(HwpLineShapeGeometry.path(for: Self.borderLine(.dotLine, thickness: .nan)))
            .to(beNil())
        // 길이 1e-6pt 이하: 물결 대각선이 0개라 경로가 없고 범위도 없다 (path == nil ⇔ 범위 == nil)
        let hairline = Self.borderLine(.wave, thickness: 8, length: 1e-7)
        expect(HwpLineShapeGeometry.path(for: hairline)).to(beNil())
        expect(HwpLineShapeGeometry.alongExtent(of: hairline)).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: hairline)).to(beNil())
        // 글자 크기만 비정상 (두께는 유한): 무한·0·음수 모두 경로·범위 없음
        for fontSize in [CGFloat.infinity, 0, -10] {
            let line = HwpLineShapeGeometry.Line(
                shape: .circle, length: 100, thickness: 1,
                scale: .characterLine(fontSize: fontSize), placement: .underlineBelow
            )
            expect(HwpLineShapeGeometry.path(for: line)).to(beNil())
            expect(HwpLineShapeGeometry.crossExtent(of: line)).to(beNil())
            expect(HwpLineShapeGeometry.alongExtent(of: line)).to(beNil())
        }
        // 대시는 장치 단위라 주기가 아무리 얇아도 2u(점 1u·공백 1u) — 상한은 길이 24,000pt 너머다
        let huge = Self.borderLine(.dotLine, thickness: 0.001, length: 30000)
        expect(HwpLineShapeGeometry.patternRepeats(of: huge))
            > HwpLineShapeGeometry.maxPatternRepeats
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: huge))
        expect(pieces.count) == 1
        expect(pieces.first?.width).to(beCloseTo(30000, within: 0.001))
        // 물결은 반주기에 0.12pt 평탄이 있어 길이 10만 pt는 돼야 상한을 넘는다
        expect(HwpLineShapeGeometry.alongExtent(of: Self.borderLine(
            .wave, thickness: 0.001, length: 100_000
        ))?.upperBound).to(beCloseTo(100_000, within: 0.001))
    }
}
