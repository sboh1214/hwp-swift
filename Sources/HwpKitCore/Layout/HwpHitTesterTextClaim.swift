import CoreGraphics
import Foundation

// MARK: - 블록 자신의 히트와 프레임 밖 글자 claim

extension HwpHitTester {
    /// 페인트 역순으로 늘어선 블록 — `hit(page:point:)`가 지금 보는 블록 **아래**에 그려진 것들.
    typealias LowerBlocks = ArraySlice<(index: Int, block: AnyHwpBlock)>

    /// 링크가 아닌 이 블록 자신의 히트 — 프레임 안과, 프레임 밖 칠해진 글자 위가 같은 답을 낸다.
    func ownHit(for block: AnyHwpBlock, index: Int, at point: CGPoint) -> HwpHitResult {
        switch block.kind {
        case .text:
            return .text(blockIndex: index, characterIndex: nil)
        case .image:
            return .image(blockIndex: index)
        case .shape, .textbox:
            return .shape(blockIndex: index)
        case .table:
            let position = tableGridPosition(block: block, point: point)
            return .table(blockIndex: index, row: position.row, col: position.col)
        case .footnote:
            return .footnote(blockIndex: index, number: footnoteNumber(block: block))
        case .placeholder:
            return .placeholder(blockIndex: index, kind: block.kind)
        }
    }

    private func footnoteNumber(block: AnyHwpBlock) -> Int {
        guard case let .footnote(footnote) = block.payload else { return 0 }
        return footnote.number
    }

    /// 프레임 밖에서 **글자로** 칠한 자리의 claim (R53의 텍스트 축) — 그 자리가 블록 프레임
    /// **위**면 아래에 그려진 앞 블록의 링크가 이긴다 (#233).
    ///
    /// 한글은 링크를 줄 클릭 띠(줄 상자 상단 ~ 다음 줄 상자 상단)로 판정하고 다음 줄의 잉크를
    /// 보지 않는다 — 12.30 편집 화면 실측(2026-09-26, 155%): 10pt 160% 링크 줄 바로 아래 줄을
    /// 상대 크기 200%·150%로 키워 그 글리프가 자기 줄 상자 위로 솟아 링크 밑줄까지 덮어도, 그
    /// 획 위를 누르면 링크 줄이 다음 줄 상자 상단(상자 바닥 +5.9·+6.06pt, 대조 줄 +6.0)까지
    /// 열렸다. 문단은 문단마다 블록이고 뒤 블록이 먼저 히트되므로, 이 양보가 없으면 다음 문단의
    /// 프레임 위 claim(글꼴 ascent가 0.85em을 넘는 몫 — 함초롬바탕 10pt 2.2pt, 40pt 8.8pt)이
    /// 방출된 링크 띠의 아래쪽을 가져가 **밑줄 위 탭이 안 열린다** — 이슈가 고치려던 바로 그
    /// 증상이다(#233 리뷰, `hyperlink-click-band`의 r08).
    ///
    /// 양보는 **위쪽만**이다 — 문서 순서로 앞 블록이 위에 놓이므로 그 자리는 앞 줄의 띠이고,
    /// 아래로 옮겨지거나 옆으로 넘친 글자는 뒤 블록 프레임 쪽이라 종전대로 claim한다
    /// (R53 — 그쪽은 페인트 순서가 뒤집힌 겹침이다). 앞 블록 링크가 없으면 claim 그대로다
    /// (선택 히트는 이 PR 밖). 아래 블록을 훑다가 프레임이 그 점을 품은 블록에 닿으면 멈춘다 —
    /// 그 블록은 이 글자에 덮였으므로 그보다 더 아래는 볼 필요가 없다.
    func textClaim(
        _ claim: HwpHitResult, of block: AnyHwpBlock, over lower: LowerBlocks, at point: CGPoint
    ) -> HwpHitResult {
        guard point.y < block.frame.minY else { return claim }
        for (index, below) in lower where hitEligibleFrame(for: below).contains(point) {
            if let url = hyperlinkURL(for: below, at: point) {
                return .hyperlink(url: url, blockIndex: index)
            }
            if below.frame.contains(point) {
                return claim
            }
        }
        return claim
    }

    /// 프레임 밖 각주 claim — **글자뿐이면** `textClaim`처럼 앞 블록 링크에 양보한다 (#233:
    /// 한 각주의 두 문단은 블록 둘이라 뒤 문단의 프레임 위 claim이 앞 문단 링크 띠를 가져간다).
    /// 개체·셀 칠이 덮은 자리는 그대로 claim한다 — 한글이 줄 띠로 보는 것은 글자뿐이다.
    func footnoteClaim(
        _ footnote: HwpFootnoteBlock, of block: AnyHwpBlock, index: Int,
        over lower: LowerBlocks, at point: CGPoint
    ) -> HwpHitResult {
        let claim = HwpHitResult.footnote(blockIndex: index, number: footnote.number)
        guard !footnoteLayersClaim(footnote, frame: block.frame, at: point) else { return claim }
        return textClaim(claim, of: block, over: lower, at: point)
    }

    /// 각주의 **글자 아닌** 층(개체·표·글상자)이 이 점을 가리거나 링크로 갖는가 — 문단을 빼고
    /// 같은 `containerHit`을 돌린다. 프레임 위 claim이 글자뿐인지 가르는 `footnoteClaim`(#233)
    /// 용이다 — 커버리지를 따로 세우면 층 판정(테두리 획 등)과 갈린다.
    func footnoteLayersClaim(
        _ footnote: HwpFootnoteBlock, frame: CGRect, at point: CGPoint
    ) -> Bool {
        let layers = containerHit(
            paragraphs: [], images: footnote.images, shapes: footnote.shapes,
            textboxes: footnote.textboxes, nestedTables: footnote.nestedTables,
            at: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        )
        if case .miss = layers {
            return false
        }
        return true
    }
}
