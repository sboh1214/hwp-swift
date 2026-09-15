import CoreGraphics
import CoreText
import Foundation

/// 한글 줄 모델의 베이스라인 앵커와 줄 상자 기하 (#178·#180).
///
/// 앵커 규칙 자체와 실측 근거는 `HwpRenderTuning.Text.baselineAnchorRatio`가
/// 소유한다. 여기에는 그 규칙을 CTLine에 적용하는 산식만 둔다.
///
/// **baseline은 앵커가 정하고, 상자 상단은 전진량이 정한다.** `HwpDrawnTextLayout.lines`는
/// 첫 줄 상자 상단을 블록 상단(이월이면 재개 상자 상단)에 핀하고, 다음 줄 상자 상단은 앞
/// 줄 상자 상단 + 그 줄의 전진량(`HwpLineAdvance` — 줄별 상자 높이 × 줄 간격 규칙)이며,
/// 각 줄의 baseline은 자기 상자 상단 + 자기 앵커다. CT 줄 origin·슬롯은 세로 배치에
/// 쓰지 않는다 — 종전 구현은 CT가 강제 줄 높이 안에서 나눈 ascent를 기준점으로 써 그 몫이
/// 베이스라인에 새어 나갔고(#178), 그 뒤로도 CT 슬롯을 복원해 상자를 타일하느라 글꼴
/// 지표·못박은 높이보다 큰 글자·프레임 첫 슬롯 특례가 전진량에 남았다 (#180·#198·#202).
extension HwpDrawnTextLayout {
    /// 한글 줄 모델의 **베이스라인 앵커** — 줄 상자 상단에서 베이스라인까지의
    /// 거리 = 줄 상자 높이 × `HwpRenderTuning.Text.baselineAnchorRatio`.
    ///
    /// 줄 상자 높이는 줄 캐시 (`PARA_LINE_SEG`)의 `vertsize`에 해당하는 값이다 —
    /// 그 줄 글자들의 **상대크기 적용 전 기본 크기** 최대값이고, 줄 공간을 예약한
    /// 글자처럼 취급 개체 (run delegate)가 더 크면 그 개체 높이다. 줄 간격 종류·
    /// 값과 글꼴 지표는 앵커에 관여하지 않는다 (#178 실측). 상자는 **줄마다** 다르다 —
    /// 한 문단이 크기 섞여 줄바꿈되면 한글 캐시의 `vertsize`도 줄별로 1000·4000·4000이다
    /// (2026-09-12 실측, #180).
    public static func baselineAnchor(of line: CTLine) -> CGFloat {
        max(0, lineMetrics(of: line).boxHeight) * HwpRenderTuning.Text.baselineAnchorRatio
    }

    /// 청크 줄 하나의 세로 기하 — 줄 상자 상단과 그 아래 앵커만큼 내린 baseline, 그리고
    /// 다음 줄 상자 상단까지의 전진량 (문단 사이 간격 포함).
    struct LineGeometry {
        let boxTop: CGFloat
        let baseline: CGFloat
        let advance: CGFloat
    }

    /// 청크 줄들의 세로 기하 (top-down).
    ///
    /// 첫 줄 상자 상단은 `base` (블록 상단, 이월이면 재개 상자 상단) 에 조건 없이 핀한다 —
    /// 블록 상단이 곧 첫 상자 상단인 것이 정의다. 재구성값으로 보정하면 그만큼 첫 줄이 블록
    /// 위로 올라간다 (실제로 그 형태의 회귀를 한 번 냈다 — 헌법주석 각주 0.63pt).
    ///
    /// 나머지 줄은 앞 줄 상자 상단 + 앞 줄 전진량이다. 전진량은 측정
    /// (`HwpParagraphLayout.makeLineFrames`)과 같은 `HwpLineAdvance.advances(of:in:)`에서
    /// 온다 — 그래서 문단 높이(쪽 나눔)와 그려지는 줄이 정의상 같은 자리다. 커밋된 줄
    /// (`keepCount`)만 낸다.
    static func lineGeometries(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString,
        base: CGFloat
    ) -> [LineGeometry] {
        let advances = HwpLineAdvance.advances(of: chunk, in: attributedString)
        var boxTop = base
        return (0 ..< chunk.keepCount).map { index in
            let anchor = baselineAnchor(of: chunk.lines[index])
            let geometry = LineGeometry(
                boxTop: boxTop, baseline: boxTop + anchor, advance: advances[index]
            )
            boxTop += advances[index]
            return geometry
        }
    }

    /// 인라인 개체 줄에서 밑줄이 되돌아갈 양 — 실물은 밑줄을 개체 하단
    /// (= 줄 상자 바닥, 베이스라인 아래 `1 − baselineAnchorRatio` 몫) 근처에
    /// 남긴다 (공공누리 실물 실측)
    ///
    /// **개체가 줄 상자를 정할 때만 되돌린다.** 개체 높이를 **글꼴 ascent**와 견주면 글자보다
    /// 낮은 개체까지 걸려, 베이스라인이 글자 자리 그대로인 줄에서 글자 아래 밑줄만 내려간다
    /// (실측, 10pt 글자: 개체 8pt에서 1.20pt·9pt 1.35pt·9.9pt 1.49pt 아래. 글꼴 ascent
    /// 7.7002와 상자 높이 10 사이의 개체 전부다 — 4pt 개체는 ascent보다 낮아 통과하지 못했다).
    /// 상자 높이는 `max(기본 크기, 개체 높이)`이므로 개체가 정했다는 것은 개체 높이가 곧 상자
    /// 높이라는 뜻이고, 그때 되돌림 `0.15 × 개체 높이`가 상자 바닥과 같아진다.
    public static func underlineReturnDrop(of line: CTLine) -> CGFloat {
        let metrics = lineMetrics(of: line)
        guard metrics.delegateAscent > 0, metrics.delegateAscent >= metrics.boxHeight
        else { return 0 }
        return metrics.delegateAscent * HwpRenderTuning.Text.baselineLiftRatio
    }
}
