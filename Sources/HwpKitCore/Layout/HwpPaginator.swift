import CoreGraphics
import CoreHwp
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
    /// 각주/미주 수집·측정·예약 상태 — 카운터·pending·예약 높이·측정 캐시를 소유한다.
    private var footnoteCoordinator: HwpFootnoteCoordinator
    private var nextSectionIndex = 0
    private var nextParagraphIndex = 0
    private var currentPageGeometry: HwpPageGeometry
    private var currentSectionDef: CoreHwp.HwpSectionDef?
    private var currentBlocks: [AnyHwpBlock] = []
    private var contentHeightUsed: CGFloat = 0
    private var didFinishPagination = false
    private var collectedUnsupported: [HwpUnsupportedElement] = []
    /// 이 페이지에 배치할 각주 (문단 + 문서 순서 번호) — 저장은 footnoteCoordinator
    private var pendingFootnotes: [HwpFootnoteLayout.Input] {
        get { footnoteCoordinator.pendingFootnotes }
        set { footnoteCoordinator.pendingFootnotes = newValue }
    }

    /// 이 페이지에 표시할 메모 (댓글) 풍선 (한글.app 편집 뷰 오른쪽 패널)
    private var pendingMemoBalloons: [HwpMemoPanelPainter.Balloon] = []
    /// 문서/구역 끝에 배치할 미주 (표 134 bits 8-9) — 저장은 footnoteCoordinator
    private var pendingEndnotes: [HwpFootnoteLayout.Input] {
        get { footnoteCoordinator.pendingEndnotes }
        set { footnoteCoordinator.pendingEndnotes = newValue }
    }

    /// 각주 영역이 차지할 높이 (본문 overflow 검사에 반영) — 저장은 footnoteCoordinator
    private var footnoteReservedHeight: CGFloat {
        get { footnoteCoordinator.footnoteReservedHeight }
        set { footnoteCoordinator.footnoteReservedHeight = newValue }
    }

    /// 현재 문단의 현재-페이지 상단 y (문단 기준 앵커의 기준점).
    /// 페이지가 넘어가면 새 페이지 콘텐츠 상단으로 재설정된다.
    private var paragraphAnchorTop: CGFloat = 0
    /// 페이지 경계 재처리 메모 — placeParagraphText 실패 (페이지 확정) 후
    /// 같은 문단을 다음 페이지에서 다시 처리할 때 build + CT 측정을
    /// 재사용한다. 키가 빌드의 모든 입력 (문단 위치·단 폭·컨트롤 치환
    /// 결과)을 포함하므로 키 일치 시 결과는 정의상 동일하다. 쪽 번호
    /// 자동 치환처럼 페이지 확정으로 치환 텍스트가 달라지는 문단은
    /// replacements 불일치로 자연히 재빌드된다.
    private struct ParagraphMeasureMemo {
        let sectionIndex: Int
        let paragraphIndex: Int
        let widthCenti: Int
        let replacements: [Int: HwpControlMarkerReplacement]
        let attributedString: NSAttributedString
        let paragraphFrame: HwpParagraphFrame
    }

    private var measureMemo: ParagraphMeasureMemo?
    /// 각주 번호 — 저장은 footnoteCoordinator
    private var footnoteCounter: Int {
        get { footnoteCoordinator.footnoteCounter }
        set { footnoteCoordinator.footnoteCounter = newValue }
    }

    /// 미주 번호 (각주와 별도 카운터, endNoteShape.startingNumber부터)
    /// — 저장은 footnoteCoordinator
    private var endnoteCounter: Int {
        get { footnoteCoordinator.endnoteCounter }
        set { footnoteCoordinator.endnoteCounter = newValue }
    }

    /// 다음에 확정될 페이지의 논리 쪽 번호 (표 141 짝/홀 판정용).
    /// 구역의 pageStartNumber(0 = 앞 구역에 이어서)로 재설정된다.
    private var nextLogicalPageNumber = 1
    /// 새 번호 지정(nwno, 표 144)의 쪽 번호 리셋은 문단이 실제 배치될 때까지
    /// 보류한다 — 배치 전에 적용하면 넘침으로 확정되는 앞 페이지까지 리셋 번호를
    /// 써 엉뚱한 쪽 번호·패리티 머리말을 갖는다.
    private var pendingPageNumber: Int?
    /// 머리말/꼬리말/쪽 번호 (페이지 크롬) 빌더 — 활성 컨트롤 상태를 소유한다.
    private var pageChrome: HwpPageChromeBuilder
    /// 다단 밴드 상태·로직 — 단 정의/프레임/index/사용량/균형 재배치 입력을
    /// 소유한다. 리셋은 band.open 한 곳 (openColumnBand·cacheCurrentPage 공용).
    /// 아래 계산 프로퍼티들은 기존 호출부를 유지하기 위한 위임이다.
    private var band = HwpColumnBandController()
    /// 현재 단 정의 (`cold` 컨트롤). nil이면 1단. — 저장은 band
    private var currentColumnDef: CoreHwp.HwpColumn? {
        get { band.currentColumnDef }
        set { band.currentColumnDef = newValue }
    }

    /// 현재 단 밴드의 단 프레임 (페이지 좌표). 비어 있으면 contentFrame 1단.
    /// — 저장은 band (쓰기는 band.open만)
    private var columnFrames: [CGRect] {
        band.columnFrames
    }

    /// 현재 채우는 단 index — 저장은 band
    private var columnIndex: Int {
        get { band.columnIndex }
        set { band.columnIndex = newValue }
    }

    /// 현재 밴드에서 실제 사용된 최대 하단 y — 밴드 종료 시 다음 밴드 시작점.
    /// 저장은 band
    private var bandUsedBottom: CGFloat {
        get { band.bandUsedBottom }
        set { band.bandUsedBottom = newValue }
    }

    /// 밴드에 들어간 본문 텍스트 블록 (밴드 종료 시 단 균형 재배치용)
    /// — 저장은 band
    private var bandTextBlocks: [(blockIndex: Int, lines: [HwpLineFrame])] {
        get { band.bandTextBlocks }
        set { band.bandTextBlocks = newValue }
    }

    /// 밴드에 텍스트 외 블록(표/개체/placeholder)이 있으면 균형 재배치를 하지
    /// 않는다 — 저장은 band
    private var bandHasNonTextContent: Bool {
        get { band.bandHasNonTextContent }
        set { band.bandHasNonTextContent = newValue }
    }

    /// 밴드 마지막 줄의 줄 간격 (pt) — 저장·산식은 band
    /// (updateBandTrailingSpacing 참조)
    private var bandTrailingLineSpacing: CGFloat {
        band.bandTrailingLineSpacing
    }

    /// 방금 배치한 본문 문단 텍스트 블록 (줄 중간 treatAsChar 앵커의 기준)
    private var currentParagraphContext: (blockFrame: CGRect, lines: [HwpLineFrame])?
    /// 절대 라인 캐시 배치 — run 분해·높이·슬라이스·stale 판정 계산과
    /// 절대 캐시 전용 상태 (모드·마지막 loc·stale 보정)를 소유한다.
    /// 페이지 확정·블록 방출은 여기 (paginator)에 남는다.
    private var absoluteCachePlacer: HwpAbsoluteCachePlacer
    /// 절대 캐시 모드: lineLocation이 페이지 내 절대 y인 저장본 (한/글 2007
    /// 계열) — 저장은 absoluteCachePlacer
    private var absoluteCacheMode: Bool {
        absoluteCachePlacer.absoluteCacheMode
    }

    /// 현재 페이지에 배치한 마지막 세그먼트의 lineLocation (절대 캐시 모드 전용)
    /// — 저장은 absoluteCachePlacer
    private var lastAbsoluteCacheLoc: Int32 {
        get { absoluteCachePlacer.lastAbsoluteCacheLoc }
        set { absoluteCachePlacer.lastAbsoluteCacheLoc = newValue }
    }

    /// 절대 캐시 모드에서 stale 캐시 문단이 만든 아래 방향 보정 오프셋
    /// (페이지 로컬) — 저장은 absoluteCachePlacer
    private var absoluteCacheStaleOffset: CGFloat {
        get { absoluteCachePlacer.absoluteCacheStaleOffset }
        set { absoluteCachePlacer.absoluteCacheStaleOffset = newValue }
    }

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
        footnoteCoordinator = HwpFootnoteCoordinator(index: index, fontResolver: fontResolver)
        pageChrome = HwpPageChromeBuilder(index: index, fontResolver: fontResolver)
        absoluteCachePlacer = HwpAbsoluteCachePlacer(sections: sections)
        currentPageGeometry = Self.initialGeometry(for: sections)
        currentSectionDef = Self.firstSectionDef(for: sections)
        // init에서는 계산 프로퍼티 (actor-isolated) 대신 저장소에 직접 쓴다.
        footnoteCoordinator.footnoteCounter = Self.initialNoteNumber(
            startingNumber: currentSectionDef?.footNoteShape.startingNumber
        )
        footnoteCoordinator.endnoteCounter = Self.initialNoteNumber(
            startingNumber: currentSectionDef?.endNoteShape.startingNumber
        )
    }

    public func page(at index: Int) async throws -> HwpPage? {
        guard index >= 0 else { return nil }
        if let page = cachedPages[index] {
            return page
        }

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

    static func initialNoteNumber(startingNumber: UInt16?) -> Int {
        let starting = Int(startingNumber ?? 1)
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

    static func columnDef(in paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpColumn? {
        paragraph.ctrlHeaderArray?.compactMap { ctrl in
            if case let .column(column) = ctrl {
                return column
            }
            return nil
        }.first
    }

    // MARK: - 단 (column band)

    /// 현재 채우는 단의 프레임. 밴드가 아직 없으면 콘텐츠 전체. (산식은 band)
    var currentColumnFrame: CGRect {
        band.currentColumnFrame(contentFrame: currentPageGeometry.contentFrame)
    }

    /// 현재 단에서 본문이 쓸 수 있는 높이 (각주 예약 제외)
    var effectiveContentHeight: CGFloat {
        max(1, currentColumnFrame.height - footnoteReservedHeight)
    }

    var sectionDefaultColumnSpacing: CGFloat {
        currentSectionDef.map { HwpUnits.points(fromHwpUnit16: $0.columnSpacing) } ?? 0
    }

    /// 현재 단의 사용량을 밴드 하단 추적에 반영한다. (산식은 band)
    func markBandUsage() {
        band.markUsage(
            contentHeightUsed: contentHeightUsed,
            contentFrame: currentPageGeometry.contentFrame
        )
    }

    /// top에서 시작하는 새 단 밴드를 연다 (밴드 추적 초기화 포함).
    /// 밴드 상태 리셋은 band.open에 단일화; 문단 배치 공유 상태
    /// (contentHeightUsed·paragraphAnchorTop)는 여기서 이어서 리셋한다
    /// (기존 리셋 순서·값 불변 — band.open 주석 참조).
    func openColumnBand(top: CGFloat) {
        band.open(
            top: top,
            contentFrame: currentPageGeometry.contentFrame,
            defaultSpacing: sectionDefaultColumnSpacing
        )
        contentHeightUsed = 0
        paragraphAnchorTop = top
    }

    /// 밴드를 닫는다. 본문 텍스트가 첫 단에만 남은 다단 밴드는
    /// 라인 단위로 균형 재배치한다 (한글의 단 배분 동작).
    func closeColumnBand() {
        markBandUsage()
        if columnFrames.count > 1, columnIndex == 0,
           !bandHasNonTextContent, !bandTextBlocks.isEmpty
        {
            rebalanceColumnBand()
            // 재배치 후 흐름 상태를 밴드 하단과 일치시킨다
            // (뒤따르는 markBandUsage가 stale 값으로 되돌리지 않게).
            columnIndex = 0
            contentHeightUsed = max(0, bandUsedBottom - currentColumnFrame.minY)
        }
        bandTextBlocks = []
        bandHasNonTextContent = false
    }

    /// 문단에 붙은 단 정의를 반영한다: 현재 밴드를 닫고 그 아래에서 새 밴드를 연다.
    /// 밴드를 열 자리가 (각주 예약을 빼고) 한 줄도 안 남으면 새 페이지에서 연다 —
    /// 퇴화 밴드는 openColumnBand의 contentHeightUsed 리셋으로 overflow 가드를
    /// 무력화해 본문이 각주 영역/페이지 밖에 강제 배치된다.
    func applyColumnDef(in paragraph: CoreHwp.HwpParagraph) {
        guard let column = Self.columnDef(in: paragraph) else { return }
        let hadBandContent = !bandTextBlocks.isEmpty || bandHasNonTextContent
        closeColumnBand()
        currentColumnDef = column
        let minimumBandHeight: CGFloat = 12 // 대략 한 줄
        let usableBottom = currentPageGeometry.contentFrame.maxY - footnoteReservedHeight
        if bandUsedBottom >= usableBottom - minimumBandHeight, !currentBlocks.isEmpty {
            cacheCurrentPage()
        } else {
            // 한글은 단 정의로 밴드를 닫을 때 마지막 줄의 줄 간격만큼 띄우고
            // 다음 밴드를 연다 (Column PrvImage 실측: 밴드 간 시작 간격
            // = 줄 전진량 + 줄 간격)
            let gap = hadBandContent ? bandTrailingLineSpacing : 0
            openColumnBand(top: bandUsedBottom + gap)
        }
    }

    /// 단이 가득 차면 다음 단으로, 마지막 단이면 새 페이지로 넘어간다.
    /// (단 전진 판정·index 증가는 band, 페이지 확정과 공유 상태 리셋은 여기.)
    func advanceColumn() {
        markBandUsage()
        if band.advanceToNextColumn() {
            contentHeightUsed = 0
            paragraphAnchorTop = currentColumnFrame.minY
        } else {
            cacheCurrentPage()
        }
    }

    /// 첫 단에만 쌓인 밴드 텍스트를 라인 단위로 모든 단에 균등 재배치한다.
    /// 재배치 플랜 (교체 index·새 블록) 산출은 band.rebalancePlan,
    /// currentBlocks 재작성 적용은 여기서 한다.
    func rebalanceColumnBand() {
        guard let plan = band.rebalancePlan(currentBlocks: currentBlocks) else { return }
        currentBlocks = currentBlocks.enumerated()
            .filter { !plan.replacedBlockIndices.contains($0.offset) }
            .map(\.element)
        currentBlocks.append(contentsOf: plan.newBlocks)
        bandUsedBottom = plan.maxBottom
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
            // 구역 시작/쪽 나누기 문단: 진행 중인 페이지를 확정하고 이 문단은
            // 다음 호출에서 새 페이지 첫머리로 다시 처리한다.
            if flushPageBeforeProcessing(paragraph) {
                return
            }

            applySectionDef(in: paragraph)
            applyColumnDef(in: paragraph)
            applyNewNumbers(in: paragraph)

            let widthCenti = Int((currentColumnFrame.width * 100).rounded())
            let replacements = noteReferenceReplacements(for: paragraph)
            let attributedString: NSAttributedString
            let paragraphFrame: HwpParagraphFrame
            if let memo = measureMemo,
               memo.sectionIndex == nextSectionIndex,
               memo.paragraphIndex == nextParagraphIndex,
               memo.widthCenti == widthCenti,
               memo.replacements == replacements
            {
                attributedString = memo.attributedString
                paragraphFrame = memo.paragraphFrame
            } else {
                attributedString = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
                    .build(paragraph: paragraph, controlReplacements: replacements)
                paragraphFrame = if absoluteCachePlacer.canSkipMeasurement(
                    for: paragraph,
                    attributedString: attributedString,
                    columnCount: columnFrames.count
                ) {
                    HwpParagraphFrame(totalHeight: 0, lines: [])
                } else {
                    try await layout(paragraph, attributedString: attributedString)
                }
            }
            guard placeParagraphText(
                paragraph,
                attributedString: attributedString,
                paragraphFrame: paragraphFrame
            ) else {
                // 현재 페이지가 확정됐고 문단은 다음 페이지에서 다시 처리한다 —
                // 빌드 입력이 그대로면 메모로 build + CT 재실행을 건너뛴다.
                measureMemo = ParagraphMeasureMemo(
                    sectionIndex: nextSectionIndex,
                    paragraphIndex: nextParagraphIndex,
                    widthCenti: widthCenti,
                    replacements: replacements,
                    attributedString: attributedString,
                    paragraphFrame: paragraphFrame
                )
                return
            }
            measureMemo = nil
            // 배치가 확정된 지금 쪽 번호 리셋을 적용한다 — 넘친 앞 페이지는 리셋
            // 전 번호를 유지하고, 이 문단이 실린 페이지부터 새 번호가 시작된다.
            if let reset = pendingPageNumber {
                nextLogicalPageNumber = reset
                pendingPageNumber = nil
            }
            collectFootnotes(from: paragraph, includeTableCells: false)
            collectMemos(from: paragraph)
            appendControlBlocks(from: paragraph)
            collectUnsupported(from: paragraph)
            advanceParagraph()
            await Task.yield()

            // 이 호출에서 이미 페이지가 생겼으면 반환해 호출자가 진행을 관찰하게 한다.
            if cachedPages.count > pageCountBefore {
                return
            }
        }

        // 문서 끝: 밴드를 닫고 마지막 본문 페이지를 확정한 뒤, 남은 미주는
        // 새 쪽에서 시작한다 (한글.app 실측 2026-07-06 — footnote-endnote
        // 픽스처의 미주가 2쪽에 표시됨을 사용자 확인).
        closeColumnBand()
        if !pendingEndnotes.isEmpty, !currentBlocks.isEmpty || contentHeightUsed > 0 {
            cacheCurrentPage()
        }
        appendPendingEndnotes()
        cacheCurrentPage()
        // 마지막 페이지에서 넘친 각주가 있으면 빈 페이지를 이어 붙여 모두 배치한다.
        while !pendingFootnotes.isEmpty {
            cacheCurrentPage()
        }
        didFinishPagination = true
    }

    /// 새 구역 정의 (이전 구역의 밴드를 닫고 구역-끝 미주 배치) 또는
    /// 쪽 나누기 (문단 헤더 columnType bit 2)를 만나면 진행 중인 페이지를
    /// 확정한다. 페이지를 확정했으면 true (호출자가 반환하고 같은 문단을
    /// 새 페이지에서 다시 처리한다).
    func flushPageBeforeProcessing(_ paragraph: CoreHwp.HwpParagraph) -> Bool {
        if Self.sectionDef(in: paragraph) != nil {
            closeColumnBand()
            if currentSectionDef?.endNoteShape.placesEndnoteAtSectionEnd == true {
                appendPendingEndnotes()
            }
            if !currentBlocks.isEmpty || contentHeightUsed > 0 {
                cacheCurrentPage()
                return true
            }
        }
        if paragraph.paraHeader.columnType & 0b100 != 0,
           !currentBlocks.isEmpty || contentHeightUsed > 0
        {
            closeColumnBand()
            cacheCurrentPage()
            return true
        }
        return false
    }

    /// 문단 텍스트 블록을 흐름에 배치한다.
    /// 문단이 남은 공간에 안 맞아 페이지를 확정했으면 false (호출자가 반환하고
    /// 같은 문단을 다음 페이지에서 다시 처리한다).
    func placeParagraphText(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame
    ) -> Bool {
        let placed: Bool
            // 절대 캐시 모드 (1단): 한글이 계산한 y/페이지 절단점을 그대로 재현한다.
            = if absoluteCacheMode, columnFrames.count <= 1,
            let runs = HwpAbsoluteCachePlacer.cacheRuns(for: paragraph)
        {
            placeAbsoluteCachedParagraph(
                paragraph,
                attributedString: attributedString,
                paragraphFrame: paragraphFrame,
                runs: runs
            )
        } else {
            placeFlowParagraph(
                paragraph,
                attributedString: attributedString,
                paragraphFrame: paragraphFrame
            )
        }
        if placed {
            appendTrackChangeBarIfNeeded(for: paragraph)
        }
        return placed
    }

    /// 변경 추적 마크 (PARA_RANGE_TAG kind 16/17)가 있는 문단 왼쪽에
    /// 한글.app처럼 빨간 변경 막대를 그린다.
    private func appendTrackChangeBarIfNeeded(for paragraph: CoreHwp.HwpParagraph) {
        let hasTrackChange = (paragraph.paraRangeTagArray ?? []).contains { tag in
            let kind = tag.tag >> 24
            return kind == 16 || kind == 17
        }
        guard hasTrackChange, let last = currentBlocks.last, last.kind == .text else { return }
        let barRect = CGRect(x: 0, y: 0, width: 1.2, height: last.frame.height)
        currentBlocks.append(AnyHwpBlock(
            frame: CGRect(
                x: currentPageGeometry.contentFrame.minX - 10,
                y: last.frame.minY,
                width: barRect.width,
                height: barRect.height
            ),
            kind: .shape,
            payload: .shape(HwpShapeGeometry(
                path: CGPath(rect: barRect, transform: nil),
                fillColor: CGColor(srgbRed: 0.87, green: 0.14, blue: 0.1, alpha: 1),
                strokeColor: nil,
                strokeWidth: 0
            ))
        ))
    }

    /// 흐름 기반 문단 배치 (절대 캐시 모드가 아닌 저장본/경로)
    private func placeFlowParagraph(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame
    ) -> Bool {
        var paragraphHeight = height(for: paragraph, fallback: paragraphFrame.totalHeight)
        // 캐시 높이가 페이지를 넘는데 CT 라인도 하나뿐이면 (표/개체 앵커가 캐시
        // 높이를 지배하는 문단) 캐시 높이를 그대로 쓸 수 없다 — 개체는 별도
        // 블록으로 배치되므로 텍스트 몫은 CT 측정 높이로 폴백한다.
        if paragraphHeight > currentColumnFrame.height, paragraphFrame.lines.count <= 1 {
            paragraphHeight = paragraphFrame.totalHeight
        }
        // 이 문단이 만들 각주 예약 높이를 미리 반영해 본문/각주 겹침을 막는다.
        let anticipatedFootnotes = anticipatedFootnoteHeight(for: paragraph)
        if columnFrames.count > 1 {
            placeMultiColumnParagraph(
                paragraph,
                attributedString: attributedString,
                paragraphFrame: paragraphFrame,
                paragraphHeight: paragraphHeight,
                anticipatedFootnotes: anticipatedFootnotes
            )
            return true
        }
        if contentHeightUsed > 0,
           contentHeightUsed + paragraphHeight
           > effectiveContentHeight - anticipatedFootnotes
        {
            cacheCurrentPage()
            return false
        }
        // 빈 페이지에도 안 들어가는 문단 (여러 페이지에 걸친 라인 캐시)은 1단에서도
        // 라인 단위로 나눠 페이지에 흘린다 (1단 밴드의 advanceColumn == 새 페이지).
        if paragraphHeight > currentColumnFrame.height,
           paragraphFrame.lines.count > 1
        {
            appendParagraphAcrossColumns(
                attributedString: attributedString,
                paragraphFrame: paragraphFrame,
                paragraphHeight: paragraphHeight,
                hyperlinkURL: hyperlinkURL(in: paragraph),
                paragraphId: paragraph.paraHeader.paraId,
                reservedFootnoteHeight: anticipatedFootnotes
            )
            updateBandTrailingSpacing(for: paragraph)
            return true
        }
        paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
        appendBlock(
            height: paragraphHeight,
            attributedString: attributedString,
            hyperlinkURL: hyperlinkURL(in: paragraph),
            paragraphId: paragraph.paraHeader.paraId,
            lines: paragraphFrame.lines
        )
        updateBandTrailingSpacing(for: paragraph)
        return true
    }

    /// 다단 밴드 문단 배치: 한글 라인 캐시가 단별 run (loc 리셋 = 단 경계)을
    /// 주면 한글의 단별 텍스트 배분을 그대로 재현하고 — 비등폭 단은 라인 수가
    /// 아니라 단 폭에 맞는 글자 위치로 나뉜다 (Column 픽스처 캐시/PrvImage
    /// 실측) — 아니면 라인 단위로 단을 채운다.
    private func placeMultiColumnParagraph(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame,
        paragraphHeight: CGFloat,
        anticipatedFootnotes: CGFloat
    ) {
        if placeCachedColumnRuns(
            paragraph,
            attributedString: attributedString,
            paragraphFrame: paragraphFrame
        ) {
            return
        }
        appendParagraphAcrossColumns(
            attributedString: attributedString,
            paragraphFrame: paragraphFrame,
            paragraphHeight: paragraphHeight,
            hyperlinkURL: hyperlinkURL(in: paragraph),
            paragraphId: paragraph.paraHeader.paraId,
            reservedFootnoteHeight: anticipatedFootnotes
        )
        updateBandTrailingSpacing(for: paragraph)
    }

    /// 밴드 마지막 줄의 줄 간격을 기록한다 (단 정의 밴드 마감 시 다음 밴드
    /// 시작 여백으로 사용). 산식은 band.updateTrailingSpacing.
    private func updateBandTrailingSpacing(for paragraph: CoreHwp.HwpParagraph) {
        band.updateTrailingSpacing(for: paragraph)
    }

    /// 한글 라인 캐시의 단별 run을 단 프레임에 그대로 배분한다 (밴드가 비어 있고
    /// 캐시가 단 경계 (loc 리셋 후 0에서 재시작)를 담고 있을 때만).
    /// 단 경계의 스트림 위치 환산·라인 스냅은
    /// HwpAbsoluteCachePlacer.columnRunBoundaries.
    /// 절대 캐시 모드에서는 loc 리셋이 페이지 절단점이므로 이 경로를 쓰지 않는다.
    private func placeCachedColumnRuns(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame
    ) -> Bool {
        let rawTotal = paragraph.paraHeader.charCount
        guard !absoluteCacheMode,
              columnIndex == 0,
              contentHeightUsed == 0,
              rawTotal > 0,
              attributedString.length > 0,
              let runs = HwpAbsoluteCachePlacer.cacheRuns(for: paragraph),
              runs.count > 1,
              runs.count <= columnFrames.count,
              runs.allSatisfy({ $0.first?.lineLocation == 0 })
        else { return false }

        guard let boundaries = HwpAbsoluteCachePlacer.columnRunBoundaries(
            runs: runs,
            rawTotal: rawTotal,
            attributedLength: attributedString.length,
            lines: paragraphFrame.lines
        ) else { return false }

        for (runIndex, run) in runs.enumerated() {
            guard let firstSegment = run.first else { return false }
            var runBottom = firstSegment.lineLocation
            for segment in run {
                runBottom = max(
                    runBottom,
                    segment.lineLocation + HwpAbsoluteCachePlacer.lineAdvance(of: segment)
                )
            }
            let start = boundaries[runIndex]
            let length = max(0, boundaries[runIndex + 1] - start)
            guard length > 0 else { continue }
            columnIndex = runIndex
            contentHeightUsed = 0
            paragraphAnchorTop = currentColumnFrame.minY
            let fragment = attributedString.attributedSubstring(
                from: NSRange(location: start, length: length)
            )
            appendBlock(
                height: max(1, HwpUnits.points(
                    fromHwpUnit: runBottom - firstSegment.lineLocation
                )),
                attributedString: runIndex < runs.count - 1
                    ? HwpTableSplitter.markedAsContinuedFragment(fragment) : fragment,
                hyperlinkURL: hyperlinkURL(in: paragraph),
                paragraphId: paragraph.paraHeader.paraId
            )
        }
        updateBandTrailingSpacing(for: paragraph)
        return true
    }

    /// 절대 캐시 문단 배치: run들을 한글이 계산한 y에 그대로 놓고,
    /// run 사이 (loc 리셋)마다 페이지를 확정한다. 문단 첫 loc이 현재 페이지의
    /// 마지막 loc보다 작으면 한글이 이 문단을 새 페이지에서 시작한 것이므로
    /// 페이지를 확정하고 false를 반환한다 (호출자가 재처리).
    private func placeAbsoluteCachedParagraph(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame,
        runs: [[CoreHwp.HwpParaLineSegInternal]]
    ) -> Bool {
        let firstLoc = runs[0][0].lineLocation
        if firstLoc < lastAbsoluteCacheLoc, !currentBlocks.isEmpty || contentHeightUsed > 0 {
            closeColumnBand()
            cacheCurrentPage()
            return false
        }

        let lines = paragraphFrame.lines
        let totalSegments = runs.reduce(0) { $0 + $1.count }
        var lineCursor = 0
        for (runIndex, run) in runs.enumerated() {
            if runIndex > 0 {
                cacheCurrentPage()
            }
            guard let runFirstSegment = run.first else { continue }
            let runFirst = runFirstSegment.lineLocation
            var height = absoluteRunBlockHeight(run: run, firstLocation: runFirst)
            let slice = HwpAbsoluteCachePlacer.runAttributedSlice(
                runIndex: runIndex,
                runShare: HwpAbsoluteCachePlacer.RunShare(
                    segments: run.count,
                    total: totalSegments,
                    runCount: runs.count
                ),
                attributedString: attributedString,
                lines: lines,
                lineCursor: &lineCursor
            )
            // appendBlock은 columnFrame.minY + contentHeightUsed에 배치하므로
            // 한글이 준 절대 y (+ stale 캐시 보정)로 커서를 옮긴다.
            contentHeightUsed = max(0, HwpUnits.points(fromHwpUnit: runFirst))
                + absoluteCacheStaleOffset
            // stale 캐시 (캐시 줄 높이 < 선언 글자 크기): 한글.app도 열 때
            // 재조판해 이 줄을 CT 자연 높이로 넓힌다 — 슬롯을 CT 높이로 키우고
            // 이후 문단을 그만큼 민다. 신선한 캐시 (h ≥ 글자 크기)는 절대 발동
            // 안 한다 (헌법주석 페이지 절단 유지).
            if runs.count == 1,
               HwpAbsoluteCachePlacer.cacheIsStale(run: run, attributedString: slice.text),
               paragraphFrame.totalHeight > height
            {
                absoluteCacheStaleOffset += paragraphFrame.totalHeight - height
                height = paragraphFrame.totalHeight
            }
            paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
            appendBlock(
                height: height,
                attributedString: slice.text,
                hyperlinkURL: hyperlinkURL(in: paragraph),
                paragraphId: paragraph.paraHeader.paraId,
                lines: slice.lines
            )
            lastAbsoluteCacheLoc = run.last?.lineLocation ?? runFirst
        }
        return true
    }

    /// 절대 캐시 run의 블록 높이 — 산식은 HwpAbsoluteCachePlacer, 하단 경계
    /// (현재 단 상단·본문 하단)만 여기서 주입한다.
    private func absoluteRunBlockHeight(
        run: [CoreHwp.HwpParaLineSegInternal],
        firstLocation: Int32
    ) -> CGFloat {
        HwpAbsoluteCachePlacer.absoluteRunBlockHeight(
            run: run,
            firstLocation: firstLocation,
            columnTop: currentColumnFrame.minY,
            contentBottom: currentPageGeometry.contentFrame.maxY
        )
    }

    /// 문단에 붙은 구역 정의를 현재 페이지 지오메트리에 반영한다.
    func applySectionDef(in paragraph: CoreHwp.HwpParagraph) {
        guard let sectionDef = Self.sectionDef(in: paragraph) else { return }
        currentPageGeometry = HwpPageGeometry.compute(
            pageDef: sectionDef.pageDef,
            sectionDef: sectionDef
        )
        currentSectionDef = sectionDef
        // 구역은 항상 새 페이지에서 시작하므로 여기서 논리 쪽 번호를 재설정해도 안전하다.
        if sectionDef.pageStartNumber > 0 {
            nextLogicalPageNumber = Int(sectionDef.pageStartNumber)
        }
        // 단 정의는 구역에 종속: 새 구역의 단 컨트롤이 다시 적용하기 전까지 1단.
        currentColumnDef = nil
        openColumnBand(top: currentPageGeometry.contentFrame.minY)
        if sectionDef.footNoteShape.numberingModeRawValue != 0 {
            footnoteCounter = Self.initialNoteNumber(
                startingNumber: sectionDef.footNoteShape.startingNumber
            )
        }
        if sectionDef.endNoteShape.numberingModeRawValue != 0 {
            endnoteCounter = Self.initialNoteNumber(
                startingNumber: sectionDef.endNoteShape.startingNumber
            )
        }
    }

    func layout(
        _ paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString
    ) async throws -> HwpParagraphFrame {
        await Task.yield()
        guard let paraShape = index.paraShape(for: paragraph) else {
            return HwpParagraphFrame(totalHeight: 0, lines: [])
        }
        return HwpParagraphLayout().layout(
            attributedString: attributedString,
            paraShape: paraShape,
            columnWidth: currentColumnFrame.width,
            tabStops: index.textTabs(for: paraShape)
        )
    }

    /// 전체 문단 대비 처리 위치 (0...1 근사) — 프로그레시브 로딩 진행률
    public func progressEstimate() -> Double {
        let total = sections.reduce(0) { $0 + $1.paragraph.count }
        guard total > 0 else { return 1 }
        let done = sections.prefix(min(nextSectionIndex, sections.count))
            .reduce(0) { $0 + $1.paragraph.count } + nextParagraphIndex
        return min(1, max(0, Double(done) / Double(total)))
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
        paragraphId: UInt32? = nil,
        lines: [HwpLineFrame] = []
    ) {
        let immutable = NSAttributedString(attributedString: attributedString)
        let columnFrame = currentColumnFrame
        let frame = CGRect(
            x: columnFrame.minX,
            y: columnFrame.minY + contentHeightUsed,
            width: columnFrame.width,
            height: height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: immutable,
            hyperlinkURL: hyperlinkURL,
            source: HwpBlockSource(paragraphId: paragraphId)
        ))
        bandTextBlocks.append((currentBlocks.count - 1, lines))
        // 줄 중간 앵커 기준은 라인 정보가 온전한 (분할되지 않은) 문단 블록만.
        currentParagraphContext = lines.isEmpty ? nil : (frame, lines)
        contentHeightUsed += height
        markBandUsage()
    }

    /// 다단 밴드에서 문단 라인을 현재 단부터 채워 넣는다.
    /// 단이 차면 다음 단으로, 마지막 단이 차면 새 페이지로 이어진다.
    /// reservedFootnoteHeight는 이 문단이 만들 각주 예약분 (본문/각주 겹침 방지).
    func appendParagraphAcrossColumns(
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame,
        paragraphHeight: CGFloat,
        hyperlinkURL: String?,
        paragraphId: UInt32?,
        reservedFootnoteHeight: CGFloat = 0
    ) {
        let lines = paragraphFrame.lines
        let usableHeight = max(1, effectiveContentHeight - reservedFootnoteHeight)
        paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
        guard lines.count > 1, paragraphHeight > 0 else {
            if contentHeightUsed > 0,
               contentHeightUsed + paragraphHeight > usableHeight
            {
                advanceColumn()
                paragraphAnchorTop = currentColumnFrame.minY
            }
            appendBlock(
                height: paragraphHeight,
                attributedString: attributedString,
                hyperlinkURL: hyperlinkURL,
                paragraphId: paragraphId,
                lines: lines
            )
            return
        }

        let lineHeight = paragraphHeight / CGFloat(lines.count)
        var lineIndex = 0
        while lineIndex < lines.count {
            let available = max(1, effectiveContentHeight - reservedFootnoteHeight)
                - contentHeightUsed
            var takeCount = lineHeight > 0 ? Int(available / lineHeight) : lines.count
            if contentHeightUsed <= 0 {
                takeCount = max(1, takeCount)
            }
            if takeCount <= 0 {
                advanceColumn()
                continue
            }
            takeCount = min(takeCount, lines.count - lineIndex)
            let slice = lines[lineIndex ..< lineIndex + takeCount]
            let range = slice.dropFirst().reduce(slice[slice.startIndex].attributedRange) {
                NSUnionRange($0, $1.attributedRange)
            }
            let isWholeParagraph = takeCount == lines.count
            appendBlock(
                height: lineHeight * CGFloat(takeCount),
                attributedString: attributedString.attributedSubstring(from: range),
                hyperlinkURL: hyperlinkURL,
                paragraphId: paragraphId,
                lines: isWholeParagraph ? lines : []
            )
            lineIndex += takeCount
            if lineIndex < lines.count {
                advanceColumn()
            }
        }
    }

    func hyperlinkURL(in paragraph: CoreHwp.HwpParagraph) -> String? {
        paragraph.hyperlinkURL
    }

    // MARK: - 자동 번호/새 번호 (표 142~144)

    /// 새 번호 지정 (nwno)을 카운터에 반영한다. 문단 처리 전에 호출해
    /// 같은 문단의 각주 참조/각주 번호가 재설정된 값부터 시작하게 한다.
    /// (문단 재처리 시에도 같은 값으로 다시 설정되므로 멱등하다.)
    func applyNewNumbers(in paragraph: CoreHwp.HwpParagraph) {
        for ctrl in paragraph.ctrlHeaderArray ?? [] {
            guard case let .newNumber(other) = ctrl,
                  let info = other.newNumberInfo
            else { continue }
            switch info.kind {
            case .page:
                pendingPageNumber = max(1, Int(info.number))
            case .footnote:
                footnoteCounter = max(1, Int(info.number))
            case .endnote:
                endnoteCounter = max(1, Int(info.number))
            case .picture, .table, .equation:
                break
            }
        }
    }

    /// 본문 문단의 extended 마커 치환 (각주/미주 번호 미리보기 + 자동 쪽 번호)
    /// — 산식은 HwpFootnoteCoordinator.noteReferenceReplacements 참조.
    func noteReferenceReplacements(
        for paragraph: CoreHwp.HwpParagraph
    ) -> [Int: HwpControlMarkerReplacement] {
        footnoteCoordinator.noteReferenceReplacements(
            for: paragraph,
            footnoteShape: currentSectionDef?.footNoteShape,
            endnoteShape: currentSectionDef?.endNoteShape,
            pageNumber: pendingPageNumber ?? nextLogicalPageNumber
        )
    }

    // MARK: - Unsupported walk (단일 traversal 지점 유지)

    func collectUnsupported(from paragraph: CoreHwp.HwpParagraph) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        let page = cachedPages.count + 1
        walkUnsupported(ctrls: ctrls, page: page)
    }

    func walkUnsupported(ctrls: [CoreHwp.HwpCtrlId], page: Int, tableDepth: Int = 0) {
        for ctrl in ctrls {
            if let element = unsupportedDetector.classify(ctrl: ctrl, page: page) {
                collectedUnsupported.append(element)
            }
            let isTable = if case .table = ctrl {
                true
            } else {
                false
            }
            // 렌더 경로 (HwpTableLayout)는 중첩 depth 3까지만 재귀 배치하므로
            // 그보다 깊은 중첩 표는 조용히 생략되는 대신 unsupported로 보고한다.
            if isTable, tableDepth > HwpTableLayout.maximumNestingDepth {
                collectedUnsupported.append(HwpUnsupportedElement(
                    kind: .placeholder,
                    page: page,
                    hint: "중첩 표 (깊이 \(HwpTableLayout.maximumNestingDepth) 초과)"
                ))
                continue
            }
            for nested in childParagraphs(of: ctrl).map(\.0) {
                guard let nestedCtrls = nested.ctrlHeaderArray else { continue }
                walkUnsupported(
                    ctrls: nestedCtrls,
                    page: page,
                    tableDepth: isTable ? tableDepth + 1 : tableDepth
                )
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
    /// inTableCell이면 중첩 표는 HwpTableLayout이 이미 셀 안에 재귀 배치했으므로
    /// 별도 블록으로 방출하지 않는다.
    func appendControlBlocks(
        from paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        inTableCell: Bool = false
    ) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        for (ctrlIndex, ctrl) in ctrls.enumerated() {
            // 줄 중간 앵커 문맥은 본문 문단 (depth 0)에서만 유효하다.
            let anchorIndex = depth == 0 ? ctrlIndex : nil
            // 셀 안 그림은 HwpTableLayout이 셀 콘텐츠 (HwpCellImage)로 이미
            // 배치했다 — 페이지 흐름 블록으로 다시 방출하면 큰 그림이 페이지를
            // 밀어내 페이지 수가 한글과 어긋난다 (noori 실측 3쪽).
            if inTableCell, Self.carriesPicture(ctrl) {
                continue
            }
            appendControlBlock(
                ctrl,
                anchorIndex: anchorIndex,
                depth: depth,
                inTableCell: inTableCell
            )
        }
    }

    /// 컨트롤 하나를 종류별 레이아웃 경로로 방출한다 (appendControlBlocks 본문).
    private func appendControlBlock(
        _ ctrl: CoreHwp.HwpCtrlId,
        anchorIndex: Int?,
        depth: Int,
        inTableCell: Bool
    ) {
        switch ctrl {
        case let .table(table):
            if !inTableCell {
                appendTableBlocks(table, controlIndex: anchorIndex)
            }
            appendNestedControlBlocks(of: ctrl, depth: depth)
        case let .genShapeObject(genShape):
            appendShapeObjectBlocks(
                components: genShape.shapeComponentArray,
                commonProperty: genShape.commonCtrlProperty,
                controlIndex: anchorIndex
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
            // 수식 (eqed)은 EQEDIT 스크립트 근사 텍스트 우선 —
            // eqEdit이 없는 개체는 false를 돌려 기존 개체 경로로 간다
            if !appendEquationBlock(shape, controlIndex: anchorIndex) {
                appendShapeObjectBlocks(
                    components: shape.shapeComponentArray,
                    commonProperty: shape.commonCtrlProperty
                        ?? CoreHwp.HwpCommonCtrlProperty(),
                    controlIndex: anchorIndex
                )
            }
            appendNestedControlBlocks(of: ctrl, depth: depth)
        case .header, .footer, .pageNumberPosition, .pageHide:
            pageChrome.register(ctrl)
        case .footnote, .endnote:
            // 각주/미주는 collectFootnotes(from:depth:)가 컨트롤 블록 방출 전에
            // 수집한다 (참조 위치 페이지 귀속).
            break
        default:
            break
        }
    }

    /// 컨트롤이 그림 컴포넌트를 갖는지 (셀 안 인셀 렌더 대상 판별)
    static func carriesPicture(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
        let components: [CoreHwp.HwpShapeComponent]
        switch ctrl {
        case let .genShapeObject(genShape):
            components = genShape.shapeComponentArray
        case let .picture(shape):
            components = shape.shapeComponentArray
        default:
            return false
        }
        return components.contains { !$0.pictureArray.isEmpty }
    }

    /// 컨테이너 문단 안에 중첩된 컨트롤 (표 셀 안 글상자/이미지 등)을 재귀 방출한다.
    func appendNestedControlBlocks(of ctrl: CoreHwp.HwpCtrlId, depth: Int) {
        guard depth < 3 else { return }
        let isTable = if case .table = ctrl {
            true
        } else {
            false
        }
        for (nested, _) in childParagraphs(of: ctrl) where nested.ctrlHeaderArray != nil {
            appendControlBlocks(from: nested, depth: depth + 1, inTableCell: isTable)
        }
    }

    // MARK: 표

    func appendTableBlocks(_ table: CoreHwp.HwpTable, controlIndex: Int? = nil) {
        let result = tableLayout.layout(
            table: table,
            availableWidth: currentColumnFrame.width,
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
            // 글자처럼 취급 표 (표 70): FFFC 앵커 라인 위치에 인라인 배치.
            // 줄 공간은 run delegate가 표 크기로 예약했으므로 흐름을 추가
            // 소비하지 않는다 (noori 실측: 캐시 줄 높이 = 표 높이).
            if table.commonCtrlProperty.propertyInfo.treatAsChar,
               appendInlineAnchoredTable(frame, table: table, controlIndex: controlIndex)
            {
                return
            }
            appendTableSegments(
                frame,
                table: table,
                instanceId: table.commonCtrlProperty.instanceId,
                pageBreakMode: table.tableProperty.pageBreakMode,
                headerRowCount: HwpTableSplitter.repeatingHeaderRowCount(of: table)
            )
        }
    }

    /// 글자처럼 취급 표를 앵커 라인 위치에 배치한다. 앵커가 없으면 false
    /// (호출자가 flow 배치로 폴백 — 라인 분할된 문단 등).
    private func appendInlineAnchoredTable(
        _ frame: HwpTableFrame,
        table: CoreHwp.HwpTable,
        controlIndex: Int?
    ) -> Bool {
        guard let position = inlineAnchorPosition(for: controlIndex) else { return false }
        let height = frame.rows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
        currentBlocks.append(AnyHwpBlock(
            frame: CGRect(
                x: position.x,
                y: position.y,
                width: frame.outerFrame.width,
                height: height
            ),
            kind: .table,
            payload: .table(frame),
            source: HwpBlockSource(controlInstanceId: table.commonCtrlProperty.instanceId)
        ))
        bandHasNonTextContent = true
        return true
    }

    /// 표를 남은 공간에 맞춰 row 단위로 잘라 페이지에 흘린다.
    /// 분할 플랜 (세그먼트 row·절단 기하)은 HwpTableSplitter가 순수 함수로
    /// 산출하고, 이 루프는 페이지 확정 (advanceColumn)·블록 방출만 담당한다.
    ///
    /// - 쪽 경계 나눔이 없으면 (표 76 bits 0-1 == 0) 표를 통째로 두고, 남은
    ///   공간에 안 맞으면 새 페이지로 넘긴다.
    /// - row 하나가 빈 페이지보다 크면 남은 높이에서 잘라 아래쪽을 이월한다.
    /// - headerRowCount > 0이면 (표 76 bit 2) 이어지는 세그먼트마다 제목 행을 복제한다.
    func appendTableSegments(
        _ frame: HwpTableFrame,
        table: CoreHwp.HwpTable? = nil,
        instanceId: UInt32,
        pageBreakMode: CoreHwp.HwpTableProperty.HwpTablePageBreakMode = .split,
        headerRowCount: Int = 0
    ) {
        guard !frame.rows.isEmpty else { return }

        if pageBreakMode == .none {
            let tableHeight = frame.rows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
            if contentHeightUsed > 0, contentHeightUsed + tableHeight > effectiveContentHeight {
                advanceColumn()
            }
            if let table {
                collectTableCellFootnotes(table, rows: nil)
            }
            appendTableSegmentBlock(rows: frame.rows, original: frame, instanceId: instanceId)
            return
        }

        // 반복할 제목 행 (표 전체가 제목이면 반복하지 않는다)
        let repeatedRows = headerRowCount > 0 && headerRowCount < frame.rows.count
            ? Array(frame.rows.prefix(headerRowCount))
            : []
        let repeatedHeight = repeatedRows.isEmpty
            ? 0
            : repeatedRows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
            - (repeatedRows.first?.rowFrame.minY ?? 0)

        var remainingRows = frame.rows
        var isFirstSegment = true
        // 이미 셀 각주를 수집한 최상위 행 — 분할된 행이 다음 세그먼트에서
        // 다시 수집돼 각주가 중복되는 것을 막는다.
        var highestCollectedRow = Int.min

        while !remainingRows.isEmpty {
            // 이어지는 세그먼트는 제목 행 반복 높이를 미리 차감한다.
            let headerAllowance = isFirstSegment ? 0 : repeatedHeight
            var remaining = effectiveContentHeight - contentHeightUsed - headerAllowance
            if remaining < HwpTableSplitter.minimumRowHeight(remainingRows), contentHeightUsed > 0 {
                advanceColumn()
                remaining = effectiveContentHeight - headerAllowance
            }

            // 후보 행의 셀 각주 예약 높이를 미리 반영해 세그먼트를 맞춘다 —
            // 사본으로 시산해 각주 높이만큼 remaining을 줄인 뒤 실제 배치한다.
            // 셀 각주가 없으면 0이라 기존 세그먼트 선택과 동일하다.
            if let table {
                var trialRows = remainingRows
                let trial = HwpTableSplitter.fillSegment(
                    remainingRows: &trialRows, remaining: remaining
                )
                let trialRows2 = trial.flatMap(\.cells).map(\.row)
                if let maxRow = trialRows2.max() {
                    let startRow = max(trialRows2.min() ?? maxRow, highestCollectedRow + 1)
                    if startRow <= maxRow {
                        let notes = anticipatedTableCellFootnoteHeight(
                            table, rows: startRow ... maxRow
                        )
                        if notes > 0 {
                            remaining = max(
                                HwpTableSplitter.minimumRowHeight(remainingRows), remaining - notes
                            )
                        }
                    }
                }
            }

            let segmentRows = HwpTableSplitter.fillSegment(
                remainingRows: &remainingRows,
                remaining: remaining
            )
            guard !segmentRows.isEmpty else { break }

            // 셀 각주는 행이 실리는 페이지 귀속 (한글 실측 — 헌법주석 p485).
            // 분할된 행은 조각이 같은 rowAddress를 유지하므로, 이미 수집한 행보다
            // 큰 행만 수집해 조각 간 중복 각주를 막는다.
            if let table {
                let rowIndexes = segmentRows.flatMap(\.cells).map(\.row)
                if let maxRow = rowIndexes.max() {
                    let startRow = max(rowIndexes.min() ?? maxRow, highestCollectedRow + 1)
                    if startRow <= maxRow {
                        collectTableCellFootnotes(table, rows: startRow ... maxRow)
                        highestCollectedRow = maxRow
                    }
                }
            }
            appendTableSegmentBlock(
                rows: segmentRows,
                original: frame,
                instanceId: instanceId,
                repeatedHeaderRows: isFirstSegment ? [] : repeatedRows
            )
            isFirstSegment = false
        }
    }

    /// 세그먼트 표 프레임 산출 (제목 줄 반복 포함)은 HwpTableSplitter에 위임하고,
    /// 여기서는 페이지 좌표 블록 방출과 흐름 상태 갱신만 한다.
    func appendTableSegmentBlock(
        rows: [HwpTableRowFrame],
        original: HwpTableFrame,
        instanceId: UInt32,
        repeatedHeaderRows: [HwpTableRowFrame] = []
    ) {
        guard let segmentFrame = HwpTableSplitter.segmentFrame(
            rows: rows,
            original: original,
            repeatedHeaderRows: repeatedHeaderRows
        ) else { return }
        let segmentHeight = segmentFrame.outerFrame.height

        let columnFrame = currentColumnFrame
        let blockFrame = CGRect(
            x: columnFrame.minX,
            y: columnFrame.minY + contentHeightUsed,
            width: segmentFrame.outerFrame.width,
            height: segmentHeight
        )
        currentBlocks.append(AnyHwpBlock(
            frame: blockFrame,
            kind: .table,
            payload: .table(segmentFrame),
            source: HwpBlockSource(controlInstanceId: instanceId)
        ))
        bandHasNonTextContent = true
        contentHeightUsed += segmentHeight
        markBandUsage()
    }

    // MARK: 개체 (글상자/도형/그림)

    func appendShapeObjectBlocks(
        components: [CoreHwp.HwpShapeComponent],
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        controlIndex: Int? = nil
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
                attributedText: textboxFrame.paragraphs.map(\.attributedString),
                controlIndex: controlIndex
            )
        }

        for component in components {
            if let picture = component.pictureArray.first {
                appendImageBlock(
                    picture: picture,
                    component: component,
                    commonProperty: commonProperty,
                    size: size,
                    controlIndex: controlIndex
                )
            } else if let chart = chartFrame(of: component) {
                // OLE 내장 차트 — 데이터 근사 렌더 (빈 도형 상자 대신)
                appendAnchoredBlock(
                    kind: .shape,
                    size: size,
                    payload: .chart(chart),
                    commonProperty: commonProperty,
                    controlIndex: controlIndex
                )
            } else if component.textBoxListArray.isEmpty,
                      let geometry = HwpShapeGeometry.build(component: component, size: size)
            {
                appendAnchoredBlock(
                    kind: .shape,
                    size: size,
                    payload: .shape(geometry),
                    commonProperty: commonProperty,
                    controlIndex: controlIndex
                )
            }
        }
    }

    /// OLE 개체 요소가 내장 차트면 BinData CFB에서 차트 데이터를 파싱한다.
    /// 차트가 아니거나 파싱 실패면 nil (기존 도형 상자 경로로 폴백).
    private func chartFrame(
        of component: CoreHwp.HwpShapeComponent
    ) -> HwpChartFrame? {
        guard let ole = component.oleArray.first,
              let binaryDataId = ole.binaryDataId,
              let payload = imageStore.data(forBinItemId: binaryDataId),
              let xml = CoreHwp.HwpEmbeddedChart.chartXML(fromOLEPayload: payload)
        else { return nil }
        return HwpChartParser.parse(xml: xml)
    }

    /// 수식 (eqed) 컨트롤을 EQEDIT 스크립트 근사 텍스트로 방출한다.
    /// 스크립트가 비어 있으면 false — 호출자가 개체 경로로 폴백한다.
    func appendEquationBlock(
        _ shape: CoreHwp.HwpShapeControl,
        controlIndex: Int?
    ) -> Bool {
        guard let edit = shape.eqEditArray.first else { return false }
        let commonProperty = shape.commonCtrlProperty ?? CoreHwp.HwpCommonCtrlProperty()
        let size = objectSize(
            commonProperty: commonProperty,
            components: shape.shapeComponentArray
        )
        guard let attributed = HwpEquationLayout.attributedString(
            edit: edit,
            fallbackSize: size.height,
            fontResolver: fontResolver
        ) else { return false }
        // 근사 텍스트가 저장된 개체 폭보다 길면 폭을 늘려 한 줄을 유지한다
        // (한글.app 수식은 줄바꿈 없이 한 줄 — equation 실물 캡처)
        let line = CTLineCreateWithAttributedString(attributed)
        let measuredWidth = ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) + 2
        let blockSize = CGSize(width: max(size.width, measuredWidth), height: size.height)
        // kind는 개체 (.textbox) — 인라인 앵커 개체는 자기 문단 text 블록과
        // 겹치는 것이 정상이라 text-text 겹침 검사 대상이 아니어야 한다
        appendAnchoredBlock(
            kind: .textbox,
            size: blockSize,
            payload: nil,
            commonProperty: commonProperty,
            attributedText: [attributed],
            controlIndex: controlIndex
        )
        return true
    }

    func objectSize(
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        components: [CoreHwp.HwpShapeComponent]
    ) -> CGSize {
        var width = HwpUnits.points(fromHwpUnitU: commonProperty.width)
        var height = HwpUnits.points(fromHwpUnitU: commonProperty.height)
        if width <= 0 || height <= 0, let detail = components.first?.detail {
            if width <= 0 {
                width = HwpUnits.points(fromHwpUnitU: detail.currentWidth)
            }
            if height <= 0 {
                height = HwpUnits.points(fromHwpUnitU: detail.currentHeight)
            }
        }
        return CGSize(width: max(1, width), height: max(1, height))
    }

    func appendImageBlock(
        picture: CoreHwp.HwpShapeComponentPicture,
        component _: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        size: CGSize,
        controlIndex: Int? = nil
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
                borderWidth: borderWidth,
                style: property.map { imageRenderStyle(from: $0) }
            )),
            commonProperty: commonProperty,
            controlIndex: controlIndex
        )
    }

    /// 표 107 그림 속성에서 crop/밝기/명암/효과 렌더 스타일을 만든다.
    func imageRenderStyle(from property: CoreHwp.HwpPictureProperty) -> HwpImageRenderStyle {
        HwpImageRenderStyle(
            cropLeft: property.cropLeft,
            cropTop: property.cropTop,
            cropRight: property.cropRight,
            cropBottom: property.cropBottom,
            brightness: Int(property.brightness),
            contrast: Int(property.contrast),
            effect: HwpImageEffect(rawEffect: property.effect)
        )
    }

    /// 앵커 규칙 (표 70)에 따라 개체 블록을 배치한다.
    ///
    /// - 글자처럼 취급 (treatAsChar)이고 문단 라인에서 U+FFFC 앵커를 찾으면:
    ///   그 라인 위치에 배치한다 (줄 높이는 run delegate가 이미 예약 —
    ///   흐름 높이를 추가 소비하지 않는다).
    /// - treatAsChar (앵커 없음) 또는 본문 흐름을 차지하는 wrap:
    ///   현재 흐름 위치에 배치하고 높이를 소비한다.
    /// - 나머지 (글 앞/뒤로 포함 anchored): 기준 (쪽/문단) + 오프셋 위치에 배치하고
    ///   본문 흐름을 소비하지 않는다.
    /// 개체 블록 하나의 내용 (배치 방식과 무관한 공통 값)
    struct ObjectBlockSpec {
        let kind: HwpBlockKind
        let size: CGSize
        /// nil이면 payload 없는 순수 텍스트 블록 (수식 근사 등 — drawText만)
        let payload: HwpBlockPayload?
        let attributedString: NSAttributedString?
        let instanceId: UInt32
    }

    func appendAnchoredBlock(
        kind: HwpBlockKind,
        size: CGSize,
        payload: HwpBlockPayload?,
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        attributedText: [NSAttributedString] = [],
        controlIndex: Int? = nil
    ) {
        let info = commonProperty.propertyInfo
        let spec = ObjectBlockSpec(
            kind: kind,
            size: size,
            payload: payload,
            attributedString: combinedAttributedString(attributedText),
            instanceId: commonProperty.instanceId
        )

        if info.treatAsChar, appendInlineAnchoredBlock(spec, controlIndex: controlIndex) {
            return
        }

        if info.treatAsChar || consumesFlow(info) {
            // 세로 기준이 종이/쪽/문단인 개체는 흐름 커서가 아니라 기준+
            // 오프셋 위치에 놓이고, 본문 흐름은 개체 아래로 밀린다
            // (한글 실측: text-box 종이 46.2/35.6mm, chart 문단 상단 —
            // 흐름 커서 배치는 앵커 문단 줄 높이만큼 밀린다).
            if !info.treatAsChar, info.verticalRelativeTo != nil {
                appendAbsolutePositionedFlowBlock(spec, commonProperty: commonProperty)
                return
            }
            appendFlowBlock(
                kind: spec.kind,
                size: spec.size,
                payload: spec.payload,
                attributedString: spec.attributedString,
                instanceId: spec.instanceId
            )
            return
        }

        appendFloatingBlock(spec, commonProperty: commonProperty)
    }

    /// 글 앞/뒤로 등 흐름을 소비하지 않는 개체를 기준 + 오프셋 위치에 배치한다.
    private func appendFloatingBlock(
        _ spec: ObjectBlockSpec,
        commonProperty: CoreHwp.HwpCommonCtrlProperty
    ) {
        let info = commonProperty.propertyInfo
        let contentFrame = currentPageGeometry.contentFrame
        // 기준 + 오프셋 (음수 오프셋 허용)
        let offsetX = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.horizontalOffset)
        )
        let offsetY = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.verticalOffset)
        )
        let baseX: CGFloat = switch info.horizontalRelativeTo {
        case .paper: 0
        case .page, nil: contentFrame.minX
        case .column, .paragraph: currentColumnFrame.minX
        }
        let baseY: CGFloat = switch info.verticalRelativeTo {
        case .paper: 0
        case .page, nil: contentFrame.minY
        case .paragraph: paragraphAnchorTop
        }
        let frame = CGRect(
            x: baseX + offsetX,
            y: baseY + offsetY,
            width: spec.size.width,
            height: spec.size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: spec.kind,
            attributedString: spec.attributedString,
            payload: spec.payload,
            source: HwpBlockSource(controlInstanceId: spec.instanceId)
        ))
        bandHasNonTextContent = true
    }

    /// 본문 흐름을 소비하는 블록을 현재 흐름 위치에 배치한다.
    /// 남은 공간에 안 맞으면 (블록이 단에 들어가는 크기일 때) 다음 단/페이지로 넘긴다.
    /// 종이/쪽 기준 절대 위치 + 흐름 회피 (topAndBottom류) 개체:
    /// 기준+오프셋 위치에 놓고, 개체 하단이 흐름 커서보다 아래면 본문
    /// 흐름을 개체 아래로 내린다.
    private func appendAbsolutePositionedFlowBlock(
        _ spec: ObjectBlockSpec,
        commonProperty: CoreHwp.HwpCommonCtrlProperty
    ) {
        let info = commonProperty.propertyInfo
        let contentFrame = currentPageGeometry.contentFrame
        let offsetX = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.horizontalOffset)
        )
        let offsetY = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.verticalOffset)
        )
        let baseX: CGFloat = switch info.horizontalRelativeTo {
        case .paper: 0
        case .page, nil: contentFrame.minX
        case .column, .paragraph: currentColumnFrame.minX
        }
        let baseY: CGFloat = switch info.verticalRelativeTo {
        case .paper: 0
        case .paragraph: paragraphAnchorTop
        default: contentFrame.minY
        }
        let frame = CGRect(
            x: baseX + offsetX,
            y: baseY + offsetY,
            width: spec.size.width,
            height: spec.size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: spec.kind,
            attributedString: spec.attributedString,
            payload: spec.payload,
            source: HwpBlockSource(controlInstanceId: spec.instanceId)
        ))
        bandHasNonTextContent = true
        // 본문 흐름을 개체 밴드 아래로 (topAndBottom 회피)
        let flowBottom = frame.maxY - currentColumnFrame.minY
        if flowBottom > contentHeightUsed {
            contentHeightUsed = flowBottom
        }
        markBandUsage()
    }

    private func appendFlowBlock(
        kind: HwpBlockKind,
        size: CGSize,
        payload: HwpBlockPayload?,
        attributedString: NSAttributedString?,
        instanceId: UInt32
    ) {
        if contentHeightUsed > 0,
           contentHeightUsed + size.height > effectiveContentHeight,
           size.height <= currentColumnFrame.height
        {
            advanceColumn()
        }
        let columnFrame = currentColumnFrame
        let frame = CGRect(
            x: columnFrame.minX,
            y: columnFrame.minY + contentHeightUsed,
            width: min(size.width, columnFrame.width),
            height: size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: kind,
            attributedString: attributedString,
            payload: payload,
            source: HwpBlockSource(controlInstanceId: instanceId)
        ))
        bandHasNonTextContent = true
        contentHeightUsed += size.height
        markBandUsage()
    }

    /// treatAsChar 개체를 FFFC 앵커 라인 위치에 배치한다. 앵커가 없으면 false
    /// (호출자가 flow 배치로 폴백). 줄 높이는 run delegate가 이미 예약했으므로
    /// 흐름 높이를 추가 소비하지 않는다.
    private func appendInlineAnchoredBlock(
        _ spec: ObjectBlockSpec,
        controlIndex: Int?
    ) -> Bool {
        guard let position = inlineAnchorPosition(for: controlIndex) else { return false }
        let contentFrame = currentPageGeometry.contentFrame
        let frame = CGRect(
            x: position.x,
            y: position.y,
            width: min(spec.size.width, max(1, contentFrame.maxX - position.x)),
            height: spec.size.height
        )
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: spec.kind,
            attributedString: spec.attributedString,
            payload: spec.payload,
            source: HwpBlockSource(controlInstanceId: spec.instanceId)
        ))
        bandHasNonTextContent = true
        return true
    }

    /// 방금 배치한 문단의 라인에서 controlIndex의 U+FFFC 앵커를 찾아
    /// 개체의 페이지 좌표 (왼쪽 위)를 계산한다.
    ///
    /// 라인 baseline의 블록 내 y = 첫 라인 baseline(= lines[0].baseline) +
    /// 라인 origin.y (첫 baseline 기준 delta). 개체 위 = baseline - 앵커 ascent
    /// (run delegate가 예약한 개체 높이).
    func inlineAnchorPosition(for controlIndex: Int?) -> CGPoint? {
        guard let controlIndex,
              let context = currentParagraphContext,
              let firstBaseline = context.lines.first?.baseline
        else { return nil }
        for line in context.lines {
            guard let anchor = line.inlineAnchors.first(where: {
                $0.controlIndex == controlIndex
            }) else { continue }
            let baselineY = context.blockFrame.minY + firstBaseline + line.origin.y
            return CGPoint(
                x: context.blockFrame.minX + line.origin.x + anchor.xOffset,
                y: baselineY - anchor.ascent
            )
        }
        return nil
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
            if offset > 0 {
                combined.append(NSAttributedString(string: "\n"))
            }
            combined.append(string)
        }
        return combined
    }

    func appendPlaceholderBlock(hint: String) {
        let height: CGFloat = 20
        if contentHeightUsed > 0, contentHeightUsed + height > effectiveContentHeight {
            advanceColumn()
        }
        let columnFrame = currentColumnFrame
        currentBlocks.append(AnyHwpBlock(
            frame: CGRect(
                x: columnFrame.minX,
                y: columnFrame.minY + contentHeightUsed,
                width: columnFrame.width,
                height: height
            ),
            kind: .placeholder,
            attributedString: NSAttributedString(string: hint)
        ))
        bandHasNonTextContent = true
        contentHeightUsed += height
        markBandUsage()
    }

    // MARK: 각주/미주

    /// 문단(과 컨테이너 안 문단)의 각주를 이 페이지 몫으로 수집한다.
    /// 표 분할 등 다른 컨트롤 방출이 페이지를 넘기기 전에 호출해
    /// 각주를 참조 위치의 페이지에 귀속시킨다.
    /// 문단의 메모 (댓글) 필드를 이 페이지의 풍선 목록에 수집한다.
    /// 앵커 y는 방금 배치한 문단 텍스트 블록의 상단 (풍선 본문 줄이 앵커
    /// 줄과 나란— 한글.app 실측). 메모 본문은 MEMO_LIST 뒤 문단 자식.
    func collectMemos(from paragraph: CoreHwp.HwpParagraph) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        let memoFields: [CoreHwp.HwpFieldControl] = ctrls.compactMap {
            if case let .memo(field) = $0 {
                field
            } else {
                nil
            }
        }
        guard !memoFields.isEmpty else { return }
        let anchorY = currentBlocks.last { $0.kind == .text }?.frame.minY
            ?? currentPageGeometry.contentFrame.minY
        let bodies = (paragraph.memoParagraphArray ?? []).map { memoParagraph in
            HwpTextRunBuilder(index: index, fontResolver: fontResolver)
                .build(paragraph: memoParagraph)
                .string
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (fieldIndex, field) in memoFields.enumerated() {
            pendingMemoBalloons.append(HwpMemoPanelPainter.Balloon(
                anchorY: anchorY,
                author: field.memoParameter?.author ?? "",
                dateText: Self.memoDateText(field.memoParameter),
                body: fieldIndex < bodies.count ? bodies[fieldIndex] : ""
            ))
        }
    }

    /// 메모 필드 파라미터의 FILETIME (100ns since 1601, low/high DWORD 순)을
    /// 한글.app 풍선 헤더 형식 "yyyy/MM/dd HH:mm"으로 만든다.
    static func memoDateText(_ parameter: CoreHwp.HwpMemoFieldParameter?) -> String {
        guard let fields = parameter?.fields, fields.count >= 4,
              let low = UInt64(fields[2]), let high = UInt64(fields[3]),
              low <= UInt64(UInt32.max), high <= UInt64(UInt32.max)
        else { return "" }
        let ticks = (high << 32) | low
        let unixSeconds = Double(ticks) / 10_000_000 - 11_644_473_600
        guard unixSeconds > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: unixSeconds))
    }

    // MARK: 각주/미주 수집·측정·예약 (HwpFootnoteCoordinator 위임)

    /// 측정/예약이 읽는 페이지·구역 환경 — 호출 시점 값 주입
    var noteEnvironment: HwpFootnoteCoordinator.Environment {
        HwpFootnoteCoordinator.Environment(
            contentWidth: currentPageGeometry.contentFrame.width,
            footnoteShape: currentSectionDef?.footNoteShape
        )
    }

    /// includeTableCells: 표 셀 안 각주 포함 여부 (HwpFootnoteCoordinator 참조)
    func collectFootnotes(
        from paragraph: CoreHwp.HwpParagraph,
        includeTableCells: Bool = true
    ) {
        footnoteCoordinator.collectFootnotes(
            from: paragraph,
            includeTableCells: includeTableCells,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 표 셀 각주를 수집한다. rows가 nil이면 전체 (HwpFootnoteCoordinator 참조)
    func collectTableCellFootnotes(_ table: CoreHwp.HwpTable, rows: ClosedRange<Int>?) {
        footnoteCoordinator.collectTableCellFootnotes(
            table,
            rows: rows,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 표 세그먼트 크기 산정 전 후보 행의 셀 각주 예약 높이 (HwpFootnoteCoordinator 참조)
    func anticipatedTableCellFootnoteHeight(
        _ table: CoreHwp.HwpTable,
        rows: ClosedRange<Int>
    ) -> CGFloat {
        footnoteCoordinator.anticipatedTableCellFootnoteHeight(
            table,
            rows: rows,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    // MARK: 미주 (문서/구역 끝)

    /// 모아 둔 미주를 현재 흐름 아래에 전체 폭 1단으로 배치한다.
    /// 남은 공간이 부족하면 다음 페이지로 이어 붙인다.
    func appendPendingEndnotes() {
        guard !pendingEndnotes.isEmpty else { return }
        // 미주 영역은 전체 폭: 진행 중인 다단 밴드를 닫고 그 아래에서 시작한다.
        closeColumnBand()
        currentColumnDef = nil
        openColumnBand(top: bandUsedBottom)

        // 첫 미주가 남은 공간에 안 들어가면 새 페이지에서 시작한다
        // (미주는 구분선을 그리지 않으므로 — 아래 drawSeparator = false —
        // 구분선 오버헤드 없이 실제 배치 높이만 본다).
        if let first = pendingEndnotes.first,
           currentColumnFrame.minY > currentPageGeometry.contentFrame.minY,
           measuredFootnoteHeight(of: first.paragraph, number: first.number)
           > effectiveContentHeight
        {
            cacheCurrentPage()
        }

        // 한글.app 실물 (footnote-endnote 2쪽): 미주 위에는 구분선을 그리지
        // 않고, 텍스트가 본문 상단에서 바로 시작한다.
        var drawSeparator = false
        while !pendingEndnotes.isEmpty {
            let columnFrame = currentColumnFrame
            let available = CGRect(
                x: columnFrame.minX,
                y: columnFrame.minY,
                width: columnFrame.width,
                height: effectiveContentHeight
            )
            let placement = footnoteCoordinator.placePendingEndnotes(
                from: columnFrame.minY + contentHeightUsed,
                in: available,
                endnoteShape: currentSectionDef?.endNoteShape,
                drawSeparator: drawSeparator
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
            bandHasNonTextContent = true
            contentHeightUsed = placement.bottom - columnFrame.minY
            markBandUsage()
            pendingEndnotes = placement.overflow
            if !pendingEndnotes.isEmpty {
                // 1단 밴드이므로 다음 단 == 새 페이지
                cacheCurrentPage()
                drawSeparator = false
            }
        }
    }

    /// 이월된 각주 입력들이 새 페이지에서 예약할 높이 (HwpFootnoteCoordinator 참조)
    func reservedFootnoteHeight(for inputs: [HwpFootnoteLayout.Input]) -> CGFloat {
        footnoteCoordinator.reservedFootnoteHeight(for: inputs, environment: noteEnvironment)
    }

    /// 이 문단이 페이지에 추가될 때 각주 영역이 요구할 높이 (커밋 전 예측용,
    /// HwpFootnoteCoordinator 참조)
    func anticipatedFootnoteHeight(for paragraph: CoreHwp.HwpParagraph) -> CGFloat {
        footnoteCoordinator.anticipatedFootnoteHeight(
            for: paragraph,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 각주 문단 높이 측정 (라인 캐시 우선, HwpFootnoteCoordinator 참조)
    func measuredFootnoteHeight(of paragraph: CoreHwp.HwpParagraph, number: Int) -> CGFloat {
        footnoteCoordinator.measuredFootnoteHeight(
            of: paragraph,
            number: number,
            environment: noteEnvironment
        )
    }

    /// 대기 중인 각주를 페이지 하단에 배치한다. 영역(콘텐츠 절반 상한)을
    /// 넘는 각주는 pendingFootnotes에 남겨 다음 페이지로 이월한다.
    func appendPendingFootnotes() {
        guard !pendingFootnotes.isEmpty else { return }
        // 절대 캐시 모드에서 본문 y는 캐시로 고정된다. 한글의 본문 절단점은
        // 이미 그 페이지 각주 공간을 반영하므로, 각주는 페이지 하단 기준으로
        // 그대로 쌓는다 — 하한을 강제해 이월시키면 한글에 없는 각주 전용
        // 페이지가 연쇄로 생긴다 (헌법주석 실측 1,031 → 1,054).
        // 절대 캐시 모드에선 절반 상한도 두지 않는다 — 한글이 확정한 페이지의
        // 각주는 참조 페이지에 전부 둔다 (이월 예약이 한글에 없는 페이지
        // 절단을 만든다 — 헌법주석 p485 실측 1,031 → 1,030).
        let placement = footnoteCoordinator.placePendingFootnotes(
            onPage: currentPageGeometry,
            footnoteShape: currentSectionDef?.footNoteShape,
            limitsAreaToHalfContent: !absoluteCacheMode
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
        // 머리말/꼬리말/쪽 번호 크롬 블록 (감추기 마스크는 빌더가 소비한다)
        currentBlocks += pageChrome.blocks(
            forPage: nextLogicalPageNumber,
            geometry: currentPageGeometry
        )
        nextLogicalPageNumber += 1
        appendPendingFootnotes()
        let pageIndex = cachedPages.count
        let page = HwpPage(
            size: currentPageGeometry.pageSize,
            margins: currentPageGeometry.margins,
            blocks: currentBlocks,
            pageNumber: pageIndex + 1
        )
        let paintList = paintListBuilder.build(for: page, index: index)
        // 메모 풍선은 종이 밖 오른쪽 패널 (한글.app 편집 뷰) — 페이지
        // paintList와 분리해 인쇄 뷰·PrvImage 정합에는 영향을 주지 않는다.
        let memoPanel = pendingMemoBalloons.isEmpty
            ? nil
            : HwpMemoPanelPainter.panel(
                balloons: pendingMemoBalloons,
                pageSize: currentPageGeometry.pageSize
            )
        pendingMemoBalloons = []
        cachedPages[pageIndex] = HwpPage(
            size: page.size,
            margins: page.margins,
            blocks: page.blocks,
            pageNumber: page.pageNumber,
            paintList: paintList,
            memoPanel: memoPanel
        )
        currentBlocks = []
        // 페이지가 넘어가면 이전 페이지 문단의 줄 앵커 좌표는 무효다.
        currentParagraphContext = nil
        // 새 페이지: 절대 캐시 loc 추적과 stale 캐시 보정을 리셋한다.
        lastAbsoluteCacheLoc = Int32.min
        absoluteCacheStaleOffset = 0
        // 새 페이지: 현재 단 정의로 콘텐츠 상단부터 새 밴드를 연다.
        openColumnBand(top: currentPageGeometry.contentFrame.minY)
        // 이월된 각주가 새 페이지에서 차지할 영역을 다시 예약한다.
        footnoteReservedHeight = reservedFootnoteHeight(for: pendingFootnotes)
        if currentSectionDef?.footNoteShape.numberingModeRawValue == 2 {
            footnoteCounter = Self.initialNoteNumber(
                startingNumber: currentSectionDef?.footNoteShape.startingNumber
            )
        }
    }

    func height(for paragraph: CoreHwp.HwpParagraph, fallback: CGFloat) -> CGFloat {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard isValidLineSegmentCache(segments) else { return fallback }
        // 일부 저장본 (한/글 2007 계열)은 lineLocation을 문단-상대 (0 시작)가 아니라
        // 페이지 내 누적 절대 y로 기록한다. 첫 세그먼트 위치를 빼서 문단-상대 높이로
        // 정규화한다 (첫 lineLocation == 0인 저장본에서는 동일 규칙).
        //
        // 실제 줄 전진량은 캐시가 직접 준다: lineHeight + lineSpacing (per-line 필드).
        // 실측: 연속 세그먼트의 lineLocation 델타와 일치 (헌법주석 30,345/30,348,
        // noori 문단 내 전부 — 저장 세대와 무관).
        let top = segments[0].lineLocation
        var bottom = top
        for segment in segments {
            bottom = max(
                bottom,
                segment.lineLocation + HwpAbsoluteCachePlacer.lineAdvance(of: segment)
            )
        }
        let lineHeights = max(0, HwpUnits.points(fromHwpUnit: bottom - top))
        // 문단 간격 위/아래는 캐시에 포함되지 않으므로 CT 폴백 경로
        // (paragraphSpacingBefore/After)와 동일하게 더한다. paraShape가
        // 없으면 간격 0 — optional helper를 쓴다.
        let paraShape = index.paraShape(for: paragraph)
        let spacing = paraShape.map {
            max(0, HwpUnits.points(fromHwpUnit: $0.paragraphSpacingTop))
                + max(0, HwpUnits.points(fromHwpUnit: $0.paragraphSpacingBottom))
        } ?? 0
        return lineHeights + spacing
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
