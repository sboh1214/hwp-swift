import CoreGraphics
import CoreHwp
import CoreText
import Foundation

public extension HwpAttributedStringKey {
    /// treatAsChar 개체 마커가 예약한 줄 공간 높이 (NSNumber, pt) — 조각을 다른 단 폭으로
    /// 다시 풀 때 예약을 다시 읽는 열쇠다 (`HwpInlineObjectReservation`). 줄 상자 높이 자체는
    /// run delegate의 ascent에서 읽는다 (`HwpDrawnTextLayout.lineMetrics`).
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
    /// 줄 상자 상단 (문단 첫 줄 상자 상단 기준, 전진량 누적)
    public let origin: CGPoint
    public let width: CGFloat
    /// 줄 상자 상단에서 베이스라인 앵커까지 (`HwpDrawnTextLayout.baselineAnchor(of:in:)`)
    public let baseline: CGFloat
    public let attributedRange: NSRange
    /// 이 라인에 있는 컨트롤 마커 앵커들
    public let inlineAnchors: [HwpInlineAnchor]
    /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`, `HwpDrawnTextLayout.LineMetrics.boxHeight`) —
    /// 한글 문서는 `baseline` ÷ 0.85와 같고, MS 워드 호환 문서(#194)는 글꼴 줄 상자라
    /// `baseline`에서 역산할 수 없어 따로 든다. 컨테이너 내용 범위
    /// (`HwpContainerContentExtent`)가 마지막 줄 상자 아래를 이것으로 잰다.
    public let boxHeight: CGFloat
    /// 이 줄의 글자처럼 취급 개체 **바깥 상자**가 베이스라인에 맞추는 자리의 비율 — 바깥 상자
    /// 상단에서 그 자리까지가 상자 높이 × 이 값이다 (`HwpObjectAnchorGeometry.inlineAnchorOrigin`,
    /// #195). 한글 문서는 글자 상자와 같은 `HwpRenderTuning.Text.baselineAnchorRatio`(0.85),
    /// MS 워드 호환 문서는 1(바깥 상자 바닥이 베이스라인) —
    /// `HwpDrawnTextLayout.LineMetrics.inlineObjectBaselineRatio`. `boxHeight`처럼 문서 모델에
    /// 딸린 값이라 `baseline`에서 역산할 수 없어 따로 든다.
    public let objectBaselineRatio: CGFloat

    /// `boxHeight`를 주지 않으면 한글 문서의 규칙(`baseline` ÷ `baselineAnchorRatio`)으로
    /// 되푼다 — 줄 프레임을 직접 만드는 호출자(각주·표 조각의 복사)는 원본 값을 넘긴다.
    /// `objectBaselineRatio`도 같다 — 주지 않으면 한글 문서의 비율이다.
    public init(
        origin: CGPoint,
        width: CGFloat,
        baseline: CGFloat,
        attributedRange: NSRange,
        inlineAnchors: [HwpInlineAnchor] = [],
        boxHeight: CGFloat? = nil,
        objectBaselineRatio: CGFloat = HwpRenderTuning.Text.baselineAnchorRatio
    ) {
        self.origin = origin
        self.width = width
        self.baseline = baseline
        self.attributedRange = attributedRange
        self.inlineAnchors = inlineAnchors
        self.boxHeight = boxHeight ?? max(0, baseline) / HwpRenderTuning.Text.baselineAnchorRatio
        self.objectBaselineRatio = objectBaselineRatio
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
        cachedLineExtent(paragraph)?.advanceHeight
    }

    /// 유효한 라인 캐시의 줄 상자 범위 (HWPUNIT, 저장된 좌표계 그대로).
    ///
    /// `cachedParagraphHeight`(문단 전진량 = `advanceHeight`)와 표 셀 높이 (#160,
    /// `HwpTableLayout.cachedLineBoxHeight`)가 **같은 유효성 검사**를 나눠 쓴다 —
    /// 줄 위치가 순서대로 증가하고 줄 높이가 음수가 아니며 전진량이 0보다 클
    /// 때만 값이 있다.
    struct CachedLineExtent: Equatable {
        /// 첫 줄의 세로 위치
        let top: Int
        /// **마지막 세그먼트** 줄 상자의 아래 (`lineLocation + lineHeight`, 줄 간격 제외) — 셀
        /// 하한·세로 정렬의 끝이고, 겹친 줄에서도 최댓값이 아니다 (`HwpContainerContentExtent`).
        let bottom: Int
        /// 줄 간격까지 더한 전진량의 끝 (`HwpAbsoluteCachePlacer.lineBottom`의 최댓값).
        let spacedBottom: Int

        /// 첫 줄 위 ~ 마지막 줄 전진량 끝 (pt, 최소 1) — 문단 높이.
        var advanceHeight: CGFloat {
            max(1, HwpUnits.points(fromHwpUnit: Int32(clamping: spacedBottom - top)))
        }
    }

    static func cachedLineExtent(
        _ paragraph: CoreHwp.HwpParagraph
    ) -> CachedLineExtent? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !segments.isEmpty else { return nil }
        var previous = Int32.min
        var top = Int.max
        var bottom = Int.min
        var spacedBottom = Int.min
        for segment in segments {
            guard segment.lineLocation > previous, segment.lineHeight >= 0 else { return nil }
            previous = segment.lineLocation
            // 미신뢰 캐시의 Int32 덧셈 트랩 방지 — Int로 넓혀 누적한다.
            top = min(top, Int(segment.lineLocation))
            bottom = Int(segment.lineLocation) + Int(segment.lineHeight) // 증가 가드 → 마지막 줄
            spacedBottom = max(spacedBottom, HwpAbsoluteCachePlacer.lineBottom(of: segment))
        }
        guard spacedBottom > top else { return nil }
        return CachedLineExtent(top: top, bottom: bottom, spacedBottom: spacedBottom)
    }

    /// paraShape로 측정/렌더 공용 CTParagraphStyle을 만든다.
    /// HwpTextRunBuilder가 렌더 경로 (drawText 재조판)에도 같은 스타일을 부착해
    /// 측정 레이아웃 (정렬/들여쓰기, 인라인 앵커 x)과 일치시킨다.
    ///
    /// **줄 간격은 이 스타일이 나르지 않는다** — 줄 전진량은 `lineSpacingRule(for:)`가
    /// `HwpAttributedStringKey.lineSpacing`으로 실어야 하며, 둘을 함께 다는
    /// `attachParagraphStyle(to:paraShape:tabStops:)`를 쓰는 것이 맞다. 여기 남는 줄 높이
    /// 지정은 서식 복사와 규칙 표식이 없는 문자열의 폴백용 힌트다 (`ParagraphMetrics`).
    /// `attributedString`은 번호 라벨의 자동 내어쓰기 표식을 읽는 데 쓴다 (#154).
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

    /// paraShape의 줄 전진량 규칙 (표 46 종류 + 값, #180).
    public static func lineSpacingRule(for paraShape: CoreHwp.HwpParaShape) -> HwpLineSpacingRule {
        HwpLineSpacingRule(paraShape: paraShape)
    }

    /// 조판 문자열 전체에 문단 스타일(`kCTParagraphStyleAttributeName`)과 줄 전진량 규칙
    /// (`HwpAttributedStringKey.lineSpacing`)을 함께 단다 — `layout`(측정)과
    /// `HwpDrawnTextLayout.lines`(렌더)의 **입력 계약**이다. 프로덕션은
    /// `HwpTextRunBuilder.attachParagraphStyle`이 부르고, 문자열을 직접 만드는 호출부는
    /// 같은 paraShape로 이 함수를 불러야 두 경로가 같은 자리에 줄을 놓는다.
    public static func attachParagraphStyle(
        to output: NSMutableAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        tabStops: [CTTextTab] = []
    ) {
        guard output.length > 0 else { return }
        let range = NSRange(location: 0, length: output.length)
        output.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: paragraphStyle(for: paraShape, attributedString: output, tabStops: tabStops),
            range: range
        )
        output.addAttribute(
            HwpAttributedStringKey.lineSpacing,
            value: lineSpacingRule(for: paraShape).attributeValue,
            range: range
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
    /// `HwpParagraphLayout.attachParagraphStyle(to:paraShape:tabStops:)`를 **같은
    /// paraShape로** 불러 문단 스타일과 줄 간격 규칙을 함께 달아야 한다. 안 달면
    /// CT 기본값(natural 정렬)과 비율 100% 줄 간격으로 조판돼 렌더와 어긋난다.
    ///
    /// `paraShape`는 부착본이 나르지 **못하는** 것에만 쓴다 — 문단 위/아래 간격
    /// (`ParagraphMetrics`). 그래서 스타일을 부착한 paraShape와 **같은 값**이어야
    /// 한다. 줄 전진량은 부착본의 줄 간격 규칙(`HwpAttributedStringKey.lineSpacing`)에서
    /// 줄마다 낸다 (`HwpLineAdvance`).
    public func layout(
        attributedString: NSAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        columnWidth: CGFloat,
        maxLineFrames: Int = HwpParagraphLayout.maximumLineFrames
    ) -> HwpParagraphFrame {
        layout(
            attributedString: attributedString, paraShape: paraShape, columnWidth: columnWidth,
            maxLineFrames: maxLineFrames, metricsReference: nil
        )
    }

    /// `metricsReference`는 문단 지표(`ParagraphMetrics` — 번호 라벨 표식·문단 간격)를 뽑을
    /// 문자열이다. 문단의 **조각**을 다시 잴 때
    /// (`HwpPaginator.remeasureRemainderIfNeeded`·`HwpColumnBandController.rebalancedFragment`)
    /// 문단 전체 문자열을 넘긴다. 줄 전진량은 줄마다 그 줄의 글자로 정해지므로 (#180) 조각
    /// 부분 문자열로 재도 문단 전체와 같은 값이 나온다. nil이면 `attributedString` 자신이다.
    func layout(
        attributedString: NSAttributedString,
        paraShape: CoreHwp.HwpParaShape,
        columnWidth: CGFloat,
        maxLineFrames: Int = HwpParagraphLayout.maximumLineFrames,
        metricsReference: NSAttributedString?
    ) -> HwpParagraphFrame {
        // 빈 문자열은 높이 0이다 — 글꼴도 `hwp.baseFontSize`도 없어 `.percent`
        // 줄 간격이 줄 높이를 낼 수 없다. 빈 **문단**은 여기 오지 않는다: 빌더가
        // 첫 글자 모양·문단 스타일을 실은 빈 문단 앵커(#145)를 내므로 실물의
        // 한 줄 높이가 같은 코드로 계산된다. 길이 0은 상한으로 잘린 결과
        // (메모 표시 예산)뿐이다.
        guard attributedString.length > 0 else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }

        let paragraphMetrics = ParagraphMetrics(
            paraShape: paraShape,
            attributedString: metricsReference ?? attributedString
        )

        // slight-overflow 한 줄 (렌더와 같은 술어): 렌더가 한 줄로 그리는
        // 문단은 측정도 한 줄 높이여야 문단 높이 (= 페이지 절단)와 실제
        // 잉크가 일치한다 (B-1b).
        if let overflow = HwpDrawnTextLayout.slightOverflowLineMetrics(
            attributedString: attributedString, lineWidth: max(1, columnWidth)
        ) {
            // 한 줄의 전진량 — 렌더(`HwpDrawnTextLayout.lines`)의 청크 줄과 같은 규칙이다.
            let lineHeight = HwpLineAdvance.lineAdvance(
                of: overflow.line, at: 0, in: attributedString
            )
            let totalHeight = paragraphMetrics.paragraphSpacingBefore
                + lineHeight
                + paragraphMetrics.paragraphSpacing
            // 원점 x는 0 그대로다 — 렌더러의 정렬 오프셋을 여기 얹으면 단 폭과 같은
            // 글자처럼 취급 표(noori 1쪽, 마커 폭이 단 폭을 0.4pt 넘는다)가 가운데 정렬
            // 오프셋만큼 단 왼쪽 밖으로 밀린다 (한글은 단 왼쪽 끝). 조각 접기
            // (`fragmentLineFramesAsDrawn`)만 렌더러 오프셋을 따른다.
            let metrics = HwpDrawnTextLayout.lineMetrics(of: overflow.line, in: attributedString)
            let lineFrame = HwpLineFrame(
                origin: .zero,
                width: CGFloat(CTLineGetTypographicBounds(overflow.line, nil, nil, nil)),
                baseline: metrics.baselineAnchor,
                attributedRange: NSRange(location: 0, length: attributedString.length),
                inlineAnchors: inlineAnchors(in: overflow.line),
                boxHeight: metrics.boxHeight,
                objectBaselineRatio: metrics.inlineObjectBaselineRatio
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
                chunk: chunk, attributedString: attributedString, yOffset: totalLineHeight
            )
            lineFrames.append(contentsOf: frameLines)
            totalLineHeight += frameHeight
            guard chunk.nextStart > startLocation else { break }
            startLocation = chunk.nextStart
        }
        guard !lineFrames.isEmpty else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }
        // 문단 높이 = 위 간격 + 줄 전진량 합 (마지막 줄의 줄 간격 몫 포함 — 한글 캐시의
        // `lineHeight + lineSpacing` 합과 같다) + 아래 간격.
        let totalHeight = paragraphMetrics.paragraphSpacingBefore
            + totalLineHeight
            + paragraphMetrics.paragraphSpacing
        return HwpParagraphFrame(totalHeight: max(1, totalHeight), lines: lineFrames)
    }
}

private extension HwpParagraphLayout {
    /// 청크의 커밋된 줄들의 줄 프레임 — 원점 y는 **줄 상자 상단**(문단 첫 줄 상자 상단
    /// 기준, `yOffset`부터 전진량 누적)이고 `baseline`은 그 줄의 상자 상단 → 베이스라인
    /// 앵커다. 전진량은 렌더(`HwpDrawnTextLayout.lineGeometries`)와 같은
    /// `HwpLineAdvance.advances(of:in:)`에서 온다 — 마지막 커밋 줄 뒤에 다음 청크가
    /// 이어지면 그 사이 문단 간격까지 든 값이라 청크 경계에서 위치 오차가 쌓이지 않는다.
    func makeLineFrames(
        chunk: HwpLineBreaker.FrameChunk,
        attributedString: NSAttributedString,
        yOffset: CGFloat = 0
    ) -> (frames: [HwpLineFrame], totalLineHeight: CGFloat) {
        let advances = HwpLineAdvance.advances(of: chunk, in: attributedString)
        var lineFrames: [HwpLineFrame] = []
        lineFrames.reserveCapacity(chunk.keepCount)
        var totalLineHeight: CGFloat = 0

        for index in 0 ..< chunk.keepCount {
            let line = chunk.lines[index]
            let range = CTLineGetStringRange(line)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let metrics = HwpDrawnTextLayout.lineMetrics(of: line, in: attributedString)
            lineFrames.append(
                HwpLineFrame(
                    origin: CGPoint(x: chunk.origins[index].x, y: yOffset + totalLineHeight),
                    width: width,
                    baseline: metrics.baselineAnchor,
                    attributedRange: NSRange(
                        location: Int(range.location),
                        length: Int(range.length)
                    ),
                    inlineAnchors: inlineAnchors(in: line),
                    boxHeight: metrics.boxHeight,
                    objectBaselineRatio: metrics.inlineObjectBaselineRatio
                )
            )
            totalLineHeight += advances[index]
        }

        return (lineFrames, totalLineHeight)
    }

    struct StyleValuePointers {
        let alignment: UnsafeMutablePointer<CTTextAlignment>
        let firstLineHeadIndent: UnsafeMutablePointer<CGFloat>
        let headIndent: UnsafeMutablePointer<CGFloat>
        let tailIndent: UnsafeMutablePointer<CGFloat>
        let paragraphSpacingBefore: UnsafeMutablePointer<CGFloat>
        let paragraphSpacing: UnsafeMutablePointer<CGFloat>
        let lineSpacing: UnsafeMutablePointer<CGFloat>
        let lineHeightMultiple: UnsafeMutablePointer<CGFloat>
        let minimumLineHeight: UnsafeMutablePointer<CGFloat>
        /// 문서 정의 탭 스톱 (비면 nil — CT 기본 탭 유지)
        let tabStops: UnsafeMutablePointer<CFArray>?

        init(metrics: ParagraphMetrics, alignment: CTTextAlignment) {
            self.alignment = Self.pointer(to: alignment)
            firstLineHeadIndent = Self.pointer(to: metrics.firstLineHeadIndent)
            headIndent = Self.pointer(to: metrics.headIndent)
            tailIndent = Self.pointer(to: metrics.tailIndent)
            paragraphSpacingBefore = Self.pointer(to: metrics.paragraphSpacingBefore)
            paragraphSpacing = Self.pointer(to: metrics.paragraphSpacing)
            // 줄 높이 힌트 셋 — 세로 배치는 `HwpAttributedStringKey.lineSpacing`의 규칙이
            // 하고 (`HwpLineAdvance`), 이 값들은 서식 복사와 폴백에만 남는다. 상한
            // (`maximumLineHeight`)은 두지 않는다 — CT가 그 높이에 안 들어가는 글자가 있는
            // 줄을 놓지 않아 문단이 사라진다 (#202).
            lineSpacing = Self.pointer(to: metrics.lineSpacingAdjustment)
            lineHeightMultiple = Self.pointer(to: metrics.lineHeightMultiple)
            minimumLineHeight = Self.pointer(to: metrics.minimumLineHeight)
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
            lineHeightMultiple.deinitialize(count: 1)
            lineHeightMultiple.deallocate()
            minimumLineHeight.deinitialize(count: 1)
            minimumLineHeight.deallocate()
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
                spec: .lineHeightMultiple,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.lineHeightMultiple
            ),
            CTParagraphStyleSetting(
                spec: .minimumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointers.minimumLineHeight
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
