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
        // 컨테이너(표/글상자/각주) 문단-레벨 링크(attributed span 없는 %hlk 필드)는
        // walkText 스팬 방출로는 안 잡히고 block.hyperlinkURL도 nil이다. 문단별
        // 폴백 링크가 이들을 paint list에 담아 hit tester의 문단-레벨 처리와
        // 일치한다 (R53 #4).
        if appendContainerParagraphHyperlinks(for: block, to: &commands) {
            emitted = true
        }
        if !emitted, let url = block.hyperlinkURL {
            commands.append(.hyperlink(rect: block.frame, url: url))
        }
    }

    /// 컨테이너 문단의 문단-레벨 hyperlinkURL을 페이지 좌표 rect로 방출한다.
    /// origin 합성은 HwpBlockContentWalker.walkTable과 같은 규칙(셀·셀 글상자·중첩
    /// 표 재귀)이다. 필드 스팬이 있는 문단은 건너뛴다 — 모델 hyperlinkURL은 스팬
    /// 존재와 무관하게 설정되므로 전체-rect 폴백을 겹치면 앞뒤 평문이 링크로
    /// 표시된다 (R55 #2). 하나라도 방출하면 true (R53 #4).
    private func appendContainerParagraphHyperlinks(
        for block: AnyHwpBlock, to commands: inout [HwpPaintCommand]
    ) -> Bool {
        var emitted = false
        func emit(_ paragraphs: [HwpLaidOutParagraph], offset: CGPoint) {
            for paragraph in paragraphs {
                guard let url = paragraph.hyperlinkURL else { continue }
                guard HwpDrawnTextLayout.hyperlinkRegions(
                    attributedString: paragraph.attributedString,
                    origin: paragraph.rect.origin,
                    lineWidth: paragraph.rect.width
                ).isEmpty else { continue }
                commands.append(.hyperlink(
                    rect: paragraph.rect.offsetBy(dx: offset.x, dy: offset.y), url: url
                ))
                emitted = true
            }
        }
        func emitTable(_ table: HwpTableFrame, origin: CGPoint) {
            for row in table.rows {
                for cell in row.cells {
                    emit(cell.paragraphs, offset: origin)
                    for textbox in cell.textboxes {
                        emit(textbox.textbox.paragraphs, offset: CGPoint(
                            x: origin.x + textbox.rect.minX, y: origin.y + textbox.rect.minY
                        ))
                    }
                    for nested in cell.nestedTables {
                        emitTable(nested.table, origin: CGPoint(
                            x: origin.x + nested.rect.minX, y: origin.y + nested.rect.minY
                        ))
                    }
                }
            }
        }
        switch block.payload {
        case let .table(table):
            emitTable(table, origin: block.frame.origin)
        case let .textbox(textbox):
            emit(textbox.paragraphs, offset: block.frame.origin)
        case let .footnote(footnote):
            // 각주 문단 + 각주 안 글상자·표 문단의 문단-레벨 링크 (#94) —
            // 셀 경로 emitTable과 같은 origin 합성.
            Self.footnoteParagraphGroups(footnote, origin: block.frame.origin).forEach(emit)
            for nested in footnote.nestedTables {
                emitTable(nested.table, origin: CGPoint(
                    x: block.frame.minX + nested.rect.minX,
                    y: block.frame.minY + nested.rect.minY
                ))
            }
        default:
            break
        }
        return emitted
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
    func drawTextCommand(
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

    /// 셀·표 테두리의 fillRect 명령 — 기하는 `HwpBorderSet.stripes`가 소유하고
    /// 히트 (`HwpTableCellFrame.paints`) 와 공유한다 (R56).
    func borderCommands(
        _ borders: HwpBorderSet,
        around rect: CGRect
    ) -> [HwpPaintCommand] {
        borders.stripes(around: rect).map {
            .fillRect(rect: $0.rect, color: $0.color.cgColor)
        }
    }

    // MARK: - 글상자

    func textboxCommands(
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
