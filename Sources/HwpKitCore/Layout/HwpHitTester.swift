import CoreGraphics
import Foundation

public enum HwpHitResult: Sendable, Hashable {
    case text(blockIndex: Int, characterIndex: Int?)
    case hyperlink(url: String, blockIndex: Int)
    case image(blockIndex: Int)
    case shape(blockIndex: Int)
    case table(blockIndex: Int, row: Int, col: Int)
    case footnote(blockIndex: Int, number: Int)
    case placeholder(blockIndex: Int, kind: HwpBlockKind)
}

public struct HwpHitTester {
    public init() {}

    public func hit(page: HwpPage, point: CGPoint) -> HwpHitResult? {
        // 위→아래 순으로 히트: 페인트 순서를 뒤집어 훑되, 반환 blockIndex는
        // 논리 배열 위치 그대로다 (선택 좌표와 정합).
        for (index, block) in AnyHwpBlock.paintOrdered(page.blocks).reversed() {
            if !block.frame.contains(point) {
                // frame 밖에도 그려지는 가시 영역이 있으면 기각 전에 링크 rect로
                // 확인한다 — 페인트가 그린 링크는 눌려야 한다 (#4, #94).
                guard hitEligibleFrame(for: block).contains(point),
                      let url = hyperlinkURL(for: block, at: point)
                else { continue }
                return .hyperlink(url: url, blockIndex: index)
            }
            if let url = hyperlinkURL(for: block, at: point) {
                return .hyperlink(url: url, blockIndex: index)
            }
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
        return nil
    }

    /// frame 밖 가시 영역까지 포함한 히트 자격 프레임 — 이 안이면 링크만 확인하고
    /// 밖이면 종전처럼 기각한다. 페인트가 클립 없이 그리는 영역과 같아야
    /// "방출 ≡ 히트"가 성립한다 (AGENTS.md "하이퍼링크 방출" 짝 규약).
    ///
    /// - `.text`: slight-overflow 한 줄 문단이 frame 폭의 허용 초과분
    ///   (`slightOverflowWidthRatio`)만큼 좌우로 넘어 그려진다 (#4).
    /// - `.footnote`: 각주 안 개체가 블록 폭을 넘어 그려질 수 있다 — 한글도
    ///   자르지 않는다 (헌법주석 883쪽 각주 29의 표는 오른쪽 본문 경계를
    ///   ~12.6pt 넘는다). R39 #3.
    /// - 그 외: frame 그대로 (확장 없음 = 종전 동작).
    private func hitEligibleFrame(for block: AnyHwpBlock) -> CGRect {
        switch block.kind {
        case .text:
            let extra = block.frame.width * (HwpRenderTuning.Text.slightOverflowWidthRatio - 1)
            return block.frame.insetBy(dx: -extra, dy: 0)
        case .footnote:
            guard case let .footnote(footnote) = block.payload else { return block.frame }
            return footnoteContentFrame(footnote, in: block.frame)
        default:
            return block.frame
        }
    }

    /// 각주 블록 frame ∪ **페인트가 실제로 닿는 모든 rect**.
    ///
    /// 최상위 개체 rect만 모으면 자손 (각주 안 표의 셀·문단, 글상자 안 문단) 이
    /// 자기 컨테이너를 넘어 그려질 때 그 띠가 자격 영역에서 빠져 보이는 링크가
    /// 안 눌린다 (R41 #2). `walkFootnote`가 페인트와 같은 재귀로 방문하므로 그
    /// 방문 rect를 그대로 합집합한다 — 영역 계산을 손으로 다시 짜면 페인트가
    /// 깊어질 때마다 또 갈린다.
    private func footnoteContentFrame(
        _ footnote: HwpFootnoteBlock, in blockFrame: CGRect
    ) -> CGRect {
        var bounds = blockFrame
        HwpBlockContentWalker.walkFootnote(
            footnote,
            origin: blockFrame.origin,
            onParagraphText: { _, rect, _ in bounds = bounds.union(rect) },
            onCellStart: { _, rect in bounds = bounds.union(rect) },
            onCellImage: { _, rect in bounds = bounds.union(rect) },
            onCellShape: { _, rect in bounds = bounds.union(rect) },
            onCellTextbox: { textbox, rect in
                bounds = bounds.union(rect)
                HwpBlockContentWalker.walkParagraphs(
                    textbox.textbox.paragraphs, offset: rect.origin
                ) { _, inner, _ in bounds = bounds.union(inner) }
            }
        )
        return bounds
    }

    /// 글상자 목록을 **받은 순서대로** 훑어 첫 링크를 돌려준다 (좌표는
    /// 컨테이너-로컬; 순서는 호출부 책임이다). 글상자 rect로 미리 거르지 않는다 —
    /// 안쪽 문단이 상자를 넘어 그려질 수 있어 (R41 #2) 포함 판정은 문단 rect를
    /// 아는 `spanAwareHyperlinkURL`에 맡긴다.
    private func textboxHyperlinkURL(
        _ textboxes: [HwpCellTextbox], at point: CGPoint
    ) -> String? {
        for textbox in textboxes {
            let inner = CGPoint(
                x: point.x - textbox.rect.minX,
                y: point.y - textbox.rect.minY
            )
            if let url = spanAwareHyperlinkURL(in: textbox.textbox.paragraphs, at: inner) {
                return url
            }
        }
        return nil
    }

    /// 필드 스팬 하이퍼링크(%hlk)를 링크 텍스트 글리프 rect에서만 히트한다 —
    /// 앞뒤 평문·다중 링크가 첫 URL로 뭉개지지 않는다 (#2). 필드 속성이 있는
    /// 블록은 링크 밖에서 nil (블록/컨테이너 폴백 금지); 없으면 종전 폴백.
    private func hyperlinkURL(for block: AnyHwpBlock, at point: CGPoint) -> String? {
        var hasFieldSpans = false
        var fieldURL: String?
        HwpBlockContentWalker.walkText(block: block) { attributed, rect, _ in
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: attributed, origin: rect.origin, lineWidth: rect.width
            )
            if !regions.isEmpty {
                hasFieldSpans = true
            }
            if fieldURL == nil {
                fieldURL = regions.first { $0.rect.contains(point) }?.url
            }
        }
        if let fieldURL {
            return fieldURL
        }
        if hasFieldSpans {
            // 블록 자체(전체-rect)의 폴백만 금지한다 — 컨테이너 문단은 문단
            // 단위 span-aware 순회가 스팬 문단의 rect 폴백을 각자 차단하므로,
            // 스팬 없는 이웃 문단의 폴백 링크는 여전히 히트된다 (R38 #4).
            // 셀 글상자는 walkText가 방문하지 않아 별도 통로 유지 (R31 #1).
            return containerHyperlinkURL(block: block, point: point)
                ?? containerTextboxHyperlinkURL(block: block, point: point)
        }
        return block.hyperlinkURL ?? containerHyperlinkURL(block: block, point: point)
    }

    private func tableGridPosition(block: AnyHwpBlock, point: CGPoint) -> (row: Int, col: Int) {
        guard case let .table(tableFrame) = block.payload else { return (0, 0) }
        let localPoint = CGPoint(
            x: point.x - block.frame.minX,
            y: point.y - block.frame.minY
        )
        for row in tableFrame.rows {
            for cell in row.cells where cell.cellFrame.contains(localPoint) {
                return (cell.row, cell.column)
            }
        }
        return (0, 0)
    }

    /// 표 셀·글상자 안 문단에 실린 하이퍼링크를 블록-로컬 좌표로 히트한다
    /// (컨테이너 블록 자체는 URL이 없어 예전에는 표/도형 히트로 떨어졌다).
    private func containerHyperlinkURL(block: AnyHwpBlock, point: CGPoint) -> String? {
        let localPoint = CGPoint(x: point.x - block.frame.minX, y: point.y - block.frame.minY)
        switch block.payload {
        case let .table(tableFrame):
            return tableHyperlinkURL(tableFrame, at: localPoint)
        case let .textbox(textbox):
            return spanAwareHyperlinkURL(in: textbox.paragraphs, at: localPoint)
        case let .footnote(footnote):
            // 각주 문단·개체 좌표는 블록-로컬(0,0 기준)이라 localPoint로 히트한다
            // (#20, #94). 순서는 **페인트 역순**이다 — 위에 그려진 것이 이겨야
            // 보이는 링크가 열린다. 페인트 순서 (글 뒤로 개체 → 문단 텍스트 →
            // 나머지 개체 → 안쪽 표) 의 소유자는 `walkFootnote`이고, 개체 정렬도
            // `footnoteTextboxesInPaintOrder`로 walker에서 받는다 (R41 #1).
            let textboxes = HwpBlockContentWalker.footnoteTextboxesInPaintOrder(footnote)
            // 컨테이너 rect로 미리 거르지 않는다 — 셀·문단이 자기 표를 넘어
            // 그려질 수 있어 (R41 #2) 포함 판정은 자손 rect를 아는
            // `tableHyperlinkURL`에 맡긴다.
            for nested in footnote.nestedTables.reversed() {
                let inner = CGPoint(
                    x: localPoint.x - nested.rect.minX,
                    y: localPoint.y - nested.rect.minY
                )
                if let url = tableHyperlinkURL(nested.table, at: inner) {
                    return url
                }
            }
            if let url = textboxHyperlinkURL(
                Array(textboxes.inFrontOfText.reversed()), at: localPoint
            ) {
                return url
            }
            if let url = spanAwareHyperlinkURL(in: footnote.paragraphs, at: localPoint) {
                return url
            }
            return textboxHyperlinkURL(
                Array(textboxes.behindText.reversed()), at: localPoint
            )
        default:
            return nil
        }
    }

    /// 표(중첩 표 포함) 셀 문단의 하이퍼링크를 표-로컬 좌표로 재귀 히트한다 —
    /// 중첩 표 안 링크도 콜백을 발화하게 한다 (#19).
    private func tableHyperlinkURL(_ tableFrame: HwpTableFrame, at point: CGPoint) -> String? {
        for row in tableFrame.rows {
            for cell in row.cells where cell.cellFrame.contains(point) {
                if let url = spanAwareHyperlinkURL(in: cell.paragraphs, at: point) {
                    return url
                }
                if let url = cellTextboxHyperlinkURL(cell, at: point) {
                    return url
                }
                for nested in cell.nestedTables {
                    let nestedPoint = CGPoint(
                        x: point.x - nested.rect.minX,
                        y: point.y - nested.rect.minY
                    )
                    if let url = tableHyperlinkURL(nested.table, at: nestedPoint) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func hyperlinkURL(in paragraphs: [HwpLaidOutParagraph], at point: CGPoint) -> String? {
        for paragraph in paragraphs
            where paragraph.hyperlinkURL != nil && paragraph.rect.contains(point)
        {
            return paragraph.hyperlinkURL
        }
        return nil
    }

    /// 셀 안 글상자 문단의 링크 히트 (글상자-로컬 좌표, R30 #3). 필드 스팬이
    /// 있는 문단은 링크 글리프 rect에서만 히트하고 전체-rect 폴백을 금지한다
    /// — 앞뒤 평문·다중 링크가 첫 URL로 뭉개지지 않는다 (R31 #1).
    private func cellTextboxHyperlinkURL(
        _ cell: HwpTableCellFrame, at point: CGPoint
    ) -> String? {
        for textbox in cell.textboxes where textbox.rect.contains(point) {
            let boxPoint = CGPoint(
                x: point.x - textbox.rect.minX,
                y: point.y - textbox.rect.minY
            )
            if let url = spanAwareHyperlinkURL(in: textbox.textbox.paragraphs, at: boxPoint) {
                return url
            }
        }
        return nil
    }

    private func spanAwareHyperlinkURL(
        in paragraphs: [HwpLaidOutParagraph], at point: CGPoint
    ) -> String? {
        for paragraph in paragraphs {
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: paragraph.attributedString,
                origin: paragraph.rect.origin,
                lineWidth: paragraph.rect.width
            )
            if !regions.isEmpty {
                if let url = regions.first(where: { $0.rect.contains(point) })?.url {
                    return url
                }
                continue
            }
            if let url = paragraph.hyperlinkURL, paragraph.rect.contains(point) {
                return url
            }
        }
        return nil
    }

    /// walkText가 방문하지 않는 셀 글상자 링크 전용 히트 — 필드 스팬 게이트
    /// (hasFieldSpans) 아래에서도 도달해야 한다 (R31 #1). 중첩 표 재귀 포함.
    private func containerTextboxHyperlinkURL(block: AnyHwpBlock, point: CGPoint) -> String? {
        guard case let .table(tableFrame) = block.payload else { return nil }
        let localPoint = CGPoint(x: point.x - block.frame.minX, y: point.y - block.frame.minY)
        return tableTextboxHyperlinkURL(tableFrame, at: localPoint)
    }

    private func tableTextboxHyperlinkURL(
        _ tableFrame: HwpTableFrame, at point: CGPoint
    ) -> String? {
        for row in tableFrame.rows {
            for cell in row.cells where cell.cellFrame.contains(point) {
                if let url = cellTextboxHyperlinkURL(cell, at: point) {
                    return url
                }
                for nested in cell.nestedTables {
                    let nestedPoint = CGPoint(
                        x: point.x - nested.rect.minX,
                        y: point.y - nested.rect.minY
                    )
                    if let url = tableTextboxHyperlinkURL(nested.table, at: nestedPoint) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func footnoteNumber(block: AnyHwpBlock) -> Int {
        guard case let .footnote(footnote) = block.payload else { return 0 }
        return footnote.number
    }
}
