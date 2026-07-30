import CoreGraphics
import Foundation

/// 블록 payload의 텍스트 콘텐츠를 렌더 방출 순서 그대로 순회한다.
/// `HwpPaintListBuilder`(drawText 방출)와 `HwpSelectableText`(선택 단위)가
/// 이 순회를 공유한다 — 순서·오프셋 계약은 `HwpSelectableTextPaintParityTests`가
/// 고정한다.
public enum HwpBlockContentWalker {
    /// 블록의 텍스트 콘텐츠 (길이 > 0)를 렌더 방출 순서로 방문한다.
    /// rect는 페이지 로컬 top-down — 렌더는 origin/폭을, 선택은 rect 전체를 쓴다.
    public static func walkText(
        block: AnyHwpBlock,
        visit: (NSAttributedString, CGRect, UInt32?) -> Void
    ) {
        switch block.payload {
        case let .table(table):
            // 셀 글상자 문단도 선택/복사 단위에 실어야 한다 — 렌더와 같은
            // 평면 순서 (글 뒤로 → 셀 텍스트 → 나머지)라 paint parity 유지 (R33 #1)
            walkTable(
                table,
                origin: block.frame.origin,
                onParagraphText: visit,
                onCellTextbox: { textbox, rect in
                    walkParagraphs(textbox.textbox.paragraphs, offset: rect.origin, visit: visit)
                }
            )
        case let .textbox(textbox):
            walkParagraphs(textbox.paragraphs, offset: block.frame.origin, visit: visit)
        case let .footnote(footnote):
            // 각주 안 개체·표의 텍스트도 선택/복사 단위에 실어야 한다 —
            // 렌더와 같은 평면 순서라 paint parity 유지 (#94, 표 셀과 같은 규약)
            walkFootnote(
                footnote,
                origin: block.frame.origin,
                onParagraphText: visit,
                onCellTextbox: { textbox, rect in
                    walkParagraphs(textbox.textbox.paragraphs, offset: rect.origin, visit: visit)
                }
            )
        case .shape, .image, .chart:
            return
        case nil:
            // 본문 텍스트 (분할된 표/글상자/각주 조각 포함) — 블록 자체가 단위
            guard [.text, .table, .textbox, .footnote].contains(block.kind),
                  let attributed = block.attributedString, attributed.length > 0
            else { return }
            visit(attributed, block.frame, block.source?.paragraphId)
        }
    }

    /// 문단 배열 (길이 > 0)을 블록 offset을 더한 페이지 좌표로 방문한다
    /// (표 셀·글상자·각주 공용). paragraphId는 복사 dedup의 출처 식별에 쓴다 (#8).
    public static func walkParagraphs(
        _ paragraphs: [HwpLaidOutParagraph],
        offset: CGPoint,
        visit: (NSAttributedString, CGRect, UInt32?) -> Void
    ) {
        for paragraph in paragraphs where paragraph.attributedString.length > 0 {
            visit(
                paragraph.attributedString,
                paragraph.rect.offsetBy(dx: offset.x, dy: offset.y),
                paragraph.paragraphId
            )
        }
    }

    /// 표를 렌더 방출 순서로 순회한다 — 셀마다
    /// onCellStart → (글 뒤로 개체)* → onParagraphText* → (나머지 개체)* →
    /// (중첩 표 재귀). 개체 이벤트는 종류별 콜백 (onCellImage/onCellShape/
    /// onCellTextbox)으로 평면·zOrder 순서에 따라 발화한다.
    /// 렌더는 모든 이벤트를 (fill/border·drawText·셀 개체), 선택은
    /// onParagraphText만 소비한다.
    public static func walkTable(
        _ table: HwpTableFrame,
        origin: CGPoint,
        onCellStart: (HwpTableCellFrame, CGRect) -> Void = { _, _ in },
        onParagraphText: (NSAttributedString, CGRect, UInt32?) -> Void,
        onCellImage: (HwpCellImage, CGRect) -> Void = { _, _ in },
        onCellShape: (HwpCellShape, CGRect) -> Void = { _, _ in },
        onCellTextbox: (HwpCellTextbox, CGRect) -> Void = { _, _ in }
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
                    }
                }
                for object in objects where object.paintsBehindText {
                    emit(object)
                }
                walkParagraphs(cell.paragraphs, offset: origin, visit: onParagraphText)
                for object in objects where !object.paintsBehindText {
                    emit(object)
                }
                // 중첩 표는 셀 안 위치를 origin으로 재귀 순회한다 —
                // origin 합성 산식은 여기 한 곳에만 둔다.
                for nested in cell.nestedTables {
                    walkTable(
                        nested.table,
                        origin: CGPoint(
                            x: origin.x + nested.rect.minX,
                            y: origin.y + nested.rect.minY
                        ),
                        onCellStart: onCellStart,
                        onParagraphText: onParagraphText,
                        onCellImage: onCellImage,
                        onCellShape: onCellShape,
                        onCellTextbox: onCellTextbox
                    )
                }
            }
        }
    }

    /// 각주/미주 블록을 렌더 방출 순서로 순회한다 — (글 뒤로 개체)* →
    /// onParagraphText* → (나머지 개체)* → (각주 안 표 재귀). 이벤트 종류와
    /// 순서 규약은 `walkTable`과 같다 (#94) — 각주는 표 셀·글상자와 같은
    /// 컨테이너라 개체 페이로드도 같은 형태다.
    /// 구분선은 블록 사이에 공유되므로 이 순회의 이벤트가 아니다 (페인터 몫).
    public static func walkFootnote(
        _ footnote: HwpFootnoteBlock,
        origin: CGPoint,
        onParagraphText: (NSAttributedString, CGRect, UInt32?) -> Void,
        onCellStart: (HwpTableCellFrame, CGRect) -> Void = { _, _ in },
        onCellImage: (HwpCellImage, CGRect) -> Void = { _, _ in },
        onCellShape: (HwpCellShape, CGRect) -> Void = { _, _ in },
        onCellTextbox: (HwpCellTextbox, CGRect) -> Void = { _, _ in }
    ) {
        let objects = sortedObjects(
            images: footnote.images,
            shapes: footnote.shapes,
            textboxes: footnote.textboxes
        )
        func emit(_ object: CellObject) {
            switch object {
            case let .image(image):
                onCellImage(image, image.rect.offsetBy(dx: origin.x, dy: origin.y))
            case let .shape(shape):
                onCellShape(shape, shape.rect.offsetBy(dx: origin.x, dy: origin.y))
            case let .textbox(textbox):
                onCellTextbox(textbox, textbox.rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        for object in objects where object.paintsBehindText {
            emit(object)
        }
        walkParagraphs(footnote.paragraphs, offset: origin, visit: onParagraphText)
        for object in objects where !object.paintsBehindText {
            emit(object)
        }
        // 각주 안 표는 블록-로컬 위치를 origin으로 재귀 순회한다 (셀 경로와
        // 같은 origin 합성 산식).
        for nested in footnote.nestedTables {
            walkTable(
                nested.table,
                origin: CGPoint(
                    x: origin.x + nested.rect.minX,
                    y: origin.y + nested.rect.minY
                ),
                onCellStart: onCellStart,
                onParagraphText: onParagraphText,
                onCellImage: onCellImage,
                onCellShape: onCellShape,
                onCellTextbox: onCellTextbox
            )
        }
    }

    /// 각주 개체 한 층 (페인트 순서의 단위)
    enum FootnoteLayer {
        case image(HwpCellImage)
        case shape(HwpCellShape)
        case textbox(HwpCellTextbox)

        var rect: CGRect {
            switch self {
            case let .image(image): image.rect
            case let .shape(shape): shape.rect
            case let .textbox(textbox): textbox.rect
            }
        }

        /// 아래 층을 가리는가 — **채워진 층만** 가린다 (R42 #2). 이 리포는
        /// 오버레이가 겹치는 것을 설계로 두므로 (`앵커 규칙`), rect만 보고 전부
        /// 가린다고 하면 속 빈 장식 도형·테두리만 있는 상자 하나가 그 아래 링크를
        /// 통째로 못 누르게 만든다. 알파는 알 수 없어 그림은 채워진 것으로 본다.
        var occludesContentBelow: Bool {
            switch self {
            case .image: true
            case let .shape(shape): shape.geometry.fillColor != nil
            case let .textbox(textbox): textbox.textbox.fillColor != nil
            }
        }
    }

    /// 각주 블록의 개체를 **페인트 순서**로 나눠 돌려준다 (글 뒤로 / 글 앞으로,
    /// 각 그룹은 `sortedObjects`와 같은 zOrder → 원본 순서). 히트 테스터가 순서를
    /// 다시 구현하면 페인트와 갈려 덮인 링크가 열리므로, 정렬 소유권은 여기 남는다
    /// (R41 #1 — `walkFootnote`가 방출 순서의 단일 소유자라는 규약의 연장).
    static func footnoteLayersInPaintOrder(
        _ footnote: HwpFootnoteBlock
    ) -> (behindText: [FootnoteLayer], inFrontOfText: [FootnoteLayer]) {
        let ordered = sortedObjects(
            images: footnote.images,
            shapes: footnote.shapes,
            textboxes: footnote.textboxes
        )
        func layers(behindText: Bool) -> [FootnoteLayer] {
            ordered.filter { $0.paintsBehindText == behindText }.map { object in
                switch object {
                case let .image(image): FootnoteLayer.image(image)
                case let .shape(shape): FootnoteLayer.shape(shape)
                case let .textbox(textbox): FootnoteLayer.textbox(textbox)
                }
            }
        }
        return (behindText: layers(behindText: true), inFrontOfText: layers(behindText: false))
    }

    /// 셀 개체 (종류 무관 통합 순회 단위)
    private enum CellObject {
        case image(HwpCellImage)
        case shape(HwpCellShape)
        case textbox(HwpCellTextbox)

        var paintsBehindText: Bool {
            switch self {
            case let .image(image): image.paintsBehindText
            case let .shape(shape): shape.paintsBehindText
            case let .textbox(textbox): textbox.paintsBehindText
            }
        }

        var zOrder: Int32 {
            switch self {
            case let .image(image): image.zOrder
            case let .shape(shape): shape.zOrder
            case let .textbox(textbox): textbox.zOrder
            }
        }

        var sourceOrder: Int {
            switch self {
            case let .image(image): image.sourceOrder
            case let .shape(shape): shape.sourceOrder
            case let .textbox(textbox): textbox.sourceOrder
            }
        }
    }

    /// 셀 개체를 zOrder 오름차순 (동순위는 원본 ctrlHeaderArray 순서 —
    /// 종류-버킷 순서가 아니다, R31 #3)으로 정렬한 방출 목록.
    private static func sortedCellObjects(_ cell: HwpTableCellFrame) -> [CellObject] {
        sortedObjects(images: cell.images, shapes: cell.shapes, textboxes: cell.textboxes)
    }

    /// 컨테이너 개체 정렬의 단일 지점 (표 셀·각주 공용, #94) — 종류 버킷을
    /// 합쳐 zOrder → 원본 순서로 정렬한다.
    private static func sortedObjects(
        images: [HwpCellImage],
        shapes: [HwpCellShape],
        textboxes: [HwpCellTextbox]
    ) -> [CellObject] {
        let objects = images.map(CellObject.image)
            + shapes.map(CellObject.shape)
            + textboxes.map(CellObject.textbox)
        return objects.sorted { lhs, rhs in
            lhs.zOrder != rhs.zOrder
                ? lhs.zOrder < rhs.zOrder
                : lhs.sourceOrder < rhs.sourceOrder
        }
    }
}
