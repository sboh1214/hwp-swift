import CoreGraphics
import Foundation

// MARK: - 블록 자신의 히트와 프레임 밖 글자 claim

extension HwpHitTester {
    /// 블록 하나가 그 점에 내는 답 (`hit(page:point:)`의 한 칸).
    enum BlockAnswer {
        /// 이 블록이 답한다 — 위에 양보 중인 글자 claim이 없으면 그대로 결과다.
        case final(HwpHitResult)
        /// 프레임 **위**로 솟은 글자뿐인 claim — 아래 블록의 답이 링크면 그 링크에 양보한다
        /// (`textClaim`). 아래 블록이 답하지 않거나 링크가 아닌 것으로 답하면 이 claim이다.
        case yielding(HwpHitResult)
    }

    /// 양보 중인 글자 claim(`yielding` — 가장 위에서 양보를 시작한 블록의 것) 밑에서 처음 나온
    /// 답을 확정한다: 링크면 그 링크, 아니면 위의 글자 claim이 이긴다.
    static func resolve(_ result: HwpHitResult, under yielding: HwpHitResult?) -> HwpHitResult {
        guard let yielding else { return result }
        if case .hyperlink = result {
            return result
        }
        return yielding
    }

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
    /// (선택 히트는 이 PR 밖).
    ///
    /// 아래 블록은 `hit`의 **같은 순회**가 이어서 판정하고 처음 답하는 블록에서 멈춘다
    /// (`BlockAnswer.yielding` → `resolve`) — 그 답이 링크면 링크가, 그 밖의 claim이면 이 글자가
    /// 이긴다. 링크와 프레임만 따로 보면 중간 블록의 **프레임 밖** claim을 지나친다: 각주 도형이
    /// 제 프레임 밖으로 넘쳐 그 자리를 덮으면 링크 조회는 그 가림을 nil로 접고 프레임 검사는
    /// 밖이라 통과시켜, 이 글자가 없을 때는 `.footnote`이던 자리가 글자를 더하자 도형 밑에 가려진
    /// 링크로 바뀌었다 (#233 리뷰 P2). 중간 블록의 글자 claim도 양보하므로(가장 위의 claim만
    /// 기억한다) 가려지지 않은 링크 띠는 그대로 열린다 (한글: 다음 줄 잉크를 안 본다).
    ///
    /// **재귀하지 않는다** — 아래 블록을 이 함수에서 다시 훑으면 같은 자리에 프레임 위 글자
    /// claim이 쌓인 만큼 호출이 깊어져, 1pt 줄 수천 개에 거대한 글자를 얹은 조작 문서 하나가 탭
    /// 한 번에 잡을 수 없는 스택 오버플로를 냈다(#233 리뷰 — 8MB 스레드 3,000겹, iOS 1MB 스레드
    /// 500겹에서 신호 11·10). 양보 중인 claim을 `hit`의 순회가 들고 내려가 깊이가 0이다.
    func textClaim(_ claim: HwpHitResult, of block: AnyHwpBlock, at point: CGPoint) -> BlockAnswer {
        point.y < block.frame.minY ? .yielding(claim) : .final(claim)
    }

    /// 프레임 밖 각주 claim — **글자뿐이면** `textClaim`처럼 앞 블록 링크에 양보한다 (#233:
    /// 한 각주의 두 문단은 블록 둘이라 뒤 문단의 프레임 위 claim이 앞 문단 링크 띠를 가져간다).
    /// 개체·셀 칠이 덮은 자리는 그대로 claim한다 — 한글이 줄 띠로 보는 것은 글자뿐이다.
    func footnoteClaim(
        _ footnote: HwpFootnoteBlock, of block: AnyHwpBlock, index: Int, at point: CGPoint
    ) -> BlockAnswer {
        let claim = HwpHitResult.footnote(blockIndex: index, number: footnote.number)
        guard !footnoteLayersClaim(footnote, frame: block.frame, at: point) else {
            return .final(claim)
        }
        return textClaim(claim, of: block, at: point)
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
