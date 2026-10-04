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
/// 세 축척(`Scale`)이 있다. 글자선의 여러 줄·물결은 띠가 **글자 크기**에서 풀리되 한글처럼 600dpi
/// 장치 단위의 정수다 (2중선·물결 띠 0.113em, 그 밖의 여러 줄 띠 0.198em을 HWPUNIT·장치 단위로 차례로
/// 반올림해 부속선·획을 나눈다, #252). 테두리·단 구분선의 여러 줄·물결은 같은 정수 규칙에 띠만 **같은
/// 굵기 실선의 획**(표 26 굵기의 무늬 두께 t에서 B = round(t ÷ 12)u)을 넣는다 (#253) — 두 갈래 모두
/// `HwpLineShapeGeometry+DeviceBands.swift`. 한글 2007 호환 문서의 글자선은 **고정 pt**다 (대시 단위
/// 0.48pt, 2중선 띠 1.44pt, 그 밖의 여러 줄 띠 4.2pt, 물결 진폭 2.88pt — #227). 그 고정 띠 안 구성만
/// 비율로 나눈다 (`hwp200XStripeFractions(for:)`). 대시와 원형 점선도 한글처럼 선·공백 길이와 원의
/// 지름·간격을 600dpi 장치 단위(0.12pt)의 정수로 정한다. 무늬 두께(글자선은 글자 크기의 0.039배, 테두리·단 구분선은 표 26
/// 굵기마다의 값)에서 단위 22/15 t를 장치 단위로 풀고, 단 구분선과 셀 간격이 있는 표의 셀 테두리는
/// 셀 간격이 없는 표의 셀 테두리가 아니라 글자선과 같은 점 무늬로 그린다 (#239·#243·#245 —
/// `dashDeviceUnits(for:hwpUnits:grid:)`·`circleDeviceGeometry(for:)`). 테두리 축척의 실선·대시 획
/// 두께도 장치 단위로 반올림한다 (`strokeThickness(for:)`) — 글자선의 실선·대시 획은 장식선 기하가
/// 같은 규칙으로 이미 반올림해 넘긴다 (`HwpDecorationLineGeometry.strokeThickness(referenceSize:)`, #252).
///
/// 여러 줄·물결 띠의 세로 자리는 `Placement`가 정한다 — 글자 아래 밑줄은 줄 상자 바닥(단선 띠의 위
/// 가장자리) 근처에서 아래로, 글자 위 밑줄은 줄 상자 상단 근처에서 위로, 취소선과 테두리·단
/// 구분선은 단선 중심에 놓인다. 글자선은 띠 가운데를 줄 상자 가장자리에서 띠 절반만큼 안쪽에 두고
/// 물결은 그 가운데에서 위로 올린다 (`characterBandCenter(for:halfBand:)`·`deviceWave(for:)`) —
/// 테두리·단 구분선도 같은 식이라 물결이 선 중심보다 −y 쪽(2중선의 위 줄 자리)에 놓인다. 2중 물결의 둘째
/// 파는 3 × 획 아래(2중선의 아래 줄 자리)다. 표 셀 테두리의 파는 선 방향 자리를 파마다 모서리 맥락으로
/// 받는다 (`Line.waveSpans` — `HwpBorderSet`이 2중선의 부속선처럼 물린다).
///
/// 원형 점선과 물결은 **자리가 `length`(물결은 파의 범위 끝) 앞인 요소를 끝까지 그린다** — 원은 중심,
/// 물결은 대각선 시작이 그 자리이고, 끝과 같은 자리의 요소는 그리지 않는다
/// (`patternElementCount(span:period:)`). 그래서 마지막 원·대각선이 `length`를 넘칠 수 있다
/// (`alongExtent(of:)`). 테두리·단 구분선의 물결은 마지막 대각선 뒤 평탄도 같은 규칙으로 긋는다. 표
/// 셀 테두리의 원형 점선도 같다 — 한글은 이웃 칸의 같은 모양 변을 한 선으로 이어 그 선의 끝에서 이 규칙을
/// 쓴다 (#238). 대시는 `length`에서 잘린다.
///
/// 이은 선(표 격자선의 사슬, #238)은 칸마다 **한 조각**씩 그린다 — 조각은 사슬 전체를 `length`로
/// 받고 제 몫의 요소 자리 범위(`Line.elementRange`)에 드는 원·대시만 그린다. 그래서 무늬의 위상이
/// 칸 경계를 넘어 이어지고, 칸 경계에 걸친 대시·원은 자리를 맡은 조각 하나가 통째로 그린다.
///
/// 3D 넷(`thick3D`·`thick3DReverse`·`single3D`·`single3DReverse`)은 한글 macOS가 아무것도
/// 그리지 않지만 (실측) 여기서는 **실선으로 대체**한다 — 지정한 테두리가 통째로 사라지는
/// 것보다 낫고, 윈도 한글은 그린다. `none`은 경로 없음이다.
public enum HwpLineShapeGeometry {
    /// 패턴 축척의 갈래
    public enum Scale: Equatable, Sendable {
        /// 글자선 — `fontSize`는 선의 기준 크기 (pt): 한글 문서는 밑줄이 줄 글자 기본 크기,
        /// 취소선이 run의 글자 모양 기본 크기이고(#226) MS 워드 호환 문서는 밑줄이 줄 글자 상자의
        /// 높이(`HwpMsWordLineBox.cellHeight` × 1.3), 취소선이 run의 글자 모양 기본 크기다 (#244).
        /// 여러 줄·물결의 띠도 이 크기에서 푼 장치 단위 정수다 (#252)
        case characterLine(fontSize: CGFloat)
        /// 한글 2007 호환 문서(`HwpCompatibleDocumentTarget.hwp200X`)의 글자선 — 패턴·띠·물결이
        /// 글자 크기와 무관한 고정 pt다 (#227, `HwpRenderTuning.LineShape.hwp200X*`). 선 두께가
        /// 고정 0.36pt인 것(#210)과 같은 갈래다.
        case hwp200XCharacterLine
        /// 표 셀 테두리·단 구분선 — 모든 무늬가 표 26 굵기마다의 무늬 두께에서 푼 장치 단위 정수다: 원형
        /// 점선과 대시(#239·#245), 실선·대시 획(#245), 여러 줄 띠·물결(같은 굵기 실선의 획 B를 띠로 —
        /// #253). `Placement`와 `Line.inSpacedTable`이 셀 간격 없는 표 셀 테두리의 격자와 단 구분선·셀
        /// 간격 있는 표의 점 무늬를 가른다 (#243)
        case border
    }

    /// 여러 줄·물결 띠의 세로 자리
    public enum Placement: Equatable, Sendable {
        /// 글자 아래 밑줄 — 한글 문서의 글자선은 띠 가운데가 줄 상자 바닥(단선의 위 가장자리)에서 띠
        /// 절반 아래(#252), 한글 2007 호환 문서는 띠가 단선의 위 가장자리에서 아래로 자라고 물결은
        /// 계단 1개 위에서 (물결 1.2pt·2중 물결 0.54pt — `waveTopStep(for:)`)
        case underlineBelow
        /// 취소선·글자 가운데 밑줄 — 띠는 단선 중심에 가운데(한글 2007 호환 문서의 물결은 계단 2개
        /// 위에서). MS 워드 호환 문서의 글자 아래·위 밑줄도 이 자리다 (#244 — 렌더러의
        /// `underlineShapePlacement`)
        case strikethrough
        /// 글자 위 밑줄 — 한글 문서의 글자선은 띠 가운데가 줄 상자 상단(단선의 아래 가장자리)에서
        /// 띠 절반 위, 한글 2007 호환 문서는 띠가 단선의 아래 가장자리에서 위로 자라고 물결은 계단
        /// 3개 위에서
        case underlineAbove
        /// 표 셀 테두리 — 여러 줄 띠는 선 중심에 가운데, 물결은 2중선의 위 줄 자리(선 중심보다 −y 쪽),
        /// 2중 물결의 둘째 파는 아래 줄 자리다 (#253). 파의 선 방향 자리는 모서리 맥락이라 호출자가
        /// `Line.waveSpans`로 준다. 원형 점선은 두께를 HWPUNIT·장치 단위로 차례로 반올림한 r이 단위인 격자다
        /// (간격 2r, #239) — 셀 간격이 있는 표(`Line.inSpacedTable`)만 단 구분선의 점 무늬다 (#243)
        case border
        /// 단 구분선 — 여러 줄·물결은 테두리와 같은 기하이고 두 파가 함께 구분선 시작에서 시작한다
        /// (#253). 원형 점선은 글자선과 같은 점 무늬다 (점 단위 = 두께 × 22/15, 간격 ≈ 2.5 × 점 단위, #239)
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
        /// 이 선이 그리는 무늬 요소의 **자리** 범위 (로컬 x, [lowerBound, upperBound)) — 이은 선의 한
        /// 조각이 제 몫만 그리게 한다 (#238). 자리는 원 중심·대시 시작이고, 요소의 개수·자리는 여전히
        /// `length` 전체로 정한다 (끝 규칙·대시 자름은 `length`에서). 실선(3D 넷 대체 포함)은 자리 0에
        /// 놓인 요소 하나라 0을 담은 조각만 선 전체를 그린다 — 한글은 이은 실선을 한 번에 긋는다 (#246).
        /// 여러 줄·물결에는 쓰지 않는다 (무시한다). nil이면 선 전체.
        public var elementRange: Range<CGFloat>?
        /// 셀 간격(표 76 `cellSpacing`)이 있는 표의 셀 테두리인가 — 테두리 축척(`Scale.border`)에서
        /// 단 구분선(`Placement.divider`)이 아닌 자리에서만 본다. 한글은 그 표의 원형 점선을 표 셀
        /// 테두리의 격자가 아니라 단 구분선과 같은 **점 무늬**로 그린다 (#243 — 셀 간격 1HWPUNIT부터,
        /// 표 26 굵기 16단 모두). 대시도 같다 — 셀 간격이 있는 표는 단 구분선과 같은 점 무늬 식, 없는
        /// 표는 격자 식으로 선·공백을 장치 단위로 반올림한다 (#245 — 1mm 점선 주기 88u vs 87u,
        /// `dashDeviceUnits(for:hwpUnits:grid:)`). 여러 줄·물결 경로는 그대로다 (한글도 여러 줄·물결은
        /// 셀 간격과 무관하다). 모서리에서 선이 나가거나 물러나는 길이는 호출자(`HwpBorderSet`)가
        /// `length`로 정한다.
        public var inSpacedTable: Bool
        /// 물결·2중 물결의 파마다 선 방향 범위 (로컬 x, [시작, 끝)) — 파 i의 대각선은 시작에서 반주기마다
        /// 놓이고 자리가 끝 앞인 것을 그린다. 표 셀 테두리는 모서리 맥락으로 파마다 정한다 (#253 —
        /// `HwpBorderSet`: 같은 모양·굵기 이웃과 맞물린 모서리에서는 두 파가 2중선의 두 부속선처럼 따로
        /// 물려 1×1 표의 위 변은 첫 파가 −2w·둘째 파가 +w에서 시작하고, 다른 모양 이웃 쪽에서는 두 파가 같은
        /// 자리다). 모자라면 마지막 범위를 쓰고, nil이면 모든 파가 [0, `length`)다. 끝이 유한하지 않은 범위는
        /// 빈 범위로 본다. 물결이 아니면 무시한다.
        public var waveSpans: [Range<CGFloat>]?

        public init(
            shape: HwpBorderType,
            length: CGFloat,
            thickness: CGFloat,
            scale: Scale,
            placement: Placement,
            elementRange: Range<CGFloat>? = nil,
            inSpacedTable: Bool = false,
            waveSpans: [Range<CGFloat>]? = nil
        ) {
            self.shape = shape
            self.length = length
            self.thickness = thickness
            self.scale = scale
            self.placement = placement
            self.elementRange = elementRange
            self.inSpacedTable = inSpacedTable
            self.waveSpans = waveSpans
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
            addOwnedSolidLine(to: path, line: line)
        case _ where patternRepeats(of: line) > maxPatternRepeats:
            addOwnedSolidBand(to: path, line: line)
        case .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash:
            addDashes(dashPattern(for: line), to: path, line: line)
        case .circle:
            addCircles(to: path, line: line)
        case .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine:
            for stripe in stripes(for: line) {
                path.addRect(stripe)
            }
        case .wave:
            addWave(to: path, line: line, index: 0)
        case .doubleWave:
            addDoubleWave(to: path, line: line)
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
            guard circleCount(for: line) > 0 else { return nil }
            let radius = circleDiameter(for: line) / 2
            let center = circleCenterY(for: line)
            return (center - radius) ... (center + radius)
        case .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine:
            let stripes = stripes(for: line)
            guard let top = stripes.map(\.minY).min(), let bottom = stripes.map(\.maxY).max()
            else { return nil }
            return top ... bottom
        case .wave, .doubleWave:
            let wave = wave(for: line)
            let half = wave.stroke / 2
            let range = wave.centerRange
            let second = line.shape == .doubleWave ? max(0, wave.secondOffset) : 0
            let lift = line.shape == .doubleWave ? min(0, wave.secondOffset) : 0
            return (range.lowerBound + lift - half) ... (range.upperBound + second + half)
        }
    }

    /// 이 선이 칠하는 선 방향의 범위 (로컬 x). 대시·여러 줄은 [0, `length`]이다. 원형 점선은
    /// 첫 원의 중심이 0이라 반지름만큼 앞으로 나가고, 중심이 `length` 앞인 마지막 원을 온전히
    /// 그려 뒤로도 반지름까지 넘칠 수 있다. 물결은 파마다 시작이 범위 끝 앞인 마지막 대각선을
    /// **끝까지 그려** 범위를 넘을 수 있고 45° 획의 butt cap 모서리가 양 끝에서 획
    /// 반폭/√2만큼 더 나간다 (`Line.waveSpans`가 있으면 파마다의 범위를 합친다). `elementRange`가 있는
    /// 대시·원형 점선은 그 범위에 자리를 둔 요소가 칠하는 범위다 (이웃 조각의 자리로 넘친 대시·원 포함).
    /// 실선은 범위가 0을 담을 때만 선 전체다.
    /// 경로 없는 입력이면 nil.
    public static func alongExtent(of line: Line) -> ClosedRange<CGFloat>? {
        guard isDrawable(line) else { return nil }
        if line.elementRange != nil, isPatterned(line.shape) {
            return ownedAlongExtent(of: line)
        }
        if isSolid(line.shape) {
            return ownsSolidLine(line) ? 0 ... line.length : nil
        }
        switch line.shape {
        case .wave, .doubleWave:
            guard patternRepeats(of: line) <= maxPatternRepeats else { return 0 ... line.length }
            let extents = (0 ..< drawnWaveCount(for: line)).compactMap {
                waveAlongExtent(for: line, index: $0)
            }
            guard let lower = extents.map(\.lowerBound).min(),
                  let upper = extents.map(\.upperBound).max()
            else { return nil }
            return lower ... upper
        case .circle where patternRepeats(of: line) <= maxPatternRepeats:
            let count = circleCount(for: line)
            guard count > 0 else { return nil }
            let radius = circleDiameter(for: line) / 2
            // 첫 원의 중심은 곱하지 않고 0 — 간격이 무한대로 넘친 입력에서 0 × ∞ = NaN을 피한다
            let lastCenter = count > 1 ? CGFloat(count - 1) * circlePitch(for: line) : 0
            return -radius ... max(line.length, lastCenter + radius)
        default:
            return 0 ... line.length
        }
    }

    /// 경로가 있는 입력인가 — 길이·두께·글자 크기가 유한한 양수이고 `none`이 아니다. 길이의
    /// 바닥 1e-6pt는 원·물결 요소 개수(`patternElementCount(span:period:)`)의 것과 같아
    /// `path == nil ⇔ 범위 == nil`이 유지된다. `elementRange`가 제 몫의 요소를 하나도 담지 않은
    /// 조각은 경로·선 방향 범위가 함께 없고 가로지르는 범위(선 전체의 것)만 남는다.
    static func isDrawable(_ line: Line) -> Bool {
        line.length.isFinite && line.thickness.isFinite && line.length > 1e-6 && line.thickness > 0
            && line.shape != .none && fontSizeIsPositive(line.scale)
    }

    /// 조각(`Line.elementRange`)으로 나눠 그릴 수 있는 무늬 — 대시와 원형 점선
    static func isPatterned(_ shape: HwpBorderType) -> Bool {
        switch shape {
        case .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash, .circle: true
        default: false
        }
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
            dashPattern(for: line).reduce(0, +)
        case .circle:
            circlePitch(for: line)
        case .wave, .doubleWave:
            wave(for: line).halfPeriod
        default:
            0
        }
        guard unit > 0, unit.isFinite else { return 0 }
        return line.length / unit
    }
}

// MARK: - 축척·자리·모양 (같은 파일의 확장 — 본체는 공개 진입점만 둔다)

extension HwpLineShapeGeometry {
    // MARK: - 자리

    /// 단선(실선·대시)의 띠 — 중심 0에 획 두께(`strokeThickness(for:)` — 테두리 축척은 장치 단위로
    /// 반올림한 두께)만큼
    static func solidBand(for line: Line) -> CGRect {
        let thickness = strokeThickness(for: line)
        return CGRect(x: 0, y: -thickness / 2, width: line.length, height: thickness)
    }

    /// 한글 2007 호환 문서 글자선의 여러 줄 띠 (로컬 y) — 고정 높이(2중선 1.44pt, 그 밖 4.2pt)를
    /// `Placement`에 따라 단선 띠에 맞춘다: 아래 밑줄은 단선 위 가장자리에서 아래로, 취소선은 가운데, 위
    /// 밑줄은 단선 아래 가장자리에서 위로 (#227). 장치 단위 축척(글자선·테두리·단 구분선)은
    /// `deviceStripes(for:)`가 맡는다.
    static func hwp200XMultiLineBand(for line: Line) -> ClosedRange<CGFloat> {
        let height = line.shape == .doubleLine
            ? HwpRenderTuning.LineShape.hwp200XDoubleLineBand
            : HwpRenderTuning.LineShape.hwp200XThickLineBand
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

    // MARK: - 모양

    /// 대시 무늬의 단위 배수 (선, 공백, 선, 공백 … 순) — 한글 2007 호환 문서의 고정 단위와 장치 단위
    /// 반올림 상한 밖의 비례 무늬가 이 배수다 (그 밖은 장치 단위 정수 — `dashPattern(for:)`). 한글은
    /// OWPML 이름과 반대로 `DOT`(`longDotLine`)을 긴 점선으로, `DASH`(`dotLine`)를 점선으로 그린다
    /// (#177).
    static func dashMultiples(for shape: HwpBorderType) -> [CGFloat] {
        switch shape {
        case .longDotLine: [5, 3]
        case .dotLine: [1, 1.5]
        case .dashDot: [10, 3, 1, 3]
        case .dashDotDot: [10, 3, 1, 3, 1, 3]
        case .longDash: [10, 3]
        default: []
        }
    }

    /// 한글 2007 호환 문서 글자선 여러 줄의 띠 안 구성 — 띠 높이에 대한 비율 [(시작, 끝)], 위(−y)에서
    /// 아래로 (4.2pt 띠에 가는 선 0.96·굵은 선 2.28, 3중선 0.6·1.8·0.6 — `hwp200XThickLineBand`; 2중선은
    /// 1.44pt 띠의 [1/4·1/2·1/4], #227).
    static func hwp200XStripeFractions(for shape: HwpBorderType) -> [(CGFloat, CGFloat)] {
        switch shape {
        case .doubleLine: [(0, 0.25), (0.75, 1)]
        case .thinThickDoubleLine: [(0, 8 / 35), (16 / 35, 1)]
        case .thickThinDoubleLine: [(0, 19 / 35), (27 / 35, 1)]
        case .thinThickThinTripleLine: [(0, 1 / 7), (2 / 7, 5 / 7), (6 / 7, 1)]
        default: []
        }
    }

    /// 여러 줄의 부속선 (위에서 아래로) — 장치 단위 축척은 획(`Stripe` 중심·두께)과 정수 행 구간
    /// (`deviceStripes(for:)`, #252·#253), 한글 2007 호환 문서의 글자선은 고정 띠를 비율로 나눈 것이다 (행
    /// 구간 = 획).
    static func stripeGeometry(for line: Line) -> [Stripe] {
        if let device = deviceStripes(for: line) {
            return device
        }
        let band = hwp200XMultiLineBand(for: line)
        let height = band.upperBound - band.lowerBound
        return hwp200XStripeFractions(for: line.shape).map { start, end in
            let lower = band.lowerBound + height * start
            let upper = band.lowerBound + height * end
            return Stripe(
                center: (lower + upper) / 2, thickness: upper - lower, slot: lower ... upper
            )
        }
    }

    /// 여러 줄의 부속선 띠 (로컬 좌표, 선 길이 전체) — `stripeGeometry(for:)`의 획을 선 길이만큼 편 것.
    static func stripes(for line: Line) -> [CGRect] {
        stripeGeometry(for: line).map { stripe in
            CGRect(
                x: 0, y: stripe.center - stripe.thickness / 2,
                width: line.length, height: stripe.thickness
            )
        }
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
