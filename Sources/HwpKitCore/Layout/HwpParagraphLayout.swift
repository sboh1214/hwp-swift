import CoreGraphics
import CoreHwp
import CoreText
import Foundation

public extension HwpAttributedStringKey {
    /// treatAsChar 개체 마커가 예약한 줄 공간 높이 (NSNumber, pt).
    /// 비율/고정 줄 간격이 개체를 자르지 않도록 상한 적용 여부 판단에 쓴다.
    static let inlineObjectHeight = NSAttributedString.Key("hwp.inlineObjectHeight")
}

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

    /// 저장본 라인 캐시가 유효하면 한글이 계산한 문단 높이 (첫 줄 위 ~ 마지막
    /// 줄 전진량)를 준다. 폰트 대체로 CT 줄 수가 달라져도 각주 스택·표 셀
    /// 높이가 한글과 일치하게 한다 (헌법주석 실측: 각주 문단 캐시 h 900 +
    /// sp 272 = 11.72pt를 CT는 2줄 22.2pt로 부풀려 각주 이월·표 분할이 밀렸다).
    public static func cachedParagraphHeight(
        _ paragraph: CoreHwp.HwpParagraph
    ) -> CGFloat? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !segments.isEmpty else { return nil }
        var previous = Int32.min
        var top = Int.max
        var bottom = Int.min
        for segment in segments {
            guard segment.lineLocation > previous, segment.lineHeight >= 0 else { return nil }
            previous = segment.lineLocation
            // 미신뢰 캐시의 Int32 덧셈 트랩 방지 — Int로 넓혀 누적한다.
            top = min(top, Int(segment.lineLocation))
            bottom = max(bottom, HwpAbsoluteCachePlacer.lineBottom(of: segment))
        }
        guard bottom > top else { return nil }
        return max(1, HwpUnits.points(fromHwpUnit: Int32(clamping: bottom - top)))
    }

    /// paraShape로 측정/렌더 공용 CTParagraphStyle을 만든다.
    /// HwpTextRunBuilder가 렌더 경로 (drawText 재조판)에도 같은 스타일을 부착해
    /// 측정 레이아웃 (정렬/들여쓰기/줄간격, 인라인 앵커 x)과 일치시킨다.
    ///
    /// 비율(%) 줄 간격은 글자 크기 기준이므로 attributedString이 있어야
    /// 정확하다 (없으면 여백만 지정과 고정값만 반영된다).
    public static func paragraphStyle(
        for paraShape: CoreHwp.HwpParaShape,
        attributedString: NSAttributedString? = nil,
        tabStops: [CTTextTab] = []
    ) -> CTParagraphStyle {
        var metrics = ParagraphMetrics(
            paraShape: paraShape, attributedString: attributedString
        )
        metrics.tabStops = tabStops
        return HwpParagraphLayout().ctParagraphStyle(
            from: metrics,
            property: paraShape.property1Info
        )
    }

    /// 문단당 줄 프레임 누적 상한 — 프레임 연장 루프(#9)는 문자열 끝까지
    /// 줄을 전량 생성·보존하므로, 수백 MB 문단(기본 스트림 한도 안)이 1pt
    /// 폭 단과 결합하면 줄 수가 문자 수에 접근해 페이지 상한이 걸리기 전에
    /// 메모리/CPU를 고갈시킨다. 100,000줄은 legacy 실측(1,030쪽 문서 전체
    /// ≈ 4만 줄)의 2.5배로, 초과분은 페이지 상한과 같은 절단 계약을 따른다.
    public static let maximumLineFrames = 100_000

    /// **입력 계약: `attributedString`에 문단 스타일이 이미 부착돼 있어야 한다.**
    /// 정렬·들여쓰기·줄 간격·문서 정의 탭은 전부 그 부착본이 나르고, 이 함수는
    /// 그것을 **그대로** framesetting한다 (#80 조각 3 — 종전에는 문단마다 전체
    /// 사본을 떠 스타일을 재생성했다. 같은 paraShape에서 나오므로 값은 같았지만,
    /// slight-overflow 분기는 부착본을 읽고 일반 분기는 재생성본을 읽어 한 함수
    /// 안에서 스타일 출처가 둘로 갈려 있었다).
    ///
    /// 부착은 `HwpTextRunBuilder.build`가 `attachParagraphStyle`로 자동으로 한다.
    /// 직접 문자열을 만들어 넘기는 호출부는
    /// `HwpParagraphLayout.paragraphStyle(for:attributedString:tabStops:)`를 **같은
    /// paraShape로** 만들어 `kCTParagraphStyleAttributeName`에 달아야 한다. 안 달면
    /// CT 기본값(natural 정렬, 자연 줄 높이)으로 조판돼 렌더와 어긋난다.
    ///
    /// `paraShape`는 부착본이 나르지 **못하는** 것에만 쓴다 — 문단 위/아래 간격,
    /// 강제 줄 높이 클램프, 줄 여분을 줄 뒤 간격으로 돌렸는지 여부
    /// (`ParagraphMetrics`). 그래서 스타일을 부착한 paraShape와 **같은 값**이어야
    /// 한다.
    public func layout(
        attributedString: NSAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        columnWidth: CGFloat,
        maxLineFrames: Int = HwpParagraphLayout.maximumLineFrames
    ) -> HwpParagraphFrame {
        // 조판 문자열이 빈 문단은 높이 0이다. **이것은 알려진 격차이고 여기서는
        // 고칠 수 없다** — 빈 문자열에는 글꼴도 `hwp.baseFontSize`도 없는데
        // (`HwpTextRunBuilder.attachParagraphStyle`이 length 0에서 빠진다) 픽스처
        // paraShape 850개 중 848개가 쓰는 `.percent` 줄 간격은 그 둘이 있어야
        // 줄 높이를 낸다. 한 줄 높이를 주려면 글자 모양을 아는 계층
        // (`HwpParagraphMeasurer`·`HwpPaginator.height(for:fallback:)`)에서
        // `charShape.baseSize × 줄간격%`로 하한을 걸어야 한다.
        //
        // 발현 경로는 라인 캐시를 쓰지 않는 측정뿐이다 (글상자·캐시 무효 문단·
        // 안전밸브로 linesegarray를 폐기한 HWPX 문단). 픽스처 전수에서는 빈 문단
        // 3,954개가 **전부** 유효한 캐시를 가져 재현되지 않는다.
        guard attributedString.length > 0 else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        let paragraphMetrics = ParagraphMetrics(
            paraShape: paraShape,
            attributedString: attributedString
        )

        // slight-overflow 한 줄 (렌더와 같은 술어): 렌더가 한 줄로 그리는
        // 문단은 측정도 한 줄 높이여야 문단 높이 (= 페이지 절단)와 실제
        // 잉크가 일치한다 (B-1b).
        if let overflow = HwpDrawnTextLayout.slightOverflowLineMetrics(
            attributedString: attributedString, lineWidth: max(1, columnWidth)
        ) {
            let lineHeight = max(1, paragraphMetrics.clampedLineHeight(
                overflow.ascent + overflow.descent + overflow.leading
            ))
            let trailingSpacing = paragraphMetrics.lineHeightAppliedAsSpacing
                ? paragraphMetrics.lineSpacingAdjustment : 0
            let totalHeight = paragraphMetrics.paragraphSpacingBefore
                + lineHeight
                + trailingSpacing
                + paragraphMetrics.paragraphSpacing
            let lineFrame = HwpLineFrame(
                origin: .zero,
                width: CGFloat(CTLineGetTypographicBounds(overflow.line, nil, nil, nil)),
                baseline: overflow.ascent,
                attributedRange: NSRange(location: 0, length: attributedString.length),
                inlineAnchors: inlineAnchors(in: overflow.line)
            )
            return HwpParagraphFrame(totalHeight: max(1, totalHeight), lines: [lineFrame])
        }
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributedString as CFAttributedString
        )
        let typesetter = CTTypesetterCreateWithAttributedString(
            attributedString as CFAttributedString
        )
        let fullLength = attributedString.length
        // 렌더(HwpDrawnTextLayout.lines)와 HwpLineBreaker.nextFrameChunk를 공유해 청크
        // 경계를 같은 CTLine 시작에 맞춘다 — 측정 range·높이가 렌더 줄과 일치한다. 단일
        // 청크(모든 정상 문단)는 문단 전체가 한 프레임이라 측정 불변 (R37 #1·R50 #4).
        var lineFrames: [HwpLineFrame] = []
        var totalLineHeight: CGFloat = 0
        var startLocation = 0
        while startLocation < fullLength, lineFrames.count < maxLineFrames {
            guard let chunk = HwpLineBreaker.nextFrameChunk(
                framesetter: framesetter, typesetter: typesetter,
                attributedString: attributedString,
                startLocation: startLocation, fullLength: fullLength,
                remainingLineBudget: maxLineFrames - lineFrames.count,
                lineWidth: max(1, columnWidth)
            ) else { break }
            let (frameLines, frameHeight) = makeLineFrames(
                lines: chunk.lines,
                origins: chunk.origins,
                keepCount: chunk.keepCount,
                continuesAfterChunk: chunk.nextStart < fullLength,
                metrics: paragraphMetrics,
                yOffset: totalLineHeight
            )
            lineFrames.append(contentsOf: frameLines)
            totalLineHeight += frameHeight
            guard chunk.nextStart > startLocation else { break }
            startLocation = chunk.nextStart
        }
        guard !lineFrames.isEmpty else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }
        // 줄 여분을 줄 뒤 간격으로 돌린 경우 마지막 줄 뒤 몫도 전진량에
        // 포함한다 (한글 캐시 lineAdvance 합과 동일)
        let trailingSpacing = paragraphMetrics.lineHeightAppliedAsSpacing && !lineFrames.isEmpty
            ? paragraphMetrics.lineSpacingAdjustment
            : 0
        let totalHeight = paragraphMetrics.paragraphSpacingBefore
            + totalLineHeight
            + trailingSpacing
            + paragraphMetrics.paragraphSpacing
        return HwpParagraphFrame(totalHeight: max(1, totalHeight), lines: lineFrames)
    }
}

private extension HwpParagraphLayout {
    func makeLineFrames(
        lines: [CTLine],
        origins: [CGPoint],
        keepCount: Int,
        continuesAfterChunk: Bool,
        metrics: ParagraphMetrics,
        yOffset: CGFloat = 0
    ) -> (frames: [HwpLineFrame], totalLineHeight: CGFloat) {
        let referenceY = origins[0].y
        var lineFrames: [HwpLineFrame] = []
        lineFrames.reserveCapacity(keepCount)
        var totalLineHeight: CGFloat = 0

        for index in 0 ..< keepCount {
            let line = lines[index]
            let origin = origins[index]
            let range = CTLineGetStringRange(line)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            // 강제 줄 높이 (비율/고정/최소)와 줄 사이 여백이 반영된 실제 줄 전진량은
            // 다음 라인 origin과의 y 델타다. 마지막 커밋 줄은 다음 origin이 있으면
            // (문자 예산으로 버린 줄) 그 델타를, 없으면(문단 끝) typographic 높이에
            // min/max 제약을 적용해 근사한다.
            let nextIndex = index + 1
            if nextIndex < keepCount || (nextIndex == keepCount && keepCount < lines.count) {
                totalLineHeight += max(1, origins[index].y - origins[nextIndex].y)
            } else {
                // 다음 origin이 없는 마지막 커밋 줄. 이어지는 청크면 다음 줄과의
                // 간격(lineSpacingAdjustment)도 더해 렌더(resumeBaseline)와 높이가
                // 맞는다 — 문단 끝 줄은 제외해 단일 청크 높이는 불변 (R51 #2).
                var lineAdvance = metrics.clampedLineHeight(ascent + descent + leading)
                if continuesAfterChunk {
                    lineAdvance += metrics.lineSpacingAdjustment
                }
                totalLineHeight += max(1, lineAdvance)
            }
            let attributedRange = NSRange(
                location: Int(range.location),
                length: Int(range.length)
            )
            lineFrames.append(
                HwpLineFrame(
                    origin: CGPoint(x: origin.x, y: yOffset + referenceY - origin.y),
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

    struct StyleValuePointers {
        let alignment: UnsafeMutablePointer<CTTextAlignment>
        let firstLineHeadIndent: UnsafeMutablePointer<CGFloat>
        let headIndent: UnsafeMutablePointer<CGFloat>
        let tailIndent: UnsafeMutablePointer<CGFloat>
        let paragraphSpacingBefore: UnsafeMutablePointer<CGFloat>
        let paragraphSpacing: UnsafeMutablePointer<CGFloat>
        let lineSpacing: UnsafeMutablePointer<CGFloat>
        let maximumLineSpacing: UnsafeMutablePointer<CGFloat>
        let minimumLineHeight: UnsafeMutablePointer<CGFloat>
        let maximumLineHeight: UnsafeMutablePointer<CGFloat>
        /// 문서 정의 탭 스톱 (비면 nil — CT 기본 탭 유지)
        let tabStops: UnsafeMutablePointer<CFArray>?

        init(metrics: ParagraphMetrics, alignment: CTTextAlignment) {
            self.alignment = Self.pointer(to: alignment)
            firstLineHeadIndent = Self.pointer(to: metrics.firstLineHeadIndent)
            headIndent = Self.pointer(to: metrics.headIndent)
            tailIndent = Self.pointer(to: metrics.tailIndent)
            paragraphSpacingBefore = Self.pointer(to: metrics.paragraphSpacingBefore)
            paragraphSpacing = Self.pointer(to: metrics.paragraphSpacing)
            lineSpacing = Self.pointer(to: metrics.lineSpacingAdjustment)
            // 줄 높이를 min=max로 강제할 때 폰트 leading 가산도 캡 —
            // 폴백 폰트의 leading이 줄 피치를 키운다 (noori +0.5pt 실측)
            maximumLineSpacing = Self.pointer(
                to: metrics.maximumLineHeight > 0
                    ? metrics.lineSpacingAdjustment : CGFloat.greatestFiniteMagnitude
            )
            minimumLineHeight = Self.pointer(to: metrics.minimumLineHeight)
            maximumLineHeight = Self.pointer(to: metrics.maximumLineHeight)
            tabStops = metrics.tabStops.isEmpty
                ? nil
                : Self.pointer(to: metrics.tabStops as CFArray)
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
            maximumLineSpacing.deinitialize(count: 1)
            maximumLineSpacing.deallocate()
            minimumLineHeight.deinitialize(count: 1)
            minimumLineHeight.deallocate()
            maximumLineHeight.deinitialize(count: 1)
            maximumLineHeight.deallocate()
            tabStops?.deinitialize(count: 1)
            tabStops?.deallocate()
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
        var settings = baseStyleSettings(from: pointers)
        if let tabStops = pointers.tabStops {
            settings.append(CTParagraphStyleSetting(
                spec: .tabStops,
                valueSize: MemoryLayout<CFArray>.size,
                value: tabStops
            ))
        }
        return settings
    }

    private func baseStyleSettings(
        from pointers: StyleValuePointers
    ) -> [CTParagraphStyleSetting] {
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
        ] + lineHeightSettings(from: pointers)
    }

    func lineHeightSettings(from pointers: StyleValuePointers) -> [CTParagraphStyleSetting] {
        [
            CTParagraphStyleSetting(
                spec: .lineSpacingAdjustment,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.lineSpacing
            ),
            CTParagraphStyleSetting(
                spec: .maximumLineSpacing,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.maximumLineSpacing
            ),
            CTParagraphStyleSetting(
                spec: .minimumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.minimumLineHeight
            ),
            CTParagraphStyleSetting(
                spec: .maximumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.maximumLineHeight
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
