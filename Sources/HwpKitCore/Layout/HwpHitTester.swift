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
                // slight-overflow 한 줄 문단은 frame 밖(허용 배율 이내)까지
                // 그려지고 링크 rect도 함께 넘는다 — 그 가시 영역의 탭을 기각
                // 전에 링크 rect로 확인한다 (#4).
                guard block.kind == .text,
                      overflowHitFrame(for: block).contains(point),
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

    /// slight-overflow 렌더가 닿을 수 있는 히트 영역 — frame 폭의 허용 초과분
    /// (`slightOverflowWidthRatio`)만큼 좌우로 확장한 frame.
    private func overflowHitFrame(for block: AnyHwpBlock) -> CGRect {
        let extra = block.frame.width * (HwpRenderTuning.Text.slightOverflowWidthRatio - 1)
        return block.frame.insetBy(dx: -extra, dy: 0)
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
        if hasFieldSpans {
            // 블록/컨테이너 전체-rect 폴백은 금지하되, 스팬 스캔 (walkText)이
            // 방문하지 않는 셀 글상자 링크는 별도 통로로 히트한다 (R31 #1).
            return fieldURL ?? containerTextboxHyperlinkURL(block: block, point: point)
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
            return hyperlinkURL(in: textbox.paragraphs, at: localPoint)
        case let .footnote(footnote):
            // 각주 문단 좌표는 블록-로컬(0,0 기준)이라 localPoint로 히트한다 (#20).
            return hyperlinkURL(in: footnote.paragraphs, at: localPoint)
        default:
            return nil
        }
    }

    /// 표(중첩 표 포함) 셀 문단의 하이퍼링크를 표-로컬 좌표로 재귀 히트한다 —
    /// 중첩 표 안 링크도 콜백을 발화하게 한다 (#19).
    private func tableHyperlinkURL(_ tableFrame: HwpTableFrame, at point: CGPoint) -> String? {
        for row in tableFrame.rows {
            for cell in row.cells where cell.cellFrame.contains(point) {
                if let url = hyperlinkURL(in: cell.paragraphs, at: point) {
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
