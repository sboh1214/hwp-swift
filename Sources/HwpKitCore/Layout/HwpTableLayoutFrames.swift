import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// MARK: - 행/셀 프레임 조립 (레이아웃 결과 → HwpTableRowFrame/HwpTableCellFrame)

extension HwpTableLayout {
    /// 행 높이 = max(저작된 셀 높이, 콘텐츠 높이). span 셀은 마지막 행에 나머지를 반영.
    /// 셀 문단 전부가 라인 캐시로 측정된 셀은 저작된 높이 (표 80 = 한글 계산값)를
    /// 그대로 신뢰한다 — 캐시 합 + 여백 근사가 저작 높이를 살짝 넘겨 표가
    /// 부풀면 페이지 분할이 한글과 어긋난다 (헌법주석 실측).
    func resolvedRowHeights(
        placed: [PlacedCell],
        rowCount: Int,
        defaultHeight: CGFloat
    ) -> [CGFloat] {
        func needed(_ cell: PlacedCell) -> CGFloat {
            // 저작 셀 높이(UInt32)를 상한한다 — UInt32.max 근처면 ~43M pt가 되어
            // 작은 문서가 페이지 단위 절단으로 수만 페이지를 만든다 (#6).
            // 실제 셀은 이 한도를 한참 밑돌아 렌더 불변.
            let raw = cell.hasCachedContent && cell.authoredHeight > 0
                ? cell.authoredHeight
                : max(cell.contentHeight, cell.authoredHeight)
            return min(raw, HwpTableLayout.maximumCellHeight)
        }
        var heights = [CGFloat](repeating: 0, count: rowCount)
        for cell in placed where cell.rowSpan == 1 {
            heights[cell.row] = max(heights[cell.row], needed(cell))
        }
        for cell in placed where cell.rowSpan > 1 {
            let spanEnd = min(cell.row + cell.rowSpan, rowCount)
            let current = heights[cell.row ..< spanEnd].reduce(CGFloat(0), +)
            if needed(cell) > current {
                heights[spanEnd - 1] += needed(cell) - current
            }
        }
        return heights.map { $0 > 0 ? $0 : defaultHeight }
    }

    func rows(
        placed: [PlacedCell],
        rowHeights: [CGFloat],
        columnWidths: [CGFloat],
        context: LayoutContext
    ) -> [HwpTableRowFrame] {
        var result: [HwpTableRowFrame] = []
        result.reserveCapacity(rowHeights.count)
        var rowOrigins: [CGFloat] = []
        var yOffset = context.metrics.spacing
        for height in rowHeights {
            rowOrigins.append(yOffset)
            yOffset += height + context.metrics.spacing
        }

        let rowWidth = columnWidths.reduce(CGFloat(0), +)
            + context.metrics.spacing * CGFloat(columnWidths.count + 1)

        // 열 원점 prefix 합을 한 번만 계산한다 — 셀마다 prefix reduce를 다시
        // 돌면 열 수의 제곱이 된다 (#9). columnOrigins[c] = xOffset(c)와 동일.
        var columnOrigins: [CGFloat] = []
        columnOrigins.reserveCapacity(columnWidths.count)
        var columnX = context.metrics.spacing
        for width in columnWidths {
            columnOrigins.append(columnX)
            columnX += width + context.metrics.spacing
        }

        // 셀을 시작 행으로 한 번만 버킷한다 — 행마다 전체 placed를 filter하면
        // 행 수 × 셀 수가 된다 (#3).
        var cellsByRow = [[PlacedCell]](repeating: [], count: rowHeights.count)
        for cell in placed where cell.row >= 0 && cell.row < rowHeights.count {
            cellsByRow[cell.row].append(cell)
        }

        for row in rowHeights.indices {
            let cells = cellsByRow[row]
                .sorted { $0.column < $1.column }
                .map { cell in
                    cellFrame(
                        for: cell,
                        rowOrigins: rowOrigins,
                        rowHeights: rowHeights,
                        columnWidths: columnWidths,
                        columnOrigins: columnOrigins,
                        context: context
                    )
                }
            result.append(HwpTableRowFrame(
                rowFrame: CGRect(
                    x: 0,
                    y: rowOrigins[row],
                    width: rowWidth,
                    height: rowHeights[row]
                ),
                cells: cells
            ))
        }
        return result
    }

    func cellFrame(
        for cell: PlacedCell,
        rowOrigins: [CGFloat],
        rowHeights: [CGFloat],
        columnWidths: [CGFloat],
        columnOrigins: [CGFloat],
        context: LayoutContext
    ) -> HwpTableCellFrame {
        let metrics = context.metrics
        let cellRect = CGRect(
            x: columnOrigins.indices.contains(cell.column)
                ? columnOrigins[cell.column]
                : xOffset(for: cell.column, columnWidths: columnWidths, spacing: metrics.spacing),
            y: rowOrigins[cell.row],
            width: width(
                from: cell.column,
                span: cell.columnSpan,
                columnWidths: columnWidths,
                spacing: metrics.spacing
            ),
            height: height(
                from: cell.row,
                span: cell.rowSpan,
                rowHeights: rowHeights,
                spacing: metrics.spacing
            )
        )
        let margins = cellMargins(for: cell.cell, metrics: metrics)
        var laidOut = laidOutContents(
            for: cell,
            in: cellRect,
            margins: margins,
            index: context.index
        )
        laidOut = verticallyAligned(laidOut, cell: cell.cell, cellRect: cellRect, margins: margins)

        let resolved = resolvedBorderFill(
            id: cell.cell.header.cellProperty?.borderFillId
                ?? context.table.tableProperty.borderFillId,
            index: context.index
        )
        return HwpTableCellFrame(
            cellFrame: cellRect,
            row: cell.row,
            column: cell.column,
            rowSpan: cell.rowSpan,
            columnSpan: cell.columnSpan,
            paragraphs: laidOut.paragraphs,
            borders: borders(from: resolved),
            fillColor: fillColor(from: resolved),
            nestedTables: laidOut.nestedTables,
            images: laidOut.images
        )
    }

    /// laidOutContents 결과 묶음
    struct LaidOutCellContents {
        let paragraphs: [HwpLaidOutParagraph]
        let nestedTables: [HwpNestedTableFrame]
        let images: [HwpCellImage]
    }

    /// 셀 세로 정렬 (표 89 리스트 헤더 속성): 콘텐츠가 셀보다 작으면
    /// 가운데/아래 정렬만큼 내린다 (noori 제목 셀 실물: 위·아래 여백 균등).
    func verticallyAligned(
        _ contents: LaidOutCellContents,
        cell: CoreHwp.HwpTableCell,
        cellRect: CGRect,
        margins: CellMargins
    ) -> LaidOutCellContents {
        let alignment = cell.header.propertyInfo.verticalAlignment ?? .top
        guard alignment != .top else { return contents }
        // 콘텐츠 하단은 문단뿐 아니라 중첩 표·이미지 자식의 extent도 포함해야
        // 한다 — 문단만 보면 slack이 과대돼 자식이 셀 하단을 넘긴다 (#7).
        let bottom = (contents.paragraphs.map(\.rect.maxY)
            + contents.nestedTables.map(\.rect.maxY)
            + contents.images.map(\.rect.maxY))
            .max() ?? (cellRect.minY + margins.top)
        let slack = cellRect.maxY - margins.bottom - bottom
        guard slack > 0.5 else { return contents }
        let offset = alignment == .center ? slack / 2 : slack
        return LaidOutCellContents(
            paragraphs: contents.paragraphs.map {
                HwpLaidOutParagraph(
                    attributedString: $0.attributedString,
                    frame: $0.frame,
                    rect: $0.rect.offsetBy(dx: 0, dy: offset),
                    paragraphId: $0.paragraphId,
                    hyperlinkURL: $0.hyperlinkURL
                )
            },
            nestedTables: contents.nestedTables.map {
                HwpNestedTableFrame(
                    rect: $0.rect.offsetBy(dx: 0, dy: offset),
                    table: $0.table,
                    controlInstanceId: $0.controlInstanceId
                )
            },
            images: contents.images.map {
                HwpCellImage(
                    rect: $0.rect.offsetBy(dx: 0, dy: offset),
                    binItemId: $0.binItemId,
                    style: $0.style,
                    controlInstanceId: $0.controlInstanceId
                )
            }
        )
    }

    /// 셀 안 문단과 중첩 표를 셀 여백 안쪽에 위에서 아래로 쌓는다.
    /// 셀 문단의 그림 컨트롤은 문단 rect 위치에 셀 이미지로 배치한다
    /// (한글: 셀 안 개체는 셀 콘텐츠 — 페이지 흐름을 소비하지 않는다).
    func laidOutContents(
        for cell: PlacedCell,
        in cellRect: CGRect,
        margins: CellMargins,
        index: HwpIndex
    ) -> LaidOutCellContents {
        let textBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        var cursorY = cellRect.minY + margins.top
        let innerX = cellRect.minX + margins.left
        let innerWidth = max(1, cellRect.width - margins.left - margins.right)
        var paragraphs: [HwpLaidOutParagraph] = []
        var nestedTables: [HwpNestedTableFrame] = []
        var images: [HwpCellImage] = []
        for content in cell.contents {
            // 문단 위 간격 (프레임 높이에 포함됨)만큼 텍스트 상단을 내린다
            let spacingBefore = HwpUnits.points(
                fromHwpUnit: index.paraShape(
                    id: UInt32(content.paragraph.paraHeader.paraShapeId)
                )?.paragraphSpacingTop ?? 0
            ) / 2
            let rect = CGRect(
                x: innerX,
                y: cursorY + spacingBefore,
                width: innerWidth,
                height: content.frame.totalHeight - spacingBefore
            )
            paragraphs.append(HwpLaidOutParagraph(
                attributedString: textBuilder.build(paragraph: content.paragraph),
                frame: content.frame,
                rect: rect,
                paragraphId: content.paragraph.paraHeader.paraId,
                hyperlinkURL: content.paragraph.hyperlinkURL
            ))
            images.append(contentsOf: cellImages(in: content.paragraph, paragraphRect: rect))
            cursorY += content.frame.totalHeight
            for nested in content.nestedTables {
                nestedTables.append(HwpNestedTableFrame(
                    rect: CGRect(
                        x: innerX,
                        y: cursorY,
                        width: nested.frame.outerFrame.width,
                        height: nested.frame.outerFrame.height
                    ),
                    table: nested.frame,
                    controlInstanceId: nested.instanceId
                ))
                cursorY += nested.frame.outerFrame.height
            }
        }
        return LaidOutCellContents(
            paragraphs: paragraphs,
            nestedTables: nestedTables,
            images: images
        )
    }

    /// 셀 문단에 붙은 그림 컨트롤 (gso/그림)을 문단 rect 안에 왼쪽부터 배치한다.
    private func cellImages(
        in paragraph: CoreHwp.HwpParagraph,
        paragraphRect: CGRect
    ) -> [HwpCellImage] {
        var images: [HwpCellImage] = []
        var cursorX = paragraphRect.minX
        for ctrl in paragraph.ctrlHeaderArray ?? [] {
            let commonProperty: CoreHwp.HwpCommonCtrlProperty?
            let components: [CoreHwp.HwpShapeComponent]
            switch ctrl {
            case let .genShapeObject(genShape):
                commonProperty = genShape.commonCtrlProperty
                components = genShape.shapeComponentArray
            case let .picture(shape):
                commonProperty = shape.commonCtrlProperty
                components = shape.shapeComponentArray
            default:
                continue
            }
            for component in components {
                for picture in component.pictureArray {
                    guard let image = cellImage(
                        picture: picture,
                        component: component,
                        commonProperty: commonProperty,
                        paragraphRect: paragraphRect,
                        cursorX: cursorX
                    ) else { continue }
                    images.append(image)
                    cursorX += image.rect.width
                }
            }
        }
        return images
    }

    /// 그림 컴포넌트 하나 → 셀 이미지 (크기/BinData 참조가 없으면 nil)
    private func cellImage(
        picture: CoreHwp.HwpShapeComponentPicture,
        component: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        paragraphRect: CGRect,
        cursorX: CGFloat
    ) -> HwpCellImage? {
        let property = picture.pictureProperty
        guard let binItemId = property.map({ UInt32($0.binItemId) })
            ?? picture.binaryDataId.map(UInt32.init)
        else { return nil }
        var width = HwpUnits.points(fromHwpUnitU: commonProperty?.width ?? 0)
        var height = HwpUnits.points(fromHwpUnitU: commonProperty?.height ?? 0)
        if width <= 0 || height <= 0, let detail = component.detail {
            if width <= 0 {
                width = HwpUnits.points(fromHwpUnitU: detail.currentWidth)
            }
            if height <= 0 {
                height = HwpUnits.points(fromHwpUnitU: detail.currentHeight)
            }
        }
        guard width > 0, height > 0 else { return nil }
        width = min(width, max(1, paragraphRect.maxX - cursorX))
        return HwpCellImage(
            rect: CGRect(
                x: cursorX,
                y: paragraphRect.minY,
                width: width,
                height: height
            ),
            binItemId: binItemId,
            style: property.map { HwpImageRenderStyle(pictureProperty: $0) },
            controlInstanceId: commonProperty?.instanceId ?? 0
        )
    }

    func width(from column: Int, span: Int, columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let last = min(column + span, columnWidths.count)
        let widths = columnWidths[column ..< last].reduce(CGFloat(0), +)
        return widths + spacing * CGFloat(max(0, span - 1))
    }

    func xOffset(for column: Int, columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        spacing + columnWidths.prefix(column).reduce(CGFloat(0), +) + spacing * CGFloat(column)
    }

    func height(from row: Int, span: Int, rowHeights: [CGFloat], spacing: CGFloat) -> CGFloat {
        let last = min(row + span, rowHeights.count)
        let heights = rowHeights[row ..< last].reduce(CGFloat(0), +)
        return heights + spacing * CGFloat(max(0, span - 1))
    }
}
