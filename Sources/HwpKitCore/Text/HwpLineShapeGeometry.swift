import CoreGraphics
import CoreHwp
import Foundation

/// 선 모양(표 25 `HwpBorderType`)을 **채우기 경로**로 푼다 — 밑줄·취소선·글자 위 밑줄,
/// 표 셀 테두리, 단 구분선이 함께 쓴다 (#191). 값은 전부 `HwpRenderTuning.LineShape`
/// (한글 12.30.0 PDF 실측).
///
/// 로컬 좌표: x = 선을 따라가는 축 (0 = 선 시작, `length` = 끝), y = 가로지르는 축 (0 =
/// **단선의 중심**, 양수 = 페이지 아래쪽 / 세로선이면 오른쪽). 호출자가 방향·위치에 맞는
/// 아핀 변환으로 옮긴다 — 가로 선은 (x, y) → (시작 x + x, 중심 y + y), 세로 선은
/// (x, y) → (중심 x + y, 시작 y + x), CoreText의 y-위 텍스트 공간이면 y를 뒤집는다.
///
/// 두 축척(`Scale`)이 있다. 글자선은 패턴·띠·물결이 **글자 크기**에 비례하고 (대시 단위
/// 0.057em, 2중선 띠 0.12em, 그 밖의 여러 줄 띠 0.2em, 물결 진폭 0.112em), 테두리·단
/// 구분선은 **명목 두께**에 비례한다 (대시 단위 22/15 t, 여러 줄 띠 t, 물결 진폭 t). 두
/// 축척의 모양 표(패턴 배수·띠 안 구성)는 같다.
///
/// 여러 줄·물결 띠의 세로 자리는 `Placement`가 정한다 — 글자 아래 밑줄은 단선 띠의 위
/// 가장자리에서 아래로 자라고, 취소선과 테두리·단 구분선은 단선 중심에 가운데 맞추며, 글자
/// 위 밑줄은 아래 가장자리에서 위로 자란다. 물결은 예외로 한글이 종류마다 다른 만큼 위로
/// 올려 그린다 (`HwpRenderTuning.LineShape.characterWaveTopShiftThicknessRatio`·
/// `borderWaveShiftThicknessRatio`). 2중 물결의 둘째 파는 테두리만 선 방향으로도 옮긴다
/// (`doubleWaveOffset(for:)`). 물결은 마지막 반주기를 자르지 않아 `length`를 넘칠 수 있다
/// (`alongExtent(of:)`).
///
/// 3D 넷(`thick3D`·`thick3DReverse`·`single3D`·`single3DReverse`)은 한글 macOS가 아무것도
/// 그리지 않지만 (실측) 여기서는 **실선으로 대체**한다 — 지정한 테두리가 통째로 사라지는
/// 것보다 낫고, 윈도 한글은 그린다. `none`은 경로 없음이다.
public enum HwpLineShapeGeometry {
    /// 패턴 축척의 갈래
    public enum Scale: Equatable, Sendable {
        /// 글자선 — `fontSize`는 첨자 축소 전 글자 크기 (pt)
        case characterLine(fontSize: CGFloat)
        /// 표 셀 테두리·단 구분선 — 명목 두께에 비례
        case border
    }

    /// 여러 줄·물결 띠의 세로 자리
    public enum Placement: Equatable, Sendable {
        /// 글자 아래 밑줄 — 띠는 단선의 위 가장자리에서 아래로, 물결은 두께 1배 위에서
        case underlineBelow
        /// 취소선·글자 가운데 밑줄 — 띠는 단선 중심에 가운데, 물결은 두께 2배 위에서
        case strikethrough
        /// 글자 위 밑줄 — 띠는 단선의 아래 가장자리에서 위로, 물결은 두께 3배 위에서
        case underlineAbove
        /// 표 셀 테두리 — 띠는 선 중심에 가운데, 물결은 두께 3/8만큼 −y 쪽, 2중 물결의
        /// 둘째 파는 선 방향으로 3/4 두께 뒤에서 시작해 내려가는 획이 첫 파와 한 직선을
        /// 이룬다 (마름모 격자)
        case border
        /// 단 구분선 — 테두리와 같되 2중 물결의 둘째 파가 첫 파와 같은 x에서 시작한다
        case divider
    }

    /// 선 하나의 입력
    public struct Line: Equatable, Sendable {
        public var shape: HwpBorderType
        /// 선 길이 (pt, x 축)
        public var length: CGFloat
        /// 단선 두께 (pt) — 글자선은 `HwpDecorationLineGeometry.Line.thickness`, 테두리는
        /// 표 26 굵기
        public var thickness: CGFloat
        public var scale: Scale
        public var placement: Placement

        public init(
            shape: HwpBorderType,
            length: CGFloat,
            thickness: CGFloat,
            scale: Scale,
            placement: Placement
        ) {
            self.shape = shape
            self.length = length
            self.thickness = thickness
            self.scale = scale
            self.placement = placement
        }
    }

    /// 패턴 반복 수의 상한 — 길이/축척이 비정상이라 이보다 많이 되풀이될 선은 실선 띠로
    /// 떨어뜨린다 (수십만 개 부분 경로를 만들지 않게)
    static let maxPatternRepeats: CGFloat = 100_000

    /// 로컬 좌표의 채우기 경로. 그릴 것이 없으면 (`none`·길이 0·두께 0·유한하지 않은 입력)
    /// nil.
    public static func path(for line: Line) -> CGPath? {
        guard isDrawable(line) else { return nil }
        let path = CGMutablePath()
        switch line.shape {
        case .none:
            return nil
        case .line, .thick3D, .thick3DReverse, .single3D, .single3DReverse:
            path.addRect(solidBand(for: line))
        case _ where patternRepeats(of: line) > maxPatternRepeats:
            path.addRect(solidBand(for: line))
        case .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash:
            addDashes(dashPattern(for: line.shape, unit: dashUnit(for: line)), to: path, line: line)
        case .circle:
            addCircles(to: path, line: line)
        case .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine:
            for stripe in stripes(for: line) {
                path.addRect(stripe)
            }
        case .wave:
            addWave(to: path, line: line, offset: .zero)
        case .doubleWave:
            addWave(to: path, line: line, offset: .zero)
            addWave(to: path, line: line, offset: doubleWaveOffset(for: line))
        }
        return path.isEmpty ? nil : path
    }

    /// 이 선이 칠하는 가로지르는 축의 범위 (로컬 y, [min, max]) — 히트 판정·클리핑용. 경로
    /// 없는 입력이면 nil.
    public static func crossExtent(of line: Line) -> ClosedRange<CGFloat>? {
        guard isDrawable(line) else { return nil }
        switch line.shape {
        case .none:
            return nil
        case .line, .thick3D, .thick3DReverse, .single3D, .single3DReverse,
             .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash:
            let band = solidBand(for: line)
            return band.minY ... band.maxY
        case _ where patternRepeats(of: line) > maxPatternRepeats:
            let band = solidBand(for: line)
            return band.minY ... band.maxY
        case .circle:
            let radius = circleDiameter(for: line) / 2
            guard radius <= line.length else { return nil }
            return -radius ... radius
        case .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine:
            let band = multiLineBand(for: line)
            return band.lowerBound ... band.upperBound
        case .wave:
            let top = waveTopVertex(for: line)
            let half = waveStroke(for: line) / 2
            return (top - half) ... (top + waveAmplitude(for: line) + half)
        case .doubleWave:
            let top = waveTopVertex(for: line)
            let half = waveStroke(for: line) / 2
            let offset = doubleWaveOffset(for: line)
            return (top - half) ... (top + offset.y + waveAmplitude(for: line) + half)
        }
    }

    /// 이 선이 칠하는 선 방향의 범위 (로컬 x). 대시·여러 줄은 [0, `length`]이고, 원형 점선은
    /// 첫 원의 중심이 0이라 반지름만큼 앞으로 나가며, 물결은 한글처럼 마지막 반주기를 **끝까지
    /// 그려** `length`를 넘을 수 있고 45° 획의 butt cap 모서리가 양 끝에서 획 반폭/√2만큼 더
    /// 나간다. 경로 없는 입력(원 하나도 안 들어가는 짧은 원형 점선 포함)이면 nil.
    public static func alongExtent(of line: Line) -> ClosedRange<CGFloat>? {
        guard isDrawable(line) else { return nil }
        switch line.shape {
        case .wave, .doubleWave:
            guard patternRepeats(of: line) <= maxPatternRepeats else { return 0 ... line.length }
            let corner = waveStroke(for: line) / 2 / 2.0.squareRoot()
            var end = waveEnd(for: line, offsetX: 0)
            if line.shape == .doubleWave {
                end = max(end, waveEnd(for: line, offsetX: doubleWaveOffset(for: line).x))
            }
            return -corner ... (end + corner)
        case .circle where patternRepeats(of: line) <= maxPatternRepeats:
            let radius = circleDiameter(for: line) / 2
            guard radius <= line.length else { return nil }
            return -radius ... line.length
        default:
            return 0 ... line.length
        }
    }

    /// 경로가 있는 입력인가 — 길이·두께·글자 크기가 유한한 양수이고 `none`이 아니다
    static func isDrawable(_ line: Line) -> Bool {
        line.length.isFinite && line.thickness.isFinite && line.length > 0 && line.thickness > 0
            && line.shape != .none && fontSizeIsPositive(line.scale)
    }

    private static func fontSizeIsPositive(_ scale: Scale) -> Bool {
        if case let .characterLine(fontSize) = scale {
            return fontSize.isFinite && fontSize > 0
        }
        return true
    }

    /// 패턴이 선 길이 안에서 되풀이되는 횟수 (대시는 패턴 한 벌, 원은 피치, 물결은 반주기
    /// 단위). 되풀이하지 않는 모양은 0.
    static func patternRepeats(of line: Line) -> CGFloat {
        let unit: CGFloat = switch line.shape {
        case .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash:
            dashPattern(for: line.shape, unit: dashUnit(for: line)).reduce(0, +)
        case .circle:
            circlePitch(for: line)
        case .wave, .doubleWave:
            waveHalfPeriod(for: line)
        default:
            0
        }
        guard unit > 0, unit.isFinite else { return 0 }
        return line.length / unit
    }
}

// MARK: - 축척·자리·모양 (같은 파일의 확장 — 본체는 공개 진입점만 둔다)

extension HwpLineShapeGeometry {
    // MARK: - 축척

    /// 대시 패턴의 단위 길이 (`HwpRenderTuning.LineShape.characterDashUnitEmRatio`·
    /// `borderDashUnitThicknessRatio`)
    static func dashUnit(for line: Line) -> CGFloat {
        switch line.scale {
        case let .characterLine(fontSize):
            fontSize * HwpRenderTuning.LineShape.characterDashUnitEmRatio
        case .border:
            line.thickness * HwpRenderTuning.LineShape.borderDashUnitThicknessRatio
        }
    }

    /// 여러 줄 띠의 높이 — 글자선은 2중선 0.12em·그 밖 0.2em, 테두리는 두께
    static func multiLineBandHeight(for line: Line) -> CGFloat {
        switch line.scale {
        case let .characterLine(fontSize):
            line.shape == .doubleLine
                ? fontSize * HwpRenderTuning.LineShape.characterDoubleLineBandEmRatio
                : fontSize * HwpRenderTuning.LineShape.characterThickBandEmRatio
        case .border:
            line.thickness
        }
    }

    static func waveAmplitude(for line: Line) -> CGFloat {
        switch line.scale {
        case let .characterLine(fontSize):
            fontSize * HwpRenderTuning.LineShape.characterWaveAmplitudeEmRatio
        case .border:
            line.thickness
        }
    }

    static func waveStroke(for line: Line) -> CGFloat {
        switch line.scale {
        case let .characterLine(fontSize):
            fontSize * HwpRenderTuning.LineShape.characterWaveStrokeEmRatio
        case .border:
            line.thickness * HwpRenderTuning.LineShape.borderWaveStrokeThicknessRatio
        }
    }

    /// 물결 반주기 — 45° 대각선(진폭만큼 전진)에 꼭짓점 평탄을 더한 길이
    static func waveHalfPeriod(for line: Line) -> CGFloat {
        waveAmplitude(for: line) + HwpRenderTuning.LineShape.waveVertexFlat
    }

    /// `offsetX`에서 시작한 물결의 대각선 개수 — 시작점이 `length` 앞에 있는 반주기는 끝까지
    /// 그린다 (한글은 마지막 대각선을 자르지 않는다). 시작점이 `length` 밖이면 0.
    static func waveDiagonalCount(for line: Line, offsetX: CGFloat) -> Int {
        let halfPeriod = waveHalfPeriod(for: line)
        let remaining = line.length - offsetX
        guard halfPeriod > 0, remaining > 1e-6 else { return 0 }
        return max(1, Int((remaining / halfPeriod - 1e-6).rounded(.up)))
    }

    /// `offsetX`에서 시작한 물결의 마지막 대각선이 끝나는 x (대각선이 없으면 `length` 안)
    static func waveEnd(for line: Line, offsetX: CGFloat) -> CGFloat {
        let count = waveDiagonalCount(for: line, offsetX: offsetX)
        guard count > 0 else { return min(offsetX, line.length) }
        return offsetX + CGFloat(count) * waveHalfPeriod(for: line)
            - HwpRenderTuning.LineShape.waveVertexFlat
    }

    static func circleDiameter(for line: Line) -> CGFloat {
        switch line.scale {
        case .characterLine:
            dashUnit(for: line)
        case .border:
            line.thickness
        }
    }

    static func circlePitch(for line: Line) -> CGFloat {
        switch line.scale {
        case .characterLine:
            circleDiameter(for: line) * HwpRenderTuning.LineShape.characterCirclePitchDiameterRatio
        case .border:
            line.thickness * HwpRenderTuning.LineShape.borderCirclePitchThicknessRatio
        }
    }

    // MARK: - 자리

    /// 단선(실선·대시)의 띠 — 중심 0에 두께만큼
    static func solidBand(for line: Line) -> CGRect {
        CGRect(x: 0, y: -line.thickness / 2, width: line.length, height: line.thickness)
    }

    /// 여러 줄 띠의 세로 범위 — `Placement`에 따라 단선 띠에 맞춘다
    static func multiLineBand(for line: Line) -> ClosedRange<CGFloat> {
        let height = multiLineBandHeight(for: line)
        let half = line.thickness / 2
        switch line.placement {
        case .underlineBelow:
            return -half ... (-half + height)
        case .strikethrough, .border, .divider:
            return (-height / 2) ... (height / 2)
        case .underlineAbove:
            return (half - height) ... half
        }
    }

    /// 물결 꼭짓점 띠의 위쪽 꼭짓점 y — 글자선은 단선 위 가장자리에서 종류 × 두께만큼 위,
    /// 테두리는 중심에서 3/8 두께 위에 진폭 절반을 더 올린 곳
    static func waveTopVertex(for line: Line) -> CGFloat {
        let half = line.thickness / 2
        let steps: CGFloat
        switch line.placement {
        case .underlineBelow: steps = 1
        case .strikethrough: steps = 2
        case .underlineAbove: steps = 3
        case .border, .divider:
            return -line.thickness * HwpRenderTuning.LineShape.borderWaveShiftThicknessRatio
                - waveAmplitude(for: line) / 2
        }
        let shift = HwpRenderTuning.LineShape.characterWaveTopShiftThicknessRatio
        return -half - line.thickness * shift * steps
    }

    /// 2중 물결의 둘째 파 이동량 — 글자선은 진폭의 0.8배 아래(같은 x 위상), 테두리는 선
    /// 방향·가로지르는 축 모두 3/4 두께 (내려가는 획이 첫 파와 한 직선을 이루는 마름모
    /// 격자), 단 구분선은 가로지르는 축만 3/4 두께
    static func doubleWaveOffset(for line: Line) -> CGPoint {
        switch line.scale {
        case .characterLine:
            return CGPoint(
                x: 0,
                y: waveAmplitude(for: line)
                    * HwpRenderTuning.LineShape.characterDoubleWaveOffsetAmplitudeRatio
            )
        case .border:
            let offset = line.thickness
                * HwpRenderTuning.LineShape.borderDoubleWaveOffsetThicknessRatio
            return CGPoint(x: line.placement == .divider ? 0 : offset, y: offset)
        }
    }

    // MARK: - 모양

    /// 대시 패턴 (선, 공백, 선, 공백 … 순, 단위의 배수). 한글은 OWPML 이름과 반대로
    /// `DOT`(`longDotLine`)을 긴 점선으로, `DASH`(`dotLine`)를 점선으로 그린다 (#177).
    static func dashPattern(for shape: HwpBorderType, unit: CGFloat) -> [CGFloat] {
        let multiples: [CGFloat] = switch shape {
        case .longDotLine: [5, 3]
        case .dotLine: [1, 1.5]
        case .dashDot: [10, 3, 1, 3]
        case .dashDotDot: [10, 3, 1, 3, 1, 3]
        case .longDash: [10, 3]
        default: []
        }
        return multiples.map { $0 * unit }
    }

    /// 여러 줄의 띠 안 구성 — 띠 높이에 대한 비율 [(시작, 끝)], 위(−y)에서 아래로
    static func stripeFractions(for shape: HwpBorderType) -> [(CGFloat, CGFloat)] {
        switch shape {
        case .doubleLine: [(0, 0.25), (0.75, 1)]
        case .thinThickDoubleLine: [(0, 0.25), (0.5, 1)]
        case .thickThinDoubleLine: [(0, 0.5), (0.75, 1)]
        case .thinThickThinTripleLine: [(0, 1 / 6), (1 / 3, 2 / 3), (5 / 6, 1)]
        default: []
        }
    }

    /// 여러 줄의 부속선 띠 (로컬 좌표, 선 길이 전체)
    static func stripes(for line: Line) -> [CGRect] {
        let band = multiLineBand(for: line)
        let height = band.upperBound - band.lowerBound
        return stripeFractions(for: line.shape).map { start, end in
            CGRect(
                x: 0,
                y: band.lowerBound + height * start,
                width: line.length,
                height: height * (end - start)
            )
        }
    }

    private static func addDashes(_ pattern: [CGFloat], to path: CGMutablePath, line: Line) {
        guard pattern.count >= 2, pattern.allSatisfy({ $0 > 0 }) else {
            path.addRect(solidBand(for: line))
            return
        }
        let band = solidBand(for: line)
        var x: CGFloat = 0
        var index = 0
        while x < line.length {
            let span = pattern[index % pattern.count]
            if index % 2 == 0 {
                path.addRect(CGRect(
                    x: x, y: band.minY, width: min(span, line.length - x), height: band.height
                ))
            }
            x += span
            index += 1
        }
    }

    private static func addCircles(to path: CGMutablePath, line: Line) {
        let diameter = circleDiameter(for: line)
        let pitch = circlePitch(for: line)
        guard diameter > 0, pitch > 0 else { return }
        var center: CGFloat = 0
        while center + diameter / 2 <= line.length {
            path.addEllipse(in: CGRect(
                x: center - diameter / 2, y: -diameter / 2, width: diameter, height: diameter
            ))
            center += pitch
        }
    }

    /// 45° 지그재그 — 위 꼭짓점에서 시작해 진폭만큼 내려갔다 올라오기를 반복하고, 꼭짓점
    /// 사이의 평탄(`waveVertexFlat`)은 짧은 띠로 잇는다. 대각선은 획 두께의 평행사변형
    /// (butt cap)이고, `length` 앞에서 시작한 마지막 대각선은 자르지 않고 끝까지 그린다
    /// (한글 실측 — `alongExtent(of:)`가 그 넘침을 보고한다).
    private static func addWave(to path: CGMutablePath, line: Line, offset: CGPoint) {
        let amplitude = waveAmplitude(for: line)
        let stroke = waveStroke(for: line)
        guard amplitude > 0, stroke > 0 else { return }
        let flat = HwpRenderTuning.LineShape.waveVertexFlat
        let halfPeriod = waveHalfPeriod(for: line)
        let top = waveTopVertex(for: line) + offset.y
        let bottom = top + amplitude
        let count = waveDiagonalCount(for: line, offsetX: offset.x)
        for index in 0 ..< count {
            let goingDown = index.isMultiple(of: 2)
            let startX = offset.x + CGFloat(index) * halfPeriod
            let start = CGPoint(x: startX, y: goingDown ? top : bottom)
            let end = CGPoint(x: startX + amplitude, y: goingDown ? bottom : top)
            addSegment(from: start, to: end, stroke: stroke, into: path)
            if index + 1 < count, flat > 0 {
                path.addRect(CGRect(
                    x: end.x, y: end.y - stroke / 2, width: flat, height: stroke
                ))
            }
        }
    }

    /// 두 점을 잇는 획 두께 `stroke`의 평행사변형 (butt cap)
    private static func addSegment(
        from start: CGPoint, to end: CGPoint, stroke: CGFloat, into path: CGMutablePath
    ) {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > 0 else { return }
        let scale = stroke / 2 / lengthSquared.squareRoot()
        let normal = CGPoint(x: -delta.y * scale, y: delta.x * scale)
        path.move(to: CGPoint(x: start.x + normal.x, y: start.y + normal.y))
        path.addLine(to: CGPoint(x: end.x + normal.x, y: end.y + normal.y))
        path.addLine(to: CGPoint(x: end.x - normal.x, y: end.y - normal.y))
        path.addLine(to: CGPoint(x: start.x - normal.x, y: start.y - normal.y))
        path.closeSubpath()
    }
}

public extension HwpBorderType {
    /// 글자 모양의 밑줄·취소선 모양 값(표 35 4비트, 실선 0)을 테두리선 종류로 옮긴다 —
    /// 글자선 값은 `LINETYPE2 − 1`이라 1을 더하면 같은 표다 (#177 실측). 4비트라
    /// `single3DReverse`(17)는 담기지 않고, 0~15 밖의 값은 실선으로 떨어진다 (`none`이나
    /// 표 밖으로 새지 않게).
    init(characterLineShape shape: Int) {
        guard (0 ... 15).contains(shape) else {
            self = .line
            return
        }
        self = HwpBorderType(rawValue: shape + 1) ?? .line
    }
}
