import CoreGraphics
import Foundation

// MARK: - 자격 영역과 칠 커버리지

/// 히트가 "어디까지 이 블록의 것인가"를 정하는 두 축이다. **정밀도가 다르다**
/// (R54): 자격 영역 (`hitEligibleFrame`/`paintedRects`) 은 실제 칠 영역의
/// **상위집합**이어야 하고 — 좁으면 그 위의 탭이 `containerHit`에 닿기도 전에
/// 기각돼 뒤 로직이 통째로 무용지물이 된다 — claim (`paintsContent`) 은 **정밀
/// 커버리지**여야 한다 (거친 rect로 claim하면 투명한 자리까지 가져가 아래 블록의
/// 보이는 링크를 막는다).
extension HwpHitTester {
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
    func hitEligibleFrame(for block: AnyHwpBlock) -> CGRect {
        switch block.kind {
        case .text:
            let extra = block.frame.width * (HwpRenderTuning.Text.slightOverflowWidthRatio - 1)
            return block.frame.insetBy(dx: -extra, dy: 0)
        default:
            // 컨테이너(각주·표·글상자)는 자손이 프레임을 넘어 그려진다 (R62)
            return paintedRects(for: block).reduce(block.frame) { $0.union($1) }
        }
    }

    /// 블록 frame ∪ **페인트가 실제로 닿는 모든 rect** — 자격 영역 전용.
    ///
    /// 최상위 개체 rect만 모으면 자손 (표 셀·문단, 글상자 안 문단) 이 자기
    /// 컨테이너를 넘어 그려질 때 그 띠가 빠져 보이는 링크가 안 눌린다 (R41 #2).
    /// walker가 페인트와 같은 재귀로 방문하므로 방문 rect를 그대로 합집합한다.
    ///
    /// 자격은 실제 칠 영역의 **상위집합**이어야 한다 — 좁으면 그 위의 탭이
    /// `containerHit`에 닿기도 전에 기각된다 (R53). 반대로 claim을 이 rect로 하면
    /// 투명한 자리까지 가져가 아래 블록의 보이는 링크를 막는다 (R54); claim은
    /// `paintsContent`가 정밀 커버리지로 판정한다.
    ///
    /// **컨테이너 종류를 가리지 않는다** (R62): 표·글상자 블록도 넘친 개체 위에
    /// 링크를 방출하므로 각주와 같은 자격을 받아야 방출된 링크가 눌린다.
    func paintedRects(for block: AnyHwpBlock) -> [CGRect] {
        var rects: [CGRect] = []
        let origin = block.frame.origin
        func addText(_: NSAttributedString, _ rect: CGRect, _: UInt32?) {
            rects.append(Self.textBounds(rect))
        }
        func addCell(_: HwpTableCellFrame, _ rect: CGRect) {
            rects.append(rect)
        }
        /// 테두리 stroke는 rect 밖으로 폭의 절반이 나간다 (R61/R62) — 자격이 그만큼
        /// 넓어야 보이는 선 위의 탭이 `containerHit`에 닿는다
        func addImage(_ image: HwpCellImage, _ rect: CGRect) {
            rects.append(Self.strokeBounds(rect, borderWidth: image.borderWidth))
        }
        /// 도형은 경로가 rect를 넘을 수 있어 `paintedRect` 하나가 칠 영역을 소유한다
        /// (R63) — walker는 페이지 좌표 rect를 주므로 그 차이만큼 옮겨 받는다.
        func addShape(_ shape: HwpCellShape, _ rect: CGRect) {
            rects.append(shape.paintedRect.offsetBy(
                dx: rect.minX - shape.rect.minX, dy: rect.minY - shape.rect.minY
            ))
        }
        func addTextboxChildren(_ textbox: HwpTextboxFrame, offset: CGPoint) {
            HwpBlockContentWalker.walkParagraphs(
                textbox.paragraphs, offset: offset
            ) { _, inner, _ in rects.append(Self.textBounds(inner)) }
            // 글상자 안 그림·도형도 `textboxCommands`가 클립 없이 그린다 — 글상자
            // rect에서 멈추면 넘친 자식 위의 탭이 기각된다 (R46 #1).
            for child in textbox.images.map(\.paintedRect)
                + textbox.shapes.map(\.paintedRect)
            {
                rects.append(child.offsetBy(dx: offset.x, dy: offset.y))
            }
        }
        func addTextbox(_ textbox: HwpCellTextbox, _ rect: CGRect) {
            rects.append(Self.strokeBounds(
                rect, borderWidth: textbox.textbox.effectiveBorderWidth
            ))
            addTextboxChildren(textbox.textbox, offset: rect.origin)
        }
        switch block.payload {
        case let .footnote(footnote):
            HwpBlockContentWalker.walkFootnote(
                footnote,
                origin: origin,
                onParagraphText: addText,
                onCellStart: addCell,
                onCellImage: addImage,
                onCellShape: addShape,
                onCellTextbox: addTextbox
            )
        case let .table(table):
            HwpBlockContentWalker.walkTable(
                table,
                origin: origin,
                onCellStart: addCell,
                onParagraphText: addText,
                onCellImage: addImage,
                onCellShape: addShape,
                onCellTextbox: addTextbox
            )
        case let .textbox(textbox):
            addTextboxChildren(textbox, offset: origin)
        default:
            break
        }
        return rects
    }

    /// 각주가 이 지점에 **실제로 칠했는가** — 자격 영역(bounding box)의 투명한
    /// 틈과 구분한다 (R54). 커버리지의 소유자는 둘뿐이다: 층은
    /// `ContentLayer.paints`, 텍스트는 그려진 줄 상자
    /// (`HwpDrawnTextLayout.textLineRegions` — 선택 하이라이트와 같은 정의).
    func paintsContent(
        _ footnote: HwpFootnoteBlock, origin: CGPoint, at point: CGPoint
    ) -> Bool {
        var painted = false
        func note(_ hit: @autoclosure () -> Bool) {
            guard !painted else { return }
            painted = hit()
        }
        func paintsText(_ attributed: NSAttributedString, in rect: CGRect) -> Bool {
            textPaints(attributed, in: rect, at: point)
        }
        HwpBlockContentWalker.walkFootnote(
            footnote,
            origin: origin,
            onParagraphText: { attributed, rect, _ in note(paintsText(attributed, in: rect)) },
            onCellStart: { cell, rect in
                // 채움 ∪ 칸막이 — 안 채운 셀의 **칸 안**만 아래 블록 몫이다 (R55)
                note(cell.paints(Self.payloadPoint(point, page: rect, payload: cell.cellFrame)))
            },
            onCellImage: { image, rect in
                note(HwpBlockContentWalker.ContentLayer.image(image)
                    .paints(Self.payloadPoint(point, page: rect, payload: image.rect)))
            },
            onCellShape: { shape, rect in
                note(HwpBlockContentWalker.ContentLayer.shape(shape)
                    .paints(Self.payloadPoint(point, page: rect, payload: shape.rect)))
            },
            onCellTextbox: { textbox, rect in
                // 글상자는 `textboxCommands`가 늘 칠한다 (fillColor 없어도 .hwpWhite)
                note(rect.contains(point))
                HwpBlockContentWalker.walkParagraphs(
                    textbox.textbox.paragraphs, offset: rect.origin
                ) { attributed, inner, _ in note(paintsText(attributed, in: inner)) }
                // 글상자를 넘어 그려지는 자식 (R46 #1) 도 같은 규칙으로 본다
                let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
                for image in textbox.textbox.images {
                    note(HwpBlockContentWalker.ContentLayer.image(image).paints(local))
                }
                for shape in textbox.textbox.shapes {
                    note(HwpBlockContentWalker.ContentLayer.shape(shape).paints(local))
                }
            }
        )
        return painted
    }

    /// 문단들이 이 지점에 글자를 칠했는지 — 그려진 줄 상자 기준.
    func paragraphsPaint(
        _ paragraphs: [HwpLaidOutParagraph], at point: CGPoint
    ) -> Bool {
        paragraphs.contains { textPaints($0.attributedString, in: $0.rect, at: point) }
    }

    /// 문단이 이 지점에 글자를 칠했는지 — **rect 밖이면 CT 조판을 하지 않는다**.
    ///
    /// 줄 상자는 문단 rect 안이다 (가로만 slight-overflow 허용치까지 넘으므로
    /// `hitEligibleFrame`의 `.text`와 같은 여유를 준다). 이 게이트가 없으면 탭 한
    /// 번이 셀·문단 수만큼 framesetting을 돌린다 — `tableHit`은 셀 프레임으로
    /// 미리 거르지 않으므로 (R44 #2) 큰 표에서 동기 탭 핸들러가 멈춘다
    /// (R55 실측: 600셀 표 탭당 29.16ms).
    func textPaints(
        _ attributed: NSAttributedString, in rect: CGRect, at point: CGPoint
    ) -> Bool {
        guard Self.textBounds(rect).contains(point) else { return false }
        return HwpDrawnTextLayout.textLineRegions(
            attributedString: attributed, origin: rect.origin, lineWidth: rect.width
        ).contains { $0.contains(point) }
    }

    /// 문단 텍스트가 닿을 수 있는 **안전한 상위집합** — 자격 영역(`paintedRects`)과
    /// claim 게이트(`textPaints`)가 이 하나를 공유해야 "자격 ⊇ 칠"이 구조적으로
    /// 성립한다 (R56). 따로 두면 자격이 좁아 게이트의 여유가 도달 불가능해진다.
    ///
    /// 넘치는 축 둘: slight-overflow 한 줄은 rect 폭을 넘고 (`hitEligibleFrame`의
    /// `.text`와 같은 여유), 캐시 높이가 대체 폰트 CT 줄보다 짧으면 아래로도
    /// 넘는다. 후자는 값싸게 정확히 잴 수 없어 (walker 콜백에 `HwpParagraphFrame`이
    /// 없다) 같은 여유를 세로에도 준다 — 상위집합을 넓히는 것은 과잉 claim이
    /// 아니다. 실제 claim은 줄 상자로 정밀 판정한다.
    /// 테두리 stroke를 포함한 자격 상위집합 — CG가 경로 중앙에 긋는 폭의 절반이
    /// rect 밖이다 (`HwpCellImage.paintedRect`와 같은 규칙, R61).
    static func strokeBounds(_ rect: CGRect, borderWidth: CGFloat) -> CGRect {
        guard borderWidth > 0 else { return rect }
        return rect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)
    }

    static func textBounds(_ rect: CGRect) -> CGRect {
        let extra = rect.width * (HwpRenderTuning.Text.slightOverflowWidthRatio - 1)
        return rect.insetBy(dx: -extra, dy: -extra)
    }
}
