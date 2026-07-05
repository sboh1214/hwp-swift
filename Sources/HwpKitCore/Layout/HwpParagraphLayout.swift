import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

/// 라인 안 U+FFFC 컨트롤 마커의 위치 (줄 중간 treatAsChar 앵커용)
public struct HwpInlineAnchor: Sendable, Hashable {
    /// ctrlHeaderArray 안 컨트롤 index
    public let controlIndex: Int
    /// 라인 origin에서 마커 왼쪽까지의 x 오프셋
    public let xOffset: CGFloat
    /// 마커 run의 ascent (treatAsChar 개체면 개체 높이)
    public let ascent: CGFloat
    /// 마커 run의 폭
    public let width: CGFloat

    public init(controlIndex: Int, xOffset: CGFloat, ascent: CGFloat, width: CGFloat) {
        self.controlIndex = controlIndex
        self.xOffset = xOffset
        self.ascent = ascent
        self.width = width
    }
}

public struct HwpLineFrame: Sendable, Hashable {
    public let origin: CGPoint
    public let width: CGFloat
    public let baseline: CGFloat
    public let attributedRange: NSRange
    /// 이 라인에 있는 컨트롤 마커 앵커들
    public let inlineAnchors: [HwpInlineAnchor]

    public init(
        origin: CGPoint,
        width: CGFloat,
        baseline: CGFloat,
        attributedRange: NSRange,
        inlineAnchors: [HwpInlineAnchor] = []
    ) {
        self.origin = origin
        self.width = width
        self.baseline = baseline
        self.attributedRange = attributedRange
        self.inlineAnchors = inlineAnchors
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

    /// paraShape로 측정/렌더 공용 CTParagraphStyle을 만든다.
    /// HwpTextRunBuilder가 렌더 경로 (drawText 재조판)에도 같은 스타일을 부착해
    /// 측정 레이아웃 (정렬/들여쓰기/줄간격, 인라인 앵커 x)과 일치시킨다.
    public static func paragraphStyle(for paraShape: CoreHwp.HwpParaShape) -> CTParagraphStyle {
        HwpParagraphLayout().ctParagraphStyle(
            from: ParagraphMetrics(paraShape: paraShape),
            property: paraShape.property1Info
        )
    }

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
        // 주의: greatestFiniteMagnitude를 쓰면 line origin(y ≈ 1.8e308)의
        // 배정도 정밀도가 무너져 라인 간 y 델타가 전부 0이 된다.
        let frameSize = CGSize(width: max(1, columnWidth), height: 1_000_000)
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
                    attributedRange: attributedRange,
                    inlineAnchors: inlineAnchors(in: line)
                )
            )
        }

        return (lineFrames, totalLineHeight)
    }

    /// 라인의 run에서 컨트롤 마커 (hwp.controlIndex attribute) 위치를 추출한다.
    func inlineAnchors(in line: CTLine) -> [HwpInlineAnchor] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var anchors: [HwpInlineAnchor] = []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let number = attributes[HwpAttributedStringKey.controlIndex] as? NSNumber
            else { continue }
            let range = CTRunGetStringRange(run)
            let xOffset = CTLineGetOffsetForStringIndex(line, range.location, nil)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(
                run,
                CFRange(location: 0, length: 0),
                &ascent,
                &descent,
                nil
            ))
            anchors.append(HwpInlineAnchor(
                controlIndex: number.intValue,
                xOffset: xOffset,
                ascent: ascent,
                width: width
            ))
        }
        return anchors
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
