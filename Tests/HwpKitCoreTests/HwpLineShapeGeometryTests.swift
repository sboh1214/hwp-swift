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
            thickness: fontSize * HwpRenderTuning.Text.decorationLineThicknessRatio,
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
        expect(pieces.first).to(equal(CGRect(x: 0, y: -0.8, width: 400, height: 1.6)))
    }

    func testNoneAndDegenerateLinesHaveNoPath() {
        expect(HwpLineShapeGeometry.path(for: Self.characterLine(.none))).to(beNil())
        expect(HwpLineShapeGeometry.path(for: Self.characterLine(.dotLine, length: 0))).to(beNil())
        expect(HwpLineShapeGeometry.path(for: Self.borderLine(.wave, thickness: 0))).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: Self.characterLine(.none))).to(beNil())
    }

    /// 3D 넷은 한글 macOS가 아무것도 그리지 않지만 실선으로 대체한다 (사라지는 것보다 낫다).
    func test3DShapesFallBackToSolid() {
        for shape in [HwpBorderType.thick3D, .thick3DReverse, .single3D, .single3DReverse] {
            let pieces = Self.pieces(
                HwpLineShapeGeometry.path(for: Self.borderLine(shape, thickness: 2))
            )
            expect(pieces).to(equal([CGRect(x: 0, y: -1, width: 200, height: 2)]))
        }
    }

    // MARK: - 대시 (실측: 80pt 긴 점선 22.8/13.68pt, 5mm 테두리 173/259u = 점선)

    func testCharacterLongDotDashesAreFiveAndThreeUnits() {
        // 80pt: 단위 0.057em = 4.56pt → 선 22.8, 공백 13.68 (한글 190u/114u)
        let line = Self.characterLine(.longDotLine, fontSize: 80, length: 200)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        expect(pieces.count) == 6 // 36.48 주기 → 0, 36.48, …, 182.4 (마지막은 잘린다)
        expect(pieces[0].minX) == 0
        expect(pieces[0].width).to(beCloseTo(22.8, within: 0.001))
        expect(pieces[1].minX).to(beCloseTo(36.48, within: 0.001))
        expect(pieces[5].maxX).to(beCloseTo(200, within: 0.001))
        for piece in pieces {
            expect(piece.minY).to(beCloseTo(-1.6, within: 0.001))
            expect(piece.height).to(beCloseTo(3.2, within: 0.001))
        }
    }

    func testCharacterDashPatternsFollowTheUnitTable() {
        let unit: CGFloat = 40 * 0.057 // 2.28pt (한글 19u)
        let expectations: [(HwpBorderType, [CGFloat])] = [
            (.dotLine, [1, 1.5]),
            (.dashDot, [10, 3, 1, 3]),
            (.dashDotDot, [10, 3, 1, 3, 1, 3]),
            (.longDash, [10, 3]),
        ]
        for (shape, multiples) in expectations {
            let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(shape)))
            var x: CGFloat = 0
            for (index, multiple) in multiples.enumerated() {
                if index % 2 == 0 {
                    let piece = pieces[index / 2]
                    expect(piece.minX).to(beCloseTo(x, within: 0.001), description: "\(shape)")
                    expect(piece.width).to(beCloseTo(multiple * unit, within: 0.001))
                }
                x += multiple * unit
            }
        }
    }

    func testBorderDashUnitIsTwentyTwoFifteenthsOfThickness() {
        // 5mm(14.173pt): 단위 20.79pt → 점선 선 20.79·공백 31.18 (한글 173u/259u)
        let thickness = 5 * 72 / 25.4
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .dotLine, thickness: thickness, length: 300
        )))
        let unit = thickness * 22 / 15
        expect(pieces[0].width).to(beCloseTo(unit, within: 0.001))
        expect(pieces[1].minX).to(beCloseTo(unit * 2.5, within: 0.001))
        expect(pieces[0].minY).to(beCloseTo(-thickness / 2, within: 0.001))
        expect(unit).to(beCloseTo(20.79, within: 0.01))
        // 긴 점선은 5·3 단위 (한글 866u/519u)
        let long = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .longDotLine, thickness: thickness, length: 300
        )))
        expect(long[0].width).to(beCloseTo(unit * 5, within: 0.001))
        expect(long[1].minX).to(beCloseTo(unit * 8, within: 0.001))
    }

    // MARK: - 원형 점선

    func testCharacterCirclesHaveUnitDiameterAtTwoAndAHalfPitch() {
        // 20pt: 지름 1.14pt, 피치 2.85pt, 첫 원 중심 = run 시작 (한글 10u/25u, 84.48~85.68)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .circle, fontSize: 20, length: 100
        )))
        expect(pieces[0].width).to(beCloseTo(1.14, within: 0.001))
        expect(pieces[0].height).to(beCloseTo(1.14, within: 0.001))
        expect(pieces[0].midX).to(beCloseTo(0, within: 0.001))
        expect(pieces[0].midY).to(beCloseTo(0, within: 0.001))
        expect(pieces[1].midX).to(beCloseTo(2.85, within: 0.001))
        // 마지막 원은 선 끝 안에 온전히 든다
        expect(pieces.last?.maxX ?? 999) <= 100
        expect(pieces.count) == 35 // 0, 2.85, …, 96.9 (99.75는 반지름이 넘친다)
    }

    func testBorderCirclesHaveThicknessDiameterAtDoublePitch() {
        // 1mm(2.835pt): 지름 2.835, 피치 5.67, 첫 중심 = 선 시작 (한글 24u/48u)
        let thickness = 72 / 25.4
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
            .circle, thickness: thickness, length: 100
        )))
        expect(pieces[0].width).to(beCloseTo(thickness, within: 0.001))
        expect(pieces[0].midX).to(beCloseTo(0, within: 0.001))
        expect(pieces[1].midX).to(beCloseTo(thickness * 2, within: 0.001))
        expect(HwpLineShapeGeometry.crossExtent(of: Self.borderLine(.circle, thickness: thickness)))
            == (-thickness / 2) ... (thickness / 2)
    }

    // MARK: - 여러 줄

    /// 글자선 2중선은 0.12em 띠(1/4·1/2·1/4) — 40pt: 1.2pt 두 줄, 중심 간격 3.6pt (한글 실측)
    func testCharacterDoubleLineBandIsTwelveHundredthsEm() {
        let line = Self.characterLine(.doubleLine)
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        expect(pieces.count) == 2
        expect(pieces[0].height).to(beCloseTo(1.2, within: 0.001))
        expect(pieces[1].height).to(beCloseTo(1.2, within: 0.001))
        expect(pieces[1].midY - pieces[0].midY).to(beCloseTo(3.6, within: 0.001))
        // 아래 밑줄: 띠 위 가장자리가 단선 띠 위 가장자리(−t/2 = −0.8)에 맞고 아래로 자란다
        expect(pieces[0].minY).to(beCloseTo(-0.8, within: 0.001))
        expect(pieces[1].maxY).to(beCloseTo(-0.8 + 4.8, within: 0.001))
    }

    /// 가는+굵은·굵은+가는·3중선은 0.2em 띠 — 40pt: 8pt 안에 [2, 2 공백, 4]·[4, 2, 2]·
    /// [4/3, 4/3, 8/3, 4/3, 4/3] (한글 1.92+1.88+4.08 = 7.9pt)
    func testCharacterThickBandsAreOneFifthEm() {
        let thinThick = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thinThickDoubleLine))
        )
        expect(thinThick.map(\.height)).to(equal([2, 4]))
        expect(thinThick[1].minY - thinThick[0].maxY).to(beCloseTo(2, within: 0.001))
        let thickThin = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thickThinDoubleLine))
        )
        expect(thickThin.map(\.height)).to(equal([4, 2]))
        let triple = Self.pieces(
            HwpLineShapeGeometry.path(for: Self.characterLine(.thinThickThinTripleLine))
        )
        expect(triple.count) == 3
        expect(triple[0].height).to(beCloseTo(8 / 6, within: 0.001))
        expect(triple[1].height).to(beCloseTo(8 / 3, within: 0.001))
        expect(triple[2].height).to(beCloseTo(8 / 6, within: 0.001))
        expect(triple[2].maxY - triple[0].minY).to(beCloseTo(8, within: 0.001))
    }

    /// 취소선은 띠를 단선 중심에 가운데 맞추고, 글자 위 밑줄은 아래 가장자리를 단선 띠의
    /// 아래 가장자리에 맞춰 위로 자란다 (한글 실측 10pt: 취소선 2중선 −3.84/−3.12pt … 중심
    /// −3.48pt = 0.35em, 위 밑줄 2중선 0.846~0.966em).
    func testMultiLinePlacementFollowsTheDecorationKind() {
        let centered = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .doubleLine, placement: .strikethrough
        )))
        expect(centered[0].minY).to(beCloseTo(-2.4, within: 0.001))
        expect(centered[1].maxY).to(beCloseTo(2.4, within: 0.001))
        let above = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(
            .thinThickDoubleLine, placement: .underlineAbove
        )))
        expect(above[1].maxY).to(beCloseTo(0.8, within: 0.001))
        expect(above[0].minY).to(beCloseTo(0.8 - 8, within: 0.001))
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

    /// 글자선 물결은 45° 지그재그 — 40pt: 진폭 4.48pt(0.112em), 획 1.2pt(0.03em), 위 꼭짓점은
    /// 단선 위 가장자리(−0.8)에서 두께(1.6) 위 = −2.4 (한글 실측: 20pt 아래 밑줄 꼭짓점
    /// −0.108~−0.216em)
    func testCharacterWaveIsFortyFiveDegreeZigzagAboveTheLine() {
        let line = Self.characterLine(.wave, length: 30)
        let extent = HwpLineShapeGeometry.crossExtent(of: line)
        expect(extent?.lowerBound).to(beCloseTo(-2.4 - 0.6, within: 0.001))
        expect(extent?.upperBound).to(beCloseTo(-2.4 + 4.48 + 0.6, within: 0.001))
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
        // 첫 대각선: x 0~4.48, y −2.4~2.08 (획 반폭 0.6의 평행사변형이라 상자는 조금 크다)
        let first = try? XCTUnwrap(pieces.first)
        expect(first?.minX).to(beCloseTo(-0.42, within: 0.01))
        expect(first?.maxX).to(beCloseTo(4.48 + 0.42, within: 0.01))
        expect(first?.minY).to(beCloseTo(-2.4 - 0.42, within: 0.01))
        expect(first?.maxY).to(beCloseTo(2.08 + 0.42, within: 0.01))
        // 반주기 = 진폭 + 0.12pt 평탄 → 둘째 대각선은 4.6에서 시작한다
        let diagonals = pieces.filter { $0.height > 2 }
        expect(diagonals[1].minX).to(beCloseTo(4.6 - 0.42, within: 0.01))
    }

    /// 취소선·글자 위 밑줄의 물결은 두께의 2배·3배 위에서 시작한다 (한글 실측: 20pt 취소선
    /// 꼭짓점 0.342~0.45em = 단선 위 가장자리 0.37 + 0.08, 위 밑줄 0.90~1.008 = 0.89 + 0.118)
    func testWaveTopVertexStepsUpByDecorationKind() {
        let strike = HwpLineShapeGeometry.crossExtent(
            of: Self.characterLine(.wave, placement: .strikethrough)
        )
        expect(strike?.lowerBound).to(beCloseTo(-0.8 - 3.2 - 0.6, within: 0.001))
        let above = HwpLineShapeGeometry.crossExtent(
            of: Self.characterLine(.wave, placement: .underlineAbove)
        )
        expect(above?.lowerBound).to(beCloseTo(-0.8 - 4.8 - 0.6, within: 0.001))
    }

    /// 2중 물결의 둘째 파는 진폭의 0.8배 아래 (한글 실측: 40pt 3.6/4.56pt)
    func testCharacterDoubleWaveOffsetsTheSecondWaveDown() {
        let extent = HwpLineShapeGeometry.crossExtent(of: Self.characterLine(.doubleWave))
        expect(extent?.lowerBound).to(beCloseTo(-3.0, within: 0.001))
        expect(extent?.upperBound).to(beCloseTo(-2.4 + 4.48 * 1.8 + 0.6, within: 0.001))
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
        // 40pt 글자선 400pt: 반주기 4.6 → 400 / 4.6 = 86.96 → 87개, 끝 = 87 × 4.6 − 0.12 =
        // 400.08 (잘랐다면 400에서 멈춘다)
        let character = Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(.wave)))
            .filter { $0.height > 2 }
        expect(character.count) == 87
        expect(character.last?.maxX).to(beCloseTo(400.08 + 0.6 / 2.0.squareRoot(), within: 0.01))
        // 대시·실선은 길이 그대로
        let dashed = Self.borderLine(.longDash, thickness: 8, length: 20)
        expect(HwpLineShapeGeometry.alongExtent(of: dashed)?.upperBound)
            .to(beCloseTo(20, within: 0.001))
        expect(Self.pieces(HwpLineShapeGeometry.path(for: dashed)).last?.maxX)
            .to(beCloseTo(20, within: 0.001))
    }

    /// 원형 점선은 첫 원의 중심이 선 시작이라 반지름만큼 앞으로 나간다 — `alongExtent`가 그
    /// 몫을 보고해야 히트 띠가 첫 원을 다 덮는다 (#191 리뷰). 원 하나도 안 들어가는 길이(반지름
    /// 미만)는 경로도 범위도 없다.
    func testCircleAlongExtentStartsHalfADiameterBeforeTheLine() {
        let border = Self.borderLine(.circle, thickness: 4)
        let along = HwpLineShapeGeometry.alongExtent(of: border)
        expect(along?.lowerBound).to(beCloseTo(-2, within: 0.001))
        expect(along?.upperBound).to(beCloseTo(200, within: 0.001))
        expect(HwpLineShapeGeometry.path(for: border)?.boundingBoxOfPath.minX)
            .to(beCloseTo(-2, within: 0.001))
        let character = Self.characterLine(.circle, fontSize: 20)
        expect(HwpLineShapeGeometry.alongExtent(of: character)?.lowerBound)
            .to(beCloseTo(-20 * 0.057 / 2, within: 0.001))
        let tooShort = Self.borderLine(.circle, thickness: 4, length: 1.5)
        expect(HwpLineShapeGeometry.path(for: tooShort)).to(beNil())
        expect(HwpLineShapeGeometry.alongExtent(of: tooShort)).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: tooShort)).to(beNil())
        // 반지름과 같은 길이는 원 하나
        let one = Self.borderLine(.circle, thickness: 4, length: 2)
        expect(Self.pieces(HwpLineShapeGeometry.path(for: one)).count) == 1
    }

    /// 물결의 대각선(평행사변형)과 꼭짓점 평탄 띠는 겹치는데, 부분 경로의 회전 방향이 다르면
    /// nonzero 채우기(`CGContext.fillPath`)에서 겹친 자리가 상쇄돼 꼭짓점에 구멍이 난다 (PR
    /// 리뷰) — 첫 대각선 끝(4.48, 2.08) 둘레의 겹침 점이 합친 경로에서도 안에 있어야 한다
    func testWaveSubpathsShareWindingSoJunctionsStayFilled() throws {
        let line = Self.characterLine(.wave, length: 30)
        let path = try XCTUnwrap(HwpLineShapeGeometry.path(for: line))
        // 대각선 끝 (4.48, 2.08): 평탄 띠 [4.48, 4.6] × [1.48, 2.68]과 butt cap 모서리가 겹친다
        for point in [CGPoint(x: 4.5, y: 2.0), CGPoint(x: 4.5, y: 2.2), CGPoint(x: 4.55, y: 2.08)] {
            expect(path.contains(point, using: .winding)) == true
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
        let huge = Self.borderLine(.dotLine, thickness: 0.001, length: 10000)
        expect(HwpLineShapeGeometry.patternRepeats(of: huge))
            > HwpLineShapeGeometry.maxPatternRepeats
        let pieces = Self.pieces(HwpLineShapeGeometry.path(for: huge))
        expect(pieces.count) == 1
        expect(pieces.first?.width).to(beCloseTo(10000, within: 0.001))
        // 물결은 반주기에 0.12pt 평탄이 있어 길이 10만 pt는 돼야 상한을 넘는다
        expect(HwpLineShapeGeometry.alongExtent(of: Self.borderLine(
            .wave, thickness: 0.001, length: 100_000
        ))?.upperBound).to(beCloseTo(100_000, within: 0.001))
    }
}
