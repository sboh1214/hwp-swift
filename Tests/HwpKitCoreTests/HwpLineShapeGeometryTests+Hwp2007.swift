import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 한글 2007 호환 문서의 글자선 모양(`Scale.hwp200XCharacterLine`, #227) — 패턴·띠·물결이
/// 글자 크기와 무관한 **고정 pt**다. 값의 근거는 `HwpRenderTuning.LineShape`의 `hwp200X*`
/// doc-comment — 한글 12.30.0 PDF 벡터(0.12pt 정수 단위)로 5~100pt 표본 493개를 읽은 것이다.
///
/// 이 축척은 글자 크기를 입력으로 받지 않으므로 "크기와 무관하다"는 구조로 성립한다 —
/// 여기서는 그 고정값과 자리(`Placement`)를 잰다. 렌더러가 어느 문서에서 이 축척을 고르는지는
/// `HwpDecorationLineGeometryTests+Hwp2007Shape`(HwpKitNative), 실물 픽셀은
/// `FixtureDecorationLineRenderTests+Hwp2007Shapes`가 잡는다. 기준 두께는 고정 0.36pt
/// (`HwpRenderTuning.Text.hwp200XDecorationLineThickness`)라 단선 띠는 [−0.18, 0.18]이다.
extension HwpLineShapeGeometryTests {
    static func hwp2007Line(
        _ shape: HwpBorderType, length: CGFloat = 200,
        placement: HwpLineShapeGeometry.Placement = .underlineBelow
    ) -> HwpLineShapeGeometry.Line {
        HwpLineShapeGeometry.Line(
            shape: shape, length: length,
            thickness: HwpRenderTuning.Text.hwp200XDecorationLineThickness,
            scale: .hwp200XCharacterLine, placement: placement
        )
    }

    /// 대시는 단위 0.48pt의 같은 배수 표다 — 한글 실측(모든 크기): 긴 점선 2.40/1.44,
    /// 점선 0.48/0.72, 일점쇄선 4.80/1.44/0.48/1.44, 이점쇄선 …/0.48/1.44, 긴 파선 4.80/1.44.
    /// 한글 문서 40pt의 긴 점선(11.40/6.84pt)과 갈리는 자리다.
    func testHwp2007DashesUseTheFixedUnit() {
        let expectations: [(HwpBorderType, [CGFloat])] = [
            (.longDotLine, [2.40, 1.44]),
            (.dotLine, [0.48, 0.72]),
            (.dashDot, [4.80, 1.44, 0.48, 1.44]),
            (.dashDotDot, [4.80, 1.44, 0.48, 1.44, 0.48, 1.44]),
            (.longDash, [4.80, 1.44]),
        ]
        for (shape, lengths) in expectations {
            let pieces = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(shape)))
            var x: CGFloat = 0
            for (index, length) in (lengths + lengths).enumerated() {
                if index % 2 == 0 {
                    let piece = pieces[index / 2]
                    expect(piece.minX)
                        .to(beCloseTo(x, within: 1e-9), description: "\(shape) \(index)")
                    expect(piece.width).to(beCloseTo(length, within: 1e-9), description: "\(shape)")
                    // 선 두께·중심은 단선과 같다
                    expect(piece.minY).to(beCloseTo(-0.18, within: 1e-9))
                    expect(piece.height).to(beCloseTo(0.36, within: 1e-9))
                }
                x += length
            }
        }
    }

    /// 원형 점선: 칠해지는 지름 1.32pt(한글: 1.20pt 원 + 0.12pt 윤곽), 중심 간격 3.0pt, 첫
    /// 중심 = run 시작. 중심은 띠가 자라는 쪽으로 0.24pt 옮겨진다 — 아래 밑줄은 아래, 위 밑줄은
    /// 위, 취소선은 제자리 (한글 실측: 단선 중심 대비 −0.24 / +0.24 / 0).
    func testHwp2007CirclesAreFixedAndShiftTowardTheBandGrowth() {
        let expectations: [(HwpLineShapeGeometry.Placement, CGFloat)] = [
            (.underlineBelow, 0.24), (.strikethrough, 0), (.underlineAbove, -0.24),
        ]
        for (placement, centerY) in expectations {
            let line = Self.hwp2007Line(.circle, length: 30, placement: placement)
            let pieces = Self.pieces(HwpLineShapeGeometry.path(for: line))
            expect(pieces.count) == 10 // 0, 3, …, 27 (30은 반지름이 넘친다)
            expect(pieces[0].width).to(beCloseTo(1.32, within: 1e-3))
            expect(pieces[0].height).to(beCloseTo(1.32, within: 1e-3))
            expect(pieces[0].midX).to(beCloseTo(0, within: 1e-3))
            expect(pieces[1].midX).to(beCloseTo(3.0, within: 1e-3))
            expect(pieces[0].midY).to(beCloseTo(centerY, within: 1e-3), description: "\(placement)")
            let extent = HwpLineShapeGeometry.crossExtent(of: line)
            expect(extent?.lowerBound).to(beCloseTo(centerY - 0.66, within: 1e-9))
            expect(extent?.upperBound).to(beCloseTo(centerY + 0.66, within: 1e-9))
        }
        // 한글 문서의 원은 옮겨지지 않는다 (종전 그대로)
        let native = Self.characterLine(.circle, fontSize: 20, placement: .underlineBelow)
        expect(Self.pieces(HwpLineShapeGeometry.path(for: native))[0].midY)
            .to(beCloseTo(0, within: 1e-3))
    }

    /// 2중선: 1.44pt 띠 [1/4, 1/2, 1/4] — 0.36pt 두 줄, 중심 간격 1.08pt. 아래 밑줄은 첫 줄이
    /// 단선 자리 그대로(한글: −6.12 / −7.20pt at 40pt), 위 밑줄은 거울, 취소선은 가운데 (±0.54;
    /// 한글 +14.64 / +13.56 대 +14.04).
    func testHwp2007DoubleLineIsAFixedBand() {
        let below = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(.doubleLine)))
        expect(below.map(\.height)).to(beCloseTo([0.36, 0.36], within: 1e-9))
        expect(below[0].midY).to(beCloseTo(0, within: 1e-9))
        expect(below[1].midY).to(beCloseTo(1.08, within: 1e-9))
        let above = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(
            .doubleLine, placement: .underlineAbove
        )))
        expect(above[0].midY).to(beCloseTo(-1.08, within: 1e-9))
        expect(above[1].midY).to(beCloseTo(0, within: 1e-9))
        let strike = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(
            .doubleLine, placement: .strikethrough
        )))
        expect(strike[0].midY).to(beCloseTo(-0.54, within: 1e-9))
        expect(strike[1].midY).to(beCloseTo(0.54, within: 1e-9))
    }

    /// 굵은 여러 줄: 4.2pt 띠 — 가는+굵은 [0.96, 0.96 공백, 2.28], 굵은+가는은 거울, 3중선
    /// [0.6, 0.6, 1.8, 0.6, 0.6]. 한글 실측(아래 밑줄 40pt, 같은 크기 실선 중심 대비 아래 양수):
    /// 가는+굵은 0.36·2.88 (0.96·2.28pt), 굵은+가는 0.96·3.60, 3중선 0.12·1.92·3.72 — 모델
    /// 0.30·2.88 / 0.96·3.54 / 0.12·1.92·3.72와 장치 반 단위(0.06) 안이다.
    func testHwp2007ThickBandsFollowTheMeasuredStripes() {
        func stripes(_ shape: HwpBorderType) -> [(center: CGFloat, height: CGFloat)] {
            Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(shape)))
                .sorted { $0.minY < $1.minY }
                .map { ($0.midY, $0.height) }
        }
        let thinThick = stripes(.thinThickDoubleLine)
        expect(thinThick.map(\.height)).to(beCloseTo([0.96, 2.28], within: 1e-9))
        expect(thinThick.map(\.center)).to(beCloseTo([0.30, 2.88], within: 0.07))
        let thickThin = stripes(.thickThinDoubleLine)
        expect(thickThin.map(\.height)).to(beCloseTo([2.28, 0.96], within: 1e-9))
        expect(thickThin.map(\.center)).to(beCloseTo([0.96, 3.54], within: 0.07))
        let triple = stripes(.thinThickThinTripleLine)
        expect(triple.map(\.height)).to(beCloseTo([0.6, 1.8, 0.6], within: 1e-9))
        expect(triple.map(\.center)).to(beCloseTo([0.12, 1.92, 3.72], within: 1e-9))
        // 띠 전체 = 4.2pt, 위 가장자리 = 단선 위 가장자리
        let band = HwpLineShapeGeometry.crossExtent(of: Self.hwp2007Line(.thinThickThinTripleLine))
        expect(band?.lowerBound).to(beCloseTo(-0.18, within: 1e-9))
        expect(band?.upperBound).to(beCloseTo(4.02, within: 1e-9))
        // 취소선은 가운데 (한글: 가는+굵은 취소선 +15.60 / +13.08pt 대 +14.04 → −1.56 / +0.96)
        let strike = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(
            .thinThickDoubleLine, placement: .strikethrough
        ))).sorted { $0.minY < $1.minY }
        expect(strike[0].midY).to(beCloseTo(-1.62, within: 1e-9))
        expect(strike[1].midY).to(beCloseTo(0.96, within: 1e-9))
    }

    /// 물결: 진폭 2.88pt·획 0.72pt·반주기 3.0pt, 위 꼭짓점은 단선 중심 위 0.12pt + 1.2pt ×
    /// 종류(1·2·3). 2중 물결: 진폭 1.44pt·획 0.36pt·반주기 1.56pt·둘째 파 1.08pt 아래, 기점
    /// 0.18pt·계단 0.54pt. 한글 실측(단선 참값 중심 위, 크기별 평균): 물결 1.32·2.49·3.71pt,
    /// 2중 물결 0.77·1.29·1.79pt — 모델은 1.32·2.52·3.72 / 0.72·1.26·1.80.
    func testHwp2007WavesAreFixedWithTheirOwnSteps() {
        struct Tops {
            let placement: HwpLineShapeGeometry.Placement
            let wave: CGFloat
            let double: CGFloat
        }
        let expectations = [
            Tops(placement: .underlineBelow, wave: -1.32, double: -0.72),
            Tops(placement: .strikethrough, wave: -2.52, double: -1.26),
            Tops(placement: .underlineAbove, wave: -3.72, double: -1.80),
        ]
        for tops in expectations {
            let (placement, waveTop, doubleTop) = (tops.placement, tops.wave, tops.double)
            let wave = Self.hwp2007Line(.wave, length: 12, placement: placement)
            expect(HwpLineShapeGeometry.waveTopVertex(for: wave))
                .to(beCloseTo(waveTop, within: 1e-9), description: "\(placement)")
            let waveExtent = HwpLineShapeGeometry.crossExtent(of: wave)
            expect(waveExtent?.lowerBound).to(beCloseTo(waveTop - 0.36, within: 1e-9))
            expect(waveExtent?.upperBound).to(beCloseTo(waveTop + 2.88 + 0.36, within: 1e-9))
            let double = Self.hwp2007Line(.doubleWave, length: 12, placement: placement)
            expect(HwpLineShapeGeometry.waveTopVertex(for: double))
                .to(beCloseTo(doubleTop, within: 1e-9), description: "\(placement)")
            // 두 파의 꼭짓점 띠 = 진폭 1.44 + 둘째 파 1.08, 획 반폭 0.18
            let doubleExtent = HwpLineShapeGeometry.crossExtent(of: double)
            expect(doubleExtent?.lowerBound).to(beCloseTo(doubleTop - 0.18, within: 1e-9))
            expect(doubleExtent?.upperBound)
                .to(beCloseTo(doubleTop + 1.08 + 1.44 + 0.18, within: 1e-9))
        }
        // 45° 대각선: 첫 대각선 x 0~2.88, 둘째는 반주기 3.0에서 (2중 물결은 1.44 / 1.56)
        let wave = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(.wave, length: 12)))
            .filter { $0.height > 2 }
        let corner: CGFloat = 0.36 / 2.0.squareRoot()
        expect(wave[0].minX).to(beCloseTo(-corner, within: 1e-9))
        expect(wave[0].width).to(beCloseTo(2.88 + 2 * corner, within: 1e-9))
        expect(wave[1].minX).to(beCloseTo(3.0 - corner, within: 1e-9))
        let double = Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(
            .doubleWave, length: 12
        ))).filter { $0.height > 1 }
        let thin: CGFloat = 0.18 / 2.0.squareRoot()
        // 같은 x 위상의 두 파 — 첫 두 대각선이 x 0에서 함께 시작한다
        expect(double.prefix(2).map(\.minX)).to(beCloseTo([-thin, -thin], within: 1e-9))
        expect(double[0].width).to(beCloseTo(1.44 + 2 * thin, within: 1e-9))
        expect(double.dropFirst(2).first?.minX).to(beCloseTo(1.56 - thin, within: 1e-9))
    }

    /// 3D 넷은 이 갈래에서도 실선 대체이고(한글은 아무것도 그리지 않는다 — #191과 같은 판단),
    /// 두께는 고정 0.36pt 그대로다. 대시는 길이 끝에서 잘리고 물결은 마지막 반주기를 끝까지
    /// 그리는 규칙도 한글 문서와 같다.
    func testHwp2007KeepsTheSharedLineRules() {
        for shape in [HwpBorderType.thick3D, .thick3DReverse, .single3D] {
            expect(Self.pieces(HwpLineShapeGeometry.path(for: Self.hwp2007Line(shape))))
                .to(equal([CGRect(x: 0, y: -0.18, width: 200, height: 0.36)]))
        }
        let dashed = Self.hwp2007Line(.longDotLine, length: 5)
        expect(Self.pieces(HwpLineShapeGeometry.path(for: dashed)).map(\.maxX).last)
            .to(beCloseTo(5, within: 1e-9)) // 2.40 선, 1.44 공백, 1.16만 남은 둘째 선
        // 물결 12pt: 반주기 3.0 → 4개, 끝 = 4 × 3.0 − 0.12 = 11.88 (길이 안) / 13pt면 5개로 넘친다
        let wave13 = Self.hwp2007Line(.wave, length: 13)
        expect(HwpLineShapeGeometry.alongExtent(of: wave13)?.upperBound)
            .to(beCloseTo(14.88 + 0.72 / 2 / 2.0.squareRoot(), within: 1e-9))
        // 패턴 되풀이 상한도 같은 기준 (0.48pt 단위라 긴 점선 한 벌 3.84pt)
        expect(HwpLineShapeGeometry.patternRepeats(of: Self.hwp2007Line(.longDotLine, length: 384)))
            .to(beCloseTo(100, within: 1e-9))
    }

    /// 튜닝 상수 값 핀 — 실측과 어긋나게 바뀌면 여기서 먼저 빨개진다.
    func testHwp2007TuningConstantsMatchTheMeasurement() {
        typealias Shape = HwpRenderTuning.LineShape
        expect(Shape.hwp200XDashUnit) == 0.48
        expect(Shape.hwp200XCircleDiameter) == 1.32
        expect(Shape.hwp200XCirclePitch) == 3.0
        expect(Shape.hwp200XCircleCenterShift) == 0.24
        expect(Shape.hwp200XDoubleLineBand) == 1.44
        expect(Shape.hwp200XThickLineBand) == 4.2
        expect(Shape.hwp200XWaveAmplitude) == 2.88
        expect(Shape.hwp200XWaveStroke) == 0.72
        expect(Shape.hwp200XWaveTopStep) == 1.2
        expect(Shape.hwp200XWaveTopBase) == 0.12
        expect(Shape.hwp200XDoubleWaveAmplitude) == 1.44
        expect(Shape.hwp200XDoubleWaveStroke) == 0.36
        expect(Shape.hwp200XDoubleWaveOffset) == 1.08
        expect(Shape.hwp200XDoubleWaveTopStep) == 0.54
        expect(Shape.hwp200XDoubleWaveTopBase) == 0.18
    }
}
