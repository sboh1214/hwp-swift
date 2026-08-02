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
                        // 자격 영역은 bounding box라 투명한 틈까지 든다 — 그 틈은
                        // 아래 블록 몫이지만 **칠해진 자손 위**라면 각주가 claim
                        // 한다 (R53). `containerHit`은 링크와 불투명 채움만 알아
                        // 링크 없는 문단·안 채운 셀에 `.miss`를 주는데, 그대로
                        // 통과시키면 보이는 각주 글자를 눌렀는데 아래 본문의 무관한
                        // 링크가 열린다 — frame **안**에서 같은 텍스트가
                        // `.footnote`가 되는 것과 답이 같아야 한다.
                        guard paintsContent(
                            footnote, origin: block.frame.origin, at: point
                        ) else { continue }
                        return .footnote(blockIndex: index, number: footnote.number)
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

    /// 페이지 좌표의 점을 페이로드 자신의 좌표계로 옮긴다 — `ContentLayer`의
    /// 커버리지 판정이 페이로드 rect 기준이라 walker가 준 페이지 rect로 되돌린다.
    static func payloadPoint(
        _ point: CGPoint, page: CGRect, payload: CGRect
    ) -> CGPoint {
        CGPoint(
            x: point.x - page.minX + payload.minX,
            y: point.y - page.minY + payload.minY
        )
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
        _ layers: [HwpBlockContentWalker.ContentLayer],
        wrappedBy paragraphs: [HwpLaidOutParagraph],
        at point: CGPoint
    ) -> LayerHit {
        for layer in layers.reversed() {
            // 안쪽부터 본다 (위에 그려진 것이 이긴다). 자손이 가렸다고 바로
            // 반환하지 않고 `innerOccluded`로 미뤄, 이 층을 **감싼** 링크를
            // 먼저 확인한다 — 채운 셀을 가진 표나 자손이 가린 글상자를 `%hlk`가
            // 감싸면 그 링크가 열려야 한다 (R50 #2).
            var innerOccluded = false
            if case let .nestedTable(nested) = layer {
                switch tableHit(nested.table, at: CGPoint(
                    x: point.x - nested.rect.minX, y: point.y - nested.rect.minY
                )) {
                case let .found(url):
                    return .found(url)
                case .occluded:
                    innerOccluded = true
                case .miss:
                    break
                }
            }
            if case let .textbox(textbox) = layer {
                switch containerHit(
                    paragraphs: textbox.textbox.paragraphs,
                    images: textbox.textbox.images,
                    shapes: textbox.textbox.shapes,
                    textboxes: [], nestedTables: [],
                    at: CGPoint(
                        x: point.x - textbox.rect.minX,
                        y: point.y - textbox.rect.minY
                    )
                ) {
                case let .found(url):
                    return .found(url)
                case .occluded:
                    innerOccluded = true
                case .miss:
                    break
                }
            }
            // **감싼 링크는 개체 rect 전체의 것**이다 (R60) — 방출이 그 rect로
            // 내므로 속 빈 도형의 안쪽처럼 칠하지 않은 자리도 이 개체의 링크다.
            // 반대로 **rect 밖은 아니다** (R62): 자손이 부모를 넘어 그려 `.occluded`
            // 를 돌려줘도 방출은 부모 rect까지만 링크를 내므로, 그 밖에서 부모
            // URL을 열면 paint list에 없는 링크가 된다. 자손 순회는 그대로 무제한.
            // 구제 대상은 `controlIndex` 가 일치하는 링크뿐이라 (R49/R50 #1) 옆의
            // 다른 링크를 덮었을 뿐인 경우는 여전히 살아나지 않는다.
            if layer.rect.contains(point),
               let url = layer.wrapperURL ?? HwpDrawnTextLayout.wrapperHyperlinkURL(
                   in: paragraphs,
                   paragraphId: layer.paragraphId,
                   controlIndex: layer.controlIndex
               )
            {
                return .found(url)
            }
            // 링크가 없으면 종전대로 **칠한 자리만** 가림으로 접는다 (R54 ①) —
            // 투명한 안쪽은 아래 블록 몫이다.
            guard innerOccluded || layer.paints(point) else { continue }
            return .occluded
        }
        return .miss
    }

    /// 필드 스팬 하이퍼링크(%hlk)를 링크 텍스트 글리프 rect에서만 히트한다 —
    /// 앞뒤 평문·다중 링크가 첫 URL로 뭉개지지 않는다 (#2). 필드 속성이 있는
    /// 블록은 링크 밖에서 nil (블록/컨테이너 폴백 금지); 없으면 종전 폴백.
    private func hyperlinkURL(for block: AnyHwpBlock, at point: CGPoint) -> String? {
        // 컨테이너는 층이 겹치므로 히트가 **페인트 역순**이어야 한다. 아래 walkText
        // 스캔은 페인트 **정순**이라 덮인 스팬 링크를 먼저 잡아 층 인식 조회에 닿지도
        // 못한다 (R42 #1). **각주 전용이 아니다** (R64): 표 셀·글상자도 같은 층을
        // 가지므로 payload가 있는 컨테이너 셋을 모두 그 조회 한 곳에 맡긴다 — 안쪽
        // `spanAwareHyperlinkURL`이 문단마다 스팬 우선 규칙을 그대로 지키고,
        // 블록-레벨 폴백의 게이트(R61)가 스팬 있는 블록의 전체-rect 폴백도 막는다.
        // payload가 없는 조각 블록(`.text`·분할된 표/글상자)은 그대로 스캔을 탄다.
        switch block.payload {
        case .footnote, .table, .textbox:
            // 층 조회가 **먼저** 이기고, 실패했을 때만 블록-레벨 계약으로 떨어진다 (R59).
            return containerHyperlinkURL(block: block, point: point)
                ?? blockLevelURL(for: block, at: point)
        default:
            break
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
        // 컨테이너도 **안쪽이 먼저**다 (R62) — 블록 링크를 앞에 두면 셀·글상자 문단의
        // 링크가 프레임 전체 URL에 뭉개져 방출된 적 없는 URL이 열린다.
        return containerHyperlinkURL(block: block, point: point) ?? blockLevelURL(for: block, at: point)
    }

    /// 블록 프레임 전체에 걸리는 링크 — **방출과 같은 게이트**를 통과할 때만 (R61/R62).
    ///
    /// 방출은 안쪽(문단·감싼 개체) 링크를 하나라도 내면 블록 링크를 내지 않는다
    /// (`appendHyperlinkCommands`의 `!emitted`). 히트가 그때도 폴백하면 paint list에
    /// 없는 URL이 열린다 — 각주뿐 아니라 표·글상자도 같은 계약이다.
    ///
    /// 게이트는 **영역이기도 하다** (R63): 방출은 이 폴백을 `block.frame`으로만 내는데
    /// 컨테이너 자격은 넘쳐 그린 자손까지 넓으므로 (R62), 그 띠에서 폴백하면 방출된 적
    /// 없는 URL이 열린다. `.text`의 slight-overflow 띠는 반대다 — 거기 넘친 것은 다른
    /// 개체가 아니라 **블록 자신의 글자**라 그 링크가 열려야 한다 (#4).
    private func blockLevelURL(for block: AnyHwpBlock, at point: CGPoint) -> String? {
        let hasInnerLink: Bool
        switch block.payload {
        case let .footnote(footnote): hasInnerLink = footnote.hasHyperlink
        case let .table(table): hasInnerLink = table.hasHyperlink
        case let .textbox(textbox): hasInnerLink = textbox.hasHyperlink
        default: return block.hyperlinkURL
        }
        guard block.frame.contains(point) else { return nil }
        return hasInnerLink ? nil : block.hyperlinkURL
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
        // 표도 같은 평면·정렬에 합류한다 (R47 #1) — 따로 앞세우면 글 뒤로 표를
        // 최상단으로 보게 돼 페인트와 갈린다.
        let layers = HwpBlockContentWalker.layersInPaintOrder(
            images: images, shapes: shapes, textboxes: textboxes, nestedTables: nestedTables
        )
        switch layerHit(layers.inFrontOfText, wrappedBy: paragraphs, at: point) {
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
        // 링크 없는 전경 글자도 **칠해진 것**이다 — 그 위의 탭이 글 뒤로 개체의
        // 링크를 열면 페인트 역순 규약이 깨진다 (R54). 줄 사이 여백·짧은 줄의 빈
        // 오른쪽은 아무것도 안 칠하므로 그대로 뒤 층으로 내려간다.
        if paragraphsPaint(paragraphs, at: point) {
            return .occluded
        }
        return layerHit(layers.behindText, wrappedBy: paragraphs, at: point)
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
                // 셀 안 표는 **평면 정렬에 넣지 않는다** (R48). 각주와 갈리는
                // 이유는 생산자다 — 각주 수집기는 표에 평면·정렬 키를 채우지만
                // (R47 #1) 셀 생산자 (`HwpTableLayout`) 는 채우지 않아 전부
                // 기본값이라, 정렬에 넣으면 `sourceOrder: 0`으로 맨 앞에 놓여
                // 히트가 가장 나중에 본다. 반면 셀 페인터 (`walkTable`) 는 표를
                // 모든 개체 **뒤에** 그린다 — 그 순서를 그대로 따라 최상단으로
                // 먼저 훑는다.
                for nested in cell.nestedTables.reversed() {
                    var innerOccluded = false
                    switch tableHit(nested.table, at: CGPoint(
                        x: point.x - nested.rect.minX, y: point.y - nested.rect.minY
                    )) {
                    case let .found(url):
                        return .found(url)
                    case .occluded:
                        innerOccluded = true
                    case .miss:
                        break
                    }
                    // 감싼 링크는 **표 rect 전체**의 것이다 (R60) — 층 경로
                    // (`layerHit`) 와 같은 규약이고 (R50 #2), 셀 안 표는 R48이 평면
                    // 정렬에서 빠져 그 경로 밖에 있으므로 여기서 되풀이한다.
                    if nested.rect.contains(point),
                       let url = nested.wrapperURL
                       ?? HwpDrawnTextLayout.wrapperHyperlinkURL(
                           in: cell.paragraphs,
                           paragraphId: nested.paragraphId,
                           controlIndex: nested.controlIndex
                       )
                    {
                        return .found(url)
                    }
                    if innerOccluded {
                        return .occluded
                    }
                }
                let hit = containerHit(
                    paragraphs: cell.paragraphs,
                    images: cell.images, shapes: cell.shapes, textboxes: cell.textboxes,
                    nestedTables: [], at: point
                )
                if case .miss = hit {
                    // 채움뿐 아니라 **칸막이**도 칠이다 (R55) — 안 채운 셀의 테두리
                    // 선 위를 눌렀는데 아래 블록 링크가 열리면 안 된다
                    if cell.paints(point) {
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
