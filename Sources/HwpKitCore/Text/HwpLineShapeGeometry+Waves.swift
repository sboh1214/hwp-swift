import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 물결 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

extension HwpLineShapeGeometry {
    /// 물결 하나의 기하 — 한글 문서·MS 워드 호환 문서의 글자선과 표 셀 테두리·단 구분선은 장치 단위 정수
    /// 기하(`deviceWave(for:)`, #252·#253), 한글 2007 호환 문서는 고정 pt(#227 — 대각선의 가로·세로가
    /// 진폭, 평탄 0.12pt, 두 평탄 높이 사이도 진폭)다.
    static func wave(for line: Line) -> Wave {
        if let device = deviceWave(for: line) {
            return device
        }
        let amplitude = waveAmplitude(for: line)
        let flat = HwpRenderTuning.LineShape.waveVertexFlat
        return Wave(
            run: amplitude, levelGap: amplitude, halfPeriod: amplitude + flat, flat: flat,
            stroke: waveStroke(for: line), top: waveTopVertex(for: line),
            secondOffset: doubleWaveOffset(for: line), straight: false
        )
    }

    /// 한글 2007 호환 문서 글자선 물결의 진폭 — 2중 물결이 단일 물결의 절반이다. 장치 단위 축척(글자선·
    /// 테두리)은 `deviceWave(for:)`가 맡는다 (여기서는 0).
    static func waveAmplitude(for line: Line) -> CGFloat {
        guard line.scale == .hwp200XCharacterLine else { return 0 }
        return line.shape == .doubleWave
            ? HwpRenderTuning.LineShape.hwp200XDoubleWaveAmplitude
            : HwpRenderTuning.LineShape.hwp200XWaveAmplitude
    }

    /// 한글 2007 호환 문서 글자선 물결의 획 (장치 단위 축척은 0 — `deviceWave(for:)`)
    static func waveStroke(for line: Line) -> CGFloat {
        guard line.scale == .hwp200XCharacterLine else { return 0 }
        return line.shape == .doubleWave
            ? HwpRenderTuning.LineShape.hwp200XDoubleWaveStroke
            : HwpRenderTuning.LineShape.hwp200XWaveStroke
    }

    /// 물결 반주기 — 대각선(가로 폭)에 꼭짓점 평탄을 더한 길이 (`wave(for:)`)
    static func waveHalfPeriod(for line: Line) -> CGFloat {
        wave(for: line).halfPeriod
    }

    /// 한글 2007 호환 문서 글자선 물결의 위쪽 꼭짓점 y — 계단의 시작(`waveTopBase(for:)`)에서 종류 ×
    /// 계단(`waveTopStep(for:)` — 물결마다 고정 pt)만큼 위. 장치 단위 축척(글자선·테두리·단 구분선)은
    /// `deviceWave(for:)`가 맡는다 (여기서는 0).
    static func waveTopVertex(for line: Line) -> CGFloat {
        guard line.scale == .hwp200XCharacterLine else { return 0 }
        let steps: CGFloat = switch line.placement {
        case .underlineBelow: 1
        case .strikethrough: 2
        case .underlineAbove: 3
        case .border, .divider: 0
        }
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

    /// 한글 2007 호환 문서 글자선 2중 물결의 둘째 파 이동량 — 1.08pt 아래(같은 x 위상). 장치 단위 축척은
    /// `deviceWave(for:)`가 맡는다 (3w 아래 — 여기서는 0).
    static func doubleWaveOffset(for line: Line) -> CGFloat {
        line.scale == .hwp200XCharacterLine ? HwpRenderTuning.LineShape.hwp200XDoubleWaveOffset : 0
    }
}
