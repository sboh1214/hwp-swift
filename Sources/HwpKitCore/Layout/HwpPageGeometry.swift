import CoreGraphics
import CoreHwp
import Foundation

/// Converts `HwpPageDef` (and optional `HwpSectionDef`) into point-based geometry
/// for a single page.
public struct HwpPageGeometry: Sendable, Hashable {
    public let pageSize: CGSize
    public let margins: HwpPageMargins
    public let contentFrame: CGRect
    public let headerFrame: CGRect?
    public let footerFrame: CGRect?
    /// 단 정의 (`cold` 컨트롤)가 주어지면 콘텐츠 영역을 나눈 단 프레임,
    /// 없으면 `[contentFrame]`.
    public let columnFrames: [CGRect]

    public static func compute(
        pageDef: CoreHwp.HwpPageDef,
        sectionDef: CoreHwp.HwpSectionDef?,
        column: CoreHwp.HwpColumn? = nil
    ) -> HwpPageGeometry {
        let pageSize = HwpUnits.size(fromHwpUnitWidth: pageDef.width, height: pageDef.height)

        // 한글의 세로 구성 (표 137): 위쪽 여백 → 머리말 영역 → 본문 →
        // 꼬리말 영역 → 아래쪽 여백. 머리말/꼬리말 컨트롤이 없어도 두 영역은
        // 본문 밖에 항상 예약된다 — 본문 시작 y = marginTop + marginHeader
        // (BinData/plain-text 픽스처 PrvImage 실측: 본문 상단 99.2pt =
        // 56.68 + 42.52).
        let paperTopMargin = HwpUnits.points(fromHwpUnitU: pageDef.marginTop)
        let paperBottomMargin = HwpUnits.points(fromHwpUnitU: pageDef.marginBottom)
        let headerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginHeader)
        let footerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginFootnote)

        // margins는 본문 콘텐츠 인셋 (머리말/꼬리말 영역 포함) — 뷰/테스트가
        // "본문 밖" 판정에 그대로 쓸 수 있는 값이다.
        let margins = HwpPageMargins(
            top: paperTopMargin + headerMarginPt,
            left: HwpUnits.points(fromHwpUnitU: pageDef.marginLeft),
            bottom: paperBottomMargin + footerMarginPt,
            right: HwpUnits.points(fromHwpUnitU: pageDef.marginRight)
        )

        let contentWidth = pageSize.width - margins.left - margins.right
        let contentFrame = CGRect(
            x: margins.left,
            y: margins.top,
            width: contentWidth,
            height: pageSize.height - margins.top - margins.bottom
        )

        let headerFrame: CGRect? = headerMarginPt > 0
            ? CGRect(
                x: margins.left,
                y: paperTopMargin,
                width: contentWidth,
                height: headerMarginPt
            )
            : nil

        let footerFrame: CGRect? = footerMarginPt > 0
            ? CGRect(
                x: margins.left,
                y: contentFrame.maxY,
                width: contentWidth,
                height: footerMarginPt
            )
            : nil

        let columnFrames = Self.columnFrames(
            in: contentFrame,
            column: column,
            defaultSpacing: sectionDef.map {
                HwpUnits.points(fromHwpUnit16: $0.columnSpacing)
            } ?? 0
        )

        return HwpPageGeometry(
            pageSize: pageSize,
            margins: margins,
            contentFrame: contentFrame,
            headerFrame: headerFrame,
            footerFrame: footerFrame,
            columnFrames: columnFrames
        )
    }

    /// 단 정의 (표 138/139)로 영역을 단 프레임으로 나눈다.
    ///
    /// - 등폭 단: `spacing` (없으면 구역의 `columnSpacing`)을 사이 간격으로
    ///   폭을 균등 분할한다.
    /// - 비등폭 단: `widthArray`/`gapArray`는 비례값 ((폭+간격) 합 기준,
    ///   Column 픽스처에서 합계 32768 검증)이며 영역 폭에 비례 배분한다.
    /// - 단 방향이 오른쪽부터면 프레임 순서를 뒤집는다.
    public static func columnFrames(
        in area: CGRect,
        column: CoreHwp.HwpColumn?,
        defaultSpacing: CGFloat = 0
    ) -> [CGRect] {
        guard let column, column.property.count > 1 else { return [area] }
        let count = column.property.count

        var frames: [CGRect] = []
        if let widths = column.widthArray, widths.count == count {
            let gaps = column.gapArray ?? []
            var total = widths.reduce(CGFloat(0)) { $0 + CGFloat($1) }
            for index in 0 ..< (count - 1) where gaps.indices.contains(index) {
                total += CGFloat(gaps[index])
            }
            guard total > 0 else { return [area] }
            let scale = area.width / total
            var cursorX = area.minX
            for index in 0 ..< count {
                let width = CGFloat(widths[index]) * scale
                frames.append(CGRect(x: cursorX, y: area.minY, width: width, height: area.height))
                cursorX += width
                if index < count - 1, gaps.indices.contains(index) {
                    cursorX += CGFloat(gaps[index]) * scale
                }
            }
        } else {
            let spacing = column.spacing.map { HwpUnits.points(fromHwpUnit16: $0) }
                ?? defaultSpacing
            let columnWidth = max(1, (area.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for index in 0 ..< count {
                frames.append(CGRect(
                    x: area.minX + (columnWidth + spacing) * CGFloat(index),
                    y: area.minY,
                    width: columnWidth,
                    height: area.height
                ))
            }
        }
        if column.property.direction == .right {
            frames.reverse()
        }
        return frames
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pageSize.width)
        hasher.combine(pageSize.height)
        hasher.combine(margins)
        hasher.combine(contentFrame.minX)
        hasher.combine(contentFrame.minY)
        hasher.combine(contentFrame.width)
        hasher.combine(contentFrame.height)
        if let header = headerFrame {
            hasher.combine(true)
            hasher.combine(header.minX)
            hasher.combine(header.minY)
            hasher.combine(header.width)
            hasher.combine(header.height)
        } else {
            hasher.combine(false)
        }
        if let footer = footerFrame {
            hasher.combine(true)
            hasher.combine(footer.minX)
            hasher.combine(footer.minY)
            hasher.combine(footer.width)
            hasher.combine(footer.height)
        } else {
            hasher.combine(false)
        }
        hasher.combine(columnFrames.count)
        for col in columnFrames {
            hasher.combine(col.minX)
            hasher.combine(col.minY)
            hasher.combine(col.width)
            hasher.combine(col.height)
        }
    }
}
