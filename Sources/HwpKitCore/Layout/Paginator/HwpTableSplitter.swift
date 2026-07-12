import CoreGraphics
import CoreHwp
import Foundation

/// 표 페이지 분할 — row 세그먼트 채우기·row/셀/문단 절단·행 이동의
/// 순수 기하 변환. HwpPaginator에서 추출 (동작 불변).
/// 상태가 없는 순수 enum: 분할 플랜 (세그먼트 row 목록·세그먼트 표 프레임)만
/// 산출하고, 페이지 확정·블록 방출은 paginator 루프가 담당한다.
enum HwpTableSplitter {
    // MARK: 세그먼트 채우기 (플랜 산출)

    /// 표 76 bit 2 (제목 줄 자동 반복): 첫 행부터 연속으로 모든 셀이
    /// 제목 셀 (표 79 bit 2)인 행 수.
    static func repeatingHeaderRowCount(of table: CoreHwp.HwpTable) -> Int {
        guard table.tableProperty.repeatsHeaderRow else { return 0 }
        var rowIsHeader: [Int: Bool] = [:]
        for cell in table.cellArray {
            guard let property = cell.header.cellProperty else { continue }
            let row = Int(property.rowAddress)
            rowIsHeader[row] = (rowIsHeader[row] ?? true) && cell.header.isHeader
        }
        var count = 0
        while rowIsHeader[count] == true {
            count += 1
        }
        return count
    }

    /// remaining 높이에 들어가는 만큼 row를 세그먼트로 옮긴다.
    /// 첫 row가 remaining보다 크면 잘라서 위 조각만 넣고 아래 조각을 이월한다.
    static func fillSegment(
        remainingRows: inout [HwpTableRowFrame],
        remaining: CGFloat
    ) -> [HwpTableRowFrame] {
        var segmentRows: [HwpTableRowFrame] = []
        var segmentHeight: CGFloat = 0
        while let row = remainingRows.first {
            // 세그먼트 높이는 row 사이 cellSpacing까지 포함해
            // (첫 row 상단 ~ 이 row 하단) 실제 블록 높이로 판정한다.
            let segmentStartY = segmentRows.first?.rowFrame.minY ?? row.rowFrame.minY
            let prospectiveHeight = row.rowFrame.maxY - segmentStartY
            if segmentHeight > 0, prospectiveHeight > remaining {
                break
            }
            if segmentHeight == 0, row.rowFrame.height > remaining {
                // 빈 페이지보다 큰 row: 남은 높이에서 잘라 나머지를 이월한다.
                let fragments = sliced(
                    row: row,
                    at: row.rowFrame.minY + max(1, remaining)
                )
                segmentRows.append(fragments.top)
                remainingRows[0] = fragments.bottom
                break
            }
            segmentRows.append(row)
            segmentHeight = prospectiveHeight
            remainingRows.removeFirst()
            if segmentHeight >= remaining {
                break
            }
        }
        return segmentRows
    }

    static func minimumRowHeight(_ rows: [HwpTableRowFrame]) -> CGFloat {
        rows.first?.rowFrame.height ?? 1
    }

    // MARK: 세그먼트 표 프레임

    /// 세그먼트 row들을 표-로컬 원점으로 올려 붙인 표 프레임을 만든다.
    /// repeatedHeaderRows가 있으면 (표 76 bit 2 제목 줄 반복) 세그먼트 위에
    /// 제목 행 사본을 얹은 뒤 본문 행을 그 아래로 이어 붙인다. rows가 비면 nil.
    static func segmentFrame(
        rows: [HwpTableRowFrame],
        original: HwpTableFrame,
        repeatedHeaderRows: [HwpTableRowFrame]
    ) -> HwpTableFrame? {
        guard let firstRow = rows.first else { return nil }
        var shiftedRows: [HwpTableRowFrame] = []
        var headerHeight: CGFloat = 0
        if let headerFirst = repeatedHeaderRows.first {
            let headerShift = headerFirst.rowFrame.minY
            let shiftedHeader = repeatedHeaderRows.map { shifted(row: $0, deltaY: -headerShift) }
            headerHeight = shiftedHeader.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
            shiftedRows.append(contentsOf: shiftedHeader)
        }
        let yShift = firstRow.rowFrame.minY - headerHeight
        shiftedRows.append(contentsOf: rows.map { shifted(row: $0, deltaY: -yShift) })
        let segmentHeight = shiftedRows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
        return HwpTableFrame(
            outerFrame: CGRect(
                x: 0,
                y: 0,
                width: original.outerFrame.width,
                height: segmentHeight
            ),
            rows: shiftedRows,
            borderColor: original.borderColor,
            borderWidth: original.borderWidth
        )
    }

    /// 행/셀/문단 지오메트리를 deltaY만큼 이동한 사본을 만든다.
    private static func shifted(row: HwpTableRowFrame, deltaY: CGFloat) -> HwpTableRowFrame {
        HwpTableRowFrame(
            rowFrame: row.rowFrame.offsetBy(dx: 0, dy: deltaY),
            cells: row.cells.map { cell in
                HwpTableCellFrame(
                    cellFrame: cell.cellFrame.offsetBy(dx: 0, dy: deltaY),
                    row: cell.row,
                    column: cell.column,
                    rowSpan: cell.rowSpan,
                    columnSpan: cell.columnSpan,
                    paragraphs: cell.paragraphs.map { paragraph in
                        HwpLaidOutParagraph(
                            attributedString: paragraph.attributedString,
                            frame: paragraph.frame,
                            rect: paragraph.rect.offsetBy(dx: 0, dy: deltaY),
                            paragraphId: paragraph.paragraphId
                        )
                    },
                    borders: cell.borders,
                    fillColor: cell.fillColor,
                    nestedTables: cell.nestedTables.map { nested in
                        HwpNestedTableFrame(
                            rect: nested.rect.offsetBy(dx: 0, dy: deltaY),
                            table: nested.table,
                            controlInstanceId: nested.controlInstanceId
                        )
                    },
                    images: cell.images.map { image in
                        HwpCellImage(
                            rect: image.rect.offsetBy(dx: 0, dy: deltaY),
                            binItemId: image.binItemId,
                            style: image.style,
                            controlInstanceId: image.controlInstanceId
                        )
                    }
                )
            }
        )
    }

    // MARK: row/셀/문단 절단

    /// rect를 y = cutY에서 위/아래로 나눈다 (표-로컬 좌표).
    private static func splitRect(
        _ rect: CGRect,
        at cutY: CGFloat
    ) -> (top: CGRect, bottom: CGRect) {
        let topHeight = max(0, min(rect.height, cutY - rect.minY))
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        let bottom = CGRect(
            x: rect.minX,
            y: rect.minY + topHeight,
            width: rect.width,
            height: max(0, rect.height - topHeight)
        )
        return (top, bottom)
    }

    /// row를 표-로컬 y ≈ cutY에서 위/아래 조각으로 나눈다.
    /// 절단선은 경계에 걸친 문단들의 라인 경계로 내려 정렬해, 이월 문단이
    /// 조각 상단 위로 삐져나오거나 분할마다 오프셋이 누적되지 않게 한다.
    /// 경계에 걸친 문단은 라인 단위로 분할해 이월하고, 중첩 표는 시작 y 기준으로
    /// 한 조각에 남는다.
    private static func sliced(
        row: HwpTableRowFrame,
        at cutY: CGFloat
    ) -> (top: HwpTableRowFrame, bottom: HwpTableRowFrame) {
        let alignedCut = lineAlignedCut(for: row, proposed: cutY)
        let rowFrames = splitRect(row.rowFrame, at: alignedCut)
        let cellFragments = row.cells.map { splitCell($0, at: alignedCut) }
        return (
            HwpTableRowFrame(rowFrame: rowFrames.top, cells: cellFragments.map(\.0)),
            HwpTableRowFrame(rowFrame: rowFrames.bottom, cells: cellFragments.map(\.1))
        )
    }

    /// 절단선을 경계에 걸친 (분할 가능한) 문단들의 라인 경계 이하로 내린다.
    /// 진행을 보장할 수 없으면 (첫 라인도 안 들어가는 경우) 원래 값을 유지한다.
    private static func lineAlignedCut(
        for row: HwpTableRowFrame,
        proposed cutY: CGFloat
    ) -> CGFloat {
        var aligned = cutY
        var changed = true
        var iterations = 0
        while changed, iterations < 4 {
            changed = false
            iterations += 1
            for cell in row.cells {
                for paragraph in cell.paragraphs {
                    let rect = paragraph.rect
                    let lineCount = paragraph.frame.lines.count
                    guard rect.minY < aligned - 0.5, rect.maxY > aligned + 0.5,
                          lineCount > 1, rect.height > 0
                    else { continue }
                    let lineHeight = rect.height / CGFloat(lineCount)
                    guard lineHeight > 0 else { continue }
                    let fittingLines = (aligned - rect.minY) / lineHeight
                    let boundary = rect.minY + fittingLines.rounded(.down) * lineHeight
                    if boundary < aligned - 0.5 {
                        aligned = boundary
                        changed = true
                    }
                }
            }
        }
        // 첫 라인조차 안 들어가면 정렬을 포기하고 원래 절단선으로 진행을 보장한다.
        return aligned > row.rowFrame.minY + 1 ? aligned : cutY
    }

    private static func splitCell(
        _ cell: HwpTableCellFrame,
        at cutY: CGFloat
    ) -> (HwpTableCellFrame, HwpTableCellFrame) {
        let frames = splitRect(cell.cellFrame, at: cutY)
        var topParagraphs: [HwpLaidOutParagraph] = []
        var bottomParagraphs: [HwpLaidOutParagraph] = []
        for paragraph in cell.paragraphs {
            if paragraph.rect.maxY <= cutY + 0.5 {
                topParagraphs.append(paragraph)
            } else if paragraph.rect.minY >= cutY - 0.5 {
                bottomParagraphs.append(paragraph)
            } else {
                let fragments = slicedParagraph(paragraph, at: cutY)
                if let top = fragments.top {
                    topParagraphs.append(top)
                }
                if let bottom = fragments.bottom {
                    bottomParagraphs.append(bottom)
                }
            }
        }
        let topNested = cell.nestedTables.filter { $0.rect.minY < cutY }
        let bottomNested = cell.nestedTables.filter { $0.rect.minY >= cutY }
        func fragment(
            _ frame: CGRect,
            _ paragraphs: [HwpLaidOutParagraph],
            _ nested: [HwpNestedTableFrame]
        ) -> HwpTableCellFrame {
            HwpTableCellFrame(
                cellFrame: frame,
                row: cell.row,
                column: cell.column,
                rowSpan: cell.rowSpan,
                columnSpan: cell.columnSpan,
                paragraphs: paragraphs,
                borders: cell.borders,
                fillColor: cell.fillColor,
                nestedTables: nested
            )
        }
        return (
            fragment(frames.top, topParagraphs, topNested),
            fragment(frames.bottom, bottomParagraphs, bottomNested)
        )
    }

    /// 조각 경계에 걸친 셀 문단을 라인 단위로 위/아래 조각으로 나눠
    /// 텍스트가 다음 페이지로 실제로 이월되게 한다.
    /// 라인 정보가 없으면 통째로 위 조각에 남긴다.
    private static func slicedParagraph(
        _ paragraph: HwpLaidOutParagraph,
        at cutY: CGFloat
    ) -> (top: HwpLaidOutParagraph?, bottom: HwpLaidOutParagraph?) {
        let lines = paragraph.frame.lines
        let rect = paragraph.rect
        guard lines.count > 1, rect.height > 0 else { return (paragraph, nil) }
        let lineHeight = rect.height / CGFloat(lines.count)
        guard lineHeight > 0 else { return (paragraph, nil) }

        let topCount = min(
            max(Int((cutY - rect.minY) / lineHeight), 0),
            lines.count
        )
        if topCount == 0 {
            return (nil, paragraph)
        }
        if topCount == lines.count {
            return (paragraph, nil)
        }

        let topHeight = lineHeight * CGFloat(topCount)
        let top = paragraphFragment(
            of: paragraph,
            lines: lines[..<topCount],
            rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        )
        let bottom = paragraphFragment(
            of: paragraph,
            lines: lines[topCount...],
            rect: CGRect(
                x: rect.minX,
                y: rect.minY + topHeight,
                width: rect.width,
                height: rect.height - topHeight
            )
        )
        return (top, bottom)
    }

    /// 문단이 다음 단/쪽으로 이어지는 조각의 마지막 문자에 마커를 단다 —
    /// 렌더러의 양쪽 정렬이 조각 끝 줄을 문단 마지막 줄로 오인하지 않도록
    /// (Column 실물: 단 경계 직전 줄도 양쪽 정렬로 늘어난다)
    static func markedAsContinuedFragment(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(
            HwpAttributedStringKey.continuedParagraphFragment,
            value: NSNumber(value: true),
            range: NSRange(location: attributed.length - 1, length: 1)
        )
        return mutable
    }

    /// 지정한 라인들만 담은 하위 문단을 만든다. 라인 range는 하위 문자열 기준으로
    /// 재기준화해 (다중 페이지 row에서) 이후 분할에서도 라인 정보를 쓸 수 있게 한다.
    private static func paragraphFragment(
        of paragraph: HwpLaidOutParagraph,
        lines: ArraySlice<HwpLineFrame>,
        rect: CGRect
    ) -> HwpLaidOutParagraph {
        let range = lines.dropFirst().reduce(lines[lines.startIndex].attributedRange) {
            NSUnionRange($0, $1.attributedRange)
        }
        let rebased = lines.map { line in
            HwpLineFrame(
                origin: line.origin,
                width: line.width,
                baseline: line.baseline,
                attributedRange: NSRange(
                    location: max(0, line.attributedRange.location - range.location),
                    length: line.attributedRange.length
                ),
                inlineAnchors: line.inlineAnchors
            )
        }
        let sub = paragraph.attributedString.attributedSubstring(from: range)
        let continued = range.location + range.length < paragraph.attributedString.length
        return HwpLaidOutParagraph(
            attributedString: continued ? markedAsContinuedFragment(sub) : sub,
            frame: HwpParagraphFrame(totalHeight: rect.height, lines: rebased),
            rect: rect,
            paragraphId: paragraph.paragraphId
        )
    }
}
