import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// swiftlint:disable file_length

public actor HwpPaginator {
    private let sections: [CoreHwp.HwpSection]
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    /// 글자 모양별 텍스트 속성 캐시 — 문서(파이프라인) 단위 소유. 본문·표 셀·
    /// 글상자·각주·머리말/꼬리말이 전부 이 하나를 공유한다. 전역이면 안 되는
    /// 이유는 `HwpTextAttributeCache` 참조.
    private let attributeCache = HwpTextAttributeCache()
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
    /// 변경 추적(PARA_RANGE_TAG kind 16/17) 문단의 paraId — 페이지가 캐시될
    /// 때마다 그 페이지 조각에 변경 막대를 방출한다 (페이지 걸친 문단의 앞
    /// 조각도 막대를 받게, #7).
    private var trackChangeParagraphIds: Set<UInt32> = []
    private var contentHeightUsed: CGFloat = 0
    private var didFinishPagination = false

    /// 문서 전역 페이지 상한 — 쪽 나누기 문단·별개 표가 다수면 표당 세그먼트
    /// 상한(maximumTableSegments)만으로는 총 페이지가 무제한이라, 작은 레코드
    /// 스트림이 수십만 페이지로 증폭돼 paint-list 메모리를 고갈시킨다 (#1).
    /// 페이지마다 블록·attributed string·paint list를 상주 보존하므로 한도는
    /// 모바일 프로세스가 실제로 감당 가능한 수준이어야 방어가 성립한다 —
    /// legacy 실측 최대 1,030쪽의 약 10배 여유로 정상 대형 문서는 통과시키고
    /// 병적 증폭은 수십 MB 수준에서 절단한다.
    static let maximumDocumentPages = 10000
    /// 컨테이너 안 컨테이너 재귀 방출 상한. 렌더(appendNestedControlBlocks)와
    /// 진단(walkUnsupported), 탐색 목록 수집(`HwpOutlineCollector`)이 같은 값을
    /// 써야 초과분이 조용히 사라지지 않는다.
    static let maximumContainerDepth = 3
    /// 인스턴스 상한 (기본 = 전역 상한) — 테스트가 cap 도달 경로를 작은
    /// 문서로 재현할 수 있게 재정의를 허용한다.
    var maximumPages = HwpPaginator.maximumDocumentPages
    /// 표 하나가 만들 수 있는 세그먼트 상한 (기본 = 전역 상한) — 위와 같은 이유로
    /// 인스턴스 값이다.
    var maximumTableSegments = HwpTableLayout.maximumTableSegments
    private var isComputingPage = false

    func overrideMaximumPages(_ count: Int) {
        maximumPages = count
    }

    /// 탐색 목록 항목 상한 재정의 (테스트가 절단 경로를 작은 문서로 재현한다).
    func overrideMaximumOutlineItems(_ count: Int) {
        outlineCollector.maximumItems = count
    }

    /// 표 세그먼트 상한 재정의 (테스트가 행 절단 경로를 작은 표로 재현한다).
    func overrideMaximumTableSegments(_ count: Int) {
        maximumTableSegments = count
    }

    private var collectedUnsupported: [HwpUnsupportedElement] = []
    /// 이 문단의 **첫 조각이 실제로 놓인** 쪽 (1-기반, 문단마다 리셋).
    /// 배치 **전**에 잡은 값은 다단에서 낡는다 — `placeMultiColumnParagraph`는
    /// 미루기(`false` 반환)가 없어 마지막 단이 모자라면 스스로 쪽을 넘긴 뒤
    /// 첫 줄을 놓는다 (1단 경로는 미뤄서 재계산되므로 안전하다).
    private var currentParagraphFirstPlacedPage: Int?
    /// 개요·책갈피 탐색 목록 수집기 (#77) — 쪽 귀속이 조판의 함수라 여기 산다.
    private var outlineCollector: HwpOutlineCollector
    /// 세그먼트 상한에 걸려 **일부 행만 방출된** 표: 인스턴스 id → (표, 방출 행 수).
    /// 탐색 목록이 그려지지 않은 행의 앵커를 내지 않게 하는 입력이다.
    /// id로 버킷만 좁히고 표 값으로 확정하는 근거는 `truncatedRowLimit(of:)`.
    private var truncatedTableRowLimits: [UInt32: [(table: CoreHwp.HwpTable, rowLimit: Int)]] = [:]
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
    /// 현재 문단의 좌우 여백 (표 43, 1/2 단위 해석 후 pt) — '문단' 기준
    /// 개체의 폭/원점 산출용 (#2). 문단 처리 시작 시 갱신된다.
    private var currentParagraphMargins: (left: CGFloat, right: CGFloat) = (0, 0)
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
    /// 이번 배치가 각주를 **조각 단위로 이미 수집했는지** (#95). 페이지에 걸친
    /// 절대 캐시 문단은 run마다 그 조각의 각주를 그 페이지에 담으므로, 문단 루프의
    /// 문단 단위 수집을 건너뛰어야 이중 수집(번호 중복)이 되지 않는다.
    /// placeParagraphText가 매 호출 초기화하고 절대 캐시 경로만 켠다.
    private var collectedFootnotesDuringPlacement = false
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
    private var currentParagraphContext: (blockFrame: CGRect, lines: [HwpLineFrame])? {
        didSet { inlineAnchorCache = nil }
    }

    /// controlIndex → 인라인 앵커 페이지 좌표 캐시 — 컨트롤마다 전 라인·앵커를
    /// 처음부터 스캔하지 않도록 컨텍스트당 한 번만 만든다 (#12).
    private var inlineAnchorCache: [Int: CGPoint]?
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
        tableLayout = HwpTableLayout(
            fontResolver: fontResolver, attributeCache: attributeCache
        )
        textboxLayout = HwpTextboxLayout(
            fontResolver: fontResolver, attributeCache: attributeCache
        )
        footnoteCoordinator = HwpFootnoteCoordinator(
            index: index, fontResolver: fontResolver, attributeCache: attributeCache
        )
        pageChrome = HwpPageChromeBuilder(
            index: index, fontResolver: fontResolver, attributeCache: attributeCache
        )
        absoluteCachePlacer = HwpAbsoluteCachePlacer(sections: sections)
        outlineCollector = HwpOutlineCollector(index: index)
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
            try await computeNextPageSerialized()
        }
        return cachedPages[index]
    }

    public func totalPages() async -> Int {
        while !didFinishPagination {
            await Task.yield()
            do {
                try await computeNextPageSerialized()
            } catch {
                break
            }
        }
        return max(1, cachedPages.count)
    }

    /// computeNextPage는 내부 suspension(Task.yield 등)에서 actor 재진입이
    /// 열리는데 병렬 실행에 안전하지 않다 (문단 커서·페이지 캐시 교차 오염) —
    /// 진행 중이면 완료를 기다린 뒤 반환해 호출자 루프가 조건을 재평가하게
    /// 한다. Task 체이닝 대신 플래그 대기인 이유: 문단 루프의
    /// checkCancellation이 호출자 자신의 취소를 관찰해야 한다 (R38 #1).
    private func computeNextPageSerialized() async throws {
        guard !isComputingPage else {
            while isComputingPage {
                try Task.checkCancellation()
                await Task.yield()
            }
            return
        }
        isComputingPage = true
        defer { isComputingPage = false }
        try await computeNextPage()
    }

    public func unsupportedElements() async -> [HwpUnsupportedElement] {
        collectedUnsupported
    }

    /// 지금까지 조판이 확정한 개요·책갈피 탐색 목록 (문서 순서, #77).
    ///
    /// `unsupportedElements()`와 달리 **조판 도중에 물어도 의미가 있다** —
    /// 확정된 쪽까지의 접두를 돌려주므로 프로그레시브 로딩의 중간 스냅샷이
    /// 그대로 실어 보낸다 (`HwpDocumentMetadata.outline`).
    /// 탐색 목록이 **항목 상한에 걸려 잘렸는가** (#77).
    ///
    /// 목록만으로는 완전한 것과 구별되지 않아 호스트가 온전한 탐색 수단으로
    /// 오인한다 — 책갈피는 미지원 목록에도 뜨지 않으므로 이 신호가 유일한 흔적이다.
    /// 확정 쪽 접두로 잘린 것(`outline()`)은 여기 해당하지 않는다: 그쪽은 조판이
    /// 끝나면 나온다.
    public func outlineIsTruncated() async -> Bool {
        outlineCollector.didReachItemLimit
    }

    public func outline() async -> [HwpOutlineItem] {
        // **확정된 쪽까지만** 낸다. 배치 도중 수집된 항목은 `cachedPages.count + 1`
        // 을 가리키는데 그 쪽은 아직 캐시되지 않았고, 취소되면 끝내 만들어지지
        // 않는다 — 그대로 내보내면 공개 API가 없는 쪽으로 안내한다.
        // `filter`가 아니라 `prefix`인 것은 발행분이 최종 목록의 접두여야
        // `ordinal`이 흔들리지 않기 때문이다 (`HwpDocumentActor`와 같은 술어).
        Array(outlineCollector.items.prefix { $0.pageNumber <= cachedPages.count })
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
        // 한글은 단 정의로 밴드를 닫을 때 마지막 줄의 줄 간격만큼 띄우고
        // 다음 밴드를 연다 (Column PrvImage 실측: 밴드 간 시작 간격
        // = 줄 전진량 + 줄 간격). 새-페이지 판정도 gap을 더한 실제 시작점으로
        // 한다 — gap 몫을 빼면 한 줄 최소에 못 미치는 퇴화 밴드가 열린다 (R56 #2).
        let gap = hadBandContent ? bandTrailingLineSpacing : 0
        if bandUsedBottom + gap >= usableBottom - minimumBandHeight, !currentBlocks.isEmpty {
            cacheCurrentPage()
        } else {
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
            // 페이지 상한 도달 후 남은 문단은 레이아웃해도 캐시되지 않는다 —
            // 즉시 종료해 상한이 CPU 상한으로도 작동하게 한다 (#1).
            if didFinishPagination {
                return
            }
            // 취소된 로드가 0-높이 문단을 대량 처리할 때 page(at:) 반환 전에
            // 취소를 관찰해 옛 문서 레이아웃이 교체본과 나란히 도는 것을 막는다 (#3).
            try Task.checkCancellation()
            // 구역 시작/쪽 나누기 문단: 진행 중인 페이지를 확정하고 이 문단은
            // 다음 호출에서 새 페이지 첫머리로 다시 처리한다.
            if try flushPageBeforeProcessing(paragraph) {
                return
            }

            applySectionDef(in: paragraph)
            applyColumnDef(in: paragraph)
            applyNewNumbers(in: paragraph)
            currentParagraphMargins = paragraphMargins(of: paragraph)

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
                attributedString = textRunBuilder()
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
            // 번호/개요 문단 머리의 진단 페이지는 문단이 시작하는 첫 페이지다 —
            // placeParagraphText가 다중 페이지 문단의 앞 조각 페이지를 먼저
            // 캐시하므로 배치 전에 첫 페이지를 잡는다 (#3).
            let paragraphFirstPage = cachedPages.count + 1
            currentParagraphFirstPlacedPage = nil
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
            collectParagraphFootnotesUnlessPlacedPerFragment(paragraph)
            collectMemos(from: paragraph)
            appendControlBlocks(from: paragraph)
            collectUnsupported(from: paragraph, firstPage: paragraphFirstPage)
            collectOutline(from: paragraph, firstPage: paragraphFirstPage)
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
        try appendPendingEndnotes()
        cacheCurrentPage()
        // 마지막 페이지에서 넘친 각주가 있으면 빈 페이지를 이어 붙여 모두 배치한다.
        // 페이지 상한에 걸려 cacheCurrentPage가 캐시를 거부하면(didFinishPagination
        // = true, pendingFootnotes 불변) 무한 회전하므로 그때 멈춘다 (#4).
        while !pendingFootnotes.isEmpty, !didFinishPagination {
            // 취소 시 각주 드레인이 페이지 상한까지 동기로 돌아 취소 관찰이
            // 늦어지지 않게 매 페이지 확인 (문단 루프 389와 동일, P2b).
            try Task.checkCancellation()
            cacheCurrentPage()
        }
        didFinishPagination = true
    }

    /// 새 구역 정의 (이전 구역의 밴드를 닫고 구역-끝 미주 배치) 또는
    /// 쪽 나누기 (문단 헤더 columnType bit 2)를 만나면 진행 중인 페이지를
    /// 확정한다. 페이지를 확정했으면 true (호출자가 반환하고 같은 문단을
    /// 새 페이지에서 다시 처리한다).
    func flushPageBeforeProcessing(_ paragraph: CoreHwp.HwpParagraph) throws -> Bool {
        if Self.sectionDef(in: paragraph) != nil {
            closeColumnBand()
            if currentSectionDef?.endNoteShape.placesEndnoteAtSectionEnd == true {
                try appendPendingEndnotes()
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
        // 조각 단위 각주 수집 여부는 배치 경로가 정한다 (#95) — 매 배치마다
        // 초기화해 앞 문단의 값이 새지 않게 한다. 미룬 컨테이너 각주 버퍼도
        // 열쇠(컨트롤 서수)가 문단 안에서만 유일해 같이 비운다.
        collectedFootnotesDuringPlacement = false
        footnoteCoordinator.resetDeferredNestedFootnotes()
        // 변경 추적 문단이면 배치 전에 paraId를 기록한다 — 배치 중 페이지가
        // 캐시될 때마다 (절대 캐시 run·advanceColumn) 그 조각이 막대를 받게 (#7).
        recordTrackChangeParagraphIfNeeded(for: paragraph)
        // 절대 캐시 모드 (1단): 한글이 계산한 y/페이지 절단점을 그대로 재현한다.
        return if absoluteCacheMode, columnFrames.count <= 1,
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
    }

    /// 변경 추적 마크(PARA_RANGE_TAG kind 16/17)가 있으면 paraId를 기록한다.
    /// 실제 막대는 페이지 캐시 직전 emitTrackChangeBars가 조각마다 그린다 (#7).
    private func recordTrackChangeParagraphIfNeeded(for paragraph: CoreHwp.HwpParagraph) {
        let hasTrackChange = (paragraph.paraRangeTagArray ?? []).contains { tag in
            let kind = tag.tag >> 24
            return kind == 16 || kind == 17
        }
        if hasTrackChange {
            trackChangeParagraphIds.insert(paragraph.paraHeader.paraId)
        }
    }

    /// 변경 추적 문단이 이 페이지에 만든 각 텍스트 조각 왼쪽에 한글.app처럼
    /// 빨간 변경 막대를 그린다. 페이지가 캐시되기 직전에 호출돼, 페이지 걸친
    /// 문단의 앞 조각도 자기 페이지에서 막대를 받는다 — 배치 후 currentBlocks만
    /// 보면 이미 캐시된 앞 페이지 조각이 빠진다 (#7, round13 #2 미완).
    private func emitTrackChangeBars() {
        guard !trackChangeParagraphIds.isEmpty else { return }
        let barX = currentPageGeometry.contentFrame.minX - 10
        let barColor = CGColor(srgbRed: 0.87, green: 0.14, blue: 0.1, alpha: 1)
        let bars: [AnyHwpBlock] = currentBlocks.compactMap { block in
            guard block.kind == .text,
                  let paragraphId = block.source?.paragraphId,
                  trackChangeParagraphIds.contains(paragraphId) else { return nil }
            let barRect = CGRect(x: 0, y: 0, width: 1.2, height: block.frame.height)
            return AnyHwpBlock(
                frame: CGRect(
                    x: barX, y: block.frame.minY, width: barRect.width, height: barRect.height
                ),
                kind: .shape,
                payload: .shape(HwpShapeGeometry(
                    path: CGPath(rect: barRect, transform: nil),
                    fillColor: barColor,
                    strokeColor: nil,
                    strokeWidth: 0
                ))
            )
        }
        currentBlocks.append(contentsOf: bars)
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
        // 문단-앞 간격은 paragraphHeight에 포함되지만 CoreText는 각 블록(별도
        // 프레임의 첫 문단)에 paragraphSpacingBefore를 렌더하지 않는다 — 모든 배치
        // 경로(다단·초과 조각·단일 블록)가 텍스트 앞에서 커서로 소비한다 (P1, #1).
        let beforeGap = index.paraShape(for: paragraph).map {
            max(0, HwpUnits.points(fromHwpUnit: $0.paragraphSpacingTop) / 2)
        } ?? 0
        if columnFrames.count > 1 {
            placeMultiColumnParagraph(
                paragraph,
                attributedString: attributedString,
                paragraphFrame: paragraphFrame,
                paragraphHeight: paragraphHeight,
                anticipatedFootnotes: anticipatedFootnotes,
                beforeGap: beforeGap
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
                reservedFootnoteHeight: anticipatedFootnotes,
                beforeGap: beforeGap
            )
            updateBandTrailingSpacing(for: paragraph)
            return true
        }
        contentHeightUsed += beforeGap
        paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
        appendBlock(
            height: paragraphHeight - beforeGap,
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
        anticipatedFootnotes: CGFloat,
        beforeGap: CGFloat = 0
    ) {
        // 캐시 run 경로는 한글이 계산한 절대 위치를 그대로 재현하므로 간격 보정을
        // 더하지 않는다 (#1).
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
            reservedFootnoteHeight: anticipatedFootnotes,
            beforeGap: beforeGap
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
            var runBottom = Int(firstSegment.lineLocation)
            for segment in run {
                runBottom = max(runBottom, HwpAbsoluteCachePlacer.lineBottom(of: segment))
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
                    fromHwpUnit: Int32(clamping: runBottom - Int(firstSegment.lineLocation))
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

        // 페이지에 걸친 문단의 각주는 참조가 놓인 **조각의 페이지**에 실린다
        // (#95). 조각을 먼저 다 자른 뒤 그 조각에 실제로 그려진 마커 서수로
        // 범위를 나눈다 — 배치와 귀속이 같은 경계를 쓴다. run마다 수집하면 다음
        // 반복 머리의 cacheCurrentPage가 그 페이지를 확정하며 각주를 배치한다.
        // 경계를 못 믿으면 (서수 불일치) nil이라 호출자가 문단 전체를 마지막
        // 조각 페이지에 귀속시키는 기존 동작으로 폴백한다.
        let slices = absoluteRunSlices(
            runs: runs,
            attributedString: attributedString,
            lines: paragraphFrame.lines
        )
        let ordinalRanges = HwpAbsoluteCachePlacer.controlOrdinalRanges(
            slices: slices.map(\.text),
            controlCount: paragraph.ctrlHeaderArray?.count ?? 0
        )
        // 조각에 걸쳐 그려진 마커는 조각마다 **일부**만 갖는다 — 그 일부를 완전한
        // 번호로 바꾸면 다음 쪽에 남은 나머지와 합쳐 깨진다 (번호가 그대로여도).
        let splitMarkers = HwpAbsoluteCachePlacer.ordinalsSpanningSlices(slices.map(\.text))
        for (runIndex, run) in runs.enumerated() {
            if runIndex > 0 {
                cacheCurrentPage()
            }
            guard let runFirstSegment = run.first else { continue }
            let runFirst = runFirstSegment.lineLocation
            var height = absoluteRunBlockHeight(run: run, firstLocation: runFirst)
            let slice = slices[runIndex]
            let sliceText = renumberedNoteMarkers(
                in: slice.text,
                paragraph: paragraph,
                ordinals: ordinalRanges?[runIndex],
                skipping: splitMarkers
            )
            // appendBlock은 columnFrame.minY + contentHeightUsed에 배치하므로
            // 한글이 준 절대 y (+ stale 캐시 보정)로 커서를 옮긴다.
            contentHeightUsed = max(0, HwpUnits.points(fromHwpUnit: runFirst))
                + absoluteCacheStaleOffset
            height = staleAdjustedHeight(
                height, runs: runs, run: run, slice: sliceText, frame: paragraphFrame
            )
            paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
            appendBlock(
                height: height,
                attributedString: sliceText,
                hyperlinkURL: hyperlinkURL(in: paragraph),
                paragraphId: paragraph.paraHeader.paraId,
                lines: slice.lines
            )
            lastAbsoluteCacheLoc = run.last?.lineLocation ?? runFirst
            collectFragmentFootnotes(
                from: paragraph,
                ordinals: ordinalRanges?[runIndex],
                collectsNested: runIndex == runs.count - 1
            )
        }
        collectedFootnotesDuringPlacement = ordinalRanges != nil
        return true
    }

    /// 문단 단위 각주 수집 — 배치가 조각마다 이미 담았으면 건너뛴다 (#95).
    /// 건너뛰지 않으면 같은 각주가 두 번 세어져 번호와 개수가 어긋난다.
    private func collectParagraphFootnotesUnlessPlacedPerFragment(
        _ paragraph: CoreHwp.HwpParagraph
    ) {
        guard !collectedFootnotesDuringPlacement else { return }
        collectFootnotes(from: paragraph, includeTableCells: false)
    }

    /// 이 페이지 조각에 실린 각주만 지금 페이지에 담는다 (#95).
    ///
    /// 다음 run 머리의 `cacheCurrentPage`가 이 페이지를 확정하며 방금 담은 각주를
    /// 배치한다 — 그 사이에 예약(`footnoteReservedHeight`)을 읽는 코드가 없어
    /// 본문 절단점이 흔들리지 않는다. `ordinals`가 nil이면 조각 경계를 못 믿는
    /// 문단이라 아무것도 하지 않고, 호출자가 문단 단위로 수집한다 (기존 동작).
    /// 표 셀 각주 제외는 문단 단위 수집과 같은 필터다 (행 페이지 귀속).
    private func collectFragmentFootnotes(
        from paragraph: CoreHwp.HwpParagraph,
        ordinals: Range<Int>?,
        collectsNested: Bool
    ) {
        guard let ordinals else { return }
        collectFootnotes(
            from: paragraph,
            includeTableCells: false,
            ordinals: ordinals,
            collectsNested: collectsNested
        )
    }

    /// run별 텍스트 조각 — 배치 **전에** 한 번에 자른다 (#95). 각주 귀속이 이
    /// 조각들을 근거로 나뉘므로 (`controlOrdinalRanges`) 자르는 곳이 한 군데여야
    /// 배치와 귀속이 갈리지 않는다.
    private func absoluteRunSlices(
        runs: [[CoreHwp.HwpParaLineSegInternal]],
        attributedString: NSAttributedString,
        lines: [HwpLineFrame]
    ) -> [(text: NSAttributedString, lines: [HwpLineFrame])] {
        let totalSegments = runs.reduce(0) { $0 + $1.count }
        var slices: [(text: NSAttributedString, lines: [HwpLineFrame])] = []
        slices.reserveCapacity(runs.count)
        var lineCursor = 0
        for (runIndex, run) in runs.enumerated() {
            slices.append(HwpAbsoluteCachePlacer.runAttributedSlice(
                runIndex: runIndex,
                runShare: HwpAbsoluteCachePlacer.RunShare(
                    segments: run.count,
                    total: totalSegments,
                    runCount: runs.count
                ),
                attributedString: attributedString,
                lines: lines,
                lineCursor: &lineCursor
            ))
        }
        return slices
    }

    /// 조각의 각주/미주 참조 마커를 **그 조각이 실릴 페이지의 번호**로 다시 쓴다.
    ///
    /// 마커 번호는 조판 전에 문단 단위로 한 번 구워지는데, "쪽마다 새로 시작"
    /// (표 134 numberingMode 2) 구역에서 문단이 페이지에 걸치면 run 사이
    /// `cacheCurrentPage`가 카운터를 리셋해 뒤 조각의 마커가 수집 번호와 어긋난다
    /// (참조는 2), 각주는 1)). 배치 직전 현재 카운터로 다시 계산하면 둘이 같은
    /// 번호를 쓴다 — 수집은 이 뒤에 오므로 카운터는 앞 조각 몫까지만 반영돼 있다.
    /// 번호가 그대로면 (연속 번호 문서 전부) 원본을 그대로 돌려줘 렌더가 불변이다.
    /// 쪽 번호 필드 (atno kind 0)는 대상이 아니다 — 같은 낡음이 있지만 코퍼스
    /// 실측 없이 바꾸면 렌더가 조용히 달라진다.
    ///
    /// **남는 근사**: 조판 (`paragraphFrame`) 과 슬라이스는 옛 번호로 이미 끝난
    /// 뒤라, 번호 폭이 바뀌면 (9) → 10)) 그 조각 **안**의 줄바꿈이 조판 당시와
    /// 달라질 수 있다. 조각 **소속**은 문자 범위로 고정돼 텍스트가 다른 쪽으로
    /// 새지는 않는다. 근본 해결은 순환이다 — 번호는 실릴 쪽이 정해져야 알 수
    /// 있고, 그 쪽은 배치가, 배치는 조판이 끝나야 안다. 고정점 반복을 새로
    /// 들이는 값이 모드 2 문서 (코퍼스 0건) 하나에 비해 크다. 가드:
    /// `testRenumberingKeepsMarkerAndNoteInSyncWhenWidthChanges` (번호 정합만).
    private func renumberedNoteMarkers(
        in slice: NSAttributedString,
        paragraph: CoreHwp.HwpParagraph,
        ordinals: Range<Int>?,
        skipping splitMarkers: Set<Int>
    ) -> NSAttributedString {
        guard let ordinals, !ordinals.isEmpty,
              let ctrls = paragraph.ctrlHeaderArray
        else { return slice }
        let noteReplacements = noteReferenceReplacements(for: paragraph, ordinals: ordinals)
            .filter { ordinal, _ in
                guard !splitMarkers.contains(ordinal),
                      ctrls.indices.contains(ordinal) else { return false }
                return switch ctrls[ordinal] {
                case .footnote, .endnote: true
                default: false
                }
            }
        return HwpTextRunBuilder.renumberingNoteMarkers(
            in: slice, replacements: noteReplacements
        )
    }

    /// stale 캐시 (캐시 줄 높이 < 선언 글자 크기) 보정된 run 높이.
    ///
    /// 한글.app도 이런 문단은 열 때 재조판해 줄을 CT 자연 높이로 넓힌다 — 슬롯을
    /// CT 높이로 키우고 이후 문단을 그만큼 민다 (`absoluteCacheStaleOffset`).
    /// 신선한 캐시 (h ≥ 글자 크기)에서는 절대 발동하지 않는다 (헌법주석 페이지
    /// 절단 유지). 여러 run으로 나뉜 문단은 대상이 아니다 — 조각마다 CT 높이를
    /// 다시 배분할 수 없다.
    private func staleAdjustedHeight(
        _ height: CGFloat,
        runs: [[CoreHwp.HwpParaLineSegInternal]],
        run: [CoreHwp.HwpParaLineSegInternal],
        slice: NSAttributedString,
        frame: HwpParagraphFrame
    ) -> CGFloat {
        guard runs.count == 1,
              HwpAbsoluteCachePlacer.cacheIsStale(run: run, attributedString: slice),
              frame.totalHeight > height
        else { return height }
        absoluteCacheStaleOffset += frame.totalHeight - height
        return frame.totalHeight
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
        pageChrome.applySectionHideFlags(sectionDef)
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
            tabStops: attributeCache.textTabs(for: paraShape, index: index)
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
        // 문단의 첫 콘텐츠가 페이지에 놓이는 지금 보류된 쪽 번호 리셋을 확정한다 —
        // 열/쪽에 걸친 조각이 캐시되기 전에 적용해야 시작 페이지가 새 번호를
        // 갖는다 (조각 캐시 후 적용하면 시작 페이지가 옛 번호로 남는다 — #12).
        // 미적합 재시도는 appendBlock 전에 return하므로 리셋이 보류로 남아 올바르다.
        if let reset = pendingPageNumber {
            nextLogicalPageNumber = reset
            pendingPageNumber = nil
        }
        // 여기가 문단의 첫 콘텐츠가 쪽에 놓이는 지점이라 개요의 시작 쪽도 여기서
        // 확정된다 (위 쪽 번호 리셋과 같은 순간이다).
        if currentParagraphFirstPlacedPage == nil {
            currentParagraphFirstPlacedPage = cachedPages.count + 1
        }
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
    func containsHyperlinkFieldSpans(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.hyperlink,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// reservedFootnoteHeight는 이 문단이 만들 각주 예약분 (본문/각주 겹침 방지).
    func appendParagraphAcrossColumns(
        attributedString: NSAttributedString,
        paragraphFrame: HwpParagraphFrame,
        paragraphHeight: CGFloat,
        hyperlinkURL: String?,
        paragraphId: UInt32?,
        reservedFootnoteHeight: CGFloat = 0,
        beforeGap: CGFloat = 0
    ) {
        let lines = paragraphFrame.lines
        let usableHeight = max(1, effectiveContentHeight - reservedFootnoteHeight)
        // 조각들은 독립 CT 프레임이라 문단-앞 간격이 렌더되지 않는다 — 첫 조각
        // 앞에서 커서로 소비하고 이후 산술은 텍스트 몫(textHeight)만 쓴다 (#1).
        // 넘김 판정은 (커서+gap) + text = 커서 + paragraphHeight로 종전과 동치.
        // 빈 단에서 gap을 먼저 더하면 단이 점유된 듯 보여 초과 문단이 빈 단을
        // 건너뛴다 — gap 추가 전 빈 단 여부를 보존한다 (R54 #3).
        let startedEmpty = contentHeightUsed <= 0
        contentHeightUsed += beforeGap
        let textHeight = paragraphHeight - beforeGap
        // 필드 스팬 문단(hyperlink attribute 보유)의 조각 블록엔 URL을 전파하지
        // 않는다 — 링크는 조각 substring의 attribute region이 운반하고, block URL은
        // region 없는 평문 조각 전체를 폴백 링크로 만든다 (#4).
        let fragmentURL = containsHyperlinkFieldSpans(attributedString) ? nil : hyperlinkURL
        paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
        guard lines.count > 1, textHeight > 0 else {
            if startedEmpty {
                // 빈 단: gap+text가 안 맞는 초과 문단이면 gap을 무르고 현재 단 top에
                // flush한다 — 빈 단을 건너뛰지 않는다 (R54 #3).
                if beforeGap + textHeight > usableHeight {
                    contentHeightUsed = 0
                    paragraphAnchorTop = currentColumnFrame.minY
                }
            } else if contentHeightUsed + textHeight > usableHeight {
                // 부분 채운 단에 안 맞으면 다음 단으로 옮기고 새 단 top에 gap을
                // 재적용한다 — 다중 줄·본문 경로와 일치 (R54 #2). gap+text가 빈
                // 단보다 크면 진행 보장을 위해 flush. 단 이동이 페이지를 넘기면
                // 각주 예약이 바뀌므로 usable을 재계산한다 (R55 #4). 이동 문단의
                // gap은 구 단에 렌더되지 않으므로 markBandUsage 전에 무른다 —
                // 밴드 하단이 부풀면 다음 밴드가 밀리거나 불필요한 새 페이지 (R56 #3).
                contentHeightUsed -= beforeGap
                advanceColumn()
                if beforeGap + textHeight
                    <= max(1, effectiveContentHeight - reservedFootnoteHeight)
                {
                    contentHeightUsed += beforeGap
                }
                paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
            }
            appendBlock(
                height: textHeight,
                attributedString: attributedString,
                hyperlinkURL: hyperlinkURL,
                paragraphId: paragraphId,
                lines: lines
            )
            return
        }

        // 라인별 실제 전진량(origin.y 델타)으로 조각을 나눈다 — 평균
        // (textHeight/개수)은 문단 간격까지 라인에 배분해 혼합 높이/간격
        // 문단을 잘못된 라인에서 절단한다 (#3). 마지막 라인이 잔여(간격 포함)를
        // 흡수해 조각 높이 총합 = textHeight를 보존한다. origin이 비단조면
        // 평균으로 폴백한다 (#4와 동일).
        let strictlyIncreasing = zip(lines, lines.dropFirst())
            .allSatisfy { $0.origin.y < $1.origin.y }
        let averageLineHeight = textHeight / CGFloat(lines.count)
        func lineAdvance(_ index: Int) -> CGFloat {
            guard strictlyIncreasing else { return max(1, averageLineHeight) }
            if index + 1 < lines.count {
                return max(1, lines[index + 1].origin.y - lines[index].origin.y)
            }
            return max(1, textHeight - lines[index].origin.y)
        }
        var lineIndex = 0
        while lineIndex < lines.count {
            let available = max(1, effectiveContentHeight - reservedFootnoteHeight)
                - contentHeightUsed
            var takeCount = 0
            var takenHeight: CGFloat = 0
            while lineIndex + takeCount < lines.count,
                  takenHeight + lineAdvance(lineIndex + takeCount) <= available
            {
                takenHeight += lineAdvance(lineIndex + takeCount)
                takeCount += 1
            }
            // 빈 단(gap만 charge)에서 gap+첫 줄이 안 맞는 초과 문단은 gap을 무르고
            // 첫 줄을 현재 단 top에 flush한다 — 빈 단을 건너뛰지 않는다 (R54 #3).
            // 단 이동 후의 빈 단은 contentHeightUsed<=0로 판정한다.
            let onEmptyStartColumn = startedEmpty && lineIndex == 0
            if contentHeightUsed <= 0 || onEmptyStartColumn, takeCount == 0 {
                if onEmptyStartColumn {
                    contentHeightUsed = 0
                    paragraphAnchorTop = currentColumnFrame.minY
                }
                takenHeight = lineAdvance(lineIndex)
                takeCount = 1
            }
            if takeCount <= 0 {
                // 아직 아무 줄도 안 놓은 통째 이동이면 진입 시 charge한 gap을
                // 구 단 사용량에서 무른다 — 렌더되지 않을 gap이 markBandUsage로
                // 밴드 하단을 부풀린다 (R56 #3). 이후 단에서 재적용될 수 있다.
                if lineIndex == 0 {
                    contentHeightUsed = max(0, contentHeightUsed - beforeGap)
                }
                advanceColumn()
                // 페이지 상한 도달: cacheCurrentPage가 밴드/커서를 리셋하지
                // 않고 종료하므로 같은 lineIndex 재시도는 무한 루프다 —
                // 남은 줄은 상한 절단 계약대로 버린다 (#1).
                if didFinishPagination {
                    return
                }
                // 문단 첫 줄을 통째로 새 단으로 옮기면(아직 아무 줄도 안 놓음) 문단
                // 위 간격을 새 단 top에도 유지한다 — 본문 단일 열이 새 페이지 top에서
                // gap을 렌더하는 것(placeFlowParagraph)과 일치 (R53 #1). gap+첫 줄이
                // 빈 단보다 크면 진행 보장을 위해 flush 배치한다. 단 이동이 페이지를
                // 넘기면 각주 예약이 바뀌므로 usable을 재계산하고 (R55 #4), gap을
                // 물리면 .paragraph 기준 개체의 anchor도 함께 내린다 (R55 #5).
                let usableAfterAdvance = max(1, effectiveContentHeight - reservedFootnoteHeight)
                if lineIndex == 0, beforeGap + lineAdvance(0) <= usableAfterAdvance {
                    contentHeightUsed += beforeGap
                    paragraphAnchorTop = currentColumnFrame.minY + contentHeightUsed
                }
                continue
            }
            let slice = lines[lineIndex ..< lineIndex + takeCount]
            let range = slice.dropFirst().reduce(slice[slice.startIndex].attributedRange) {
                NSUnionRange($0, $1.attributedRange)
            }
            let isWholeParagraph = takeCount == lines.count
            appendBlock(
                height: takenHeight,
                attributedString: attributedString.attributedSubstring(from: range),
                hyperlinkURL: isWholeParagraph ? hyperlinkURL : fragmentURL,
                paragraphId: paragraphId,
                lines: isWholeParagraph ? lines : []
            )
            lineIndex += takeCount
            if lineIndex < lines.count {
                advanceColumn()
                if didFinishPagination {
                    return
                }
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
        for paragraph: CoreHwp.HwpParagraph,
        ordinals: Range<Int>? = nil
    ) -> [Int: HwpControlMarkerReplacement] {
        footnoteCoordinator.noteReferenceReplacements(
            for: paragraph,
            footnoteShape: currentSectionDef?.footNoteShape,
            endnoteShape: currentSectionDef?.endNoteShape,
            pageNumber: pendingPageNumber ?? nextLogicalPageNumber,
            ordinals: ordinals
        )
    }

    // MARK: - Unsupported walk (단일 traversal 지점 유지)

    func collectUnsupported(from paragraph: CoreHwp.HwpParagraph, firstPage: Int) {
        // 번호/개요 마커는 문단 첫 페이지 첫 줄에 속하므로 firstPage로 보고하고,
        // 컨트롤은 현재 배치 페이지 기준으로 보고한다 (#3).
        collectUnsupportedNumberingHeading(from: paragraph, page: firstPage)
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        walkUnsupported(ctrls: ctrls, page: cachedPages.count + 1)
    }

    /// 개요(머리 종류 1)/번호(2) 문단 머리의 생성 라벨은 numbering 정의에 있고
    /// PARA_TEXT에 없다 — 렌더러가 아직 그 라벨을 만들지 않으므로, 번호가
    /// 조용히 사라지지 않게 unsupported로 보고한다. 글머리표(3)는
    /// appendBulletHeading이 렌더하므로 제외 (#1).
    private func collectUnsupportedNumberingHeading(
        from paragraph: CoreHwp.HwpParagraph,
        page: Int
    ) {
        guard let paraShape = index.paraShape(
            id: UInt32(paragraph.paraHeader.paraShapeId)
        ) else { return }
        let headingType = paraShape.property1Info.headingTypeRawValue
        guard headingType == 1 || headingType == 2,
              paraShape.numberingOrBulletId > 0
        else { return }
        collectedUnsupported.append(HwpUnsupportedElement(
            kind: .placeholder,
            page: page,
            hint: headingType == 1 ? "개요 번호 문단 머리 (미렌더)" : "번호 매기기 문단 머리 (미렌더)"
        ))
    }

    /// 개요·책갈피 탐색 목록 수집 (#77). `collectUnsupported`와 같은 자리에서
    /// 같은 두 페이지 값을 쓴다 — 문단 머리는 문단이 **시작한** 쪽(`firstPage`),
    /// 컨트롤은 배치가 **끝난** 쪽. 같은 개요 문단이 미지원 목록(생성 라벨
    /// 미렌더 진단)과 탐색 목록에 동시에 뜨는 것은 의도다
    /// (`HwpOutlineCollector.collectHeading` doc-comment 참조).
    func collectOutline(from paragraph: CoreHwp.HwpParagraph, firstPage: Int) {
        // 상한에 걸린 쪽은 끝내 캐시되지 않는데 문단 배치는 한 쪽 더 진행되므로,
        // 안 막으면 **문서에 없는 쪽**을 가리키는 항목이 남는다. 다만 자르는 것은
        // **쪽 값마다 따로**다 (`collect`의 `maximumPage`) — 하나로 묶으면 상한
        // 쪽에서 시작해 걸치는 제목까지 버린다. 클램프가 아니라 버리는 근거는
        // 루트 `AGENTS.md`의 "개요·책갈피 탐색 (#77)".
        outlineCollector.collect(
            from: paragraph,
            // 개요 쪽은 문단의 **첫 조각이 놓인** 쪽이다 — 인자로 받은 사전
            // 포착값은 다단에서 낡는다 (`currentParagraphFirstPlacedPage` 참조).
            // 텍스트 블록이 하나도 없는 문단(개체만 있는 문단)은 기록이 없으므로
            // 그때만 사전 포착값으로 폴백한다. 진단(`collectUnsupported`)은 종전
            // 값을 그대로 쓴다 — 보고 문자열이고 공개 출력이라 별건이다.
            headingPage: currentParagraphFirstPlacedPage ?? firstPage,
            bookmarkPage: cachedPages.count + 1,
            maximumPage: maximumPages,
            childParagraphs: outlineChildParagraphs(of:context:)
        )
    }

    func walkUnsupported(
        ctrls: [CoreHwp.HwpCtrlId],
        page: Int,
        tableDepth: Int = 0,
        containerDepth: Int = 0
    ) {
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
            let children = childParagraphs(of: ctrl).map(\.0)
            // 이 깊이에서 appendNestedControlBlocks가 자식 방출을 멈춘다 — 그 안의
            // 그림·도형·표·글상자가 조용히 사라지므로 진단으로 보고한다 (R72 #4).
            // 표는 자체 한도 (HwpTableLayout.maximumNestingDepth)와 전용 진단을
            // 쓰므로 제외한다 — 여기서 가로채면 위의 "중첩 표" 보고가 사라진다.
            if !isTable,
               containerDepth >= Self.maximumContainerDepth,
               children.contains(where: { !($0.ctrlHeaderArray ?? []).isEmpty })
            {
                collectedUnsupported.append(HwpUnsupportedElement(
                    kind: .placeholder,
                    page: page,
                    hint: "중첩 컨테이너 (깊이 \(Self.maximumContainerDepth) 초과)"
                ))
                continue
            }
            for nested in children {
                guard let nestedCtrls = nested.ctrlHeaderArray else { continue }
                walkUnsupported(
                    ctrls: nestedCtrls,
                    page: page,
                    tableDepth: isTable ? tableDepth + 1 : tableDepth,
                    containerDepth: containerDepth + 1
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

    /// 이 표가 세그먼트 상한에 걸려 **일부 행만 방출**됐다면 그 행 수.
    ///
    /// **인스턴스 id만으로 찾으면 안 된다.** "문서 내 각 개체에 대한 고유 아이디"라는
    /// 모델 doc과 달리 파서는 중복을 거부하지 않고 공개 기본값이 0이라, 잘린 표가
    /// 남긴 상한이 뒤의 **온전히 렌더된** 표에 적용돼 실제로 그려진 행의 책갈피가
    /// 조용히 사라진다 (실측: 잘린 3행 표 뒤 2행 표에서 2행 앵커가 목록에만 없다).
    /// id는 버킷을 좁히는 데만 쓰고 표 값으로 확정한다 — 잘린 표가 없는 정상
    /// 문서는 miss 한 번이라 깊은 비교를 하지 않는다.
    private func truncatedRowLimit(of table: CoreHwp.HwpTable) -> Int? {
        truncatedTableRowLimits[table.commonCtrlProperty.instanceId]?
            .first { $0.table == table }?.rowLimit
    }

    /// 탐색 목록 전용 순회 — 개체(gso 계열)는 **렌더되는 컴포넌트만** 본다.
    ///
    /// `childParagraphs`는 전 컴포넌트를 도는데 `HwpTextboxLayout`은 텍스트를 가진
    /// **첫** 컴포넌트만 그리므로, 그대로 쓰면 그려지지 않은 텍스트의 앵커가
    /// 목록에 올라 누르면 아무것도 없는 자리로 간다 (실측: 컴포넌트 2개 중 첫째만
    /// 렌더되는데 목록엔 둘 다). 진단·흐름 경로는 `childParagraphs`를 그대로
    /// 쓴다 — 그쪽은 "그려지지 않는 것"을 보고하는 것이 일이다.
    func outlineChildParagraphs(
        of ctrl: CoreHwp.HwpCtrlId,
        context: HwpOutlineCollector.RenderContext
    ) -> [HwpOutlineCollector.ChildParagraph] {
        // 각주는 **어디에 있든** `HwpFootnoteCoordinator`가 걷어 그리므로, 안
        // 그려지는 자리 안이라도 그 각주는 순회한다 (실측: 각주 안 글상자 속
        // 각주 텍스트가 렌더에 있는데 목록은 비어 있었다).
        switch ctrl {
        case .footnote, .endnote:
            return childParagraphs(of: ctrl).map {
                HwpOutlineCollector.ChildParagraph(paragraph: $0.0, rendersText: true)
            }
        default:
            break
        }
        // 그 밖에는 아무것도 그려지지 않는 자리에서 더 내려가지 않는다.
        guard context.drawsAnything else { return [] }
        return switch ctrl {
        case let .table(table):
            // 배치가 거부한 셀(선언 격자 밖·occupancy 충돌)은 그려지지 않는다.
            // 세그먼트 상한에 걸려 방출되지 않은 행도 같다 — 배치는 받아들였지만
            // 페이지에 그려진 적이 없다.
            tableLayout.renderedCells(of: table, rowLimit: truncatedRowLimit(of: table))
                .flatMap(\.paragraphArray)
                .map { HwpOutlineCollector.ChildParagraph(paragraph: $0, rendersText: true) }
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
            // 수식 근사 텍스트로 그려지는 개체는 글상자 경로를 타지 않는다 —
            // 렌더 분기(`appendControlBlocks`)와 같은 판정을 공유한다.
            equationAttributedString(shape) != nil ? [] : objectChildParagraphs(
                of: ctrl, components: shape.shapeComponentArray, context: context
            )
        case let .genShapeObject(genShape):
            objectChildParagraphs(
                of: ctrl, components: genShape.shapeComponentArray, context: context
            )
        default:
            childParagraphs(of: ctrl).map {
                HwpOutlineCollector.ChildParagraph(paragraph: $0.0, rendersText: true)
            }
        }
    }

    /// 이 컨트롤의 **전 컴포넌트가** 그려지는가.
    ///
    /// 부모가 표 셀·각주라는 것만으로는 모자란다 — `HwpParagraphObjectCollector`가
    /// 건너뛰는 컨트롤(수집 대상이 아닌 종류, OLE를 품은 컴포넌트)은 컨테이너
    /// 안에서도 **흐름 경로**가 그리고, 그쪽은 첫 컴포넌트만 본다. 판정을 그
    /// 수집기의 술어(`handledControl`·`collectible`)에서 그대로 파생시켜야
    /// 갈리지 않는다 (실측: OLE를 품은 개체를 셀에 넣으면 렌더는 첫 컴포넌트뿐인데
    /// 목록엔 둘 다 올랐다). 셀·각주 수집기는 `collectsTextboxes: true`로 부른다
    /// (`HwpTableLayout`·`HwpFootnoteLayout`).
    private func containerDrawsEveryComponent(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
        guard let (_, components) = HwpParagraphObjectCollector.handledControl(ctrl)
        else { return false }
        return HwpParagraphObjectCollector.collectible(components, collectsTextboxes: true)
    }

    /// 개체의 글상자 문단 — **문맥별 렌더 범위**를 그대로 따른다.
    ///
    /// - 컨테이너(표 셀·각주)가 그리는 개체: 전 컴포넌트의 텍스트가 그려진다.
    /// - **각주에서 수집기가 건너뛴 개체: 아무도 그리지 않는다** — 각주는
    ///   `appendNestedControlBlocks`를 부르지 않아 흐름 폴백이 없다 (실측: 각주 안
    ///   OLE 포함 개체의 글상자 텍스트가 렌더에 없는데 목록엔 앵커가 있었다).
    /// - 그 밖(흐름·표 셀의 폴백): 첫 글상자 컴포넌트의 **텍스트만** 그려지지만
    ///   중첩 컨트롤은 `appendNestedControlBlocks`가 전 컴포넌트에서 방출하므로,
    ///   나머지 컴포넌트도 **자식만** 따라가도록 남긴다 (실측: 둘째 컴포넌트 안
    ///   중첩 표는 그려지는데 그 셀 앵커가 빠졌다).
    private func objectChildParagraphs(
        of ctrl: CoreHwp.HwpCtrlId,
        components: [CoreHwp.HwpShapeComponent],
        context: HwpOutlineCollector.RenderContext
    ) -> [HwpOutlineCollector.ChildParagraph] {
        if context.containerDraws, containerDrawsEveryComponent(ctrl) {
            // 수집기가 그리지만 **컴포넌트마다 다르다** — 그림이 있는 컴포넌트는
            // 그림만 그리고 반환하므로 그 글상자는 그려지지 않는다
            // (`HwpParagraphObjectCollector.collect(component:)`).
            return components.flatMap { component in
                let draws = HwpParagraphObjectCollector.drawsTextbox(
                    component, collectsTextboxes: true
                )
                // 안 그려지는 글상자도 흐름 폴백이 있으면 **자식만** 따라간다.
                guard draws || context.hasFlowFallback else {
                    return [HwpOutlineCollector.ChildParagraph]()
                }
                return component.textBoxListArray.flatMap(\.paragraphArray).map {
                    HwpOutlineCollector.ChildParagraph(paragraph: $0, rendersText: draws)
                }
            }
        }
        // 수집기가 안 그리는 컨트롤은 흐름이 받는다 — 각주엔 그 폴백이 없다.
        guard context.hasFlowFallback else { return [] }
        let renderedIndex = HwpTextboxLayout.renderedTextboxComponentIndex(of: components)
        return components.enumerated().flatMap { index, component in
            component.textBoxListArray.flatMap(\.paragraphArray).map {
                HwpOutlineCollector.ChildParagraph(
                    paragraph: $0, rendersText: index == renderedIndex
                )
            }
        }
    }

    /// 개체의 글상자 문단 — **그려지는 컴포넌트만**.
    ///
    /// 그 범위가 문맥마다 다르다: 흐름에 놓인 개체는 `HwpTextboxLayout`이 텍스트를
    /// 가진 **첫** 컴포넌트만 그리지만, 표 셀·각주 안 개체는
    /// `HwpParagraphObjectCollector`가 **전 컴포넌트**를 그린다 (실측: 셀 안
    /// 컴포넌트 2개가 둘 다 렌더된다). 한쪽으로 통일하면 반드시 한 문맥이 틀린다 —
    /// 흐름 기준으로 좁히면 셀 안 뒤 컴포넌트의 앵커가 조용히 빠지고, 컨테이너
    /// 기준으로 넓히면 흐름 개체가 없는 자리를 가리킨다.
    private func renderedTextboxParagraphs(
        of components: [CoreHwp.HwpShapeComponent],
        allComponents: Bool
    ) -> [(CoreHwp.HwpParagraph, HwpBlockKind)] {
        let rendered: [CoreHwp.HwpShapeComponent] = if allComponents {
            components
        } else if let component = HwpTextboxLayout.renderedTextboxComponent(of: components) {
            [component]
        } else {
            []
        }
        return rendered
            .flatMap(\.textBoxListArray)
            .flatMap(\.paragraphArray)
            .map { ($0, HwpBlockKind.textbox) }
    }

    // MARK: - 컨트롤 블록 방출

    /// 컨테이너 문맥 — 컨테이너 레이아웃이 셀/글상자 콘텐츠로 그린 컨트롤의
    /// 페이지 흐름 재방출 억제에 쓴다 (R29 #1).
    enum ContainerContext {
        case none, tableCell, textbox
    }

    /// 문단에 붙은 컨트롤을 실제 레이아웃 엔진으로 방출한다.
    /// depth는 컨테이너 안 컨테이너 재귀 제한 (표 안 글상자 등).
    /// 셀 안 중첩 표는 HwpTableLayout이 이미 셀 안에 재귀 배치했으므로
    /// 별도 블록으로 방출하지 않는다.
    func appendControlBlocks(
        from paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        container: ContainerContext = .none
    ) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        for (ctrlIndex, ctrl) in ctrls.enumerated() {
            // 줄 중간 앵커 문맥은 본문 문단 (depth 0)에서만 유효하다.
            let anchorIndex = depth == 0 ? ctrlIndex : nil
            // 컨테이너 안 개체 (그림/도형/글상자)는 컨테이너 레이아웃이 이미
            // 콘텐츠로 배치했다 — 페이지 흐름 블록으로 다시 방출하면 컨테이너
            // 밖 좌표에 그려지고 흐름을 밀어낸다 (noori 실측 3쪽).
            if container != .none, Self.rendersInsideContainer(ctrl, container: container) {
                // 렌더된 컨트롤이라도 자식 문단의 미수집 컨트롤 (글상자 안
                // 글상자 등)은 흐름 폴백을 유지한다.
                appendNestedControlBlocks(of: ctrl, depth: depth)
                continue
            }
            appendControlBlock(
                ctrl,
                anchorIndex: anchorIndex,
                depth: depth,
                container: container
            )
        }
    }

    /// 컨테이너 레이아웃 (HwpTableLayout/HwpTextboxLayout)이 컨테이너
    /// 콘텐츠로 이미 배치한 컨트롤인지 —
    /// HwpParagraphObjectCollector.collectible과 반드시 일치 (R29 #1).
    static func rendersInsideContainer(
        _ ctrl: CoreHwp.HwpCtrlId,
        container: ContainerContext
    ) -> Bool {
        guard let (_, components) = HwpParagraphObjectCollector.handledControl(ctrl) else {
            return false
        }
        return HwpParagraphObjectCollector.collectible(
            components, collectsTextboxes: container == .tableCell
        )
    }

    /// 컨트롤 하나를 종류별 레이아웃 경로로 방출한다 (appendControlBlocks 본문).
    private func appendControlBlock(
        _ ctrl: CoreHwp.HwpCtrlId,
        anchorIndex: Int?,
        depth: Int,
        container: ContainerContext
    ) {
        switch ctrl {
        case let .table(table):
            if container != .tableCell {
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
            //
            // 각주 문단 안 개체는 형제 케이스처럼 appendNestedControlBlocks로
            // 흐름 방출하지 **않는다** — 각주 영역 안 콘텐츠라 흐름으로 내보내면
            // 본문 자리에 그려지고 흐름까지 밀어낸다 (한글.app 실측: 헌법주석
            // 883쪽 각주 29의 표는 각주 영역 안에 있다). `HwpFootnoteLayout`이
            // `HwpParagraphObjectCollector`로 담고 (#94), 그것이 담지 못하는
            // 컨트롤 (OLE·수식)은 walkUnsupported가 각주 문단까지 걸어
            // (childParagraphs) 진단으로 보고하므로 손실이 조용하지 않다.
            break
        default:
            break
        }
    }

    /// 컨테이너 문단 안에 중첩된 컨트롤 (표 셀 안 글상자/이미지 등)을 재귀 방출한다.
    func appendNestedControlBlocks(of ctrl: CoreHwp.HwpCtrlId, depth: Int) {
        guard depth < Self.maximumContainerDepth else { return }
        let container: ContainerContext = if case .table = ctrl {
            .tableCell
        } else if let (_, components) = HwpParagraphObjectCollector.handledControl(ctrl),
                  components.contains(where: { !$0.textBoxListArray.isEmpty })
        {
            .textbox
        } else {
            .none
        }
        for (nested, _) in childParagraphs(of: ctrl) where nested.ctrlHeaderArray != nil {
            appendControlBlocks(from: nested, depth: depth + 1, container: container)
        }
    }

    // MARK: 표

    func appendTableBlocks(_ table: CoreHwp.HwpTable, controlIndex: Int? = nil) {
        // 글 앞/뒤로 표는 appendFloatingTableIfNeeded가 흐름 밖에 통째로
        // 배치하므로 저작 폭 (예: 종이 100%)을 단 폭으로 자르지 않는다.
        let info = table.commonCtrlProperty.propertyInfo
        let result = tableLayout.layout(
            table: table,
            availableWidth: currentColumnFrame.width,
            index: index,
            sizeResolver: objectSizeResolver,
            clampToAvailableWidth: info.treatAsChar || consumesFlow(info)
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
            // 글 앞/뒤로 표는 흐름 소비·페이지 분할 없이 기준+오프셋에 통째로
            // 둔다 (개체와 동일 경로) — 흐름 경로로 보내면 밀리고 잘린다 (#2).
            if appendFloatingTableIfNeeded(frame, table: table) {
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

    /// 글 앞/뒤로 표 (behindText/inFrontOfText)를 기준+오프셋 위치에 통째로
    /// 배치한다 (흐름 소비·페이지 분할 없음 — 일반 개체 appendFloatingBlock과
    /// 동일 경로). 흐름을 소비하는 wrap (square/topAndBottom)이거나 treatAsChar면
    /// false를 반환해 호출자가 흐름 분할 경로 (appendTableSegments)로 폴백한다 (#2).
    private func appendFloatingTableIfNeeded(
        _ frame: HwpTableFrame,
        table: CoreHwp.HwpTable
    ) -> Bool {
        let info = table.commonCtrlProperty.propertyInfo
        guard !info.treatAsChar, !consumesFlow(info) else { return false }
        let height = frame.rows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
        appendFloatingBlock(
            ObjectBlockSpec(
                kind: .table,
                size: CGSize(width: frame.outerFrame.width, height: height),
                payload: .table(frame),
                attributedString: nil,
                instanceId: table.commonCtrlProperty.instanceId,
                zOrder: table.commonCtrlProperty.zOrder
            ),
            commonProperty: table.commonCtrlProperty
        )
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

        // 셀 각주 수집용 시작 행 인덱스를 표당 한 번만 만든다 (세그먼트마다
        // 전수 스캔 방지, #15; fallback 셀도 실제 행에 귀속, #23).
        let cellsByRow = table.map { HwpTableLayout.cellRowIndex(for: $0) } ?? [:]

        if pageBreakMode == .none {
            let tableHeight = frame.rows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
            if contentHeightUsed > 0, contentHeightUsed + tableHeight > effectiveContentHeight {
                advanceColumn()
            }
            if table != nil {
                collectTableCellFootnotes(cellsByRow: cellsByRow, rows: nil)
            }
            appendTableSegmentBlock(rows: frame.rows, original: frame, instanceId: instanceId)
            return
        }

        // 반복할 제목 행 (표 전체가 제목이면 반복하지 않는다)
        let candidateHeaderRows = headerRowCount > 0 && headerRowCount < frame.rows.count
            ? Array(frame.rows.prefix(headerRowCount))
            : []
        let candidateHeaderHeight = candidateHeaderRows.isEmpty
            ? 0
            : candidateHeaderRows.reduce(CGFloat(0)) { partial, row in
                // rowspan 셀은 비-제목 행까지 뻗으므로 cellFrame.maxY를 반영해
                // segmentFrame의 클론 머리행 높이와 일치시킨다 — continuation
                // allowance가 과소평가돼 페이지를 넘는 것을 막는다 (#3, 라운드6 #29 정합).
                let rowExtent = row.cells.reduce(row.rowFrame.maxY) { extent, cell in
                    cell.rowSpan > 1 ? max(extent, cell.cellFrame.maxY) : extent
                }
                return max(partial, rowExtent)
            }
            - (candidateHeaderRows.first?.rowFrame.minY ?? 0)
        // 반복 제목이 페이지 본문보다 크거나 같으면 continuation에 본문 행 공간이
        // 남지 않아 splitter가 0-높이 조각을 유지하며 제목만 반복해 페이지가
        // 폭주한다 — 반복을 끈다 (#13). 실제 제목(몇 줄)은 페이지보다 훨씬 작아 불변.
        let headerLeavesBodyRoom = candidateHeaderHeight < effectiveContentHeight
        let repeatedRows = headerLeavesBodyRoom ? candidateHeaderRows : []
        let repeatedHeight = headerLeavesBodyRoom ? candidateHeaderHeight : 0

        // 커서로 소비한다 — removeFirst의 배열 앞 반복 시프트(O(n²))를 피한다 (#5).
        // 잘린 행의 아래 조각은 커서 위치에 제자리 치환한다.
        var rows = frame.rows
        var cursor = 0
        var isFirstSegment = true
        // 표 하나가 만드는 세그먼트 수를 상한한다 (병적 행 페이지 증폭 방어, #5)
        var segmentCount = 0
        // 이미 셀 각주를 수집한 최상위 행 — 분할된 행이 다음 세그먼트에서
        // 다시 수집돼 각주가 중복되는 것을 막는다.
        var highestCollectedRow = Int.min
        // 실제로 방출된 최대 행 — 세그먼트가 행을 **슬라이스**하면 `cursor`는
        // 그 행을 넘지 않으므로 커서만으로는 "그려진 행"을 셀 수 없다.
        var highestEmittedRow = -1

        // 취소된 로드가 병적 표를 분할 중이면 최대 4,096 세그먼트를 만들기 전에
        // 빠져 옛·새 로드가 동시에 CPU/메모리를 소비하지 않게 조기 탈출한다 (#6).
        while cursor < rows.count, segmentCount < maximumTableSegments,
              !Task.isCancelled
        {
            // 이어지는 세그먼트는 제목 행 반복 높이를 미리 차감한다.
            let headerAllowance = isFirstSegment ? 0 : repeatedHeight
            var remaining = effectiveContentHeight - contentHeightUsed - headerAllowance
            let freshPage = effectiveContentHeight - headerAllowance
            // 물리 첫 행이 안 들어가거나(기존), 시작 행 rowspan 셀 스팬이 남은
            // 공간을 넘는데 새 페이지엔 들어가면 먼저 페이지를 넘겨 스팬 그룹을
            // 통째로 유지한다 — 병합 셀 하단이 세그먼트 밖에 그려지거나 이월에서
            // 사라지는 것을 막는다 (#3). 새 페이지도 넘는 스팬은 물리 행 기준
            // 슬라이스로 폴백한다 (zero-height continuation 방지, round13 #1).
            let spanHeight = HwpTableSplitter.firstRowSpanningHeight(rows[cursor...])
            let deferForSpan = remaining < spanHeight && spanHeight <= freshPage
            if contentHeightUsed > 0,
               remaining < HwpTableSplitter.minimumRowHeight(rows[cursor...]) || deferForSpan
            {
                advanceColumn()
                remaining = freshPage
            }

            // 후보 행의 셀 각주 예약 높이를 미리 반영해 세그먼트를 맞춘다 (#6).
            // 각주 예약 후 최소 행조차 안 들어가면 remaining을 되돌리지 않고
            // 새 페이지로 이월한다 — 각주가 이미 claim한 공간에 행을 밀어넣어
            // 각주 영역과 겹치지 않게 한다 (#11). 셀 각주가 없으면 no-op.
            if table != nil {
                var notes = anticipatedNotesForNextSegment(
                    cellsByRow: cellsByRow, remainingRows: rows[cursor...],
                    remaining: remaining, highestCollectedRow: highestCollectedRow
                )
                if notes > 0,
                   remaining - notes < HwpTableSplitter.minimumRowHeight(rows[cursor...]),
                   contentHeightUsed > 0
                {
                    advanceColumn()
                    remaining = effectiveContentHeight - headerAllowance
                    notes = anticipatedNotesForNextSegment(
                        cellsByRow: cellsByRow, remainingRows: rows[cursor...],
                        remaining: remaining, highestCollectedRow: highestCollectedRow
                    )
                }
                if notes > 0 {
                    remaining = max(1, remaining - notes)
                }
            }

            let fill = HwpTableSplitter.fillSegment(rows: rows[cursor...], remaining: remaining)
            let segmentRows = fill.segment
            guard !segmentRows.isEmpty else { break }
            cursor += fill.consumed
            if let replacement = fill.replacement {
                rows[cursor] = replacement
            }

            // 셀 각주는 행이 실리는 페이지 귀속 (한글 실측 — 헌법주석 p485).
            // 분할된 행은 조각이 같은 rowAddress를 유지하므로, 이미 수집한 행보다
            // 큰 행만 수집해 조각 간 중복 각주를 막는다.
            let rowIndexes = segmentRows.flatMap(\.cells).map(\.row)
            if let maxRow = rowIndexes.max() {
                highestEmittedRow = max(highestEmittedRow, maxRow)
            }
            if table != nil {
                if let maxRow = rowIndexes.max() {
                    let startRow = max(rowIndexes.min() ?? maxRow, highestCollectedRow + 1)
                    if startRow <= maxRow {
                        collectTableCellFootnotes(cellsByRow: cellsByRow, rows: startRow ... maxRow)
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
            segmentCount += 1
        }
        // 세그먼트 상한(또는 취소)에 걸려 **방출되지 않은 행**이 남았다면 기록해
        // 둔다 — 탐색 목록이 그 행의 앵커를 내면 그려진 적 없는 자리를 가리킨다.
        // 잘린 표만 담으므로 항목은 사실상 없고(정상 문서는 0개), 조회는
        // `truncatedRowLimit(of:)`가 표 값으로 확정한다 (id는 유일하지 않다).
        if cursor < rows.count, let table {
            truncatedTableRowLimits[instanceId, default: []].append((table, highestEmittedRow + 1))
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
            index: index,
            sizeResolver: objectSizeResolver
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

    /// 수식 근사 텍스트 — nil이면 개체(글상자·도형) 경로로 폴백한다.
    ///
    /// 렌더 분기와 **탐색 목록 순회가 같은 판정을 공유**하도록 이 함수 하나가
    /// 소유한다: 수식으로 그려지는 개체는 `appendShapeObjectBlocks`를 건너뛰므로
    /// 그 글상자 텍스트가 렌더되지 않고, 따라서 그 안 앵커도 목록에 없어야 한다.
    func equationAttributedString(
        _ shape: CoreHwp.HwpShapeControl
    ) -> NSAttributedString? {
        guard let edit = shape.eqEditArray.first else { return nil }
        let commonProperty = shape.commonCtrlProperty ?? CoreHwp.HwpCommonCtrlProperty()
        let size = objectSize(
            commonProperty: commonProperty,
            components: shape.shapeComponentArray
        )
        return HwpEquationLayout.attributedString(
            edit: edit,
            fallbackSize: size.height,
            fontResolver: fontResolver
        )
    }

    /// 수식 (eqed) 컨트롤을 EQEDIT 스크립트 근사 텍스트로 방출한다.
    /// 스크립트가 비어 있으면 false — 호출자가 개체 경로로 폴백한다.
    func appendEquationBlock(
        _ shape: CoreHwp.HwpShapeControl,
        controlIndex: Int?
    ) -> Bool {
        guard let attributed = equationAttributedString(shape) else { return false }
        let commonProperty = shape.commonCtrlProperty ?? CoreHwp.HwpCommonCtrlProperty()
        let size = objectSize(
            commonProperty: commonProperty,
            components: shape.shapeComponentArray
        )
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
        let info = commonProperty.propertyInfo
        let resolver = objectSizeResolver
        var width = resolver.width(commonProperty.width, basis: info.widthRelativeTo)
        var height = resolver.height(commonProperty.height, basis: info.heightRelativeTo)
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

    /// 본문 텍스트 빌더 — 현재 기하의 크기 해석기를 붙여 treatAsChar 줄
    /// 공간 예약이 paint 크기와 일치하게 한다.
    func textRunBuilder() -> HwpTextRunBuilder {
        HwpTextRunBuilder(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: objectSizeResolver,
            attributeCache: attributeCache
        )
    }

    /// 현재 페이지/단 기하 기준의 개체 크기 해석기 — 전용 레이아웃 경로
    /// (표/글상자/셀 그림/줄 공간 예약)가 퍼센트 저장값을 HWPUNIT로
    /// 오해하지 않도록 전달한다.
    var objectSizeResolver: HwpObjectSizeResolver {
        HwpObjectSizeResolver(
            paperSize: currentPageGeometry.pageSize,
            contentSize: currentPageGeometry.contentFrame.size,
            columnWidth: currentColumnFrame.width,
            paragraphWidth: currentParagraphWidth
        )
    }

    /// '문단' 기준 폭 — 단 폭 − 현재 문단 좌우 여백 (첫 줄 들여쓰기 제외 근사)
    private var currentParagraphWidth: CGFloat {
        max(
            1,
            currentColumnFrame.width
                - currentParagraphMargins.left - currentParagraphMargins.right
        )
    }

    /// 표 43: 문단 좌우 여백은 1/2 단위 (HWPUNIT×2)로 저장된다.
    private func paragraphMargins(
        of paragraph: CoreHwp.HwpParagraph
    ) -> (left: CGFloat, right: CGFloat) {
        guard let paraShape = index.paraShape(for: paragraph) else { return (0, 0) }
        return (
            HwpUnits.points(fromHwpUnit: paraShape.marginLeft) / 2,
            HwpUnits.points(fromHwpUnit: paraShape.marginRight) / 2
        )
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
        /// 겹치는 개체 z-순서 (Send Backward/Forward) — 페인트/히트 정렬 기준 (#9).
        let zOrder: Int32
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
            instanceId: commonProperty.instanceId,
            zOrder: commonProperty.zOrder
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
        // 기준 + 오프셋 (음수 오프셋 허용)
        let offsetX = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.horizontalOffset)
        )
        let offsetY = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.verticalOffset)
        )
        var frame = anchoredObjectFrame(spec, info: info, offsetX: offsetX, offsetY: offsetY)
        frame = restrictedToPageFrame(
            frame, spec: spec, info: info, offsetX: offsetX, offsetY: offsetY
        )
        // 글 앞/뒤로 개체는 블록 배열 순서(선택/복사)를 논리대로 두고, 페인트·
        // 히트만 평면·zOrder로 정렬한다 — behind는 텍스트 뒤, inFront는 앞 (#8/#9/#10).
        let plane: HwpBlockPaintPlane = info.textWrap == .behindText ? .behind : .front
        currentBlocks.append(AnyHwpBlock(
            frame: frame,
            kind: spec.kind,
            attributedString: spec.attributedString,
            payload: spec.payload,
            source: HwpBlockSource(controlInstanceId: spec.instanceId),
            paintPlane: plane,
            zOrder: spec.zOrder
        ))
        bandHasNonTextContent = true
    }

    /// 기준 프레임(base, extent) 안에서 정렬을 반영한 앵커. topOrLeft(기본)·
    /// nil·extent<=0이면 base 그대로 (오프셋 배치 개체 렌더 불변, #5).
    private func alignedAnchor(
        _ base: CGFloat, _ extent: CGFloat, _ size: CGFloat,
        _ alignment: CoreHwp.HwpCommonCtrlRelativeAlignment?
    ) -> CGFloat {
        guard extent > 0 else { return base }
        return switch alignment {
        case .center: base + (extent - size) / 2
        case .bottomOrRight, .outside: base + extent - size
        case .topOrLeft, .inside, nil: base
        }
    }

    /// 앵커 규칙(표 70)의 기준 프레임(base, extent) + 정렬 + 오프셋으로 개체
    /// 프레임을 만든다. floating·absolute-flow 경로가 공유한다 (#5 정렬 반영).
    private func anchoredObjectFrame(
        _ spec: ObjectBlockSpec,
        info: CoreHwp.HwpCommonCtrlPropertyInfo,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> CGRect {
        let contentFrame = currentPageGeometry.contentFrame
        let hRef: (base: CGFloat, extent: CGFloat) = switch info.horizontalRelativeTo {
        case .paper: (0, currentPageGeometry.pageSize.width)
        case .page, nil: (contentFrame.minX, contentFrame.width)
        case .column: (currentColumnFrame.minX, currentColumnFrame.width)
        case .paragraph: (
                currentColumnFrame.minX + currentParagraphMargins.left,
                currentParagraphWidth
            )
        }
        let vRef: (base: CGFloat, extent: CGFloat) = switch info.verticalRelativeTo {
        case .paper: (0, currentPageGeometry.pageSize.height)
        case .page, nil: (contentFrame.minY, contentFrame.height)
        case .paragraph: (paragraphAnchorTop, 0)
        }
        return CGRect(
            x: alignedAnchor(hRef.base, hRef.extent, spec.size.width, info.horizontalAlignment)
                + offsetX,
            y: alignedAnchor(vRef.base, vRef.extent, spec.size.height, info.verticalAlignment)
                + offsetY,
            width: spec.size.width,
            height: spec.size.height
        )
    }

    /// 문단 기준 + restrictInPage 개체가 현재 페이지 본문 하단을 넘으면 다음
    /// 페이지로 넘기고 새 페이지 기준으로 프레임을 재계산한다 (표 70 restrictInPage,
    /// errata 31b — 꼬리말/페이지 밖 렌더 방지, #6). 이미 페이지 상단이면
    /// (contentHeightUsed==0) 넘겨도 소용없어 그대로 둔다.
    private func restrictedToPageFrame(
        _ frame: CGRect,
        spec: ObjectBlockSpec,
        info: CoreHwp.HwpCommonCtrlPropertyInfo,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> CGRect {
        guard info.verticalRelativeTo == .paragraph, info.restrictInPage,
              contentHeightUsed > 0,
              frame.maxY > currentPageGeometry.contentFrame.maxY
        else { return frame }
        advanceColumn()
        // 페이지 상한 도달: advanceColumn이 커서를 못 옮기면 같은 frame으로
        // 재귀가 반복된다 — 현재 frame을 그대로 쓴다 (#1).
        if didFinishPagination {
            return frame
        }
        return anchoredObjectFrame(spec, info: info, offsetX: offsetX, offsetY: offsetY)
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
        let offsetX = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.horizontalOffset)
        )
        let offsetY = HwpUnits.points(
            fromHwpUnit: Int32(bitPattern: commonProperty.verticalOffset)
        )
        var frame = anchoredObjectFrame(spec, info: info, offsetX: offsetX, offsetY: offsetY)
        frame = restrictedToPageFrame(
            frame, spec: spec, info: info, offsetX: offsetX, offsetY: offsetY
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
        guard let controlIndex, currentParagraphContext != nil else { return nil }
        return inlineAnchorMap()[controlIndex]
    }

    /// controlIndex → 앵커 좌표 맵을 컨텍스트당 한 번 만들고 캐시한다 (#12).
    /// 라인·앵커를 방출 순서로 훑어 각 controlIndex의 첫 매칭만 담는다
    /// (기존 lines.first(where:) 순서와 동일).
    private func inlineAnchorMap() -> [Int: CGPoint] {
        if let cached = inlineAnchorCache {
            return cached
        }
        guard let context = currentParagraphContext,
              let firstBaseline = context.lines.first?.baseline
        else {
            inlineAnchorCache = [:]
            return [:]
        }
        var map: [Int: CGPoint] = [:]
        for line in context.lines {
            let baselineY = context.blockFrame.minY + firstBaseline + line.origin.y
            for anchor in line.inlineAnchors where map[anchor.controlIndex] == nil {
                map[anchor.controlIndex] = CGPoint(
                    x: context.blockFrame.minX + line.origin.x + anchor.xOffset,
                    y: baselineY - anchor.ascent
                )
            }
        }
        inlineAnchorCache = map
        return map
    }

    /// 술어 본체는 `HwpParagraphObjectCollector.consumesFlow`가 소유한다 —
    /// 컨테이너 높이 하한 (`growsContainer`)과 반드시 같은 답을 써야 한다 (#91).
    func consumesFlow(_ info: CoreHwp.HwpCommonCtrlPropertyInfo) -> Bool {
        HwpParagraphObjectCollector.consumesFlow(info)
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
        // 메모별 필드 마커의 controlIndex(= ctrlHeaderArray 인덱스 = extended
        // 컨트롤 순서)를 보존해, 뒤에서 각 메모의 인라인 앵커 라인 위치를 찾는다 (P2).
        let memoFields: [(controlIndex: Int, field: CoreHwp.HwpFieldControl)] = ctrls
            .enumerated()
            .compactMap { index, ctrl in
                if case let .memo(field) = ctrl {
                    (controlIndex: index, field: field)
                } else {
                    nil
                }
            }
        guard !memoFields.isEmpty else { return }
        // crafted 문단이 메모 필드를 대량 삽입해 패널 backing layer·paint 명령을
        // 폭발시키지 못하게 페이지당 풍선 수를 제한한다 (P1). 초과분은 body를
        // build하기 전에 버린다.
        let remaining = HwpMemoPanelPainter.maxBalloonsPerPage - pendingMemoBalloons.count
        guard remaining > 0 else { return }
        let cappedFields = Array(memoFields.prefix(remaining))
        let fallbackAnchorY = currentBlocks.last { $0.kind == .text }?.frame.minY
            ?? currentPageGeometry.contentFrame.minY
        // 메모별 문단 그룹을 join해 필드와 1:1로 짝짓는다 — 평탄 배열을 필드
        // 인덱스로 끊으면 여러 문단 메모는 2번째+ 문단이 누락되고 다중 메모는
        // 엉뚱한 필드에 페어링된다 (#7).
        // 표시 예산(HwpMemoPanelPainter.maxBodyChars)까지만 추출한다 — 각 문단
        // build를 남은 예산으로 상한(maxCharacters)해, 단일 거대 문단도 전체를
        // build한 뒤에야 캡되지 않게 한다 (R44 #3).
        let budget = HwpMemoPanelPainter.maxBodyChars
        let groups = (paragraph.memoParagraphGroups ?? []).prefix(remaining)
        let bodies = groups.map { group -> String in
            var parts: [String] = []
            var total = 0
            for memoParagraph in group where total < budget {
                let remainingBudget = budget - total
                let text = HwpTextRunBuilder(
                    index: index, fontResolver: fontResolver, attributeCache: attributeCache
                )
                .build(paragraph: memoParagraph, maxCharacters: remainingBudget)
                .string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let clipped = text.count > remainingBudget
                    ? String(text.prefix(remainingBudget))
                    : text
                parts.append(clipped)
                total += clipped.count
            }
            return parts.joined(separator: "\n")
        }
        for (fieldIndex, entry) in cappedFields.enumerated() {
            // 메모마다 자기 필드 마커의 인라인 앵커 라인 y를 앵커로 삼아, 한 문단
            // 안 서로 다른 줄의 메모가 각자 줄에 맞춘다. 분할된 문단은 라인 문맥이
            // 없어 문단 상단으로 폴백한다 (인라인 앵커와 동일 한계, P2).
            let anchorY = inlineAnchorPosition(for: entry.controlIndex)?.y ?? fallbackAnchorY
            pendingMemoBalloons.append(HwpMemoPanelPainter.Balloon(
                anchorY: anchorY,
                author: entry.field.memoParameter?.author ?? "",
                dateText: Self.memoDateText(entry.field.memoParameter),
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
            footnoteShape: currentSectionDef?.footNoteShape,
            sizeResolver: objectSizeResolver
        )
    }

    /// includeTableCells: 표 셀 안 각주 포함 여부 (HwpFootnoteCoordinator 참조)
    /// ordinals: 이 페이지 조각에 실린 top-level 컨트롤 서수 범위 (#95, nil = 전체)
    func collectFootnotes(
        from paragraph: CoreHwp.HwpParagraph,
        includeTableCells: Bool = true,
        ordinals: Range<Int>? = nil,
        collectsNested: Bool = true
    ) {
        footnoteCoordinator.collectFootnotes(
            from: paragraph,
            includeTableCells: includeTableCells,
            ordinals: ordinals,
            collectsNested: collectsNested,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 표 셀 각주를 수집한다. rows가 nil이면 전체 (HwpFootnoteCoordinator 참조)
    /// cellsByRow는 HwpTableLayout.cellRowIndex — 세그먼트마다 전수 스캔 방지 (#15)
    func collectTableCellFootnotes(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>?
    ) {
        footnoteCoordinator.collectTableCellFootnotes(
            cellsByRow: cellsByRow,
            rows: rows,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 표 세그먼트 크기 산정 전 후보 행의 셀 각주 예약 높이 (HwpFootnoteCoordinator 참조)
    func anticipatedTableCellFootnoteHeight(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>
    ) -> CGFloat {
        footnoteCoordinator.anticipatedTableCellFootnoteHeight(
            cellsByRow: cellsByRow,
            rows: rows,
            environment: noteEnvironment,
            childParagraphs: childParagraphs(of:)
        )
    }

    /// 다음 세그먼트에 들어갈 후보 행들의 셀 각주가 예약할 높이 — 사본으로
    /// 시산만 한다(상태 불변). 이미 수집한 행 이후분만 세고, 셀 각주가 없으면 0.
    private func anticipatedNotesForNextSegment(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        remainingRows: ArraySlice<HwpTableRowFrame>,
        remaining: CGFloat,
        highestCollectedRow: Int
    ) -> CGFloat {
        let trial = HwpTableSplitter.fillSegment(rows: remainingRows, remaining: remaining)
        let rows = trial.segment.flatMap(\.cells).map(\.row)
        guard let maxRow = rows.max() else { return 0 }
        let startRow = max(rows.min() ?? maxRow, highestCollectedRow + 1)
        guard startRow <= maxRow else { return 0 }
        return anticipatedTableCellFootnoteHeight(cellsByRow: cellsByRow, rows: startRow ... maxRow)
    }

    // MARK: 미주 (문서/구역 끝)

    /// 모아 둔 미주를 현재 흐름 아래에 전체 폭 1단으로 배치한다.
    /// 남은 공간이 부족하면 다음 페이지로 이어 붙인다.
    func appendPendingEndnotes() throws {
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
        // 페이지 상한에 걸려 cacheCurrentPage가 캐시를 거부하면(didFinishPagination)
        // overflow가 안 줄어 같은 만석 페이지를 무한 재시도하므로 그때 멈춘다
        // (각주 드레인 루프와 동일, #1).
        while !pendingEndnotes.isEmpty, !didFinishPagination {
            // 취소 시 미주 드레인이 페이지 상한까지 동기로 돌아 취소 관찰이
            // 늦어지지 않게 매 페이지 확인 (각주 드레인·389와 동일, P2b).
            try Task.checkCancellation()
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
                drawSeparator: drawSeparator,
                sizeResolver: objectSizeResolver
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
            limitsAreaToHalfContent: !absoluteCacheMode,
            sizeResolver: objectSizeResolver
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
        // 문서 전역 페이지 상한 초과 시 더 캐시하지 않고 페이지네이션을 종료한다 —
        // page(at:) 루프가 nil을 관찰하고 멈춘다 (#1).
        guard cachedPages.count < maximumPages else {
            didFinishPagination = true
            return
        }
        // 변경 추적 문단의 이 페이지 조각마다 변경 막대를 방출한다 — 페이지 걸친
        // 문단의 앞 조각도 자기 페이지에서 막대를 받는다 (#7).
        emitTrackChangeBars()
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
        let top = Int(segments[0].lineLocation)
        var bottom = top
        for segment in segments {
            bottom = max(bottom, HwpAbsoluteCachePlacer.lineBottom(of: segment))
        }
        let lineHeights = max(0, HwpUnits.points(fromHwpUnit: Int32(clamping: bottom - top)))
        // 문단 간격 위/아래는 캐시에 포함되지 않으므로 CT 폴백 경로
        // (HwpParagraphMetrics)와 동일하게 더한다 — 표 43 여백 계열과 같은 1/2
        // 단위라 /2 한다. full로 더하면 캐시 문단만 2배 간격이 된다 (P1). paraShape
        // 없으면 간격 0.
        let paraShape = index.paraShape(for: paragraph)
        let spacing = paraShape.map {
            max(0, HwpUnits.points(fromHwpUnit: $0.paragraphSpacingTop) / 2)
                + max(0, HwpUnits.points(fromHwpUnit: $0.paragraphSpacingBottom) / 2)
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
