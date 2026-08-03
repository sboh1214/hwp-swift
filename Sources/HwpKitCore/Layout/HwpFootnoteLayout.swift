import CoreGraphics
import CoreHwp
import Foundation

public struct HwpFootnoteBlock: @unchecked Sendable, Hashable {
    /// 페이지 좌표계 (top-left origin)의 각주 영역
    public let frame: CGRect
    /// 각주 문단 (텍스트 + 지오메트리 + paraId)
    public let paragraphs: [HwpLaidOutParagraph]
    /// 각주 번호 (구역 각주 모양의 시작 번호부터 이어짐)
    public let number: Int
    /// 구분선 영역 (첫 각주 블록 위). 페이지 좌표계.
    public let separatorLine: CGRect
    /// 구분선 색
    public let separatorColor: HwpRGBColor
    /// 각주 문단 안 그림 (블록-로컬 rect, #94)
    public let images: [HwpCellImage]
    /// 각주 문단 안 도형 (블록-로컬 rect, #94)
    public let shapes: [HwpCellShape]
    /// 각주 문단 안 글상자 (블록-로컬 rect, #94)
    public let textboxes: [HwpCellTextbox]
    /// 각주 문단 안 표 (블록-로컬 rect, #94). 한글.app 실측 (헌법주석 883쪽
    /// 각주 29): 표가 각주 영역 안에 그려지고 그 아래로 다음 각주가 이어진다.
    public let nestedTables: [HwpNestedTableFrame]

    public init(
        frame: CGRect,
        paragraphs: [HwpLaidOutParagraph],
        number: Int,
        separatorLine: CGRect,
        separatorColor: HwpRGBColor = HwpRGBColor(red: 0, green: 0, blue: 0),
        images: [HwpCellImage] = [],
        shapes: [HwpCellShape] = [],
        textboxes: [HwpCellTextbox] = [],
        nestedTables: [HwpNestedTableFrame] = []
    ) {
        self.frame = frame
        self.paragraphs = paragraphs
        self.number = number
        self.separatorLine = separatorLine
        self.separatorColor = separatorColor
        self.images = images
        self.shapes = shapes
        self.textboxes = textboxes
        self.nestedTables = nestedTables
    }

    /// 하위 호환: 문단 지오메트리만 필요할 때
    public var paragraphFrames: [HwpParagraphFrame] {
        paragraphs.map(\.frame)
    }
}

/// 페이지 하단 각주 영역 레이아웃.
///
/// 구분선 지오메트리 (길이/여백/색)는 구역 정의의 각주 모양 (HWPTAG_FOOTNOTE_SHAPE)에서
/// 가져오고, 길이가 자동(-1)이면 단 폭의 1/3을 쓴다.
public struct HwpFootnoteLayout {
    private let fontResolver: HwpFontResolver
    /// 각주 문단이 본문과 같은 글자 모양 속성 캐시를 쓰게 한다 (소유는 `HwpPaginator`).
    private let attributeCache: HwpTextAttributeCache?

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.init(fontResolver: fontResolver, attributeCache: nil)
    }

    /// 캐시를 주입하는 모듈 내부용 init (`HwpTextAttributeCache` 참조).
    init(fontResolver: HwpFontResolver, attributeCache: HwpTextAttributeCache?) {
        self.fontResolver = fontResolver
        self.attributeCache = attributeCache
    }

    public struct Input {
        public let paragraph: CoreHwp.HwpParagraph
        public let number: Int
        /// 이 각주를 **수집한 시점**의 크기 해석기 (R44 #1).
        ///
        /// `HwpPaginator.objectSizeResolver`는 현재 단·문단 폭을 읽는 계산
        /// 프로퍼티라 시점마다 값이 다르다. 예약은 수집 시점에 계산되는데 배치가
        /// 페이지 확정 시점의 값을 다시 읽으면, 그 사이 단 밴드가 바뀌거나 비등폭
        /// 단으로 넘어갔을 때 `.column`·`.paragraph` 기준 개체가 다른 크기로
        /// 재조판된다 (본문 겹침·없던 페이지 절단). 예약이 쓴 값을 그대로 실어
        /// 배치까지 들고 간다 — 예약 ≡ 배치의 **시간 축**이다.
        public let sizeResolver: HwpObjectSizeResolver?

        public init(
            paragraph: CoreHwp.HwpParagraph,
            number: Int,
            sizeResolver: HwpObjectSizeResolver? = nil
        ) {
            self.paragraph = paragraph
            self.number = number
            self.sizeResolver = sizeResolver
        }
    }

    /// 배치 결과: 이 페이지에 들어간 블록과 다음 페이지로 이월할 입력.
    public struct Placement {
        public let blocks: [HwpFootnoteBlock]
        public let overflow: [Input]
    }

    /// 페이지 하단에 배치할 각주 블록들을 계산한다.
    ///
    /// - Parameters:
    ///   - footnotes: 이 페이지의 각주 문단 + 문서 순서 번호
    ///   - geometry: 페이지 지오메트리
    ///   - index: id 매핑 인덱스
    ///   - footnoteShape: 구역의 각주 모양 (nil이면 기본값)
    /// - Returns: 페이지 좌표계의 각주 블록 (아래에서 위로 쌓아 올린 결과)
    public func layout(
        footnotes: [Input],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> [HwpFootnoteBlock] {
        place(
            footnotes: footnotes,
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        ).blocks
    }

    /// 각주 영역(콘텐츠 절반 상한)에 들어가는 만큼 배치하고 나머지는 이월로 돌려준다.
    /// 진행 보장을 위해 첫 각주는 영역보다 커도 항상 배치한다.
    /// limitsAreaToHalfContent: 흐름 조판에선 콘텐츠 절반 상한 (한글 기본 동작).
    /// 절대 캐시 모드에선 false — 한글이 이미 확정한 페이지의 각주는 참조
    /// 페이지에 전부 둔다 (이월하면 다음 페이지 예약이 한글에 없는 페이지
    /// 절단을 만든다 — 헌법주석 p485 실측).
    /// 예약 기하 — paginator가 본문 배치 전에 각주 영역 높이를 예측할 때
    /// 실제 배치 (place의 스택 산식)와 동형이 되도록 노출한다:
    /// 예약 = Σ 각주 높이 + spacingBetweenNotes × (노트 경계 수)
    ///       + separatorOverhead (페이지 첫 각주만).
    public struct ReservationMetrics {
        /// 구분선 위 여백 + 아래 여백 + 선 두께 (place의 stackHeight와 동일)
        public let separatorOverhead: CGFloat
        /// 서로 다른 번호의 노트 사이 간격 (같은 번호의 이어지는 문단은 0)
        public let spacingBetweenNotes: CGFloat
    }

    public func reservationMetrics(
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        contentWidth: CGFloat
    ) -> ReservationMetrics {
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: contentWidth
        )
        return ReservationMetrics(
            separatorOverhead: divider.marginTop + divider.marginBottom + divider.thickness,
            spacingBetweenNotes: divider.betweenNotes
        )
    }

    public func place(
        footnotes: [Input],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        limitsAreaToHalfContent: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> Placement {
        guard !footnotes.isEmpty else { return Placement(blocks: [], overflow: []) }

        let contentFrame = geometry.contentFrame
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: contentFrame.width
        )

        // 각 블록 높이를 먼저 계산한다.
        let measured = measure(
            footnotes,
            index: index,
            width: contentFrame.width,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        )

        // 페이지 하단에서 위로 필요한 만큼 확보하되 콘텐츠 절반을 넘지 않는다.
        // 같은 각주 컨트롤의 이어지는 문단 사이에는 간격이 없다 (stackBlocks와 동일).
        var notesHeight: CGFloat = 0
        var previousNumber: Int?
        for note in measured {
            if previousNumber != nil, previousNumber != note.input.number {
                notesHeight += divider.betweenNotes
            }
            notesHeight += note.blockHeight
            previousNumber = note.input.number
        }
        let stackHeight = notesHeight + divider.marginTop + divider.marginBottom
            + divider.thickness
        let areaHeight = limitsAreaToHalfContent
            ? min(contentFrame.height / 2, stackHeight)
            : stackHeight
        // 각주 영역 상단은 본문 상단 아래로 내려오지 못한다 (#95). 상한 없는
        // 배치 (절대 캐시 모드)에서 스택이 콘텐츠 높이를 넘으면 maxY − 높이가
        // contentFrame.minY보다 작아지고, 심하면 음수가 돼 각주 앞부분이 종이
        // 밖으로 잘려 **사라진다** (헌법주석 실측: 5쪽, 최악 −217.6pt).
        // 아래로 밀어내는 클램프라 이월이 생기지 않으므로 (stackFrame이 스택을
        // 그대로 담는다) 한글에 없는 각주 전용 페이지가 연쇄하지 않는다 — 강제
        // 이월이 그 페이지를 만든다 (실측 1,035쪽, `Sources/HwpKitCore/AGENTS.md`).
        // 절반 상한 모드는 areaHeight ≤ 콘텐츠/2라 이 클램프가 무동작이다.
        let areaTop = max(contentFrame.minY, contentFrame.maxY - areaHeight)

        let separatorLine = CGRect(
            x: contentFrame.minX,
            y: areaTop + divider.marginTop,
            width: divider.length,
            height: max(0.5, divider.thickness)
        )

        // 상한 없는 배치는 이월 없이 전부 페이지 하단 영역에 쌓는다
        let stackFrame = limitsAreaToHalfContent
            ? contentFrame
            : CGRect(
                x: contentFrame.minX,
                y: contentFrame.minY,
                width: contentFrame.width,
                height: max(contentFrame.height, areaTop + areaHeight - contentFrame.minY)
            )
        let stacked = stackBlocks(
            measured: measured,
            from: separatorLine.maxY + divider.marginBottom,
            in: stackFrame,
            separatorLine: separatorLine,
            divider: divider
        )
        return Placement(blocks: stacked.blocks, overflow: stacked.overflow)
    }

    /// 흐름 배치 결과: 배치된 블록, 이월 입력, 다음 흐름 y
    public struct FlowPlacement {
        public let blocks: [HwpFootnoteBlock]
        public let overflow: [Input]
        public let bottom: CGFloat
    }

    /// 미주처럼 흐름 위치에서 아래로 쌓는 배치 (문서/구역 끝).
    ///
    /// - Parameters:
    ///   - footnotes: 배치할 미주 문단 + 번호
    ///   - startY: 시작 y (페이지 좌표)
    ///   - columnFrame: 배치할 단 프레임 (maxY가 하한)
    ///   - drawSeparator: 첫 블록 위에 구분선을 둘지 (이월 연속 배치면 false)
    /// - Returns: columnFrame 하한을 넘는 입력은 overflow로 돌려준다.
    ///   진행 보장을 위해 첫 블록은 항상 배치한다.
    public func placeFlow(
        footnotes: [Input],
        from startY: CGFloat,
        in columnFrame: CGRect,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        drawSeparator: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> FlowPlacement {
        guard !footnotes.isEmpty else {
            return FlowPlacement(blocks: [], overflow: [], bottom: startY)
        }
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: columnFrame.width
        )
        let measured = measure(
            footnotes,
            index: index,
            width: columnFrame.width,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        )

        var cursorY = startY
        var separatorLine = CGRect(x: columnFrame.minX, y: startY, width: 0, height: 0)
        if drawSeparator {
            separatorLine = CGRect(
                x: columnFrame.minX,
                y: cursorY + divider.marginTop,
                width: divider.length,
                height: max(0.5, divider.thickness)
            )
            cursorY = separatorLine.maxY + divider.marginBottom
        }

        let stacked = stackBlocks(
            measured: measured,
            from: cursorY,
            in: columnFrame,
            separatorLine: separatorLine,
            divider: divider
        )
        return FlowPlacement(
            blocks: stacked.blocks,
            overflow: stacked.overflow,
            bottom: stacked.bottom
        )
    }

    /// 측정 끝난 각주들을 frame 폭으로 위에서 아래로 쌓는다.
    /// frame.maxY를 넘는 입력은 overflow로 돌려주되, 진행 보장을 위해
    /// 첫 블록은 항상 배치한다.
    private func stackBlocks(
        measured: [MeasuredFootnote],
        from startY: CGFloat,
        in frame: CGRect,
        separatorLine: CGRect,
        divider: DividerMetrics
    ) -> FlowPlacement {
        var blocks: [HwpFootnoteBlock] = []
        var overflow: [Input] = []
        var cursorY = startY
        var previousNumber: Int?
        for (noteIndex, note) in measured.enumerated() {
            // 같은 각주 컨트롤의 이어지는 문단은 간격 없이 붙인다
            // (헌법주석 실측: 한 각주의 문단 캐시 loc이 연속 — 내부 간격 0).
            if let previousNumber, previousNumber == note.input.number {
                cursorY -= divider.betweenNotes
            }
            let blockHeight = note.blockHeight
            if !blocks.isEmpty, cursorY + blockHeight > frame.maxY + 0.5 {
                overflow = measured[noteIndex...].map(\.input)
                break
            }
            previousNumber = note.input.number
            blocks.append(HwpFootnoteBlock(
                frame: CGRect(
                    x: frame.minX,
                    y: cursorY,
                    width: frame.width,
                    height: blockHeight
                ),
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: note.attributed,
                    frame: note.frame,
                    // 문단 rect는 **문단 자신의** 텍스트 높이다 — 떠 있는 개체가
                    // 블록을 키운 몫까지 문단이 흡수하면 문단-레벨 링크 폴백
                    // (`HwpHitTester.spanAwareHyperlinkURL`)이 개체 아래 빈
                    // 영역까지 자기 URL로 claim한다 (R39 #2). 컨테이너가 개체를
                    // 담는 높이는 블록 frame (blockHeight) 몫이다.
                    rect: CGRect(x: 0, y: 0, width: frame.width, height: note.textRectHeight),
                    paragraphId: note.input.paragraph.paraHeader.paraId,
                    hyperlinkURL: note.input.paragraph.hyperlinkURL
                )],
                number: note.input.number,
                separatorLine: separatorLine,
                separatorColor: divider.color,
                // 개체는 measure가 문단-로컬 (0, 0) 기준으로 수집했고, 문단 rect도
                // 블록-로컬 (0, 0)이라 그대로 블록-로컬 좌표다 (#94).
                images: note.objects.images,
                shapes: note.objects.shapes,
                textboxes: note.objects.textboxes,
                nestedTables: note.objects.nestedTables
            ))
            cursorY += blockHeight + divider.betweenNotes
        }
        return FlowPlacement(blocks: blocks, overflow: overflow, bottom: cursorY)
    }

    /// 높이 계산이 끝난 각주 문단 (+ 그 문단에 붙은 개체, 문단-로컬 rect)
    private struct MeasuredFootnote {
        let input: Input
        let measurement: NoteMeasurement

        var attributed: NSAttributedString {
            measurement.attributed
        }

        var frame: HwpParagraphFrame {
            measurement.frame
        }

        var objects: HwpParagraphObjectCollector.Objects {
            measurement.objects
        }

        var textRectHeight: CGFloat {
            measurement.textRectHeight
        }

        var blockHeight: CGFloat {
            measurement.blockHeight
        }
    }
}

// MARK: - 예약·배치 공유 측정

extension HwpFootnoteLayout {
    /// 각주 문단 하나의 측정 결과 — 텍스트·개체·높이.
    struct NoteMeasurement {
        let attributed: NSAttributedString
        let frame: HwpParagraphFrame
        let objects: HwpParagraphObjectCollector.Objects

        /// 문단 rect 높이 — **문단 자신의** 텍스트 높이. 블록 높이와 달리 개체
        /// 성장분을 포함하지 않는다 (R39 #2).
        var textRectHeight: CGFloat {
            max(1, frame.totalHeight)
        }

        /// 블록 높이 — 텍스트 높이와 **떠 있는** 개체 하단의 최대값 (#94).
        ///
        /// 글자처럼 취급 개체는 라인 캐시가 이미 담는 몫이라 (헌법주석 실측:
        /// 883쪽 각주 29의 408×62.52pt 표가 캐시 71.32pt 안에, 459쪽 각주 38의
        /// 9.6×10.8pt 그림이 3줄 36.96pt 안에 들어간다) 하한을 얹지 않는다 —
        /// 얹으면 캐시를 신뢰하는 규약이 깨져 페이지 절단이 한글과 어긋난다.
        /// 떠 있는 개체는 캐시에 없으므로 (한글.app 합성 실측 2026-07-30: 각주
        /// 문단에 떠 있는 도형을 붙이면 구분선이 위로 밀려 각주 영역이 개체를
        /// 담는다) `HwpParagraphObjectCollector.raisesContainerFloor` 술어로
        /// 담는다 — 떠 있는 개체와, 줄 앵커를 못 얻어 어떤 줄도 자리를 잡아
        /// 주지 않은 글자처럼 취급 개체 (R40 #1) 둘 다.
        var blockHeight: CGFloat {
            Swift.max(textRectHeight, objects.floatingBottom ?? 0)
        }
    }

    /// 각주 문단 하나를 재고 그 문단에 붙은 개체를 문단-로컬 rect로 수집한다.
    ///
    /// 예약 (`HwpFootnoteCoordinator`) 과 배치 (`stackBlocks`) 가 **이 함수
    /// 하나만** 쓴다 — 산식을 복제하면 두 경로가 갈려 각주 스택이 본문을 덮거나
    /// 한글에 없는 페이지 절단이 생긴다 (#94, R39 #1). 특히 줄 앵커 유무가 개체
    /// 높이 하한을 가르므로 (`escapesLineBox`) 양쪽이 **같은 프레임**을 봐야
    /// 한다 — 예약이 줄 없는 프레임으로 따로 재던 것이 R40 #1의 원인이었다.
    func measureNote(
        _ paragraph: CoreHwp.HwpParagraph,
        number: Int,
        width: CGFloat,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        sizeResolver: HwpObjectSizeResolver?
    ) -> NoteMeasurement {
        let noteResolver = sizeResolver?.forFootnoteArea(width: width)
        // 각주 첫머리의 자동 번호 (ext18) 마커를 번호 문자열로 치환한다 (번호는
        // paginator가 부여한 문서 순서 번호 — 본문 참조와 동일 소스). 스택
        // 높이는 한글 라인 캐시를 우선한다 (본문 절대 캐시와 동일 철학).
        let measured = HwpParagraphMeasurer(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: noteResolver,
            attributeCache: attributeCache
        )
        .measure(
            paragraph,
            width: width,
            options: .init(
                controlReplacements: HwpTextRunBuilder.autoNumberReplacements(
                    in: paragraph,
                    number: number,
                    footnoteShape: footnoteShape
                ),
                preferCachedHeight: true
            )
        )
        // 각주 문단에 붙은 개체 (그림/도형/글상자/표)는 각주 영역 안 콘텐츠다 —
        // 페이지 흐름 블록으로 방출하면 각주 밖에 그려진다 (#94). 표 셀과 같은
        // 수집기를 쓰되 표까지 담는다: 셀은 `PlacedCellContent.nestedTables`가
        // 따로 배치하지만 각주에는 그 경로가 없다.
        let collector = HwpParagraphObjectCollector(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: noteResolver,
            collectsTextboxes: true,
            attributeCache: attributeCache,
            collectsTables: true
        )
        return NoteMeasurement(
            attributed: measured.attributed,
            frame: measured.frame,
            objects: collector.objects(
                in: paragraph,
                frame: measured.frame,
                paragraphRect: Self.paragraphRect(
                    width: width, textHeight: measured.frame.totalHeight
                )
            )
        )
    }

    /// 각주 모양에서 해석한 구분선 지오메트리 (point 단위)
    private struct DividerMetrics {
        let marginTop: CGFloat
        let marginBottom: CGFloat
        let betweenNotes: CGFloat
        let length: CGFloat
        let color: HwpRGBColor
        let thickness: CGFloat
    }

    private func dividerMetrics(
        from divider: CoreHwp.HwpFootnoteDividerInfo?,
        contentWidth: CGFloat
    ) -> DividerMetrics {
        let length: CGFloat = if let length = divider?.length, length > 0 {
            min(contentWidth, HwpUnits.points(fromHwpUnit: length))
        } else {
            contentWidth / 3
        }
        return DividerMetrics(
            marginTop: max(0, points(
                fromHwpUnit16: divider?.marginTop,
                fallback: HwpRenderTuning.Footnote.dividerDefaultMarginTop
            )),
            marginBottom: max(0, points(
                fromHwpUnit16: divider?.marginBottom,
                fallback: HwpRenderTuning.Footnote.dividerDefaultMarginBottom
            )),
            betweenNotes: max(0, points(
                fromHwpUnit16: divider?.spacingBetweenNotes,
                fallback: HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes
            )),
            length: length,
            color: divider.map { HwpRGBColor($0.color) }
                ?? HwpRGBColor(red: 0, green: 0, blue: 0),
            thickness: divider.map {
                CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: $0.thickness))
            } ?? 1
        )
    }
}

// MARK: - 문단 측정 + 개체 수집

private extension HwpFootnoteLayout {
    private func measure(
        _ footnotes: [Input],
        index: HwpIndex,
        width: CGFloat,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> [MeasuredFootnote] {
        footnotes.map { input in
            MeasuredFootnote(
                input: input,
                measurement: measureNote(
                    input.paragraph,
                    number: input.number,
                    width: width,
                    index: index,
                    footnoteShape: footnoteShape,
                    // 수집 시점 해석기를 우선한다 — 인자는 그것이 없는 호출
                    // (테스트·직접 배치) 의 폴백이다 (R44 #1).
                    sizeResolver: input.sizeResolver ?? sizeResolver
                )
            )
        }
    }

    /// 개체 수집에 쓰는 문단-로컬 rect. `stackBlocks`의 문단 rect와 원점이 같아야
    /// 수집 좌표가 곧 블록-로컬 좌표다. 높이는 **텍스트 높이**를 쓴다 — 블록
    /// 높이는 이 수집 결과에서 나오므로 순환을 피하고, 예약 경로
    /// (`HwpFootnoteCoordinator`)가 같은 rect로 재수집해 값이 갈리지 않게 한다.
    internal static func paragraphRect(width: CGFloat, textHeight: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: textHeight)
    }

    func points(fromHwpUnit16 value: Int16?, fallback: CGFloat) -> CGFloat {
        guard let value else { return fallback }
        return HwpUnits.points(fromHwpUnit16: value)
    }
}

public extension HwpFootnoteBlock {
    /// 각주가 하이퍼링크를 품는지 — 블록-레벨 폴백의 게이트 (R61)
    var hasHyperlink: Bool {
        paragraphs.contains { $0.hasHyperlink }
            || images.contains { $0.wrapperURL != nil }
            || shapes.contains { $0.wrapperURL != nil }
            || textboxes.contains { $0.wrapperURL != nil || $0.textbox.hasHyperlink }
            || nestedTables.contains { $0.wrapperURL != nil || $0.table.hasHyperlink }
    }
}
