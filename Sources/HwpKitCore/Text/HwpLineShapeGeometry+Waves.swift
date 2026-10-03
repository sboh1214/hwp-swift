import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 물결 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

extension HwpLineShapeGeometry {
    /// 물결 하나의 기하 — 한글 문서·MS 워드 호환 문서의 글자선은 장치 단위 정수 기하
    /// (`characterWave(for:)`, #252), 한글 2007 호환 문서는 고정 pt(#227), 테두리·단 구분선은 명목
    /// 두께 비례(#191 — 대각선의 가로·세로가 진폭, 평탄 0.12pt, 두 평탄 높이 사이도 진폭)다.
    static func wave(for line: Line) -> Wave {
        if let character = characterWave(for: line) {
            return character
        }
        let amplitude = waveAmplitude(for: line)
        let flat = HwpRenderTuning.LineShape.waveVertexFlat
        return Wave(
            run: amplitude, levelGap: amplitude, halfPeriod: amplitude + flat, flat: flat,
            stroke: waveStroke(for: line), top: waveTopVertex(for: line),
            secondOffset: doubleWaveOffset(for: line), straight: false
        )
    }

    /// 비례 물결의 진폭 — 한글 2007 호환 문서의 글자선만 2중 물결이 단일 물결의 절반이다. 한글
    /// 문서·MS 워드 호환 문서의 글자선은 `characterWave(for:)`가 맡는다 (여기서는 0).
    static func waveAmplitude(for line: Line) -> CGFloat {
        switch line.scale {
        case .characterLine:
            0
        case .hwp200XCharacterLine:
            line.shape == .doubleWave
                ? HwpRenderTuning.LineShape.hwp200XDoubleWaveAmplitude
                : HwpRenderTuning.LineShape.hwp200XWaveAmplitude
        case .border:
            line.thickness
        }
    }

    static func waveStroke(for line: Line) -> CGFloat {
        switch line.scale {
        case .characterLine:
            0
        case .hwp200XCharacterLine:
            line.shape == .doubleWave
                ? HwpRenderTuning.LineShape.hwp200XDoubleWaveStroke
                : HwpRenderTuning.LineShape.hwp200XWaveStroke
        case .border:
            line.thickness * HwpRenderTuning.LineShape.borderWaveStrokeThicknessRatio
        }
    }

    /// 물결 반주기 — 대각선(가로 폭)에 꼭짓점 평탄을 더한 길이 (`wave(for:)`)
    static func waveHalfPeriod(for line: Line) -> CGFloat {
        wave(for: line).halfPeriod
    }

    /// 비례 물결 꼭짓점 띠의 위쪽 꼭짓점 y — 한글 2007 호환 문서의 글자선은 계단의 시작
    /// (`waveTopBase(for:)`)에서 종류 × 계단(`waveTopStep(for:)` — 물결마다 고정 pt)만큼 위, 테두리는
    /// 중심에서 3/8 두께 위에 진폭 절반을 더 올린 곳. 한글 문서·MS 워드 호환 문서의 글자선은
    /// `characterWave(for:)`가 맡는다 (여기서는 0).
    static func waveTopVertex(for line: Line) -> CGFloat {
        let steps: CGFloat
        switch line.placement {
        case .underlineBelow: steps = 1
        case .strikethrough: steps = 2
        case .underlineAbove: steps = 3
        case .border, .divider:
            return -line.thickness * HwpRenderTuning.LineShape.borderWaveShiftThicknessRatio
                - waveAmplitude(for: line) / 2
        }
        guard line.scale == .hwp200XCharacterLine else { return 0 }
        return -waveTopBase(for: line) - waveTopStep(for: line) * steps
    }

    /// 한글 2007 호환 문서 글자선 물결 꼭짓점 계단이 시작하는 자리 (단선 중심 위, pt) — 물결
    /// 0.12pt·2중 물결 0.18pt
    static func waveTopBase(for line: Line) -> CGFloat {
        line.shape == .doubleWave
            ? HwpRenderTuning.LineShape.hwp200XDoubleWaveTopBase
            : HwpRenderTuning.LineShape.hwp200XWaveTopBase
    }

    /// 한글 2007 호환 문서 글자선 물결의 위쪽 꼭짓점 계단 폭 — 단일 물결 1.2pt·2중 물결 0.54pt
    static func waveTopStep(for line: Line) -> CGFloat {
        line.shape == .doubleWave
            ? HwpRenderTuning.LineShape.hwp200XDoubleWaveTopStep
            : HwpRenderTuning.LineShape.hwp200XWaveTopStep
    }

    /// 비례 2중 물결의 둘째 파 이동량 — 한글 2007 호환 문서의 글자선은 1.08pt 아래(같은 x 위상),
    /// 테두리는 선 방향·가로지르는 축 모두 3/4 두께(내려가는 획이 첫 파와 한 직선을 이루는 마름모
    /// 격자), 단 구분선은 가로지르는 축만 3/4 두께. 한글 문서·MS 워드 호환 문서의 글자선은
    /// `characterWave(for:)`가 맡는다 (3w 아래 — 여기서는 0).
    static func doubleWaveOffset(for line: Line) -> CGPoint {
        switch line.scale {
        case .characterLine:
            return .zero
        case .hwp200XCharacterLine:
            return CGPoint(x: 0, y: HwpRenderTuning.LineShape.hwp200XDoubleWaveOffset)
        case .border:
            let offset = line.thickness
                * HwpRenderTuning.LineShape.borderDoubleWaveOffsetThicknessRatio
            return CGPoint(x: line.placement == .divider ? 0 : offset, y: offset)
        }
    }
}
