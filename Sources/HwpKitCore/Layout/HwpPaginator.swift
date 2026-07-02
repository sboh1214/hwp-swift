import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

public actor HwpPaginator {
    private let sections: [CoreHwp.HwpSection]
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    private var nextSectionIndex = 0
    private var nextParagraphIndex = 0
    private var currentPageGeometry: HwpPageGeometry
    private var currentBlocks: [AnyHwpBlock] = []
    private var contentHeightUsed: CGFloat = 0
    private var didFinishPagination = false

    var cachedPages: [Int: HwpPage] = [:]

    public init(
        sections: [CoreHwp.HwpSection],
        index: HwpIndex,
        fontResolver: HwpFontResolver = HwpFontResolver()
    ) {
        self.sections = sections
        self.index = index
        self.fontResolver = fontResolver
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
        await Task.yield()
        return max(1, cachedPages.count)
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
                currentPageGeometry = HwpPageGeometry.compute(pageDef: sectionDef.pageDef, sectionDef: sectionDef)
            }

            let paragraphFrame = try await layout(paragraph)
            let paragraphHeight = height(for: paragraph, fallback: paragraphFrame.totalHeight)
            let contentHeight = currentPageGeometry.contentFrame.height
            if contentHeightUsed > 0, contentHeightUsed + paragraphHeight > contentHeight {
                cacheCurrentPage()
                return
            }

            appendBlock(height: paragraphHeight)
            advanceParagraph()
            await Task.yield()
        }

        cacheCurrentPage()
        didFinishPagination = true
    }

    func layout(_ paragraph: CoreHwp.HwpParagraph) async throws -> HwpParagraphFrame {
        await Task.yield()
        let attributedString = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
            .build(paragraph: paragraph)
        guard let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
            ?? index.paraShape(id: 0)
        else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }
        return HwpParagraphLayout(fontResolver: fontResolver).layout(
            attributedString: attributedString,
            paraShape: paraShape,
            columnWidth: currentPageGeometry.contentFrame.width
        )
    }

    func nextParagraph() -> CoreHwp.HwpParagraph? {
        var sectionIndex = nextSectionIndex
        var paragraphIndex = nextParagraphIndex
        while sections.indices.contains(sectionIndex) {
            let paragraphs = sections[sectionIndex].paragraph
            if paragraphs.indices.contains(paragraphIndex) {
                return paragraphs[paragraphIndex]
            }
            sectionIndex += 1
            paragraphIndex = 0
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

    func appendBlock(height: CGFloat) {
        let contentFrame = currentPageGeometry.contentFrame
        let frame = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY + contentHeightUsed,
            width: contentFrame.width,
            height: height
        )
        currentBlocks.append(AnyHwpBlock(frame: frame, kind: .text))
        contentHeightUsed += height
    }

    func cacheCurrentPage() {
        let pageIndex = cachedPages.count
        cachedPages[pageIndex] = HwpPage(
            size: currentPageGeometry.pageSize,
            margins: currentPageGeometry.margins,
            blocks: currentBlocks,
            pageNumber: pageIndex + 1
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
