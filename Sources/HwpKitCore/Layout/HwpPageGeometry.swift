import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

/// Converts `HwpPageDef` (and optional `HwpSectionDef`) into point-based geometry for a single page.
public struct HwpPageGeometry: Sendable, Hashable {
    public let pageSize: CGSize
    public let margins: HwpPageMargins
    public let contentFrame: CGRect
    public let headerFrame: CGRect?
    public let footerFrame: CGRect?
    /// Always `[contentFrame]` in v1; column count requires the Column control, not `HwpSectionDef`.
    public let columnFrames: [CGRect]

    public static func compute(
        pageDef: CoreHwp.HwpPageDef,
        sectionDef: CoreHwp.HwpSectionDef?
    ) -> HwpPageGeometry {
        let pageSize = HwpUnits.size(fromHwpUnitWidth: pageDef.width, height: pageDef.height)

        let margins = HwpPageMargins(
            top: HwpUnits.points(fromHwpUnitU: pageDef.marginTop),
            left: HwpUnits.points(fromHwpUnitU: pageDef.marginLeft),
            bottom: HwpUnits.points(fromHwpUnitU: pageDef.marginBottom),
            right: HwpUnits.points(fromHwpUnitU: pageDef.marginRight)
        )

        let contentWidth = pageSize.width - margins.left - margins.right
        let contentHeight = pageSize.height - margins.top - margins.bottom
        let contentFrame = CGRect(
            x: margins.left,
            y: margins.top,
            width: contentWidth,
            height: contentHeight
        )

        let headerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginHeader)
        let headerFrame: CGRect? = headerMarginPt > 0
            ? CGRect(x: margins.left, y: 0, width: contentWidth, height: headerMarginPt)
            : nil

        let footerMarginPt = HwpUnits.points(fromHwpUnitU: pageDef.marginFootnote)
        let footerFrame: CGRect? = footerMarginPt > 0
            ? CGRect(
                x: margins.left,
                y: pageSize.height - footerMarginPt,
                width: contentWidth,
                height: footerMarginPt
            )
            : nil

        // Column count lives in the Column control (CtrlHeader/Column/), not in HwpSectionDef.
        // sectionDef is accepted for future v2 multi-column support; v1 always returns [contentFrame].
        _ = sectionDef
        let columnFrames: [CGRect] = [contentFrame]

        return HwpPageGeometry(
            pageSize: pageSize,
            margins: margins,
            contentFrame: contentFrame,
            headerFrame: headerFrame,
            footerFrame: footerFrame,
            columnFrames: columnFrames
        )
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
