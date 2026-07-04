import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

public actor HwpPaginator {
    private let sections: [CoreHwp.HwpSection]
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    private let paintListBuilder: HwpPaintListBuilder
    private let unsupportedDetector = HwpUnsupportedDetector()
    private var nextSectionIndex = 0
    private var nextParagraphIndex = 0
    private var currentPageGeometry: HwpPageGeometry
    private var currentBlocks: [AnyHwpBlock] = []
    private var contentHeightUsed: CGFloat = 0
    private var didFinishPagination = false
    private var collectedUnsupported: [HwpUnsupportedElement] = []

    var cachedPages: [Int: HwpPage] = [:]

    public init(
        sections: [CoreHwp.HwpSection],
        index: HwpIndex,
        fontResolver: HwpFontResolver = HwpFontResolver()
    ) {
        self.sections = sections
        self.index = index
        self.fontResolver = fontResolver
        paintListBuilder = HwpPaintListBuilder(fontResolver: fontResolver)
        currentPageGeometry = Self.initialGeometry(for: sections)
    }

    public func page(at index: Int) async throws -> HwpPage? {
        guard index >= 0 else { return nil }
        if let page = cachedPages[index] { return page }

        while cachedPages[index] == nil, !didFinishPagination {
            await Task.yield()
            try await computeNextPage()
        }
        return cachedPages[index]
    }

    public func totalPages() async -> Int {
        while !didFinishPagination {
            await Task.yield()
            do {
                try await computeNextPage()
            } catch {
                break
            }
        }
        return max(1, cachedPages.count)
    }

    public func unsupportedElements() async -> [HwpUnsupportedElement] {
        collectedUnsupported
    }
}

private extension HwpPaginator {
    static func initialGeometry(for sections: [CoreHwp.HwpSection]) -> HwpPageGeometry {
        let firstSectionDef = sections.lazy
            .flatMap(\.paragraph)
            .compactMap { sectionDef(in: $0) }
            .first
        let sectionDef = firstSectionDef ?? CoreHwp.HwpSectionDef()
        return HwpPageGeometry.compute(pageDef: sectionDef.pageDef, sectionDef: sectionDef)
    }

    static func sectionDef(in paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpSectionDef? {
        paragraph.ctrlHeaderArray?.compactMap { ctrl in
            if case let .section(sectionDef) = ctrl {
                return sectionDef
            }
            return nil
        }.first
    }

    func computeNextPage() async throws {
        await Task.yield()

        if sections.isEmpty {
            cacheCurrentPage()
            didFinishPagination = true
            return
        }

        while let paragraph = nextParagraph() {
            if let sectionDef = Self.sectionDef(in: paragraph) {
                if !currentBlocks.isEmpty || contentHeightUsed > 0 {
                    cacheCurrentPage()
                    return
                }
                currentPageGeometry = HwpPageGeometry.compute(
                    pageDef: sectionDef.pageDef,
                    sectionDef: sectionDef
                )
            }

            let attributedString = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
                .build(paragraph: paragraph)
            let paragraphFrame = try await layout(paragraph, attributedString: attributedString)
            let paragraphHeight = height(for: paragraph, fallback: paragraphFrame.totalHeight)
            let contentHeight = currentPageGeometry.contentFrame.height
            if contentHeightUsed > 0, contentHeightUsed + paragraphHeight > contentHeight {
                cacheCurrentPage()
                return
            }

            appendBlock(
                height: paragraphHeight,
                attributedString: attributedString,
                hyperlinkURL: hyperlinkURL(in: paragraph)
            )
            appendEmbeddedBlocks(from: paragraph)
            collectUnsupported(from: paragraph)
            advanceParagraph()
            await Task.yield()
        }

        cacheCurrentPage()
        didFinishPagination = true
    }

    func layout(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString
    ) async throws -> HwpParagraphFrame {
        await Task.yield()
        guard let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
            ?? index.paraShape(id: 0)
        else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }
        return HwpParagraphLayout().layout(
            attributedString: attributedString,
            paraShape: paraShape,
            columnWidth: currentPageGeometry.contentFrame.width
        )
    }

    func nextParagraph() -> CoreHwp.HwpParagraph? {
        while sections.indices.contains(nextSectionIndex) {
            let paragraphs = sections[nextSectionIndex].paragraph
            if paragraphs.indices.contains(nextParagraphIndex) {
                return paragraphs[nextParagraphIndex]
            }
            nextSectionIndex += 1
            nextParagraphIndex = 0
        }
        return nil
    }

    func advanceParagraph() {
        nextParagraphIndex += 1
        while sections.indices.contains(nextSectionIndex),
              nextParagraphIndex >= sections[nextSectionIndex].paragraph.count
        {
            nextSectionIndex += 1
            nextParagraphIndex = 0
        }
    }

    func appendBlock(
        height: CGFloat,
        attributedString: NSAttributedString,
        hyperlinkURL: String? = nil
    ) {
        let immutable = NSAttributedString(attributedString: attributedString)
        let contentFrame = currentPageGeometry.contentFrame
        let frame = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY + contentHeightUsed,
            width: contentFrame.width,
            height: height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: immutable,
            hyperlinkURL: hyperlinkURL
        ))
        contentHeightUsed += height
    }

    func hyperlinkURL(in paragraph: CoreHwp.HwpParagraph) -> String? {
        guard let ctrls = paragraph.ctrlHeaderArray else { return nil }
        for ctrl in ctrls {
            if case let .hyperLink(link) = ctrl, !link.url.isEmpty {
                return link.url
            }
        }
        return nil
    }

    func collectUnsupported(from paragraph: CoreHwp.HwpParagraph) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        let page = cachedPages.count + 1
        walkUnsupported(ctrls: ctrls, page: page)
    }

    func walkUnsupported(ctrls: [CoreHwp.HwpCtrlId], page: Int) {
        for ctrl in ctrls {
            if let element = unsupportedDetector.classify(ctrl: ctrl, page: page) {
                collectedUnsupported.append(element)
            }
            for nested in nestedParagraphs(in: ctrl) {
                guard let nestedCtrls = nested.ctrlHeaderArray else { continue }
                walkUnsupported(ctrls: nestedCtrls, page: page)
            }
        }
    }

    func nestedParagraphs(in ctrl: CoreHwp.HwpCtrlId) -> [CoreHwp.HwpParagraph] {
        childParagraphs(of: ctrl).map(\.0)
    }

    /// Single traversal point for paragraph-bearing containers: both the
    /// unsupported-element walk and embedded-block emission consume this list,
    /// so a container added here is handled by both automatically.
    func childParagraphs(of ctrl: CoreHwp.HwpCtrlId) -> [(CoreHwp.HwpParagraph, HwpBlockKind)] {
        switch ctrl {
        case let .header(list), let .footer(list):
            list.listArray.flatMap(\.paragraphArray).map { ($0, HwpBlockKind.text) }
        case let .footnote(list), let .endnote(list):
            list.listArray.flatMap(\.paragraphArray).map { ($0, HwpBlockKind.footnote) }
        case let .table(table):
            table.cellArray.flatMap(\.paragraphArray).map { ($0, HwpBlockKind.table) }
        case let .shape(shape),
             let .line(shape),
             let .rectangle(shape),
             let .ellipse(shape),
             let .arc(shape),
             let .polygon(shape),
             let .curve(shape),
             let .equation(shape),
             let .equationLegacy(shape),
             let .picture(shape),
             let .ole(shape),
             let .container(shape):
            shape.shapeComponentArray
                .flatMap(\.textBoxListArray)
                .flatMap(\.paragraphArray)
                .map { ($0, HwpBlockKind.textbox) }
        case let .genShapeObject(genShape):
            genShape.shapeComponentArray
                .flatMap(\.textBoxListArray)
                .flatMap(\.paragraphArray)
                .map { ($0, HwpBlockKind.textbox) }
        default:
            []
        }
    }

    func appendEmbeddedBlocks(from paragraph: CoreHwp.HwpParagraph) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        let builder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let embeddedHeight: CGFloat = 20
        for (embeddedParagraph, kind) in embeddedParagraphs(from: ctrls) {
            let contentFrame = currentPageGeometry.contentFrame
            if contentHeightUsed > 0, contentHeightUsed + embeddedHeight > contentFrame.height {
                cacheCurrentPage()
            }
            let attributedString = NSAttributedString(
                attributedString: builder.build(paragraph: embeddedParagraph)
            )
            let frame = CGRect(
                x: contentFrame.minX,
                y: contentFrame.minY + contentHeightUsed,
                width: contentFrame.width,
                height: embeddedHeight
            )
            currentBlocks.append(AnyHwpBlock(
                frame: frame,
                kind: kind,
                attributedString: attributedString,
                hyperlinkURL: hyperlinkURL(in: embeddedParagraph)
            ))
            contentHeightUsed += embeddedHeight
        }
    }

    func embeddedParagraphs(
        from ctrls: [CoreHwp.HwpCtrlId]
    ) -> [(CoreHwp.HwpParagraph, HwpBlockKind)] {
        var result: [(CoreHwp.HwpParagraph, HwpBlockKind)] = []
        for ctrl in ctrls {
            for (para, kind) in childParagraphs(of: ctrl) {
                result.append((para, kind))
                appendNestedEmbedded(from: para, into: &result)
            }
        }
        return result
    }

    func appendNestedEmbedded(
        from paragraph: CoreHwp.HwpParagraph,
        into result: inout [(CoreHwp.HwpParagraph, HwpBlockKind)]
    ) {
        guard let subCtrls = paragraph.ctrlHeaderArray else { return }
        result.append(contentsOf: embeddedParagraphs(from: subCtrls))
    }

    func cacheCurrentPage() {
        let pageIndex = cachedPages.count
        let page = HwpPage(
            size: currentPageGeometry.pageSize,
            margins: currentPageGeometry.margins,
            blocks: currentBlocks,
            pageNumber: pageIndex + 1
        )
        let paintList = paintListBuilder.build(for: page, index: index)
        cachedPages[pageIndex] = HwpPage(
            size: page.size,
            margins: page.margins,
            blocks: page.blocks,
            pageNumber: page.pageNumber,
            paintList: paintList
        )
        currentBlocks = []
        contentHeightUsed = 0
    }

    func height(for paragraph: CoreHwp.HwpParagraph, fallback: CGFloat) -> CGFloat {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard isValidLineSegmentCache(segments) else { return fallback }
        let bottom = segments.reduce(Int32.min) { max($0, $1.lineLocation + max(0, $1.lineHeight)) }
        return max(0, HwpUnits.points(fromHwpUnit: bottom))
    }

    func isValidLineSegmentCache(_ segments: [CoreHwp.HwpParaLineSegInternal]) -> Bool {
        guard !segments.isEmpty else { return false }
        var previous = Int32.min
        for segment in segments {
            guard segment.lineLocation > previous, segment.lineHeight >= 0 else { return false }
            previous = segment.lineLocation
        }
        return true
    }
}
