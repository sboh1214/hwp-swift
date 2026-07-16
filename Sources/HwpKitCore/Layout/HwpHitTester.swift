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
            guard block.frame.contains(point) else { continue }
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
            return fieldURL
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

    private func footnoteNumber(block: AnyHwpBlock) -> Int {
        guard case let .footnote(footnote) = block.payload else { return 0 }
        return footnote.number
    }
}
