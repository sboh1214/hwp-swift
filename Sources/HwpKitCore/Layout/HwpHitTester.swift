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
                guard hitEligibleFrame(for: block).contains(point) else { continue }
                // 각주는 가림까지 살려 판정한다 — `.occluded`를 nil로 접어 아래
                // 블록으로 내려가면 그 개체 밑에 숨은 링크가 열린다 (R45 #3).
                if case let .footnote(footnote) = block.payload {
                    switch containerHit(
                        paragraphs: footnote.paragraphs,
                        images: footnote.images, shapes: footnote.shapes,
                        textboxes: footnote.textboxes,
                        nestedTables: footnote.nestedTables,
                        at: CGPoint(
                            x: point.x - block.frame.minX, y: point.y - block.frame.minY
                        )
                    ) {
                    case let .found(url):
                        return .hyperlink(url: url, blockIndex: index)
                    case .occluded:
                        return .footnote(blockIndex: index, number: footnote.number)
                    case .miss:
                        continue
                    }
                }
                guard let url = hyperlinkURL(for: block, at: point) else { continue }
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

    /// 개체 층을 페인트 역순으로 훑은 결과.
    private enum LayerHit {
        case found(String)
        /// 링크 없는 **불투명** 층이 그 지점을 덮고 있다 — 아래 층 탐색을 멈춘다.
        /// 보이는 개체를 눌렀는데 그 밑에 숨은 링크가 열리면 안 된다 (R42 #2).
        case occluded
        case miss
    }

    /// 개체 층을 **페인트 역순**(위→아래)으로 훑는다. 글상자는 그 안도 같은
    /// 컨테이너 규약으로 재귀한다 — 글상자 안 전경 그림·도형이 그 글상자 문단
    /// **뒤에** 그려지므로 (`textboxCommands`) 안쪽 링크를 덮을 수 있다 (R43 #4).
    private func layerHit(
        _ layers: [HwpBlockContentWalker.ContentLayer], at point: CGPoint
    ) -> LayerHit {
        for layer in layers.reversed() {
            if case let .textbox(textbox) = layer {
                let inner = CGPoint(
                    x: point.x - textbox.rect.minX,
                    y: point.y - textbox.rect.minY
                )
                // 재귀 결과를 **그대로 전파**한다 — `.occluded`를 버리면 글상자
                // rect 밖에 놓인 자식이 덮은 자리에서 (글상자 자신은 그 자리를
                // 안 가리므로) 아래 링크가 열린다 (R44 #3).
                switch containerHit(
                    paragraphs: textbox.textbox.paragraphs,
                    images: textbox.textbox.images,
                    shapes: textbox.textbox.shapes,
                    textboxes: [], nestedTables: [], at: inner
                ) {
                case let .found(url):
                    return .found(url)
                case .occluded:
                    return .occluded
                case .miss:
                    break
                }
            }
            if layer.occludes(point) {
                return .occluded
            }
        }
        return .miss
    }

    /// 필드 스팬 하이퍼링크(%hlk)를 링크 텍스트 글리프 rect에서만 히트한다 —
    /// 앞뒤 평문·다중 링크가 첫 URL로 뭉개지지 않는다 (#2). 필드 속성이 있는
    /// 블록은 링크 밖에서 nil (블록/컨테이너 폴백 금지); 없으면 종전 폴백.
    private func hyperlinkURL(for block: AnyHwpBlock, at point: CGPoint) -> String? {
        // 각주는 층이 겹치므로 히트가 **페인트 역순**이어야 한다. 블록 전체를 훑는
        // 아래 walkText 스캔은 페인트 **정순**이라 덮인 스팬 링크를 먼저 잡아
        // 층 인식 조회에 닿지도 못했다 (R42 #1). 각주만 그 조회 한 곳에 맡긴다 —
        // 안쪽 `spanAwareHyperlinkURL`이 문단마다 스팬 우선 규칙을 그대로 지킨다.
        if case .footnote = block.payload {
            return containerHyperlinkURL(block: block, point: point)
        }
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
            // 셀 글상자 전용 통로 (R31 #1) 는 필요 없어졌다 — containerHit이
            // 컨테이너를 재귀로 훑는다. 되살리면 가림 (`.occluded`) 으로 nil이 된
            // 지점에서 덮인 링크가 다시 열린다 (R43).
            return containerHyperlinkURL(block: block, point: point)
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
        let hit: LayerHit = switch block.payload {
        case let .table(tableFrame):
            tableHit(tableFrame, at: localPoint)
        case let .textbox(textbox):
            containerHit(
                paragraphs: textbox.paragraphs,
                images: textbox.images, shapes: textbox.shapes,
                textboxes: [], nestedTables: [], at: localPoint
            )
        case let .footnote(footnote):
            containerHit(
                paragraphs: footnote.paragraphs,
                images: footnote.images, shapes: footnote.shapes,
                textboxes: footnote.textboxes,
                nestedTables: footnote.nestedTables, at: localPoint
            )
        default:
            LayerHit.miss
        }
        guard case let .found(url) = hit else { return nil }
        return url
    }

    /// 컨테이너(각주·표 셀·글상자) 하나를 **페인트 역순**으로 훑는다.
    ///
    /// 페인트 순서는 글 뒤로 개체 → 문단 텍스트 → 나머지 개체 → 안쪽 표이므로
    /// (`walkFootnote`/`walkTable`) 역순은 그 반대다. 컨테이너마다 이 함수 하나를
    /// 재귀로 쓰는 이유는 R39~R43이 전부 "히트가 페인트의 어느 겹을 안 따라갔다"
    /// 였기 때문이다 — 겹마다 따로 구현하면 다음 겹에서 또 갈린다.
    ///
    /// 링크 조회는 층 rect로 미리 거르지 않는다 (자손이 컨테이너를 넘어 그려질 수
    /// 있다, R41 #2). **가림 판정만** 실제 칠한 영역을 본다 (R43).
    private func containerHit(
        paragraphs: [HwpLaidOutParagraph],
        images: [HwpCellImage],
        shapes: [HwpCellShape],
        textboxes: [HwpCellTextbox],
        nestedTables: [HwpNestedTableFrame],
        at point: CGPoint
    ) -> LayerHit {
        for nested in nestedTables.reversed() {
            let hit = tableHit(nested.table, at: CGPoint(
                x: point.x - nested.rect.minX, y: point.y - nested.rect.minY
            ))
            if case .miss = hit {
                continue
            }
            return hit
        }
        let layers = HwpBlockContentWalker.layersInPaintOrder(
            images: images, shapes: shapes, textboxes: textboxes
        )
        switch layerHit(layers.inFrontOfText, at: point) {
        case let .found(url):
            return .found(url)
        case .occluded:
            return .occluded
        case .miss:
            break
        }
        if let url = spanAwareHyperlinkURL(in: paragraphs, at: point) {
            return .found(url)
        }
        return layerHit(layers.behindText, at: point)
    }

    /// 표를 셀 단위로 훑는다. 셀 안은 같은 컨테이너 규약이고, **채운 셀은 아래를
    /// 가린다** — 페인터가 `fillRect`로 칠하므로 (R43 #5) 링크가 없다고 통과시키면
    /// 그 아래 문단 링크가 열린다.
    private func tableHit(_ table: HwpTableFrame, at point: CGPoint) -> LayerHit {
        // 셀 프레임으로 **미리 거르지 않는다** — 셀 문단·자식이 자기 셀을 넘어
        // 그려질 수 있고 (R44 #2) 자격 영역(`footnoteContentFrame`)은 그 자리를
        // 이미 인정한다. `cellFrame`은 **셀 채움 가림 판정에만** 쓴다.
        // 순서는 페인트 역순 (`walkTable`이 행·셀 순으로 그린다).
        for row in table.rows.reversed() {
            for cell in row.cells.reversed() {
                let hit = containerHit(
                    paragraphs: cell.paragraphs,
                    images: cell.images, shapes: cell.shapes, textboxes: cell.textboxes,
                    nestedTables: cell.nestedTables, at: point
                )
                if case .miss = hit {
                    if cell.fillColor != nil, cell.cellFrame.contains(point) {
                        return .occluded
                    }
                    continue
                }
                return hit
            }
        }
        return .miss
    }

    /// 문단 목록에서 링크를 찾는다 — 필드 스팬이 있으면 **글리프 rect에서만**,
    /// 없으면 문단 rect 폴백 (R38 #4, 루트 규약 "하이퍼링크 방출은 스팬 우선").
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

    private func footnoteNumber(block: AnyHwpBlock) -> Int {
        guard case let .footnote(footnote) = block.payload else { return 0 }
        return footnote.number
    }
}
