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
    /// 감싼 링크 조회에 필요한 개체 참조 — 종류가 달라도 (rect, 문단, 서수) 셋만 본다
    private struct WrappedObjectRef {
        let rect: CGRect
        let paragraphId: UInt32
        let controlIndex: Int
        /// 분할이 마커 문단을 떼어간 조각에서도 링크를 유지한다 (R58)
        let wrapperURL: String?
    }

    /// 컨테이너 하나가 담은 개체들 — 각주·표 셀·글상자가 같은 모양이라 방출도
    /// 한 함수(`emitWrappedObjects`)가 셋을 다 처리한다 (R57).
    private struct ContainerObjects {
        var images: [HwpCellImage] = []
        var shapes: [HwpCellShape] = []
        var textboxes: [HwpCellTextbox] = []
        var nestedTables: [HwpNestedTableFrame] = []
    }

    private static func wrappedObjects(_ objects: ContainerObjects) -> [WrappedObjectRef] {
        // 그림은 **보이는 조각**만 링크다 — 절단면 밖은 그려지지 않으므로 저작
        // rect로 내면 안 보이는 자리가 링크로 표시된다 (R57)
        objects.images.map {
            WrappedObjectRef(
                rect: $0.visibleRect, paragraphId: $0.paragraphId,
                controlIndex: $0.controlIndex, wrapperURL: $0.wrapperURL
            )
        } + objects.shapes.map {
            WrappedObjectRef(
                rect: $0.rect, paragraphId: $0.paragraphId,
                controlIndex: $0.controlIndex, wrapperURL: $0.wrapperURL
            )
        } + objects.textboxes.map {
            WrappedObjectRef(
                rect: $0.rect, paragraphId: $0.paragraphId,
                controlIndex: $0.controlIndex, wrapperURL: $0.wrapperURL
            )
        } + objects.nestedTables.map {
            WrappedObjectRef(
                rect: $0.rect, paragraphId: $0.paragraphId,
                controlIndex: $0.controlIndex, wrapperURL: $0.wrapperURL
            )
        }
    }

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
        /// 개체를 감싼 `%hlk` — 링크가 개체가 아니라 부모 문단의 U+FFFC run에
        /// 살고 (R49) 비 treatAsChar 개체의 마커는 폭이 0이라, 스팬 방출이 아무
        /// rect도 못 낸다. 히트는 `wrapperHyperlinkURL`로 **개체에서** 링크를
        /// 여니 방출도 개체 rect로 내야 밑줄과 탭이 같은 자리에 있다 (R56).
        func emitWrapped(
            _ paragraphs: [HwpLaidOutParagraph], _ objects: [WrappedObjectRef], offset: CGPoint
        ) {
            // 절단면 밖으로 완전히 잘린 조각은 그려지지 않으므로 링크도 없다
            let painted = objects.filter { !$0.rect.isEmpty }
            // 조회를 개체마다 하면 O(N²)다 (R63) — 규칙이 같은 색인을 **한 번** 만들어
            // 나눠 쓴다. 분할이 이미 고정한 `wrapperURL`뿐이면 색인도 만들지 않는다.
            let wrapperIndex = painted.contains { $0.wrapperURL == nil }
                ? HwpDrawnTextLayout.wrapperHyperlinkIndex(in: paragraphs)
                : [:]
            for object in painted {
                guard let url = object.wrapperURL ?? wrapperIndex[HwpWrapperLinkKey(
                    paragraphId: object.paragraphId, controlIndex: object.controlIndex
                )] else { continue }
                commands.append(.hyperlink(
                    rect: object.rect.offsetBy(dx: offset.x, dy: offset.y), url: url
                ))
                emitted = true
            }
        }
        /// 컨테이너의 감싼 개체 링크 — **글상자 자식까지 같은 규칙으로** 내려간다
        /// (R57). 컨테이너가 셋 (각주·표 셀·글상자) 이라 호출부마다 손으로 쓰면
        /// 한 곳을 빠뜨린다 — 실제로 각주 안 글상자가 빠져 있었다.
        func emitWrappedObjects(
            _ paragraphs: [HwpLaidOutParagraph], _ objects: ContainerObjects, offset: CGPoint
        ) {
            emitWrapped(paragraphs, Self.wrappedObjects(objects), offset: offset)
            for textbox in objects.textboxes {
                emitWrappedObjects(
                    textbox.textbox.paragraphs,
                    ContainerObjects(
                        images: textbox.textbox.images, shapes: textbox.textbox.shapes
                    ),
                    offset: CGPoint(
                        x: offset.x + textbox.rect.minX, y: offset.y + textbox.rect.minY
                    )
                )
            }
        }
        func emitTable(_ table: HwpTableFrame, origin: CGPoint) {
            for row in table.rows {
                for cell in row.cells {
                    emit(cell.paragraphs, offset: origin)
                    emitWrappedObjects(cell.paragraphs, ContainerObjects(
                        images: cell.images, shapes: cell.shapes,
                        textboxes: cell.textboxes, nestedTables: cell.nestedTables
                    ), offset: origin)
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
            emitWrappedObjects(textbox.paragraphs, ContainerObjects(
                images: textbox.images, shapes: textbox.shapes
            ), offset: block.frame.origin)
        case let .footnote(footnote):
            // 각주 문단 + 각주 안 글상자·표 문단의 문단-레벨 링크 (#94) —
            // 셀 경로 emitTable과 같은 origin 합성.
            Self.footnoteParagraphGroups(footnote, origin: block.frame.origin).forEach(emit)
            emitWrappedObjects(footnote.paragraphs, ContainerObjects(
                images: footnote.images, shapes: footnote.shapes,
                textboxes: footnote.textboxes, nestedTables: footnote.nestedTables
            ), offset: block.frame.origin)
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
                width: textbox.effectiveBorderWidth
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
