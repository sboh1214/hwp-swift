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
    public init() {}

    public func layout(
        attributedString: NSAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        columnWidth: CGFloat
    ) -> HwpParagraphFrame {
        guard attributedString.length > 0 else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        let paragraphMetrics = ParagraphMetrics(paraShape: paraShape)
        let paragraphStyle = ctParagraphStyle(
            from: paragraphMetrics,
            property: paraShape.property1Info
        )

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        mutable.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutable.length)
        )

        let framesetter = CTFramesetterCreateWithAttributedString(mutable as CFAttributedString)
        let frameSize = CGSize(width: max(1, columnWidth), height: .greatestFiniteMagnitude)
        let path = CGPath(rect: CGRect(origin: .zero, size: frameSize), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        guard !lines.isEmpty else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let (lineFrames, totalLineHeight) = makeLineFrames(lines: lines, origins: origins)
        let totalHeight = paragraphMetrics.paragraphSpacingBefore
            + totalLineHeight
            + paragraphMetrics.paragraphSpacing
        return HwpParagraphFrame(totalHeight: max(1, totalHeight), lines: lineFrames)
    }
}

private extension HwpParagraphLayout {
    func makeLineFrames(
        lines: [CTLine],
        origins: [CGPoint]
    ) -> (frames: [HwpLineFrame], totalLineHeight: CGFloat) {
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
            let attributedRange = NSRange(
                location: Int(range.location),
                length: Int(range.length)
            )
            lineFrames.append(
                HwpLineFrame(
                    origin: CGPoint(x: origin.x, y: referenceY - origin.y),
                    width: width,
                    baseline: ascent,
                    attributedRange: attributedRange
                )
            )
        }

        return (lineFrames, totalLineHeight)
    }

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

    struct StyleValuePointers {
        let alignment: UnsafeMutablePointer<CTTextAlignment>
        let firstLineHeadIndent: UnsafeMutablePointer<CGFloat>
        let headIndent: UnsafeMutablePointer<CGFloat>
        let tailIndent: UnsafeMutablePointer<CGFloat>
        let paragraphSpacingBefore: UnsafeMutablePointer<CGFloat>
        let paragraphSpacing: UnsafeMutablePointer<CGFloat>
        let lineSpacing: UnsafeMutablePointer<CGFloat>

        init(metrics: ParagraphMetrics, alignment: CTTextAlignment) {
            self.alignment = Self.pointer(to: alignment)
            firstLineHeadIndent = Self.pointer(to: metrics.firstLineHeadIndent)
            headIndent = Self.pointer(to: metrics.headIndent)
            tailIndent = Self.pointer(to: metrics.tailIndent)
            paragraphSpacingBefore = Self.pointer(to: metrics.paragraphSpacingBefore)
            paragraphSpacing = Self.pointer(to: metrics.paragraphSpacing)
            lineSpacing = Self.pointer(to: metrics.lineSpacing)
        }

        func deallocate() {
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

        static func pointer<T>(to value: T) -> UnsafeMutablePointer<T> {
            let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
            pointer.initialize(to: value)
            return pointer
        }
    }

    func ctParagraphStyle(
        from metrics: ParagraphMetrics,
        property: CoreHwp.HwpParaShapeProperty1
    ) -> CTParagraphStyle {
        let pointers = StyleValuePointers(
            metrics: metrics,
            alignment: textAlignment(from: property)
        )
        defer { pointers.deallocate() }

        let settings = styleSettings(from: pointers)
        return CTParagraphStyleCreate(settings, settings.count)
    }

    func styleSettings(from pointers: StyleValuePointers) -> [CTParagraphStyleSetting] {
        [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointers.alignment
            ),
            CTParagraphStyleSetting(
                spec: .firstLineHeadIndent,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.firstLineHeadIndent
            ),
            CTParagraphStyleSetting(
                spec: .headIndent,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.headIndent
            ),
            CTParagraphStyleSetting(
                spec: .tailIndent,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.tailIndent
            ),
            CTParagraphStyleSetting(
                spec: .paragraphSpacingBefore,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.paragraphSpacingBefore
            ),
            CTParagraphStyleSetting(
                spec: .paragraphSpacing,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.paragraphSpacing
            ),
            CTParagraphStyleSetting(
                spec: .lineSpacingAdjustment,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.lineSpacing
            ),
        ]
    }

    func textAlignment(from property: CoreHwp.HwpParaShapeProperty1) -> CTTextAlignment {
        // 문단 모양 속성1: bits 0-1 = 줄 간격 종류, bits 2-4 = 정렬 방식
        // (0 양쪽, 1 왼쪽, 2 오른쪽, 3 가운데, 4 배분, 5 나눔)
        switch (property.rawValue >> 2) & 0b111 {
        case 0, 4, 5:
            .justified
        case 2:
            .right
        case 3:
            .center
        default:
            .left
        }
    }
}
