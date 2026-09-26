import CoreGraphics
import CoreText
import Foundation

/// 한글 줄 모델의 베이스라인 앵커와 줄 상자 기하 (#178·#180·#194).
///
/// 앵커 규칙 자체와 실측 근거는 `HwpRenderTuning.Text.baselineAnchorRatio`(한글 문서)와
/// `HwpMsWordLineBox`(MS 워드 호환 문서)가 소유한다. 여기에는 그 규칙을 CTLine에 적용하는
/// 산식만 둔다 (`LineMetrics.baselineAnchor`).
///
/// **baseline은 앵커가 정하고, 상자 상단은 전진량이 정한다.** `HwpDrawnTextLayout.lines`는
/// 첫 줄 상자 상단을 블록 상단(이월이면 재개 상자 상단)에 핀하고, 다음 줄 상자 상단은 앞
/// 줄 상자 상단 + 그 줄의 전진량(`HwpLineAdvance` — 줄별 상자 높이 × 줄 간격 규칙)이며,
/// 각 줄의 baseline은 자기 상자 상단 + 자기 앵커다. CT 줄 origin·슬롯은 세로 배치에
/// 쓰지 않는다 — 종전 구현은 CT가 강제 줄 높이 안에서 나눈 ascent를 기준점으로 써 그 몫이
/// 베이스라인에 새어 나갔고(#178), 그 뒤로도 CT 슬롯을 복원해 상자를 타일하느라 글꼴
/// 지표·못박은 높이보다 큰 글자·프레임 첫 슬롯 특례가 전진량에 남았다 (#180·#198·#202).
public extension HwpDrawnTextLayout {
    /// 한글 줄 모델의 **베이스라인 앵커** — 줄 상자 상단에서 베이스라인까지의 거리.
    ///
    /// 한글 문서는 줄 상자 높이 × `HwpRenderTuning.Text.baselineAnchorRatio`(0.85)다. 줄
    /// 상자 높이는 줄 캐시 (`PARA_LINE_SEG`)의 `vertsize`에 해당하는 값 — 그 줄 글자들의
    /// **상대크기 적용 전 기본 크기** 최대값이고, 줄 공간을 예약한 글자처럼 취급 개체
    /// (run delegate)가 더 크면 그 개체 높이다 — 그 개체 마커의 글자 모양 크기는 상자에 들지
    /// 않는다 (#217: 10pt 글에 40pt 글자 모양 마커로 넣은 20pt 그림 줄의 `vertsize`는 20).
    /// 줄 간격 종류·값과 글꼴 지표는 앵커에
    /// 관여하지 않는다 (#178 실측). 상자는 **줄마다** 다르다 — 한 문단이 크기 섞여
    /// 줄바꿈되면 한글 캐시의 `vertsize`도 줄별로 1000·4000·4000이다 (2026-09-12 실측, #180).
    ///
    /// MS 워드 호환 문서(`hwp.compatibleDocumentTarget` == `msWord`, #194)는 글꼴 줄 상자
    /// (`HwpMsWordLineBox`)의 베이스라인이다 — 함초롬돋움 10pt 줄이면 12.66pt(0.85 × 10 =
    /// 8.5가 아니다). 문단의 마지막 줄에는 접힌 문단 끝 글자(CR)의 글자 모양도 드는데(한글
    /// 문서는 그 기본 크기 #206, MS 워드 호환 문서는 라틴 슬롯 글꼴 상자 #194) 이 변형은
    /// CTLine만 보므로 그것을 모른다 — 문단 문자열이 있는 호출자는 `baselineAnchor(of:in:)`를
    /// 쓴다.
    static func baselineAnchor(of line: CTLine) -> CGFloat {
        lineMetrics(of: line).baselineAnchor
    }

    /// 문단 문자열 `attributedString` 안 줄 `line`의 베이스라인 앵커 — 줄이 문단의 마지막
    /// 줄(`HwpDrawnLine.endsParagraph`)이면 접힌 문단 끝 글자(CR)의 글자 모양을 포함한다:
    /// 한글 문서는 그 기본 크기(`hwp.paragraphEndBaseFontSize`, #206 — 한글 12.30 실측: 10pt
    /// 본문 + 16pt CR 문단의 마지막 줄만 `baseline` 1360, 앞 줄은 850), MS 워드 호환 문서는
    /// 그 글꼴 상자(`hwp.msWordParagraphEndBox`, #194 — Apple SD 산돌고딕 Neo 10pt 한글
    /// 문단의 마지막 줄만 라틴 슬롯 Menlo의 베이스라인 11.04pt, 앞 줄은 10.80pt).
    static func baselineAnchor(
        of line: CTLine, in attributedString: NSAttributedString
    ) -> CGFloat {
        lineMetrics(of: line, in: attributedString).baselineAnchor
    }

    /// 청크 줄 하나의 세로 기하 — 줄 상자 상단과 그 아래 앵커만큼 내린 baseline, 그리고
    /// 다음 줄 상자 상단까지의 전진량 (문단 사이 간격 포함). 줄 상자 높이와 줄 자신의 전진량
    /// (문단 사이 간격 제외)은 링크 클릭 띠(#233)가 그려진 줄에서 그대로 쓴다
    /// (`HwpDrawnLine.boxHeight`·`lineAdvance`).
    internal struct LineGeometry {
        let boxTop: CGFloat
        let baseline: CGFloat
        let advance: CGFloat
        let boxHeight: CGFloat
        let lineAdvance: CGFloat
    }

    /// 청크 줄들의 세로 기하 (top-down).
    ///
    /// 첫 줄 상자 상단은 `base` (블록 상단, 이월이면 재개 상자 상단) 에 조건 없이 핀한다 —
    /// 블록 상단이 곧 첫 상자 상단인 것이 정의다. 재구성값으로 보정하면 그만큼 첫 줄이 블록
    /// 위로 올라간다 (실제로 그 형태의 회귀를 한 번 냈다 — 헌법주석 각주 0.63pt).
    ///
    /// 나머지 줄은 앞 줄 상자 상단 + 앞 줄 전진량이다. 전진량은 측정
    /// (`HwpParagraphLayout.makeLineFrames`)과 같은 `HwpLineAdvance.advanceParts(of:in:)`에서
    /// 온다(측정은 그 합 `advances`) — 그래서 문단 높이(쪽 나눔)와 그려지는 줄이 정의상 같은
    /// 자리다. 커밋된 줄
    /// (`keepCount`)만 낸다.
    internal static func lineGeometries(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString,
        base: CGFloat
    ) -> [LineGeometry] {
        let parts = HwpLineAdvance.advanceParts(of: chunk, in: attributedString)
        var boxTop = base
        return (0 ..< chunk.keepCount).map { index in
            let metrics = lineMetrics(of: chunk.lines[index], in: attributedString)
            let advance = parts[index].line + parts[index].gap
            let geometry = LineGeometry(
                boxTop: boxTop, baseline: boxTop + metrics.baselineAnchor, advance: advance,
                boxHeight: metrics.boxHeight, lineAdvance: parts[index].line
            )
            boxTop += advance
            return geometry
        }
    }
}
