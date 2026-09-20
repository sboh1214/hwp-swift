import CoreGraphics
import CoreHwp
import Foundation

/// 컨테이너(표 셀·글상자) **내용 범위**의 끝 — 마지막 줄 상자의 아래 (#193).
///
/// 한글은 셀과 글상자의 내용을 첫 문단의 위 간격부터 마지막 줄 **상자** 아래까지로 잰다.
/// 마지막 줄의 줄 간격 여분과 마지막 문단의 아래 간격은 범위에 들지 않는다 — 세로 정렬
/// (표 89)의 가운데·아래 기준도, 내용이 정하는 행 높이도 이 범위다. 한컴오피스 한글 12.30
/// (macOS) 합성 문서 실측(2026-09-18, 한글 PDF의 베이스라인과 테두리):
///
/// - 40pt 셀·글상자에 10pt 한 줄: 가운데 정렬 첫 줄 상자 상단이 안쪽 위에서
///   (안쪽 높이 − 10) / 2 — 줄 간격 160%·300%·고정 20pt·100%, 문단 아래 간격 10pt가
///   모두 같은 자리다. 아래 정렬은 상자 바닥이 안쪽 아래에 닿는다(160%·300%·고정 20pt·
///   아래 간격 10pt 모두). 문단 위 간격 10pt는 범위에 든다(상자 상단이 그만큼 내려간다).
/// - 크기가 다른 두 문단(10pt·20pt)은 둘째 문단 상자 바닥까지가 범위다.
/// - 행 높이: 저작 높이 282 셀에 아래 간격 10pt 문단 → 12.82pt(10 + 안쪽 여백), 두 문단이
///   각자 아래 간격 10pt면 첫 문단의 아래 간격만 든 38.82pt다.
///
/// 종전에는 문단 rect 바닥(마지막 줄 전진량 + 아래 간격)을 내용 끝으로 써서 가운데 정렬
/// 글자가 (줄 간격 여분 + 아래 간격) / 2만큼 위에 놓였다 — noori 1쪽 표 셀 1.3~2.6pt.
enum HwpContainerContentExtent {
    /// CT로 잰 문단 프레임의 `totalHeight` 가운데 마지막 줄 상자 아래 몫 (pt).
    ///
    /// 프레임 높이는 위 간격 + 줄 전진량 합 + 아래 간격이고
    /// (`HwpParagraphLayout.layout`), 마지막 줄 상자 바닥은 위 간격 + 그 줄 상자 상단
    /// (`HwpLineFrame.origin.y`) + 상자 높이다. 줄이 없으면(빈 문자열) 0.
    ///
    /// **음수일 수 있다** — 줄 전진량이 상자보다 작으면(비율 100% 미만·글자보다 작은 고정값)
    /// 상자가 프레임 아래로 나가므로, 내용 범위는 그 상자 바닥까지 늘어나야 한다. 캐시 경로도
    /// 같은 답을 낸다 — `CachedLineExtent.bottom`이 마지막 세그먼트의 줄 상자 아래다
    /// (PR 리뷰: 60% 줄 간격 셀·글상자가 캐시 유무에 따라 4pt 갈렸다).
    ///
    /// **기준은 마지막 줄뿐이다** — 겹친 줄(고정 줄 간격이 앞 줄 상자보다 작음)에서 앞 줄이 더
    /// 아래까지 내려가도 한글은 그 줄을 컨테이너 밖으로 흘려 보낸다 (#193 리뷰, 한글 12.30 실측:
    /// 30pt + 10pt 두 줄·고정 16pt 셀의 아래 정렬 30pt 줄이 셀 아래로 4pt 넘는다).
    static func trailingGap(
        of frame: HwpParagraphFrame,
        paraShape: CoreHwp.HwpParaShape
    ) -> CGFloat {
        guard let last = frame.lines.last else { return 0 }
        // 문단 간격은 표 43 여백 계열과 같은 1/2 단위다 (`HwpParagraphLayout.ParagraphMetrics`).
        let spacingBefore = HwpUnits.points(fromHwpUnit: paraShape.paragraphSpacingTop) / 2
        let boxBottom = spacingBefore + last.origin.y + lineBoxHeight(of: last)
        return frame.totalHeight - boxBottom
    }

    /// 문단 위 간격 (pt) — 표 43 여백 계열과 같은 1/2 단위다. 컨테이너 문단의 CT 높이는 이
    /// 간격을 첫 줄 위에 담으므로 배치가 문단 rect 상단을 그만큼 내려야 첫 줄 상자가 측정한
    /// 자리에 그려진다 (표 셀 `laidOutContents`·글상자 `laidOutContents`).
    static func spacingBefore(of paragraph: CoreHwp.HwpParagraph, index: HwpIndex) -> CGFloat {
        HwpUnits.points(fromHwpUnit: index.paraShape(for: paragraph)?.paragraphSpacingTop ?? 0) / 2
    }

    /// 줄 프레임의 상자 높이 — `baseline`은 상자 상단에서 베이스라인 앵커까지의 거리
    /// (= 상자 높이 × `baselineAnchorRatio`, `HwpDrawnTextLayout.baselineAnchor`)라 그
    /// 역이다. 측정(`HwpParagraphLayout.makeLineFrames`·한 줄 넘침 갈래)이 줄 프레임을
    /// 모두 그 앵커로 만든다.
    static func lineBoxHeight(of line: HwpLineFrame) -> CGFloat {
        max(0, line.baseline) / HwpRenderTuning.Text.baselineAnchorRatio
    }
}

extension HwpParagraphLayout.CachedLineExtent {
    /// 마지막 줄의 줄 간격 여분 (pt) — 전진량 끝(`spacedBottom`)에서 그 줄 상자 아래
    /// (`bottom`)까지. 앞 줄이 더 아래로 내려가는 겹친 줄에서도 기준은 마지막 줄이다 (#193).
    var trailingLineSpacing: CGFloat {
        HwpUnits.points(fromHwpUnit: Int32(clamping: spacedBottom - bottom))
    }
}
