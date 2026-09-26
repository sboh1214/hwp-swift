import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 원형 점선·물결의 **끝점 규칙** (#235) — 한글은 자리(원 중심·물결 대각선 시작)가 선 끝보다
/// 앞인 요소를 끝을 넘어도 온전히 그리고, 끝과 같은 자리의 요소는 그리지 않는다.
///
/// 근거는 한글 12.30.0 PDF 벡터 실측(2026-09-27)이다. '가' run의 자간을 1%씩 −50~50%로 바꿔
/// run 길이를 조금씩 늘린 표본(12pt에서 1% = 0.12pt = 600dpi 한 단위) 4,242개 — 한글 2007 호환
/// 문서 7·12·20pt와 한글 문서 7·12·16pt의 원형 점선·물결·2중 물결 밑줄·취소선, 한글 문서 20·40pt의
/// 같은 세 모양 밑줄 — 전부에서 요소는 자리 < run 진행 폭(다음 run 글리프 원점 − 이 run 글리프
/// 원점)일 때만 그려졌다. 한글 2007 호환 문서 표본 1,818개는 한글의 진행 폭을 이 기하에 그대로
/// 넣은 요소 수도 한글과 모두 같다 (무늬가 고정 pt라 간격이 한글과 같다 — 종전 규칙은 원 표본
/// 606개 중 124개가 달랐다). 한글은 실선을 진행 폭 + 0.12pt(장치 한 단위의 포함 끝)까지 그으므로,
/// 실선 길이를 run 길이로 읽으면 요소가 0.12pt 더 앞이어야 그려지는 것처럼 보인다 — 이 기하의
/// `length`는 렌더러가 넘기는 **진행 폭**이다. 단 구분선의 물결·원형 점선도 줄 상자 길이 기준으로
/// 같은 규칙이다 (0.4·1·2mm).
extension HwpLineShapeGeometryTests {
    /// 물결 조각 가운데 대각선(평행사변형)만 — 꼭짓점 평탄 띠는 높이가 획 두께뿐이다
    static func diagonals(_ line: HwpLineShapeGeometry.Line) -> [CGRect] {
        let amplitude = HwpLineShapeGeometry.waveAmplitude(for: line)
        return pieces(HwpLineShapeGeometry.path(for: line)).filter { $0.height > amplitude / 2 }
    }

    /// 한글 2007 호환 문서 12pt 실측 그대로 (자리·길이는 run 시작 기준, 0.12pt 단위): 원 간격
    /// 3.0pt(25u)에 진행 폭 50u면 원 둘(0·3.0 — 6.0은 끝과 같은 자리), 51u면 셋째 원(6.0)을 그려
    /// 끝을 0.54pt 넘는다. 물결 반주기 3.0pt도 50u → 대각선 둘, 51u → 셋. 2중 물결 반주기 1.56pt
    /// (13u)는 52u → 파마다 넷, 53u → 다섯.
    func testHwp2007ElementsBeforeTheRunEndAreDrawnWhole() {
        func circles(_ length: CGFloat) -> [CGRect] {
            Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(.circle, length: length)))
        }
        expect(circles(6.0).map(\.midX)).to(beCloseTo([0, 3.0], within: 1e-9))
        expect(circles(6.12).map(\.midX)).to(beCloseTo([0, 3.0, 6.0], within: 1e-9))
        expect(circles(6.12).last?.maxX).to(beCloseTo(6.66, within: 1e-9))
        expect(HwpLineShapeGeometry.alongExtent(of: Self.hwp2007Line(.circle, length: 6.12))?
            .upperBound).to(beCloseTo(6.66, within: 1e-9))
        // 넘치지 않을 때 뒤는 선 끝 그대로 (마지막 원 3.0 + 0.66 < 6.0)
        expect(HwpLineShapeGeometry.alongExtent(of: Self.hwp2007Line(.circle, length: 6.0))?
            .upperBound).to(beCloseTo(6.0, within: 1e-9))

        expect(Self.diagonals(Self.hwp2007Line(.wave, length: 6.0)).count) == 2
        let wave = Self.diagonals(Self.hwp2007Line(.wave, length: 6.12))
        expect(wave.count) == 3
        // 셋째 대각선은 6.0에서 시작해 진폭 2.88만큼 끝까지 간다 (획 모서리 0.72/2/√2 포함)
        let corner = 0.72 / 2 / 2.0.squareRoot()
        expect(wave.last?.maxX).to(beCloseTo(6.0 + 2.88 + corner, within: 1e-9))
        expect(HwpLineShapeGeometry.alongExtent(of: Self.hwp2007Line(.wave, length: 6.12))?
            .upperBound).to(beCloseTo(6.0 + 2.88 + corner, within: 1e-9))

        expect(Self.diagonals(Self.hwp2007Line(.doubleWave, length: 6.24)).count) == 8
        expect(Self.diagonals(Self.hwp2007Line(.doubleWave, length: 6.36)).count) == 10
    }

    /// 이슈에 적힌 한글 표본을 진행 폭으로 옮긴 것 — 20pt 원형 점선은 실선 339.36pt = 진행 폭
    /// 339.24pt라 중심 339.00(= 113 × 3.0)의 마지막 원을 그려 339.66까지 넘치고, 7pt 물결은 실선
    /// 342.12pt = 진행 폭 342.00pt라 342.00에서 시작하는 대각선은 그리지 않는다. 실선 길이를 그대로
    /// 넣으면 그 대각선이 생긴다 — 입력이 진행 폭이어야 하는 이유다.
    func testHangulSamplesInAdvanceTerms() {
        let circles = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(
            .circle, length: 339.24
        )))
        expect(circles.count) == 114
        expect(circles.last?.midX).to(beCloseTo(339.0, within: 1e-9))
        expect(circles.last?.maxX).to(beCloseTo(339.66, within: 1e-9))

        let waves = Self.diagonals(Self.hwp2007Line(.wave, length: 342.0))
        expect(waves.count) == 114
        expect(waves.last?.minX ?? 0) < 339.1
        expect(Self.diagonals(Self.hwp2007Line(.wave, length: 342.12)).count) == 115
    }

    /// 한글 문서(글자 크기 비례)도 같은 규칙 — 40pt 원 간격 5.7pt(반지름 1.14): 길이 11.4면 원
    /// 둘, 한 단위라도 길면 셋째 원(11.4)을 그려 12.54까지 넘친다. 물결 반주기 4.6pt도 같다.
    /// 규칙은 반지름·획과 무관하다 (한글 40pt 원 지름 2.4pt도 중심이 진행 폭 한 단위 앞이면 그린다).
    func testNativeElementsBeforeTheRunEndAreDrawnWhole() {
        func circles(_ length: CGFloat) -> [CGRect] {
            Self.pieces(HwpLineShapeGeometry.path(for: Self.characterLine(.circle, length: length)))
        }
        expect(circles(11.4).count) == 2
        expect(circles(11.52).count) == 3
        expect(circles(11.52).last?.maxX).to(beCloseTo(11.4 + 1.14, within: 1e-9))
        expect(Self.diagonals(Self.characterLine(.wave, length: 9.2)).count) == 2
        expect(Self.diagonals(Self.characterLine(.wave, length: 9.32)).count) == 3
        expect(Self.diagonals(Self.characterLine(.doubleWave, length: 9.2)).count) == 4
        expect(Self.diagonals(Self.characterLine(.doubleWave, length: 9.32)).count) == 6
    }

    /// 단 구분선은 같은 규칙이다 (한글 실측: 줄 상자 길이 기준으로 정확히 같다) — 원형 점선은
    /// 두께 4pt(간격 8pt)에서 길이 16이면 원 둘, 16.12면 셋째 원(16)이 반지름 2만큼 넘친다.
    /// 표 셀 테두리의 **원**은 예외로 변 안에 온전히 드는 것만 그린다: 한글은 같은 모양 이웃 칸의
    /// 원형 점선 변을 한 선으로 이어 칸 경계에 걸친 원이 없는데 우리는 칸마다 다시 시작하므로,
    /// 끝 규칙을 쓰면 칸 경계마다 원 둘이 겹친다 (#235 재검증 — 1×3·3×1 표). 테두리 물결은 한글도
    /// 칸마다 다시 시작해 넘치므로 같은 규칙이고, 2중 물결의 둘째 파는 3t/4 뒤에서 시작하므로 그
    /// 자리부터 센다.
    func testDividerEndsFollowTheRuleWhileCellBorderCirclesStayInside() {
        func divider(_ shape: HwpBorderType, _ length: CGFloat) -> HwpLineShapeGeometry.Line {
            HwpLineShapeGeometry.Line(
                shape: shape, length: length, thickness: 4, scale: .border, placement: .divider
            )
        }
        expect(Self.pieces(HwpLineShapeGeometry.path(for: divider(.circle, 16))).count) == 2
        expect(Self.pieces(HwpLineShapeGeometry.path(for: divider(.circle, 16.12))).map(\.midX))
            .to(beCloseTo([0, 8, 16], within: 1e-9))
        expect(HwpLineShapeGeometry.alongExtent(of: divider(.circle, 16.12))?.upperBound)
            .to(beCloseTo(18, within: 1e-9))
        expect(Self.diagonals(divider(.wave, 8.24)).count) == 2
        expect(Self.diagonals(divider(.wave, 8.25)).count) == 3

        /// 표 셀 테두리: 중심 ≤ 길이 − 반지름 (길이 18에서 셋째 원 16이 끝에 닿는다)
        func cellCircles(_ length: CGFloat) -> [CGRect] {
            Self.pieces(HwpLineShapeGeometry.path(for: Self.borderLine(
                .circle, thickness: 4, length: length
            )))
        }
        expect(cellCircles(16.12).map(\.midX)).to(beCloseTo([0, 8], within: 1e-9))
        expect(cellCircles(17.99).count) == 2
        expect(cellCircles(18).map(\.midX)).to(beCloseTo([0, 8, 16], within: 1e-9))
        expect(HwpLineShapeGeometry.alongExtent(of: Self.borderLine(
            .circle, thickness: 4, length: 16.12
        ))?.upperBound).to(beCloseTo(16.12, within: 1e-9))
        expect(HwpLineShapeGeometry.circleCount(for: Self.borderLine(
            .circle, thickness: 4, length: 1.99
        ))) == 0

        /// 테두리 2중 물결: 첫 파 0·4.12, 둘째 파 3.0부터 — 7.12면 둘째 파는 3.0 하나(7.12는 끝과
        /// 같은 자리), 7.13이면 7.12까지 둘
        func doubleWave(_ length: CGFloat) -> HwpLineShapeGeometry.Line {
            Self.borderLine(.doubleWave, thickness: 4, length: length)
        }
        expect(HwpLineShapeGeometry.waveDiagonalCount(for: doubleWave(7.12), offsetX: 3)) == 1
        expect(HwpLineShapeGeometry.waveDiagonalCount(for: doubleWave(7.13), offsetX: 3)) == 2
        expect(Self.diagonals(doubleWave(7.12)).count) == 2 + 1
        expect(Self.diagonals(doubleWave(7.13)).count) == 2 + 2
    }

    /// 끝과 같은 자리는 부동소수점 잡음(상대 1e-6) 안이면 그리지 않는 쪽으로 가른다. 1e-6pt 이하
    /// 길이는 요소가 없어 경로·범위가 함께 없고 (`isDrawable`), 비율이 반복 상한을 넘거나 유한하지
    /// 않아도 개수 계산이 트랩하지 않는다.
    func testEndTiesAndDegenerateSpans() throws {
        let tied = Self.hwp2007Line(.circle, length: 6.0 * (1 + 1e-9))
        expect(Self.pieces(HwpLineShapeGeometry.path(for: tied)).count) == 2
        let hairline = Self.borderLine(.circle, thickness: 4, length: 1e-7)
        expect(HwpLineShapeGeometry.path(for: hairline)).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: hairline)).to(beNil())
        expect(HwpLineShapeGeometry.alongExtent(of: hairline)).to(beNil())

        expect(HwpLineShapeGeometry.patternElementCount(span: 1e-7, period: 3)) == 0
        expect(HwpLineShapeGeometry.patternElementCount(span: 2e-6, period: 3)) == 1
        expect(HwpLineShapeGeometry.patternElementCount(span: 3, period: 0)) == 0
        expect(HwpLineShapeGeometry.patternElementCount(span: 3, period: -1)) == 0
        expect(HwpLineShapeGeometry.patternElementCount(span: 3, period: .infinity)) == 1
        expect(HwpLineShapeGeometry.fittingElementCount(span: 0, period: 3)) == 1
        expect(HwpLineShapeGeometry.fittingElementCount(span: -1e-9, period: 3)) == 0
        expect(HwpLineShapeGeometry.fittingElementCount(span: 6 * (1 - 1e-9), period: 3)) == 3
        expect(HwpLineShapeGeometry.fittingElementCount(span: 3, period: 0)) == 0
        expect(HwpLineShapeGeometry.fittingElementCount(span: .infinity, period: 3)) == 0
        // 원 간격(두께 × 2)이 무한대로 넘치는 두께도 첫 원(자리 0)만 그린다 — 자리를 0 × ∞ = NaN으로
        // 곱하지 않으므로 경로가 유한하고 범위가 그 원을 담는다. 표 셀 테두리는 원이 변 안에 들지
        // 않아 경로·범위가 함께 없다 (종전과 같다)
        let overflow = HwpLineShapeGeometry.Line(
            shape: .circle, length: 100, thickness: 1e308, scale: .border, placement: .divider
        )
        let overflowBox = try XCTUnwrap(HwpLineShapeGeometry.path(for: overflow)).boundingBoxOfPath
        expect(overflowBox.minX) == -5e307
        expect(overflowBox.width) == 1e308
        expect(HwpLineShapeGeometry.alongExtent(of: overflow)) == -5e307 ... 5e307
        expect(HwpLineShapeGeometry.crossExtent(of: overflow)) == -5e307 ... 5e307
        let overflowCell = Self.borderLine(.circle, thickness: 1e308, length: 100)
        expect(HwpLineShapeGeometry.path(for: overflowCell)).to(beNil())
        expect(HwpLineShapeGeometry.crossExtent(of: overflowCell)).to(beNil())
        expect(HwpLineShapeGeometry.alongExtent(of: overflowCell)).to(beNil())
        let infinite = HwpLineShapeGeometry.patternElementCount(
            span: .greatestFiniteMagnitude, period: 1e-300
        )
        expect(infinite) == 0
        expect(HwpLineShapeGeometry.patternElementCount(span: 1e12, period: 1e-3))
            == Int(HwpLineShapeGeometry.maxPatternRepeats) + 1
    }
}
