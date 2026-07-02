import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

public struct HwpLineFrame: Sendable, Hashable {
    public let origin: CGPoint
    public let width: CGFloat
    public let baseline: CGFloat
    public let attributedRange: NSRange

    public init(origin: CGPoint, width: CGFloat, baseline: CGFloat, attributedRange: NSRange) {
        self.origin = origin
        self.width = width
        self.baseline = baseline
        self.attributedRange = attributedRange
    }
}

public struct HwpParagraphFrame: Sendable, Hashable {
    public let totalHeight: CGFloat
    public let lines: [HwpLineFrame]

    public init(totalHeight: CGFloat, lines: [HwpLineFrame]) {
        self.totalHeight = totalHeight
        self.lines = lines
    }
}

public struct HwpParagraphLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public func layout(
        attributedString: NSAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        columnWidth: CGFloat
    ) -> HwpParagraphFrame {
        guard attributedString.length > 0 else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        _ = fontResolver

        let paragraphMetrics = ParagraphMetrics(paraShape: paraShape)
        let paragraphStyle = ctParagraphStyle(from: paragraphMetrics, property: paraShape.property1Info)

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        mutable.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutable.length)
        )

        let framesetter = CTFramesetterCreateWithAttributedString(mutable as CFAttributedString)
        let frameSize = CGSize(width: max(1, columnWidth), height: .greatestFiniteMagnitude)
        let path = CGPath(rect: CGRect(origin: .zero, size: frameSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        guard !lines.isEmpty else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let referenceY = origins[0].y
        var lineFrames: [HwpLineFrame] = []
        lineFrames.reserveCapacity(lines.count)
        var totalLineHeight: CGFloat = 0

        for index in lines.indices {
            let line = lines[index]
            let origin = origins[index]
            let range = CTLineGetStringRange(line)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            totalLineHeight += max(1, ascent + descent + leading)
            lineFrames.append(
                HwpLineFrame(
                    origin: CGPoint(x: origin.x, y: referenceY - origin.y),
                    width: width,
                    baseline: ascent,
                    attributedRange: NSRange(location: Int(range.location), length: Int(range.length))
                )
            )
        }

        let totalHeight = paragraphMetrics.paragraphSpacingBefore + totalLineHeight + paragraphMetrics.paragraphSpacing
        return HwpParagraphFrame(totalHeight: max(1, totalHeight), lines: lineFrames)
    }
}

private extension HwpParagraphLayout {
    struct ParagraphMetrics {
        var firstLineHeadIndent: CGFloat
        var headIndent: CGFloat
        var tailIndent: CGFloat
        var paragraphSpacingBefore: CGFloat
        var paragraphSpacing: CGFloat
        var lineSpacing: CGFloat

        init(paraShape: CoreHwp.HwpParaShape) {
            firstLineHeadIndent = HwpUnits.points(fromHwpUnit: paraShape.indent)
            headIndent = HwpUnits.points(fromHwpUnit: paraShape.marginLeft)
            tailIndent = -HwpUnits.points(fromHwpUnit: paraShape.marginRight)
            paragraphSpacingBefore = HwpUnits.points(fromHwpUnit: paraShape.paragraphSpacingTop)
            paragraphSpacing = HwpUnits.points(fromHwpUnit: paraShape.paragraphSpacingBottom)
            lineSpacing = if let lineSpacing2 = paraShape.lineSpacing2 {
                HwpUnits.points(fromHwpUnitU: lineSpacing2)
            } else {
                HwpUnits.points(fromHwpUnit: paraShape.lineSpacing)
            }
        }
    }

    func ctParagraphStyle(
        from metrics: ParagraphMetrics,
        property: CoreHwp.HwpParaShapeProperty1
    ) -> CTParagraphStyle {
        let alignment = pointer(to: textAlignment(from: property))
        let firstLineHeadIndent = pointer(to: metrics.firstLineHeadIndent)
        let headIndent = pointer(to: metrics.headIndent)
        let tailIndent = pointer(to: metrics.tailIndent)
        let paragraphSpacingBefore = pointer(to: metrics.paragraphSpacingBefore)
        let paragraphSpacing = pointer(to: metrics.paragraphSpacing)
        let lineSpacing = pointer(to: metrics.lineSpacing)
        defer {
            alignment.deinitialize(count: 1)
            alignment.deallocate()
            firstLineHeadIndent.deinitialize(count: 1)
            firstLineHeadIndent.deallocate()
            headIndent.deinitialize(count: 1)
            headIndent.deallocate()
            tailIndent.deinitialize(count: 1)
            tailIndent.deallocate()
            paragraphSpacingBefore.deinitialize(count: 1)
            paragraphSpacingBefore.deallocate()
            paragraphSpacing.deinitialize(count: 1)
            paragraphSpacing.deallocate()
            lineSpacing.deinitialize(count: 1)
            lineSpacing.deallocate()
        }

        let settings = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: alignment
            ),
            CTParagraphStyleSetting(
                spec: .firstLineHeadIndent,
                valueSize: MemoryLayout<CGFloat>.size,
                value: firstLineHeadIndent
            ),
            CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: headIndent),
            CTParagraphStyleSetting(spec: .tailIndent, valueSize: MemoryLayout<CGFloat>.size, value: tailIndent),
            CTParagraphStyleSetting(
                spec: .paragraphSpacingBefore,
                valueSize: MemoryLayout<CGFloat>.size,
                value: paragraphSpacingBefore
            ),
            CTParagraphStyleSetting(
                spec: .paragraphSpacing,
                valueSize: MemoryLayout<CGFloat>.size,
                value: paragraphSpacing
            ),
            CTParagraphStyleSetting(
                spec: .lineSpacingAdjustment,
                valueSize: MemoryLayout<CGFloat>.size,
                value: lineSpacing
            ),
        ]
        return CTParagraphStyleCreate(settings, settings.count)
    }

    func pointer<T>(to value: T) -> UnsafeMutablePointer<T> {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        pointer.initialize(to: value)
        return pointer
    }

    func textAlignment(from property: CoreHwp.HwpParaShapeProperty1) -> CTTextAlignment {
        switch property.rawValue & 0b111 {
        case 1:
            .right
        case 2:
            .center
        case 3:
            .justified
        default:
            .left
        }
    }
}
