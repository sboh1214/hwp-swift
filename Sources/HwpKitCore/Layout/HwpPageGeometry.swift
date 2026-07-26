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
        let rawPageSize = HwpUnits.size(fromHwpUnitWidth: pageDef.width, height: pageDef.height)
        // 미신뢰 페이지 치수 방어: 유한·양수·상한으로 클램프해 거대 backing store를 막는다.
        let sanitizedSize = CGSize(
            width: Self.sanitizedDimension(rawPageSize.width),
            height: Self.sanitizedDimension(rawPageSize.height)
        )
        // 용지 방향 (표 13 bit 0: 0 좁게 / 1 넓게)을 여백·단 계산 전에 반영한다.
        let pageSize = Self.orientedPageSize(sanitizedSize, property: pageDef.property)

        // 한글의 세로 구성 (표 137): 위쪽 여백 → 머리말 영역 → 본문 →
        // 꼬리말 영역 → 아래쪽 여백. 머리말/꼬리말 컨트롤이 없어도 두 영역은
        // 본문 밖에 항상 예약된다 — 본문 시작 y = marginTop + marginHeader
        // (BinData/plain-text 픽스처 PrvImage 실측: 본문 상단 99.2pt =
        // 56.68 + 42.52).
        let paperTopMargin = HwpUnits.points(fromHwpUnitU: pageDef.marginTop)
        let paperBottomMargin = HwpUnits.points(fromHwpUnitU: pageDef.marginBottom)
        let headerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginHeader)
        let footerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginFootnote)

        let (leftGutter, topGutter) = Self.gutterInsets(pageDef)

        // margins는 본문 콘텐츠 인셋 (머리말/꼬리말 영역 포함) — 뷰/테스트가
        // "본문 밖" 판정에 그대로 쓸 수 있는 값이다.
        let topInset = paperTopMargin + headerMarginPt + topGutter
        let leftInset = HwpUnits.points(fromHwpUnitU: pageDef.marginLeft) + leftGutter
        let bottomInset = paperBottomMargin + footerMarginPt
        let rightInset = HwpUnits.points(fromHwpUnitU: pageDef.marginRight)
        let margins = HwpPageMargins(
            top: Self.clampMargin(topInset, limit: pageSize.height),
            left: Self.clampMargin(leftInset, limit: pageSize.width),
            bottom: Self.clampMargin(bottomInset, limit: pageSize.height),
            right: Self.clampMargin(rightInset, limit: pageSize.width)
        )

        // 여백 합이 페이지를 넘으면 콘텐츠 rect가 음수가 되므로 최소 1로 클램프한다.
        let contentWidth = max(1, pageSize.width - margins.left - margins.right)
        let contentFrame = CGRect(
            x: margins.left,
            y: margins.top,
            width: contentWidth,
            height: max(1, pageSize.height - margins.top - margins.bottom)
        )

        // 위로 제책이면 topGutter가 위 여백 다음에 오므로 머리말도 그만큼 내려
        // 위 여백 → gutter → 머리말 → 본문 순서를 만든다 (아니면 머리말이 제본
        // 영역에 놓이고 머리말·본문 사이에 gutter 간격이 생긴다, R43 #2).
        let headerFrame: CGRect? = headerMarginPt > 0
            ? CGRect(
                x: margins.left,
                y: paperTopMargin + topGutter,
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

    /// 페이지 치수 클램프 상한 (pt, 200인치) — 실제 문서는 한참 아래다.
    static let maximumPageDimension: CGFloat = 14400
    /// 비유한/비양수 치수 폴백 (A4 폭)
    static let fallbackPageDimension: CGFloat = 595

    /// 용지 방향 (표 13 bit 0)을 반영한 페이지 크기.
    ///
    /// 넓게(landscape)로 선언됐는데 저장 치수가 세로 형태(폭 < 높이)면 축을
    /// 바꾼다. 저장 치수가 이미 가로 형태면 그대로 둔다 — 한글 저장본이 회전을
    /// 이미 반영했는지 여부와 무관하게 같은 결과를 내고(멱등), 무조건 교환했을
    /// 때 생기는 이중 회전을 원리적으로 막는다 (R69 #1).
    static func orientedPageSize(_ size: CGSize, property: UInt32) -> CGSize {
        guard property & 1 == 1, size.width < size.height else { return size }
        return CGSize(width: size.height, height: size.width)
    }

    private static func sanitizedDimension(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallbackPageDimension }
        return min(value, maximumPageDimension)
    }

    private static func clampMargin(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, limit)
    }

    /// 제본 여백(gutter)을 제책 방향(property bit1~2: 0 한쪽·1 맞쪽·2 위로)에 따라
    /// (왼쪽, 위쪽) 인셋으로 배분한다 — 한쪽/맞쪽은 왼쪽, 위로는 위쪽. 맞쪽은
    /// 페이지 홀짝의 안쪽(홀=왼)인데 기하엔 페이지 번호가 없어 왼쪽 근사 (R42 #3).
    private static func gutterInsets(
        _ pageDef: CoreHwp.HwpPageDef
    ) -> (left: CGFloat, top: CGFloat) {
        let gutterPt = HwpUnits.points(fromHwpUnitU: pageDef.marginGutter)
        let makingBook = (pageDef.property >> 1) & 0b11
        return makingBook == 2 ? (0, gutterPt) : (gutterPt, 0)
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
