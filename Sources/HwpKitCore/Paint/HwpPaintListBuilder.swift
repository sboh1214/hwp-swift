@preconcurrency import CoreGraphics
import CoreHwp
import CoreText
import Foundation

public struct HwpPaintListBuilder: Sendable {
    private let fontResolver: HwpFontResolver
    private let imageStore: HwpImageStore

    public init(
        fontResolver: HwpFontResolver = HwpFontResolver(),
        imageStore: HwpImageStore = HwpImageStore()
    ) {
        self.fontResolver = fontResolver
        self.imageStore = imageStore
    }

    public func build(for page: HwpPage, index _: HwpIndex) -> HwpPaintList {
        var commands: [HwpPaintCommand] = []
        // 같은 구분선을 공유하는 각주 블록들에서 한 번만 그린다.
        // (미주 블록은 자기 위치의 구분선을 따로 가진다.)
        var drawnSeparators: [CGRect] = []
        for (_, block) in AnyHwpBlock.paintOrdered(page.blocks) {
            if case let .footnote(footnote) = block.payload {
                let separator = footnote.separatorLine
                let drawSeparator = separator.width > 0 && !drawnSeparators.contains(separator)
                commands.append(contentsOf: footnoteCommands(
                    footnote,
                    blockFrame: block.frame,
                    drawSeparator: drawSeparator
                ))
                if drawSeparator {
                    drawnSeparators.append(separator)
                }
            } else {
                commands.append(contentsOf: paintCommands(for: block))
            }
            appendHyperlinkCommands(for: block, to: &commands)
        }
        return HwpPaintList(commands: commands)
    }

    /// 하이퍼링크(%hlk)를 필드 스팬 글리프 rect로 스코프해 방출한다 — 링크
    /// 텍스트에만 히트/오버레이가 걸리고, 앞뒤 평문이나 다중 링크가 첫 URL로
    /// 뭉개지지 않는다 (#2). 필드 속성이 없는 블록(직접 설정·컨테이너 폴백)만
    /// 블록 프레임으로 방출한다.
    private func appendHyperlinkCommands(
        for block: AnyHwpBlock,
        to commands: inout [HwpPaintCommand]
    ) {
        var emitted = false
        HwpBlockContentWalker.walkText(block: block) { attributed, rect, _ in
            for region in HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: attributed, origin: rect.origin, lineWidth: rect.width
            ) {
                commands.append(.hyperlink(rect: region.rect, url: region.url))
                emitted = true
            }
        }
        if !emitted, let url = block.hyperlinkURL {
            commands.append(.hyperlink(rect: block.frame, url: url))
        }
    }

    private func paintCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        switch block.payload {
        case let .table(tableFrame):
            tableCommands(tableFrame, origin: block.frame.origin)
        case let .textbox(textboxFrame):
            textboxCommands(textboxFrame, origin: block.frame.origin)
        case let .footnote(footnoteBlock):
            footnoteCommands(footnoteBlock, blockFrame: block.frame, drawSeparator: true)
        case let .shape(geometry):
            shapeCommands(geometry, origin: block.frame.origin)
        case let .image(imageInfo):
            imageCommands(imageInfo, frame: block.frame)
        case let .chart(chart):
            HwpChartPainter.commands(chart, frame: block.frame, fontResolver: fontResolver)
        case nil:
            plainCommands(for: block)
        }
    }

    private func plainCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        let frame = block.frame
        switch block.kind {
        case .text, .table, .textbox, .footnote:
            var commands: [HwpPaintCommand] = []
            HwpBlockContentWalker.walkText(block: block) { attributed, rect, _ in
                commands.append(drawTextCommand(attributed, in: rect))
            }
            return commands
        case .image:
            return [.drawPlaceholder(rect: frame, text: "[이미지]")]
        case .shape:
            return [.drawPath(
                path: CGPath(rect: frame, transform: nil),
                fill: nil,
                stroke: .hwpBlack,
                strokeWidth: 1
            )]
        case .placeholder:
            return [.drawPlaceholder(
                rect: frame,
                text: block.attributedString?.string ?? "[placeholder]"
            )]
        }
    }

    /// (attributed, 페이지 좌표 rect) → drawText — `HwpBlockContentWalker`가
    /// 방문한 텍스트를 명령으로 바꾸는 단일 지점.
    private func drawTextCommand(
        _ attributed: NSAttributedString,
        in rect: CGRect
    ) -> HwpPaintCommand {
        .drawText(
            attributedString: attributed,
            origin: rect.origin,
            lineWidth: max(rect.width, 1)
        )
    }

    // MARK: - 표

    private func tableCommands(
        _ table: HwpTableFrame,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        // 방출 순서 (셀마다 fill → border → 문단 텍스트 → 셀 그림 → 중첩 표
        // 재귀)는 walker의 이벤트 순서가 정의한다.
        var commands: [HwpPaintCommand] = []
        HwpBlockContentWalker.walkTable(
            table,
            origin: origin,
            onCellStart: { cell, cellRect in
                if let fill = cell.fillColor {
                    commands.append(.fillRect(rect: cellRect, color: fill.cgColor))
                }
                commands.append(contentsOf: borderCommands(cell.borders, around: cellRect))
            },
            onParagraphText: { attributed, rect, _ in
                commands.append(drawTextCommand(attributed, in: rect))
            },
            onCellImage: { image, rect in
                commands.append(contentsOf: cellImageCommands(image, rect: rect))
            },
            onCellShape: { shape, rect in
                commands.append(contentsOf: shapeCommands(shape.geometry, origin: rect.origin))
            },
            onCellTextbox: { textbox, rect in
                commands.append(contentsOf: textboxCommands(textbox.textbox, origin: rect.origin))
            }
        )
        return commands
    }

    private func borderCommands(
        _ borders: HwpBorderSet,
        around rect: CGRect
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        func edge(
            _ width: CGFloat,
            _ color: HwpRGBColor,
            _ edgeRect: CGRect,
            isDouble: Bool,
            horizontal: Bool
        ) {
            guard width > 0 else { return }
            guard isDouble else {
                commands.append(.fillRect(rect: edgeRect, color: color.cgColor))
                return
            }
            // 이중선 (표 25 종류 8-10): 가는 선 2개 + 사이 간격
            // (noori 제목 상자 실물 — 1px 두 줄)
            let thin = max(0.4, width * 0.4)
            let gap = max(thin, width)
            var first = edgeRect
            var second = edgeRect
            if horizontal {
                first.size.height = thin
                second.origin.y = edgeRect.minY + thin + gap
                second.size.height = thin
            } else {
                first.size.width = thin
                second.origin.x = edgeRect.minX + thin + gap
                second.size.width = thin
            }
            commands.append(.fillRect(rect: first, color: color.cgColor))
            commands.append(.fillRect(rect: second, color: color.cgColor))
        }
        edge(borders.top, borders.topColor, CGRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: borders.top
        ), isDouble: borders.topDouble, horizontal: true)
        edge(borders.bottom, borders.bottomColor, CGRect(
            x: rect.minX, y: rect.maxY - borders.bottom, width: rect.width, height: borders.bottom
        ), isDouble: borders.bottomDouble, horizontal: true)
        edge(borders.left, borders.leftColor, CGRect(
            x: rect.minX, y: rect.minY, width: borders.left, height: rect.height
        ), isDouble: borders.leftDouble, horizontal: false)
        edge(borders.right, borders.rightColor, CGRect(
            x: rect.maxX - borders.right, y: rect.minY, width: borders.right, height: rect.height
        ), isDouble: borders.rightDouble, horizontal: false)
        return commands
    }

    // MARK: - 글상자

    private func textboxCommands(
        _ textbox: HwpTextboxFrame,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        let outerRect = textbox.outerFrame.offsetBy(dx: origin.x, dy: origin.y)
        if let fill = textbox.fillColor {
            commands.append(.fillRect(rect: outerRect, color: fill.cgColor))
        } else {
            commands.append(.fillRect(rect: outerRect, color: .hwpWhite))
        }
        // 테두리 정보가 없으면 그리지 않는다 (한글.app: CCL 실측 — 선 없는
        // 글상자는 테두리 없이 렌더)
        if let borderColor = textbox.borderColor, textbox.borderWidth > 0 {
            // 한글은 0.33pt 헤어라인도 최소 1px 실선으로 그린다 (text-box 실물)
            commands.append(.strokeRect(
                rect: outerRect,
                color: borderColor.cgColor,
                width: max(0.7, textbox.borderWidth)
            ))
        }
        // 글상자 안 개체 (그림/도형)는 글상자 콘텐츠로 그린다 (R29 #1).
        // 글 뒤로 개체는 텍스트보다 먼저 — 각 평면 안은 zOrder 정렬 (R30 #2).
        let objects = textboxObjectCommands(textbox, origin: origin)
        for object in objects where object.behind {
            commands.append(contentsOf: object.commands)
        }
        HwpBlockContentWalker.walkParagraphs(
            textbox.paragraphs,
            offset: origin
        ) { attributed, rect, _ in
            commands.append(drawTextCommand(attributed, in: rect))
        }
        for object in objects where !object.behind {
            commands.append(contentsOf: object.commands)
        }
        return commands
    }

    // MARK: - 각주

    private func footnoteCommands(
        _ footnote: HwpFootnoteBlock,
        blockFrame: CGRect,
        drawSeparator: Bool
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        // 구분선은 페이지의 첫 번째 각주 블록에서 한 번만 그린다.
        if drawSeparator {
            commands.append(.fillRect(
                rect: footnote.separatorLine,
                color: footnote.separatorColor.cgColor
            ))
        }
        HwpBlockContentWalker.walkParagraphs(
            footnote.paragraphs,
            offset: blockFrame.origin
        ) { attributed, rect, _ in
            commands.append(drawTextCommand(attributed, in: rect))
        }
        return commands
    }

    // MARK: - 도형

    func shapeCommands(
        _ geometry: HwpShapeGeometry,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        var transform = CGAffineTransform(translationX: origin.x, y: origin.y)
        let translated = geometry.path.copy(using: &transform) ?? geometry.path
        return [.drawPath(
            path: translated,
            fill: geometry.fillColor,
            stroke: geometry.strokeColor,
            strokeWidth: geometry.strokeWidth
        )]
    }

    // MARK: - 이미지

    private func imageCommands(
        _ image: HwpImageBlockInfo,
        frame: CGRect
    ) -> [HwpPaintCommand] {
        guard imageStore.data(forBinItemId: image.binItemId) != nil else {
            return [.drawPlaceholder(rect: frame, text: "[이미지]")]
        }
        var commands: [HwpPaintCommand] = [
            .drawImageReference(binItemId: image.binItemId, rect: frame, style: image.style),
        ]
        if let borderColor = image.borderColor, image.borderWidth > 0 {
            commands.append(.strokeRect(
                rect: frame,
                color: borderColor.cgColor,
                width: image.borderWidth
            ))
        }
        return commands
    }
}
