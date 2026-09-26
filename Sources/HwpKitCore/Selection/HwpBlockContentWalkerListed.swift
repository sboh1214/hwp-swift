import CoreGraphics
import Foundation

/// **목록 끝**을 함께 넘기는 순회 (#233) — 공개 순회(`walkText`·`walkParagraphs`·`walkTable`·
/// `walkFootnote`)의 본체다. 방문이 넷째 인자로 **그 문단 뒤에 무엇이 오는지**
/// (`HwpDrawnTextLayout.ListEnd`)를 받는다: 표 셀(`cell.paragraphs`)·셀 글상자·글상자·각주의
/// 배열이 한글의 문단 목록이고, 그 마지막 문단은 `.end`(마지막 줄 아래는 한글이 링크를 열지
/// 않는다 — `HwpDrawnTextLayout.ClickBand`), 나머지는 `.followed`다. 길이 0 문단은 방문하지
/// 않지만 목록 끝 판정에는 든다 — 배열 끝이 빈 문단이면 그 앞 문단은 끝이 아니다 (한글도 그 빈
/// 문단 줄이 뒤따른다). 본문(payload 없는 블록)은 `.unknown`이다 — 문단 블록은 자기가 단의
/// 끝인지 모른다. 공개 순회는 넷째 인자를 버리므로 방문 순서·rect는 같다.
extension HwpBlockContentWalker {
    /// `walkText` 방문 + 그 문단 뒤에 무엇이 오는지
    typealias ListedParagraphVisit = (
        NSAttributedString, CGRect, UInt32?, HwpDrawnTextLayout.ListEnd
    ) -> Void

    static func walkListedText(
        block: AnyHwpBlock,
        visit: ListedParagraphVisit
    ) {
        switch block.payload {
        case let .table(table):
            // 셀 글상자 문단도 선택/복사 단위에 실어야 한다 — 렌더와 같은
            // 평면 순서 (글 뒤로 → 셀 텍스트 → 나머지)라 paint parity 유지 (R33 #1)
            walkListedTable(
                table,
                origin: block.frame.origin,
                onParagraphText: visit,
                onCellTextbox: { textbox, rect in
                    walkListedParagraphs(
                        textbox.textbox.paragraphs, offset: rect.origin, visit: visit
                    )
                }
            )
        case let .textbox(textbox):
            walkListedParagraphs(textbox.paragraphs, offset: block.frame.origin, visit: visit)
        case let .footnote(footnote):
            // 각주 안 개체·표의 텍스트도 선택/복사 단위에 실어야 한다 —
            // 렌더와 같은 평면 순서라 paint parity 유지 (#94, 표 셀과 같은 규약)
            walkListedFootnote(
                footnote,
                origin: block.frame.origin,
                onParagraphText: visit,
                onCellTextbox: { textbox, rect in
                    walkListedParagraphs(
                        textbox.textbox.paragraphs, offset: rect.origin, visit: visit
                    )
                }
            )
        case .shape, .image, .chart:
            return
        case nil:
            // 본문 텍스트 (분할된 표/글상자/각주 조각 포함) — 블록 자체가 단위
            guard let attributed = plainText(of: block) else { return }
            visit(attributed, block.frame, block.source?.paragraphId, .unknown)
        }
    }

    /// `lastEndsList`가 거짓이면 배열의 마지막 문단도 목록 끝이 아니다 — 각주는 문단마다
    /// 블록 하나라 같은 각주의 다음 문단이 다음 블록에 있다 (`HwpFootnoteBlock.isNoteEnd`).
    static func walkListedParagraphs(
        _ paragraphs: [HwpLaidOutParagraph],
        offset: CGPoint,
        lastEndsList: Bool = true,
        visit: ListedParagraphVisit
    ) {
        for (index, paragraph) in paragraphs.enumerated()
            where paragraph.attributedString.length > 0
        {
            visit(
                paragraph.attributedString,
                paragraph.rect.offsetBy(dx: offset.x, dy: offset.y),
                paragraph.paragraphId,
                index < paragraphs.count - 1 || !lastEndsList ? .followed : .end
            )
        }
    }

    static func walkListedTable(
        _ table: HwpTableFrame,
        origin: CGPoint,
        onCellStart: (HwpTableCellFrame, CGRect) -> Void = { _, _ in },
        onParagraphText: ListedParagraphVisit,
        onCellImage: (HwpCellImage, CGRect) -> Void = { _, _ in },
        onCellShape: (HwpCellShape, CGRect) -> Void = { _, _ in },
        onCellTextbox: (HwpCellTextbox, CGRect) -> Void = { _, _ in },
        onNestedTable: (HwpNestedTableFrame, CGRect) -> Void = { _, _ in },
        onNestedTableEnd: (HwpNestedTableFrame, CGRect) -> Void = { _, _ in }
    ) {
        for row in table.rows {
            for cell in row.cells {
                onCellStart(cell, cell.cellFrame.offsetBy(dx: origin.x, dy: origin.y))
                // 셀 안 개체는 셀 콘텐츠로 순회한다 (표-로컬 rect + 블록 origin).
                // 글 뒤로 개체는 텍스트보다 먼저, 나머지는 뒤에 — 각 평면 안은
                // zOrder 정렬 (같으면 수집 순서 유지, R30 #2).
                let objects = sortedCellObjects(cell)
                func emit(_ object: CellObject) {
                    switch object {
                    case let .image(image):
                        onCellImage(image, image.rect.offsetBy(dx: origin.x, dy: origin.y))
                    case let .shape(shape):
                        onCellShape(shape, shape.rect.offsetBy(dx: origin.x, dy: origin.y))
                    case let .textbox(textbox):
                        onCellTextbox(textbox, textbox.rect.offsetBy(dx: origin.x, dy: origin.y))
                    case let .nestedTable(nested):
                        let rect = nested.rect.offsetBy(dx: origin.x, dy: origin.y)
                        onNestedTable(nested, rect)
                        walkListedTable(
                            nested.table,
                            origin: CGPoint(
                                x: origin.x + nested.rect.minX,
                                y: origin.y + nested.rect.minY
                            ),
                            onCellStart: onCellStart,
                            onParagraphText: onParagraphText,
                            onCellImage: onCellImage,
                            onCellShape: onCellShape,
                            onCellTextbox: onCellTextbox,
                            onNestedTable: onNestedTable,
                            onNestedTableEnd: onNestedTableEnd
                        )
                        onNestedTableEnd(nested, rect)
                    }
                }
                for object in objects where object.paintsBehindText {
                    emit(object)
                }
                walkListedParagraphs(cell.paragraphs, offset: origin, visit: onParagraphText)
                for object in objects where !object.paintsBehindText {
                    emit(object)
                }
                // 중첩 표는 셀 안 위치를 origin으로 재귀 순회한다 —
                // origin 합성 산식은 여기 한 곳에만 둔다.
                for nested in cell.nestedTables {
                    let rect = nested.rect.offsetBy(dx: origin.x, dy: origin.y)
                    onNestedTable(nested, rect)
                    walkListedTable(
                        nested.table,
                        origin: CGPoint(
                            x: origin.x + nested.rect.minX,
                            y: origin.y + nested.rect.minY
                        ),
                        onCellStart: onCellStart,
                        onParagraphText: onParagraphText,
                        onCellImage: onCellImage,
                        onCellShape: onCellShape,
                        onCellTextbox: onCellTextbox,
                        onNestedTable: onNestedTable,
                        onNestedTableEnd: onNestedTableEnd
                    )
                    onNestedTableEnd(nested, rect)
                }
            }
        }
    }

    static func walkListedFootnote(
        _ footnote: HwpFootnoteBlock,
        origin: CGPoint,
        onParagraphText: ListedParagraphVisit,
        onCellStart: (HwpTableCellFrame, CGRect) -> Void = { _, _ in },
        onCellImage: (HwpCellImage, CGRect) -> Void = { _, _ in },
        onCellShape: (HwpCellShape, CGRect) -> Void = { _, _ in },
        onCellTextbox: (HwpCellTextbox, CGRect) -> Void = { _, _ in },
        onNestedTable: (HwpNestedTableFrame, CGRect) -> Void = { _, _ in },
        onNestedTableEnd: (HwpNestedTableFrame, CGRect) -> Void = { _, _ in }
    ) {
        // 표도 같은 평면·정렬에 합류한다 (R47 #1) — 따로 두고 마지막에 그리면
        // 글 뒤로 표가 텍스트 앞에 나온다.
        let objects = sortedObjects(
            images: footnote.images,
            shapes: footnote.shapes,
            textboxes: footnote.textboxes,
            nestedTables: footnote.nestedTables
        )
        func emit(_ object: CellObject) {
            switch object {
            case let .image(image):
                onCellImage(image, image.rect.offsetBy(dx: origin.x, dy: origin.y))
            case let .shape(shape):
                onCellShape(shape, shape.rect.offsetBy(dx: origin.x, dy: origin.y))
            case let .textbox(textbox):
                onCellTextbox(textbox, textbox.rect.offsetBy(dx: origin.x, dy: origin.y))
            case let .nestedTable(nested):
                // 각주 안 표는 블록-로컬 위치를 origin으로 재귀 순회한다
                // (셀 경로와 같은 origin 합성 산식).
                let rect = nested.rect.offsetBy(dx: origin.x, dy: origin.y)
                onNestedTable(nested, rect)
                walkListedTable(
                    nested.table,
                    origin: CGPoint(
                        x: origin.x + nested.rect.minX,
                        y: origin.y + nested.rect.minY
                    ),
                    onCellStart: onCellStart,
                    onParagraphText: onParagraphText,
                    onCellImage: onCellImage,
                    onCellShape: onCellShape,
                    onCellTextbox: onCellTextbox,
                    onNestedTable: onNestedTable,
                    onNestedTableEnd: onNestedTableEnd
                )
                onNestedTableEnd(nested, rect)
            }
        }
        for object in objects where object.paintsBehindText {
            emit(object)
        }
        walkListedParagraphs(
            footnote.paragraphs, offset: origin, lastEndsList: footnote.isNoteEnd,
            visit: onParagraphText
        )
        for object in objects where !object.paintsBehindText {
            emit(object)
        }
    }
}
