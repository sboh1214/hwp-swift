import CoreGraphics
@preconcurrency import CoreHwp
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

    public init(
        frame: CGRect,
        paragraphs: [HwpLaidOutParagraph],
        number: Int,
        separatorLine: CGRect,
        separatorColor: HwpRGBColor = HwpRGBColor(red: 0, green: 0, blue: 0)
    ) {
        self.frame = frame
        self.paragraphs = paragraphs
        self.number = number
        self.separatorLine = separatorLine
        self.separatorColor = separatorColor
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

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public struct Input {
        public let paragraph: CoreHwp.HwpParagraph
        public let number: Int

        public init(paragraph: CoreHwp.HwpParagraph, number: Int) {
            self.paragraph = paragraph
            self.number = number
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
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil
    ) -> [HwpFootnoteBlock] {
        place(
            footnotes: footnotes,
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape
        ).blocks
    }

    /// 각주 영역(콘텐츠 절반 상한)에 들어가는 만큼 배치하고 나머지는 이월로 돌려준다.
    /// 진행 보장을 위해 첫 각주는 영역보다 커도 항상 배치한다.
    public func place(
        footnotes: [Input],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil
    ) -> Placement {
        guard !footnotes.isEmpty else { return Placement(blocks: [], overflow: []) }

        let contentFrame = geometry.contentFrame
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: contentFrame.width
        )

        // 각 블록 높이를 먼저 계산한다.
        let measured = measure(footnotes, index: index, width: contentFrame.width)

        // 페이지 하단에서 위로 필요한 만큼 확보하되 콘텐츠 절반을 넘지 않는다.
        let notesHeight = measured.reduce(CGFloat(0)) { $0 + max(1, $1.frame.totalHeight) }
            + divider.betweenNotes * CGFloat(max(0, measured.count - 1))
        let areaHeight = min(
            contentFrame.height / 2,
            notesHeight + divider.marginTop + divider.marginBottom + divider.thickness
        )
        let areaTop = contentFrame.maxY - areaHeight

        let separatorLine = CGRect(
            x: contentFrame.minX,
            y: areaTop + divider.marginTop,
            width: divider.length,
            height: max(0.5, divider.thickness)
        )

        var blocks: [HwpFootnoteBlock] = []
        var overflow: [Input] = []
        var cursorY = separatorLine.maxY + divider.marginBottom
        for (noteIndex, note) in measured.enumerated() {
            let blockHeight = max(1, note.frame.totalHeight)
            if !blocks.isEmpty, cursorY + blockHeight > contentFrame.maxY + 0.5 {
                overflow = measured[noteIndex...].map(\.input)
                break
            }
            let blockFrame = CGRect(
                x: contentFrame.minX,
                y: cursorY,
                width: contentFrame.width,
                height: blockHeight
            )
            blocks.append(HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: note.attributed,
                    frame: note.frame,
                    rect: CGRect(x: 0, y: 0, width: contentFrame.width, height: blockHeight),
                    paragraphId: note.input.paragraph.paraHeader.paraId
                )],
                number: note.input.number,
                separatorLine: separatorLine,
                separatorColor: divider.color
            ))
            cursorY += blockHeight + divider.betweenNotes
        }
        return Placement(blocks: blocks, overflow: overflow)
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
        drawSeparator: Bool = true
    ) -> FlowPlacement {
        guard !footnotes.isEmpty else {
            return FlowPlacement(blocks: [], overflow: [], bottom: startY)
        }
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: columnFrame.width
        )
        let measured = measure(footnotes, index: index, width: columnFrame.width)

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

        var blocks: [HwpFootnoteBlock] = []
        var overflow: [Input] = []
        for (noteIndex, note) in measured.enumerated() {
            let blockHeight = max(1, note.frame.totalHeight)
            if !blocks.isEmpty, cursorY + blockHeight > columnFrame.maxY + 0.5 {
                overflow = measured[noteIndex...].map(\.input)
                break
            }
            blocks.append(HwpFootnoteBlock(
                frame: CGRect(
                    x: columnFrame.minX,
                    y: cursorY,
                    width: columnFrame.width,
                    height: blockHeight
                ),
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: note.attributed,
                    frame: note.frame,
                    rect: CGRect(x: 0, y: 0, width: columnFrame.width, height: blockHeight),
                    paragraphId: note.input.paragraph.paraHeader.paraId
                )],
                number: note.input.number,
                separatorLine: separatorLine,
                separatorColor: divider.color
            ))
            cursorY += blockHeight + divider.betweenNotes
        }
        return FlowPlacement(blocks: blocks, overflow: overflow, bottom: cursorY)
    }

    /// 높이 계산이 끝난 각주 문단
    private struct MeasuredFootnote {
        let input: Input
        let attributed: NSAttributedString
        let frame: HwpParagraphFrame
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
            marginTop: max(0, points(fromHwpUnit16: divider?.marginTop, fallback: 8.5)),
            marginBottom: max(0, points(fromHwpUnit16: divider?.marginBottom, fallback: 5.7)),
            betweenNotes: max(
                0,
                points(fromHwpUnit16: divider?.spacingBetweenNotes, fallback: 2.8)
            ),
            length: length,
            color: divider.map { HwpRGBColor($0.color) }
                ?? HwpRGBColor(red: 0, green: 0, blue: 0),
            thickness: divider.map {
                CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: $0.thickness))
            } ?? 1
        )
    }

    private func measure(
        _ footnotes: [Input],
        index: HwpIndex,
        width: CGFloat
    ) -> [MeasuredFootnote] {
        let textRunBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout()
        return footnotes.map { input in
            let attributed = textRunBuilder.build(paragraph: input.paragraph)
            let paraShape = index.paraShape(id: UInt32(input.paragraph.paraHeader.paraShapeId))
                ?? index.paraShape(id: 0)
                ?? CoreHwp.HwpParaShape()
            let frame = paragraphLayout.layout(
                attributedString: attributed,
                paraShape: paraShape,
                columnWidth: width
            )
            return MeasuredFootnote(input: input, attributed: attributed, frame: frame)
        }
    }

    private func points(fromHwpUnit16 value: Int16?, fallback: CGFloat) -> CGFloat {
        guard let value else { return fallback }
        return HwpUnits.points(fromHwpUnit16: value)
    }
}
