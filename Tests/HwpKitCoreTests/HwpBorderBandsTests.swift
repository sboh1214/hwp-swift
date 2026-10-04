import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 표 셀 테두리·단 구분선의 2중선·가는+굵은 선·굵은+가는 선·3중선·물결·2중 물결 (#253) — 한글 12.30.0(build
/// 6523)이 2026-10-04에 내보낸 PDF의 벡터 좌표(로컬 `probes/253`, PyMuPDF — 한글은 테두리를 선분마다 획으로
/// 내보낸다)를 값 표로 고정한다 (`HwpBorderBandsTests+Samples.swift`). 단위는 u = 0.12pt다. 한글은 칸 경계를
/// 600dpi 장치 격자에 맞추므로(쪽 HWPUNIT h → ⌊(h + 10) ÷ 12⌋u) 여기서는 그 격자 위 칸(1×1 표 1667u × 667u,
/// 칸 길이를 1u씩 바꾼 표본은 한글이 반올림한 칸 길이)을 그대로 만들어 정수 기하를 요소마다 대조한다 — 우리
/// 렌더는 칸 경계를 HWPUNIT 그대로 두어 실제 문서에서는 칸 길이의 분수(< 1u)만큼 끝 쪽 요소가 갈릴 수 있다.
/// 모서리 규칙의 단위 핀은 `HwpBorderBandsTests+Rules.swift`, 값 표의 형과 경로 읽기는 `+Support.swift`.
final class HwpBorderBandsTests: XCTestCase {
    typealias Chaining = HwpBorderChainingTests
    static let unit: CGFloat = 0.12
    static let green = HwpRGBColor(red: 0, green: 1, blue: 0)
    static let blue = HwpRGBColor(red: 0, green: 0, blue: 1)
    static let red = HwpRGBColor(red: 1, green: 0, blue: 0)

    /// 표 26 굵기 (pt)
    static func thickness(_ index: Int) -> CGFloat {
        CGFloat(HwpBorderFill.borderThicknessPoints(at: UInt8(index)))
    }

    /// 표 26 굵기 (mm → pt)
    static func thickness(millimetres: CGFloat) -> CGFloat {
        let index = HwpBorderFill.borderThicknessMillimeters.firstIndex {
            abs(CGFloat($0) - millimetres) < 1e-9
        }
        return thickness(index ?? 0)
    }

    static func line(_ shape: HwpBorderType, _ index: Int) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: 100, thickness: thickness(index), scale: .border,
            placement: .border
        )
    }

    // MARK: - 값 표

    /// 여러 줄 4종 × 표 26 16단의 부속선 — 한글은 같은 굵기 실선의 획 B를 띠로 #252의 글자선 행 규칙을
    /// 쓴다: 2중선은 w = round(B/4) 두 줄이 중심 사이 3w (0.25mm(B 6u)에서 w = 2u — round(t ÷ 48) = 1u가
    /// 아니다), 가는+굵은은 ⌊B/4⌋(최소 1u)·굵은 선 최소 3u (0.12~0.2mm는 띠가 B보다 넓은 1/1/3u, 0.1mm는 2u
    /// 한 줄), 3중선은 max(1, ⌊B/6⌋)·굵은 선 max(B − 4a, min(B − 2, 2)) — 띠는 −⌊전체/2⌋에서, 획 중심은
    /// 행 시작 + ⌊폭/2⌋. 표 셀 테두리의 네 변·셀 간격 0·283HWPUNIT과 단 구분선이 모두 같다 (각 9벌).
    func testBorderStripesMatchHangul() {
        expect(Self.stripeSamples.count) == 64
        for sample in Self.stripeSamples {
            let label = "\(sample.shape) #\(sample.index)"
            let stripes = HwpLineShapeGeometry.stripeGeometry(
                for: Self.line(sample.shape, sample.index)
            )
            expect(stripes.count).to(equal(sample.stripes.count), description: label)
            for (stripe, want) in zip(stripes, sample.stripes) {
                expect(stripe.center / Self.unit)
                    .to(beCloseTo(want.center, within: 1e-6), description: label)
                expect(stripe.thickness / Self.unit)
                    .to(beCloseTo(want.width, within: 1e-6), description: label)
                // 행은 획 중심 − ⌊폭/2⌋에서 폭만큼 (홀수 폭의 획은 행보다 반 칸 위)
                let start = want.center - (want.width / 2).rounded(.down)
                expect(stripe.slot.lowerBound / Self.unit)
                    .to(beCloseTo(start, within: 1e-6), description: label)
                expect(stripe.slot.upperBound / Self.unit)
                    .to(beCloseTo(start + want.width, within: 1e-6), description: label)
            }
        }
    }

    /// 물결 × 16단 — 대각선 가로·세로 B, 반주기 B + 1, 획 max(1, round(B/4)), 위 평탄 −(⌊B/2⌋ + ⌈3w/2⌉)·
    /// 아래 평탄 그 + 2⌊B/2⌋ (홀수 B면 대각선이 평탄을 1u 넘는다), 2중 물결 둘째 파 3w 아래 — 단일 물결은
    /// 2중 물결의 위 파와 같다.
    func testBorderWavesMatchHangul() {
        expect(Self.waveSamples.count) == 16
        for sample in Self.waveSamples {
            let label = "#\(sample.index)"
            let single = HwpLineShapeGeometry.wave(for: Self.line(.wave, sample.index))
            let double = HwpLineShapeGeometry.wave(for: Self.line(.doubleWave, sample.index))
            expect(double).to(equal(single), description: label)
            expect(single.stroke / Self.unit)
                .to(beCloseTo(sample.stroke, within: 1e-6), description: label)
            expect(single.run / Self.unit)
                .to(beCloseTo(sample.run, within: 1e-6), description: label)
            expect(single.halfPeriod / Self.unit)
                .to(beCloseTo(sample.halfPeriod, within: 1e-6), description: label)
            expect(single.flat / Self.unit).to(beCloseTo(1, within: 1e-6), description: label)
            expect(single.top / Self.unit)
                .to(beCloseTo(sample.levels.0, within: 1e-6), description: label)
            expect((single.top + single.levelGap) / Self.unit)
                .to(beCloseTo(sample.levels.1, within: 1e-6), description: label)
            expect(single.secondOffset / Self.unit)
                .to(beCloseTo(sample.second, within: 1e-6), description: label)
            expect(single.straight).to(beFalse(), description: label)
        }
    }

    /// 1×1 표(네 변이 같은 모양·굵기) — 한글 칸 1667u × 667u 그대로 여섯 모양 × 0.1·0.12·0.25·0.5·1·2·5mm의
    /// 네 변을 대조한다: 부속선은 획과 선 방향 끝(맞물린 모서리 — `HwpBorderSet.nestedStripeOffset`), 물결은
    /// 파마다 첫 대각선 시작(위·왼 변 첫 파 −2w·둘째 파 +w, 아래·오른 변 그 반대)·대각선 수·마지막 요소
    /// 끝(시작 + 칸 길이 앞에서 시작한 대각선과 평탄을 끝까지).
    func testOneByOneTablesMatchHangul() {
        expect(Self.tableSamples.count) == 42
        for sample in Self.tableSamples {
            let side = Chaining.Side(width: Self.thickness(sample.index), shape: sample.shape)
            let set = Chaining.borders(top: side, bottom: side, left: side, right: side)
            let rect = CGRect(
                x: 0, y: 0, width: sample.width * Self.unit, height: sample.height * Self.unit
            )
            let edges = set.edges(around: rect)
            expect(edges.count) == 4
            for (position, edge) in zip([Side.top, .bottom, .left, .right], edges) {
                let label = "\(sample.shape) #\(sample.index) \(position)"
                let length = position.horizontal ? sample.width : sample.height
                let cross: CGFloat = switch position {
                case .top, .left: 0
                case .bottom: rect.maxY
                case .right: rect.maxX
                }
                let elements = Self.elements(
                    of: edge.path, horizontal: position.horizontal, cross: cross
                )
                if let want = sample.stripes[position] {
                    Self.expectStripes(elements, want, length: length, label)
                }
                if let want = sample.waves[position] {
                    Self.expectWaves(Self.waveSummaries(elements, length: length), want, label)
                }
            }
        }
    }

    /// 다른 모양 이웃 사이 1mm 물결 (`so253-ends` — 칸 길이를 1u씩 늘린 300표본 가운데 요소가 느는
    /// 자리) — 이웃 획 B를 모서리의 행 [−⌊B/2⌋, ⌈B/2⌉)로 보고 가로 변은 [−⌊B/2⌋, 길이 + ⌈B/2⌉ − 1), 세로
    /// 변은 [⌈B/2⌉, 길이 − ⌊B/2⌋)에 두 파가 함께다 (`HwpBorderSet.framedReach`).
    func testFramedWaveEndsMatchHangul() {
        expect(Self.framedSamples.count) == 52
        for sample in Self.framedSamples {
            let label = "\(sample.shape) \(sample.horizontal) \(sample.neighbour) \(sample.length)"
            let wave = Chaining.Side(
                width: Self.thickness(millimetres: sample.millimetres), shape: sample.shape,
                color: Self.green
            )
            let neighbour = Chaining.Side(
                width: Self.thickness(millimetres: sample.neighbour.millimetres),
                shape: sample.neighbour.shape, color: Self.blue
            )
            let length = sample.length * Self.unit
            let (set, rect) = sample.horizontal
                ? (Chaining.borders(top: wave, left: neighbour, right: neighbour),
                   CGRect(x: 0, y: 0, width: length, height: 30))
                : (Chaining.borders(top: neighbour, bottom: neighbour, left: wave),
                   CGRect(x: 0, y: 0, width: 30, height: length))
            guard let edge = Self.edge(set, around: rect, ink: Self.green) else {
                fail("\(label): 물결 변이 없다")
                continue
            }
            let elements = Self.elements(of: edge.path, horizontal: sample.horizontal, cross: 0)
            Self.expectWaves(
                Self.waveSummaries(elements, length: sample.length), sample.waves, label
            )
        }
    }

    /// 한쪽 모서리만 같은 물결 이웃 (`so253-mixed` — 1·2mm 물결·2중 물결, 칸 길이를 1u씩) — 맞물린 시작
    /// 모서리만 파를 옮기고, 끝은 칸 끝을 그 몫만큼 옮긴 자리에 다른 모양 이웃 쪽 몫을 더한다: 시작 이웃이
    /// 다르면 두 파가 그 행 앞(가로)·뒤(세로)에서 시작해 칸 끝에서 끝나고, 끝 이웃이 다르면 파마다
    /// −2w·+w에서 시작해 칸 끝 + 그 몫 + 이웃 행 몫에서 끝난다.
    func testHalfJoinedWaveEndsMatchHangul() {
        expect(Self.halfJoinedSamples.count) == 55
        let solid = Chaining.Side(
            width: Self.thickness(millimetres: 2), shape: .line, color: Self.blue
        )
        for sample in Self.halfJoinedSamples {
            let label = "\(sample.shape) \(sample.millimetres) \(sample.horizontal) " +
                "\(sample.mode) \(sample.length)"
            let width = Self.thickness(millimetres: sample.millimetres)
            let wave = Chaining.Side(width: width, shape: sample.shape, color: Self.green)
            // 같은 모양·굵기 이웃 — 색은 맞물림에 상관없다 (#243·#246)
            let same = Chaining.Side(width: width, shape: sample.shape, color: Self.red)
            let (first, last) = sample.mode == .endJoined ? (solid, same) : (same, solid)
            let length = sample.length * Self.unit
            let (set, rect) = sample.horizontal
                ? (Chaining.borders(top: wave, left: first, right: last),
                   CGRect(x: 0, y: 0, width: length, height: 30))
                : (Chaining.borders(top: first, bottom: last, left: wave),
                   CGRect(x: 0, y: 0, width: 30, height: length))
            guard let edge = Self.edge(set, around: rect, ink: Self.green) else {
                fail("\(label): 물결 변이 없다")
                continue
            }
            let elements = Self.elements(of: edge.path, horizontal: sample.horizontal, cross: 0)
            Self.expectWaves(
                Self.waveSummaries(elements, length: sample.length), sample.waves, label
            )
        }
    }
}
