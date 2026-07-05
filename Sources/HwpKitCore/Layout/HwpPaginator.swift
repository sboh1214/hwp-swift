import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

// swiftlint:disable file_length

public actor HwpPaginator {
    private let sections: [CoreHwp.HwpSection]
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    private let imageStore: HwpImageStore
    private let paintListBuilder: HwpPaintListBuilder
    private let unsupportedDetector = HwpUnsupportedDetector()
    private let tableLayout: HwpTableLayout
    private let textboxLayout: HwpTextboxLayout
    private let footnoteLayout: HwpFootnoteLayout
    private var nextSectionIndex = 0
    private var nextParagraphIndex = 0
    private var currentPageGeometry: HwpPageGeometry
    private var currentSectionDef: CoreHwp.HwpSectionDef?
    private var currentBlocks: [AnyHwpBlock] = []
    private var contentHeightUsed: CGFloat = 0
    private var didFinishPagination = false
    private var collectedUnsupported: [HwpUnsupportedElement] = []
    /// 이 페이지에 배치할 각주 (문단 + 문서 순서 번호)
    private var pendingFootnotes: [HwpFootnoteLayout.Input] = []
    /// 각주 영역이 차지할 높이 (본문 overflow 검사에 반영)
    private var footnoteReservedHeight: CGFloat = 0
    /// 현재 문단의 현재-페이지 상단 y (문단 기준 앵커의 기준점).
    /// 페이지가 넘어가면 새 페이지 콘텐츠 상단으로 재설정된다.
    private var paragraphAnchorTop: CGFloat = 0
    private var footnoteCounter = 0
    /// 구역의 활성 머리말/꼬리말 (적용 범위별, 표 141).
    /// 컨트롤을 만난 이후의 모든 페이지에 반복 방출되며, 같은 범위의
    /// 새 컨트롤이 나오면 교체된다.
    private var activeHeaders: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl] = [:]
    private var activeFooters: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl] = [:]

    var cachedPages: [Int: HwpPage] = [:]

    public init(
        sections: [CoreHwp.HwpSection],
        index: HwpIndex,
        fontResolver: HwpFontResolver = HwpFontResolver(),
        imageStore: HwpImageStore = HwpImageStore()
    ) {
        self.sections = sections
        self.index = index
        self.fontResolver = fontResolver
        self.imageStore = imageStore
        paintListBuilder = HwpPaintListBuilder(fontResolver: fontResolver, imageStore: imageStore)
        tableLayout = HwpTableLayout(fontResolver: fontResolver)
        textboxLayout = HwpTextboxLayout(fontResolver: fontResolver)
        footnoteLayout = HwpFootnoteLayout(fontResolver: fontResolver)
        currentPageGeometry = Self.initialGeometry(for: sections)
        currentSectionDef = Self.firstSectionDef(for: sections)
        footnoteCounter = Self.initialFootnoteNumber(for: currentSectionDef)
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
    static func firstSectionDef(for sections: [CoreHwp.HwpSection]) -> CoreHwp.HwpSectionDef? {
        sections.lazy
            .flatMap(\.paragraph)
            .compactMap { sectionDef(in: $0) }
            .first
    }

    static func initialGeometry(for sections: [CoreHwp.HwpSection]) -> HwpPageGeometry {
        let sectionDef = firstSectionDef(for: sections) ?? CoreHwp.HwpSectionDef()
        return HwpPageGeometry.compute(pageDef: sectionDef.pageDef, sectionDef: sectionDef)
    }

    static func initialFootnoteNumber(for sectionDef: CoreHwp.HwpSectionDef?) -> Int {
        let starting = Int(sectionDef?.footNoteShape.startingNumber ?? 1)
        return starting > 0 ? starting : 1
    }

    static func sectionDef(in paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpSectionDef? {
        paragraph.ctrlHeaderArray?.compactMap { ctrl in
            if case let .section(sectionDef) = ctrl {
                return sectionDef
            }
            return nil
        }.first
    }

    // MARK: - Page flow

    var effectiveContentHeight: CGFloat {
        max(1, currentPageGeometry.contentFrame.height - footnoteReservedHeight)
    }

    func computeNextPage() async throws {
        await Task.yield()

        if sections.isEmpty {
            cacheCurrentPage()
            didFinishPagination = true
            return
        }

        let pageCountBefore = cachedPages.count

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
                currentSectionDef = sectionDef
                if sectionDef.footNoteShape.numberingModeRawValue != 0 {
                    footnoteCounter = Self.initialFootnoteNumber(for: sectionDef)
                }
            }

            let attributedString = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
                .build(paragraph: paragraph)
            let paragraphFrame = try await layout(paragraph, attributedString: attributedString)
            let paragraphHeight = height(for: paragraph, fallback: paragraphFrame.totalHeight)
            // 이 문단이 만들 각주 예약 높이를 미리 반영해 본문/각주 겹침을 막는다.
            let anticipatedFootnotes = anticipatedFootnoteHeight(for: paragraph)
            if contentHeightUsed > 0,
               contentHeightUsed + paragraphHeight
               > effectiveContentHeight - anticipatedFootnotes
            {
                cacheCurrentPage()
                return
            }

            paragraphAnchorTop = currentPageGeometry.contentFrame.minY + contentHeightUsed
            appendBlock(
                height: paragraphHeight,
                attributedString: attributedString,
                hyperlinkURL: hyperlinkURL(in: paragraph),
                paragraphId: paragraph.paraHeader.paraId
            )
            collectFootnotes(from: paragraph)
            appendControlBlocks(from: paragraph)
            collectUnsupported(from: paragraph)
            advanceParagraph()
            await Task.yield()

            // 이 호출에서 이미 페이지가 생겼으면 반환해 호출자가 진행을 관찰하게 한다.
            if cachedPages.count > pageCountBefore {
                return
            }
        }

        cacheCurrentPage()
        // 마지막 페이지에서 넘친 각주가 있으면 빈 페이지를 이어 붙여 모두 배치한다.
        while !pendingFootnotes.isEmpty {
            cacheCurrentPage()
        }
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
        hyperlinkURL: String? = nil,
        paragraphId: UInt32? = nil
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
            hyperlinkURL: hyperlinkURL,
            source: HwpBlockSource(paragraphId: paragraphId)
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

    // MARK: - Unsupported walk (단일 traversal 지점 유지)

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
            for nested in childParagraphs(of: ctrl).map(\.0) {
                guard let nestedCtrls = nested.ctrlHeaderArray else { continue }
                walkUnsupported(ctrls: nestedCtrls, page: page)
            }
        }
    }

    /// paragraph-bearing 컨테이너의 단일 traversal 지점.
    /// unsupported walk가 사용하며, 새 컨테이너는 여기 추가하면
    /// 렌더 경로 (appendControlBlocks)와 함께 관리된다.
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

    // MARK: - 컨트롤 블록 방출

    /// 문단에 붙은 컨트롤을 실제 레이아웃 엔진으로 방출한다.
    /// depth는 컨테이너 안 컨테이너 재귀 제한 (표 안 글상자 등).
    func appendControlBlocks(from paragraph: CoreHwp.HwpParagraph, depth: Int = 0) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        for ctrl in ctrls {
            switch ctrl {
            case let .table(table):
                appendTableBlocks(table)
                appendNestedControlBlocks(of: ctrl, depth: depth)
            case let .genShapeObject(genShape):
                appendShapeObjectBlocks(
                    components: genShape.shapeComponentArray,
                    commonProperty: genShape.commonCtrlProperty
                )
                appendNestedControlBlocks(of: ctrl, depth: depth)
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
                appendShapeObjectBlocks(
                    components: shape.shapeComponentArray,
                    commonProperty: shape.commonCtrlProperty
                        ?? CoreHwp.HwpCommonCtrlProperty()
                )
                appendNestedControlBlocks(of: ctrl, depth: depth)
            case let .header(list):
                activeHeaders[list.headerFooterApplyScope] = list
            case let .footer(list):
                activeFooters[list.headerFooterApplyScope] = list
            case .footnote, .endnote:
                // 각주/미주는 collectFootnotes(from:depth:)가 컨트롤 블록 방출 전에
                // 수집한다 (참조 위치 페이지 귀속).
                continue
            default:
                continue
            }
        }
    }

    /// 컨테이너 문단 안에 중첩된 컨트롤 (표 셀 안 글상자/이미지 등)을 재귀 방출한다.
    func appendNestedControlBlocks(of ctrl: CoreHwp.HwpCtrlId, depth: Int) {
        guard depth < 3 else { return }
        for (nested, _) in childParagraphs(of: ctrl) where nested.ctrlHeaderArray != nil {
            appendControlBlocks(from: nested, depth: depth + 1)
        }
    }

    // MARK: 표

    func appendTableBlocks(_ table: CoreHwp.HwpTable) {
        let contentFrame = currentPageGeometry.contentFrame
        let result = tableLayout.layout(
            table: table,
            availableWidth: contentFrame.width,
            index: index
        )
        switch result {
        case let .failure(element):
            collectedUnsupported.append(HwpUnsupportedElement(
                kind: element.kind,
                page: cachedPages.count + 1,
                hint: element.hint
            ))
            appendPlaceholderBlock(hint: element.hint)
        case let .success(frame):
            appendTableSegments(
                frame,
                instanceId: table.commonCtrlProperty.instanceId
            )
        }
    }

    /// 표를 남은 공간에 맞춰 row 단위로 잘라 페이지에 흘린다.
    func appendTableSegments(_ frame: HwpTableFrame, instanceId: UInt32) {
        guard !frame.rows.isEmpty else { return }
        var remainingRows = frame.rows

        while !remainingRows.isEmpty {
            var remaining = effectiveContentHeight - contentHeightUsed
            if remaining < minimumRowHeight(remainingRows), contentHeightUsed > 0 {
                cacheCurrentPage()
                remaining = effectiveContentHeight
            }

            var segmentRows: [HwpTableRowFrame] = []
            var segmentHeight: CGFloat = 0
            while let row = remainingRows.first {
                let rowHeight = row.rowFrame.height
                if segmentHeight > 0, segmentHeight + rowHeight > remaining {
                    break
                }
                segmentRows.append(row)
                segmentHeight += rowHeight
                remainingRows.removeFirst()
                if segmentHeight >= remaining { break }
            }
            guard !segmentRows.isEmpty else { break }

            appendTableSegmentBlock(
                rows: segmentRows,
                original: frame,
                instanceId: instanceId
            )
        }
    }

    func minimumRowHeight(_ rows: [HwpTableRowFrame]) -> CGFloat {
        rows.first?.rowFrame.height ?? 1
    }

    func appendTableSegmentBlock(
        rows: [HwpTableRowFrame],
        original: HwpTableFrame,
        instanceId: UInt32
    ) {
        guard let firstRow = rows.first else { return }
        let yShift = firstRow.rowFrame.minY
        let shiftedRows = rows.map { shifted(row: $0, deltaY: -yShift) }
        let segmentHeight = shiftedRows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
        let segmentFrame = HwpTableFrame(
            outerFrame: CGRect(
                x: 0,
                y: 0,
                width: original.outerFrame.width,
                height: segmentHeight
            ),
            rows: shiftedRows,
            borderColor: original.borderColor,
            borderWidth: original.borderWidth
        )

        let contentFrame = currentPageGeometry.contentFrame
        let blockFrame = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY + contentHeightUsed,
            width: segmentFrame.outerFrame.width,
            height: segmentHeight
        )
        currentBlocks.append(AnyHwpBlock(
            frame: blockFrame,
            kind: .table,
            payload: .table(segmentFrame),
            source: HwpBlockSource(controlInstanceId: instanceId)
        ))
        contentHeightUsed += segmentHeight
    }

    /// 행/셀/문단 지오메트리를 deltaY만큼 이동한 사본을 만든다.
    private func shifted(row: HwpTableRowFrame, deltaY: CGFloat) -> HwpTableRowFrame {
        HwpTableRowFrame(
            rowFrame: row.rowFrame.offsetBy(dx: 0, dy: deltaY),
            cells: row.cells.map { cell in
                HwpTableCellFrame(
                    cellFrame: cell.cellFrame.offsetBy(dx: 0, dy: deltaY),
                    row: cell.row,
                    column: cell.column,
                    rowSpan: cell.rowSpan,
                    columnSpan: cell.columnSpan,
                    paragraphs: cell.paragraphs.map { paragraph in
                        HwpLaidOutParagraph(
                            attributedString: paragraph.attributedString,
                            frame: paragraph.frame,
                            rect: paragraph.rect.offsetBy(dx: 0, dy: deltaY),
                            paragraphId: paragraph.paragraphId
                        )
                    },
                    borders: cell.borders,
                    fillColor: cell.fillColor
                )
            }
        )
    }

    // MARK: 개체 (글상자/도형/그림)

    func appendShapeObjectBlocks(
        components: [CoreHwp.HwpShapeComponent],
        commonProperty: CoreHwp.HwpCommonCtrlProperty
    ) {
        let size = objectSize(commonProperty: commonProperty, components: components)

        if let textboxFrame = textboxLayout.layout(
            components: components,
            commonProperty: commonProperty,
            fallbackWidth: currentPageGeometry.contentFrame.width,
            index: index
        ) {
            appendAnchoredBlock(
                kind: .textbox,
                size: textboxFrame.outerFrame.size,
                payload: .textbox(textboxFrame),
                commonProperty: commonProperty,
                attributedText: textboxFrame.paragraphs.map(\.attributedString)
            )
        }

        for component in components {
            if let picture = component.pictureArray.first {
                appendImageBlock(
                    picture: picture,
                    component: component,
                    commonProperty: commonProperty,
                    size: size
                )
            } else if component.textBoxListArray.isEmpty,
                      let geometry = HwpShapeGeometry.build(component: component, size: size)
            {
                appendAnchoredBlock(
                    kind: .shape,
                    size: size,
                    payload: .shape(geometry),
                    commonProperty: commonProperty
                )
            }
        }
    }

    func objectSize(
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        components: [CoreHwp.HwpShapeComponent]
    ) -> CGSize {
        var width = HwpUnits.points(fromHwpUnitU: commonProperty.width)
        var height = HwpUnits.points(fromHwpUnitU: commonProperty.height)
        if width <= 0 || height <= 0, let detail = components.first?.detail {
            if width <= 0 { width = HwpUnits.points(fromHwpUnitU: detail.currentWidth) }
            if height <= 0 { height = HwpUnits.points(fromHwpUnitU: detail.currentHeight) }
        }
        return CGSize(width: max(1, width), height: max(1, height))
    }

    func appendImageBlock(
        picture: CoreHwp.HwpShapeComponentPicture,
        component _: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        size: CGSize
    ) {
        let property = picture.pictureProperty
        let binItemId = property.map { UInt32($0.binItemId) }
            ?? picture.binaryDataId.map(UInt32.init)
        guard let binItemId else {
            appendPlaceholderBlock(hint: "그림: BinData 참조 없음")
            return
        }
        guard imageStore.data(forBinItemId: binItemId) != nil else {
            collectedUnsupported.append(HwpUnsupportedElement(
                kind: .placeholder,
                page: cachedPages.count + 1,
                hint: "그림: 데이터 없음"
            ))
            appendPlaceholderBlock(hint: "[이미지]")
            return
        }

        var borderColor: HwpRGBColor?
        var borderWidth: CGFloat = 0
        if let property, property.borderThickness > 0 {
            borderColor = HwpRGBColor(property.borderColor)
            borderWidth = HwpUnits.points(fromHwpUnit: property.borderThickness)
        }
        appendAnchoredBlock(
            kind: .image,
            size: size,
            payload: .image(HwpImageBlockInfo(
                binItemId: binItemId,
                borderColor: borderColor,
                borderWidth: borderWidth
            )),
            commonProperty: commonProperty
        )
    }

    /// 앵커 규칙 (표 70)에 따라 개체 블록을 배치한다.
    ///
    /// - 글자처럼 취급 (treatAsChar) 또는 본문 흐름을 차지하는 wrap:
    ///   현재 흐름 위치에 배치하고 높이를 소비한다.
    /// - 나머지 (글 앞/뒤로 포함 anchored): 기준 (쪽/문단) + 오프셋 위치에 배치하고
    ///   본문 흐름을 소비하지 않는다.
    func appendAnchoredBlock(
        kind: HwpBlockKind,
        size: CGSize,
        payload: HwpBlockPayload,
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        attributedText: [NSAttributedString] = []
    ) {
        let info = commonProperty.propertyInfo
        let contentFrame = currentPageGeometry.contentFrame
        let combinedText = combinedAttributedString(attributedText)

        if info.treatAsChar || consumesFlow(info) {
            appendFlowBlock(
                kind: kind,
                size: size,
                payload: payload,
                attributedString: combinedText,
                instanceId: commonProperty.instanceId
            )
            return
        }

        // anchored: 기준 + 오프셋 (음수 오프셋 허용)
        let offsetX = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.horizontalOffset)
        )
        let offsetY = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.verticalOffset)
        )
        let baseX: CGFloat = switch info.horizontalRelativeTo {
        case .paper: 0
        case .page, .column, .paragraph, nil: contentFrame.minX
        }
        let baseY: CGFloat = switch info.verticalRelativeTo {
        case .paper: 0
        case .page, nil: contentFrame.minY
        case .paragraph: paragraphAnchorTop
        }
        let frame = CGRect(
            x: baseX + offsetX,
            y: baseY + offsetY,
            width: size.width,
            height: size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: kind,
            attributedString: combinedText,
            payload: payload,
            source: HwpBlockSource(controlInstanceId: commonProperty.instanceId)
        ))
    }

    /// 본문 흐름을 소비하는 블록을 현재 흐름 위치에 배치한다.
    /// 남은 공간에 안 맞으면 (블록이 한 페이지에 들어가는 크기일 때) 새 페이지로 넘긴다.
    private func appendFlowBlock(
        kind: HwpBlockKind,
        size: CGSize,
        payload: HwpBlockPayload,
        attributedString: NSAttributedString?,
        instanceId: UInt32
    ) {
        if contentHeightUsed > 0,
           contentHeightUsed + size.height > effectiveContentHeight,
           size.height <= currentPageGeometry.contentFrame.height
        {
            cacheCurrentPage()
        }
        let contentFrame = currentPageGeometry.contentFrame
        let frame = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY + contentHeightUsed,
            width: min(size.width, contentFrame.width),
            height: size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: kind,
            attributedString: attributedString,
            payload: payload,
            source: HwpBlockSource(controlInstanceId: instanceId)
        ))
        contentHeightUsed += size.height
    }

    func consumesFlow(_ info: CoreHwp.HwpCommonCtrlPropertyInfo) -> Bool {
        switch info.textWrap {
        case .square, .tight, .through, .topAndBottom, nil:
            true
        case .behindText, .inFrontOfText:
            false
        }
    }

    func combinedAttributedString(_ strings: [NSAttributedString]) -> NSAttributedString? {
        guard !strings.isEmpty else { return nil }
        let combined = NSMutableAttributedString()
        for (offset, string) in strings.enumerated() {
            if offset > 0 { combined.append(NSAttributedString(string: "\n")) }
            combined.append(string)
        }
        return combined
    }

    func appendPlaceholderBlock(hint: String) {
        let contentFrame = currentPageGeometry.contentFrame
        let height: CGFloat = 20
        if contentHeightUsed > 0, contentHeightUsed + height > effectiveContentHeight {
            cacheCurrentPage()
        }
        currentBlocks.append(AnyHwpBlock(
            frame: CGRect(
                x: contentFrame.minX,
                y: contentFrame.minY + contentHeightUsed,
                width: contentFrame.width,
                height: height
            ),
            kind: .placeholder,
            attributedString: NSAttributedString(string: hint)
        ))
        contentHeightUsed += height
    }

    // MARK: 머리말/꼬리말

    /// 페이지 번호(1-based)와 적용 범위(표 141)에 맞는 활성 머리말/꼬리말을 고른다.
    /// 짝수/홀수 전용이 양쪽보다 우선한다.
    func resolvedBand(
        from bands: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl],
        pageNumber: Int
    ) -> CoreHwp.HwpListControl? {
        let parity: CoreHwp.HwpHeaderFooterApplyScope = pageNumber.isMultiple(of: 2)
            ? .evenPagesOnly
            : .oddPagesOnly
        return bands[parity] ?? bands[.bothPages]
    }

    /// 이 페이지에 적용되는 머리말/꼬리말 밴드 블록을 방출한다 (cacheCurrentPage 전용).
    func appendActiveBandBlocks(pageNumber: Int) {
        if let header = resolvedBand(from: activeHeaders, pageNumber: pageNumber) {
            appendBandBlocks(header, band: currentPageGeometry.headerFrame, isHeader: true)
        }
        if let footer = resolvedBand(from: activeFooters, pageNumber: pageNumber) {
            appendBandBlocks(footer, band: currentPageGeometry.footerFrame, isHeader: false)
        }
    }

    func appendBandBlocks(_ list: CoreHwp.HwpListControl, band: CGRect?, isHeader: Bool) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        let contentFrame = currentPageGeometry.contentFrame
        let builder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout()

        var cursorY: CGFloat
        let bandFrame: CGRect = band ?? CGRect(
            x: contentFrame.minX,
            y: isHeader ? max(0, contentFrame.minY - 20) : contentFrame.maxY,
            width: contentFrame.width,
            height: 20
        )
        cursorY = bandFrame.minY

        for paragraph in paragraphs {
            let attributed = builder.build(paragraph: paragraph)
            guard attributed.length > 0 else { continue }
            let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
                ?? index.paraShape(id: 0)
                ?? CoreHwp.HwpParaShape()
            let frame = paragraphLayout.layout(
                attributedString: attributed,
                paraShape: paraShape,
                columnWidth: bandFrame.width
            )
            let blockHeight = max(1, frame.totalHeight)
            currentBlocks.append(AnyHwpBlock(
                frame: CGRect(
                    x: bandFrame.minX,
                    y: cursorY,
                    width: bandFrame.width,
                    height: blockHeight
                ),
                kind: .text,
                attributedString: NSAttributedString(attributedString: attributed),
                source: HwpBlockSource(paragraphId: paragraph.paraHeader.paraId)
            ))
            cursorY += blockHeight
        }
    }

    // MARK: 각주/미주

    /// 문단(과 컨테이너 안 문단)의 각주를 이 페이지 몫으로 수집한다.
    /// 표 분할 등 다른 컨트롤 방출이 페이지를 넘기기 전에 호출해
    /// 각주를 참조 위치의 페이지에 귀속시킨다.
    func collectFootnotes(from paragraph: CoreHwp.HwpParagraph, depth: Int = 0) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        for ctrl in ctrls {
            switch ctrl {
            case let .footnote(list), let .endnote(list):
                collectFootnotes(list)
            default:
                break
            }
            guard depth < 3 else { continue }
            for (nested, _) in childParagraphs(of: ctrl) where nested.ctrlHeaderArray != nil {
                collectFootnotes(from: nested, depth: depth + 1)
            }
        }
    }

    func collectFootnotes(_ list: CoreHwp.HwpListControl) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        let isFirstOnPage = pendingFootnotes.isEmpty
        for paragraph in paragraphs {
            pendingFootnotes.append(HwpFootnoteLayout.Input(
                paragraph: paragraph,
                number: footnoteCounter
            ))
            footnoteCounter += 1
            footnoteReservedHeight += measuredFootnoteHeight(of: paragraph) + 4
        }
        if isFirstOnPage {
            footnoteReservedHeight += 16 // 구분선 + 위/아래 여백
        }
    }

    /// 이월된 각주 입력들이 새 페이지에서 예약할 높이 (구분선 여백 포함)
    func reservedFootnoteHeight(for inputs: [HwpFootnoteLayout.Input]) -> CGFloat {
        guard !inputs.isEmpty else { return 0 }
        return inputs.reduce(CGFloat(0)) {
            $0 + measuredFootnoteHeight(of: $1.paragraph) + 4
        } + 16 // 구분선 + 위/아래 여백
    }

    /// 이 문단이 페이지에 추가될 때 각주 영역이 요구할 높이 (커밋 전 예측용)
    func anticipatedFootnoteHeight(for paragraph: CoreHwp.HwpParagraph) -> CGFloat {
        guard let ctrls = paragraph.ctrlHeaderArray else { return 0 }
        var total: CGFloat = 0
        for ctrl in ctrls {
            guard case let .footnote(list) = ctrl else {
                if case let .endnote(list) = ctrl {
                    total += list.listArray.flatMap(\.paragraphArray)
                        .reduce(0) { $0 + measuredFootnoteHeight(of: $1) + 4 }
                }
                continue
            }
            total += list.listArray.flatMap(\.paragraphArray)
                .reduce(0) { $0 + measuredFootnoteHeight(of: $1) + 4 }
        }
        if total > 0, pendingFootnotes.isEmpty {
            total += 16 // 구분선 + 위/아래 여백
        }
        return total
    }

    func measuredFootnoteHeight(of paragraph: CoreHwp.HwpParagraph) -> CGFloat {
        let textRunBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let attributed = textRunBuilder.build(paragraph: paragraph)
        let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
            ?? index.paraShape(id: 0)
            ?? CoreHwp.HwpParaShape()
        let frame = HwpParagraphLayout().layout(
            attributedString: attributed,
            paraShape: paraShape,
            columnWidth: currentPageGeometry.contentFrame.width
        )
        return max(1, frame.totalHeight)
    }

    /// 대기 중인 각주를 페이지 하단에 배치한다. 영역(콘텐츠 절반 상한)을
    /// 넘는 각주는 pendingFootnotes에 남겨 다음 페이지로 이월한다.
    func appendPendingFootnotes() {
        guard !pendingFootnotes.isEmpty else { return }
        let placement = footnoteLayout.place(
            footnotes: pendingFootnotes,
            onPage: currentPageGeometry,
            index: index,
            footnoteShape: currentSectionDef?.footNoteShape
        )
        for block in placement.blocks {
            currentBlocks.append(AnyHwpBlock(
                frame: block.frame,
                kind: .footnote,
                attributedString: combinedAttributedString(
                    block.paragraphs.map(\.attributedString)
                ),
                payload: .footnote(block),
                source: HwpBlockSource(paragraphId: block.paragraphs.first?.paragraphId)
            ))
        }
        pendingFootnotes = placement.overflow
        footnoteReservedHeight = 0
    }

    // MARK: 페이지 확정

    func cacheCurrentPage() {
        appendActiveBandBlocks(pageNumber: cachedPages.count + 1)
        appendPendingFootnotes()
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
        paragraphAnchorTop = currentPageGeometry.contentFrame.minY
        // 이월된 각주가 새 페이지에서 차지할 영역을 다시 예약한다.
        footnoteReservedHeight = reservedFootnoteHeight(for: pendingFootnotes)
        if currentSectionDef?.footNoteShape.numberingModeRawValue == 2 {
            footnoteCounter = Self.initialFootnoteNumber(for: currentSectionDef)
        }
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
