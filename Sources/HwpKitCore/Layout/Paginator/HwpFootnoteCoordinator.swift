import CoreGraphics
import CoreHwp
import Foundation

/// 각주/미주 수집·측정·예약 — 문단을 걸어 각주 (페이지 하단 몫)와 미주
/// (문서/구역 끝 몫)를 분리 수집하고, 번호 카운터·예약 높이·측정 캐시를
/// 관리한다. HwpPaginator에서 추출 (동작 불변). 상태는 paginator가 소유하는
/// 값 타입 — 블록 방출·pending 소비·페이지 확정 같은 부수효과는 paginator에 남는다.
struct HwpFootnoteCoordinator {
    /// 측정/예약이 읽는 페이지·구역 환경. paginator의 mutable 상태
    /// (currentPageGeometry/currentSectionDef)이므로 호출 시점 값을 주입받는다.
    struct Environment {
        /// currentPageGeometry.contentFrame.width
        let contentWidth: CGFloat
        /// currentSectionDef?.footNoteShape
        let footnoteShape: CoreHwp.HwpFootnoteShape?
        /// 각주 문단 안 개체의 상대 크기 기준 해석기 (paginator 페이지/단 기하).
        /// 예약(measuredFootnoteHeight)과 배치(HwpFootnoteLayout.place)가 같은
        /// 기준을 써야 떠 있는 개체 하한이 갈리지 않는다 (#94).
        let sizeResolver: HwpObjectSizeResolver?

        init(
            contentWidth: CGFloat,
            footnoteShape: CoreHwp.HwpFootnoteShape?,
            sizeResolver: HwpObjectSizeResolver? = nil
        ) {
            self.contentWidth = contentWidth
            self.footnoteShape = footnoteShape
            self.sizeResolver = sizeResolver
        }

        /// 해석기만 바꾼 사본 — 이월 각주를 재예약할 때 그 각주를 **수집할 때
        /// 잡은** 해석기로 되돌린다 (R45 #1). 현재 environment로 다시 재면 배치
        /// (`Input.sizeResolver`를 쓴다) 와 갈린다.
        func withSizeResolver(_ resolver: HwpObjectSizeResolver?) -> Environment {
            Environment(
                contentWidth: contentWidth,
                footnoteShape: footnoteShape,
                sizeResolver: resolver
            )
        }
    }

    /// paragraph-bearing 컨테이너의 단일 traversal 지점 주입
    /// (HwpPaginator.childParagraphs(of:) — unsupported walk/렌더 경로와 공유).
    typealias ChildParagraphs = (CoreHwp.HwpCtrlId) -> [(CoreHwp.HwpParagraph, HwpBlockKind)]

    struct FootnoteHeightKey: Hashable {
        let paragraph: CoreHwp.HwpParagraph
        let widthCenti: Int
        /// 자동 번호 치환 텍스트가 폭에 영향을 주므로 번호도 키에 포함한다
        let number: Int
        /// 상대 크기 개체가 든 문단은 줄 높이가 해석기 기하의 함수다 — 폭만
        /// 키에 넣으면 종이/쪽 높이·단 폭만 바뀐 재사용이 살아나 예약이 배치와
        /// 갈린다 (R39 #1). 배치 (`HwpFootnoteLayout.measure`)는 캐시가 없어
        /// 항상 현재 기하로 재측정하므로 어긋나는 쪽은 언제나 예약이다.
        let sizeResolver: HwpObjectSizeResolver?
        /// `measureNote`가 받는 **모든** 입력이 키에 있어야 한다 (R54): 번호 모양
        /// (표 134) 은 자동 번호 치환 텍스트를 바꿔 첫 줄 폭 → 줄바꿈 → 블록
        /// 높이를 바꾼다. 구역이 번호를 재시작하면 (문단, 번호, 폭, 해석기) 가
        /// 모두 같으면서 모양만 다른 재사용이 살아난다.
        let footnoteShape: CoreHwp.HwpFootnoteShape?
    }

    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    /// 글자 모양별 속성 캐시 (소유는 `HwpPaginator`) — 각주 측정도 본문과 공유한다.
    private let attributeCache: HwpTextAttributeCache?
    private let footnoteLayout: HwpFootnoteLayout

    /// 이 페이지에 배치할 각주 (문단 + 문서 순서 번호)
    var pendingFootnotes: [HwpFootnoteLayout.Input] = []
    /// 문서/구역 끝에 배치할 미주 (표 134 bits 8-9)
    var pendingEndnotes: [HwpFootnoteLayout.Input] = []
    /// 각주 영역이 차지할 높이 (본문 overflow 검사에 반영)
    var footnoteReservedHeight: CGFloat = 0
    var footnoteCounter = 0
    /// 미주 번호 (각주와 별도 카운터, endNoteShape.startingNumber부터)
    var endnoteCounter = 0
    /// (문단, 폭)별 각주 문단 높이 캐시 — anticipated/collect/이월 예약 경로가
    /// 같은 각주를 반복 CT 레이아웃하지 않게 한다.
    private var footnoteHeightCache: [FootnoteHeightKey: CGFloat] = [:]
    /// 개체를 담는 각주의 블록 높이 캐시 — 위 텍스트 높이 캐시와 값의 의미가
    /// 달라 (개체 하한 포함) 사전을 나눈다.
    private var footnoteBlockHeightCache: [FootnoteHeightKey: CGFloat] = [:]

    init(
        index: HwpIndex,
        fontResolver: HwpFontResolver,
        attributeCache: HwpTextAttributeCache? = nil
    ) {
        self.index = index
        self.fontResolver = fontResolver
        self.attributeCache = attributeCache
        footnoteLayout = HwpFootnoteLayout(
            fontResolver: fontResolver, attributeCache: attributeCache
        )
    }

    // MARK: 수집

    /// includeTableCells: 표 셀 안 각주 포함 여부. 본문 top-level 걷기에서는
    /// false — 셀 각주는 그 행이 실리는 페이지에서 수집한다 (한글: 참조 행
    /// 페이지 귀속 — 헌법주석 p485 실측). 셀 문단 걷기 (표 배치 시)는 true.
    ///
    /// ordinals: **이 조각에 실린** top-level 컨트롤 서수 범위 (#95). 페이지에
    /// 걸친 문단은 조각마다 이 함수를 그 조각의 범위로 부르므로 각주가 참조가
    /// 놓인 페이지에 귀속된다. nil이면 문단 전체 (기존 동작). 깊이 0에만 적용된다.
    ///
    /// collectsNested: 컨트롤 **안쪽** 문단까지 내려갈지. 조각 단위 수집에서는
    /// 마지막 조각만 켠다 — 글상자·도형 같은 컨테이너는 `appendControlBlocks`가
    /// 모든 조각을 놓은 **뒤** 방출해 마지막 조각 페이지에 그려지므로, 그 안의
    /// 각주를 앞 조각에서 걷으면 각주와 그것을 그리는 컨테이너가 갈린다. 마지막
    /// 조각에서는 서수 범위와 **무관하게** 전체 컨트롤을 훑는다 (앞 범위의
    /// 컨테이너도 그 페이지에 그려지므로 범위로 자르면 그 각주가 유실된다).
    mutating func collectFootnotes(
        from paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        includeTableCells: Bool = true,
        ordinals: Range<Int>? = nil,
        collectsNested: Bool = true,
        environment: Environment,
        childParagraphs: ChildParagraphs
    ) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        func collectDirectNote(_ ctrl: CoreHwp.HwpCtrlId) {
            switch ctrl {
            case let .footnote(list):
                collectFootnotes(list, environment: environment)
            case let .endnote(list):
                collectEndnotes(list)
            default:
                break
            }
        }
        func walkChildren(of ctrl: CoreHwp.HwpCtrlId) {
            for (nested, _) in childParagraphs(ctrl) where nested.ctrlHeaderArray != nil {
                collectFootnotes(
                    from: nested,
                    depth: depth + 1,
                    includeTableCells: includeTableCells,
                    environment: environment,
                    childParagraphs: childParagraphs
                )
            }
        }
        /// 각주·미주는 이 조각이 곧바로 배치하므로 **안쪽 노트도 지금** 걷어야
        /// 참조와 같은 쪽에 실리고 번호 순서도 안 밀린다. 마지막 조각으로 미루는
        /// 것은 `appendControlBlocks`가 거기서 방출하는 컨테이너 (글상자·도형) 뿐이다.
        func isNoteContainer(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
            switch ctrl {
            case .footnote, .endnote: true
            default: false
            }
        }
        // 중첩을 안 걷는 조각은 **요청된 범위만** 훑는다 — 조각마다 전수 순회하면
        // O(run × 컨트롤)이라 조작 문서 (run·컨트롤 각 10,000, 파일은 수백 KB) 가
        // 페이지네이션을 세운다. 마지막 조각의 전수 순회는 문단당 한 번이라
        // 이차가 아니다.
        if let ordinals, !collectsNested {
            for ordinal in ordinals where ctrls.indices.contains(ordinal) {
                let ctrl = ctrls[ordinal]
                collectDirectNote(ctrl)
                guard depth < 3, isNoteContainer(ctrl) else { continue }
                walkChildren(of: ctrl)
            }
            return
        }
        for (ordinal, ctrl) in ctrls.enumerated() {
            let inFragment = depth > 0 || (ordinals?.contains(ordinal) ?? true)
            if inFragment {
                collectDirectNote(ctrl)
            }
            guard depth < 3 else { continue }
            if !includeTableCells, case .table = ctrl {
                continue
            }
            // 노트 컨테이너의 자식은 **그 노트를 배치하는 조각**이 걷는다 —
            // 마지막 조각이 또 걷으면 같은 각주를 두 번 센다.
            guard isNoteContainer(ctrl) ? inFragment : collectsNested else { continue }
            walkChildren(of: ctrl)
        }
    }

    /// 표 셀 각주를 수집한다. rows가 nil이면 전체, 아니면 해당 grid 행만
    /// (행 주소 없는 셀은 첫 세그먼트에서 수집).
    mutating func collectTableCellFootnotes(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>?,
        environment: Environment,
        childParagraphs: ChildParagraphs
    ) {
        for cell in Self.cellsInRows(cellsByRow, rows: rows) {
            for paragraph in cell.paragraphArray {
                collectFootnotes(
                    from: paragraph,
                    depth: 1,
                    environment: environment,
                    childParagraphs: childParagraphs
                )
            }
        }
    }

    /// 행 범위(nil이면 전체)의 셀을 행 오름차순 + 버킷 내 cellArray 순서로
    /// 훑는다 — 행 우선 저장 표에서 문서 순서와 동일하다 (각주 번호 보존).
    private static func cellsInRows(
        _ cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>?
    ) -> [CoreHwp.HwpTableCell] {
        let orderedRows = rows.map(Array.init) ?? cellsByRow.keys.sorted()
        // 원래 cellArray 인덱스로 재정렬해 문서 순서(=각주 번호 순서)를 정확히
        // 복원한다 — 행 우선 저장이 아니어도 기존 전수 스캔과 동일한 순서.
        return orderedRows
            .flatMap { cellsByRow[$0] ?? [] }
            .sorted { $0.index < $1.index }
            .map(\.cell)
    }

    private mutating func collectFootnotes(
        _ list: CoreHwp.HwpListControl,
        environment: Environment
    ) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        let isFirstOnPage = pendingFootnotes.isEmpty
        // 번호는 각주 컨트롤당 하나다 (한글과 동일). 여러 문단짜리 각주는
        // 같은 번호를 공유하고 첫 문단의 ext18 마커만 번호로 치환된다.
        let number = footnoteCounter
        footnoteCounter += 1
        // 예약은 실제 배치 (place의 스택 산식)와 동형: 페이지 첫 노트는
        // 구분선 오버헤드, 이후 노트는 노트 사이 간격 1회 (같은 번호의
        // 이어지는 문단은 간격 0 — stackBlocks와 동일).
        let metrics = footnoteReservationMetrics(environment: environment)
        footnoteReservedHeight += isFirstOnPage
            ? metrics.separatorOverhead
            : metrics.spacingBetweenNotes
        for paragraph in paragraphs {
            // 바로 아래 예약이 쓰는 해석기를 그대로 실어 배치까지 들고 간다 —
            // 배치 시점에 다시 읽으면 그 사이 단이 바뀌었을 때 갈린다 (R44 #1).
            pendingFootnotes.append(HwpFootnoteLayout.Input(
                paragraph: paragraph,
                number: number,
                sizeResolver: environment.sizeResolver
            ))
            footnoteReservedHeight += measuredFootnoteHeight(
                of: paragraph,
                number: number,
                environment: environment
            )
        }
    }

    /// 미주는 페이지 하단이 아니라 문서/구역 끝에 모아 배치한다 (표 134 bits 8-9).
    /// 각주와 별도 카운터를 쓴다.
    private mutating func collectEndnotes(_ list: CoreHwp.HwpListControl) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        let number = endnoteCounter
        endnoteCounter += 1
        for paragraph in paragraphs {
            pendingEndnotes.append(HwpFootnoteLayout.Input(
                paragraph: paragraph,
                number: number
            ))
        }
    }
}

// MARK: - 예약/측정

//
// 예약은 **배치와 동형**이어야 한다 (`HwpFootnoteLayout.place`의 스택 산식) —
// 예약이 작으면 각주 스택이 본문을 덮고, 크면 한글에 없는 페이지 절단이 생긴다.
// 그 동형성을 한 곳에서 읽을 수 있도록 확장으로 묶었다.

extension HwpFootnoteCoordinator {
    /// 각주 예약 기하 — 배치 (HwpFootnoteLayout.place)와 같은 divider 소스
    private func footnoteReservationMetrics(
        environment: Environment
    ) -> HwpFootnoteLayout.ReservationMetrics {
        footnoteLayout.reservationMetrics(
            footnoteShape: environment.footnoteShape,
            contentWidth: environment.contentWidth
        )
    }

    /// 이월된 각주 입력들이 새 페이지에서 예약할 높이 — 배치 (place)와
    /// 동형: Σ 높이 + 노트 경계마다 간격 + 구분선 오버헤드.
    mutating func reservedFootnoteHeight(
        for inputs: [HwpFootnoteLayout.Input],
        environment: Environment
    ) -> CGFloat {
        guard !inputs.isEmpty else { return 0 }
        let metrics = footnoteReservationMetrics(environment: environment)
        var total = metrics.separatorOverhead
        var previousNumber: Int?
        for input in inputs {
            if let previousNumber, previousNumber != input.number {
                total += metrics.spacingBetweenNotes
            }
            // 배치(`HwpFootnoteLayout.measure`)가 `input.sizeResolver`를 쓰므로
            // 재예약도 같은 값으로 재야 한다 — 현재 environment로 재면 그 사이
            // 단·구역 기하가 바뀐 문서에서 예약과 배치가 갈린다 (R45 #1).
            total += measuredFootnoteHeight(
                of: input.paragraph,
                number: input.number,
                environment: input.sizeResolver.map(environment.withSizeResolver) ?? environment
            )
            previousNumber = input.number
        }
        return total
    }

    /// 이 문단이 페이지에 추가될 때 각주 영역이 요구할 높이 (커밋 전 예측용).
    /// 컨테이너 (표 셀 등) 안 각주도 포함하며, 미주는 페이지 하단 영역을
    /// 쓰지 않으므로 계산에서 제외한다.
    mutating func anticipatedFootnoteHeight(
        for paragraph: CoreHwp.HwpParagraph,
        environment: Environment,
        childParagraphs: ChildParagraphs
    ) -> CGFloat {
        // collectFootnotes가 부여할 번호와 같은 순서의 미리보기 카운터
        var preview = footnoteCounter
        let body = anticipatedFootnoteBodyHeight(
            for: paragraph,
            preview: &preview,
            environment: environment,
            childParagraphs: childParagraphs
        )
        guard body > 0 else { return 0 }
        // 배치와 동형: 새 노트 수만큼의 경계 간격 (페이지 첫 노트는 경계가
        // 하나 적다) + 페이지 첫 각주면 구분선 오버헤드.
        let metrics = footnoteReservationMetrics(environment: environment)
        let newNotes = preview - footnoteCounter
        let boundaries = max(0, pendingFootnotes.isEmpty ? newNotes - 1 : newNotes)
        return body + metrics.spacingBetweenNotes * CGFloat(boundaries)
            + (pendingFootnotes.isEmpty ? metrics.separatorOverhead : 0)
    }

    /// 주어진 grid 행 범위의 셀 각주가 예약할 높이 — pending/reserved/counter를
    /// 바꾸지 않고 측정만 한다 (표 세그먼트 크기 산정 전 예약용, collect와 동형
    /// 필터). 셀 각주가 없으면 0이라 표 배치가 기존과 동일하다.
    mutating func anticipatedTableCellFootnoteHeight(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>,
        environment: Environment,
        childParagraphs: ChildParagraphs
    ) -> CGFloat {
        var preview = footnoteCounter
        var body: CGFloat = 0
        for cell in Self.cellsInRows(cellsByRow, rows: rows) {
            for paragraph in cell.paragraphArray {
                body += anticipatedFootnoteBodyHeight(
                    for: paragraph,
                    preview: &preview,
                    environment: environment,
                    childParagraphs: childParagraphs
                )
            }
        }
        guard body > 0 else { return 0 }
        let metrics = footnoteReservationMetrics(environment: environment)
        let newNotes = preview - footnoteCounter
        let boundaries = max(0, pendingFootnotes.isEmpty ? newNotes - 1 : newNotes)
        return body + metrics.spacingBetweenNotes * CGFloat(boundaries)
            + (pendingFootnotes.isEmpty ? metrics.separatorOverhead : 0)
    }

    private mutating func anticipatedFootnoteBodyHeight(
        for paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        preview: inout Int,
        environment: Environment,
        childParagraphs: ChildParagraphs
    ) -> CGFloat {
        guard let ctrls = paragraph.ctrlHeaderArray else { return 0 }
        var total: CGFloat = 0
        for ctrl in ctrls {
            if case let .footnote(list) = ctrl {
                let paragraphs = list.listArray.flatMap(\.paragraphArray)
                if !paragraphs.isEmpty {
                    let number = preview
                    preview += 1
                    // 같은 컨트롤의 문단은 간격 없이 이어진다 — 노트 경계
                    // 간격은 anticipatedFootnoteHeight가 노트 수로 계산한다
                    total += paragraphs.reduce(0) {
                        $0 + measuredFootnoteHeight(
                            of: $1,
                            number: number,
                            environment: environment
                        )
                    }
                }
            }
            guard depth < 3 else { continue }
            // 셀 각주는 행이 실리는 페이지에서 수집/예약되므로 예측에서도 제외
            if case .table = ctrl {
                continue
            }
            for (nested, _) in childParagraphs(ctrl) where nested.ctrlHeaderArray != nil {
                total += anticipatedFootnoteBodyHeight(
                    for: nested,
                    depth: depth + 1,
                    preview: &preview,
                    environment: environment,
                    childParagraphs: childParagraphs
                )
            }
        }
        return total
    }

    mutating func measuredFootnoteHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment
    ) -> CGFloat {
        // 개체 없는 각주 (대다수) 는 라인 캐시만으로 끝낸다 — CT 조판을 건너뛰는
        // 이 빠른 길이 대형 문서 로드 시간을 좌우한다 (헌법주석 1,030쪽).
        guard HwpParagraphObjectCollector.hasFloatingObject(
            in: paragraph, collectsTextboxes: true, collectsTables: true
        ) else {
            return measuredFootnoteTextHeight(
                of: paragraph, number: number, environment: environment
            )
        }
        return measuredNoteBlockHeight(
            of: paragraph, number: number, environment: environment
        )
    }

    /// 개체를 담는 각주의 예약 높이 — 배치와 **같은 함수**
    /// (`HwpFootnoteLayout.measureNote`) 로 재서 줄 앵커 판정까지 일치시킨다.
    /// 예약이 줄 없는 프레임으로 따로 재면 앵커 있는 개체까지 하한을 받아
    /// 배치보다 커진다 (R40 #1).
    private mutating func measuredNoteBlockHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment
    ) -> CGFloat {
        let width = environment.contentWidth
        let key = FootnoteHeightKey(
            paragraph: paragraph,
            widthCenti: Int(width * 100),
            number: number,
            sizeResolver: environment.sizeResolver?.forFootnoteArea(width: width),
            footnoteShape: environment.footnoteShape
        )
        if let cached = footnoteBlockHeightCache[key] {
            return cached
        }
        let height = footnoteLayout.measureNote(
            paragraph,
            number: number,
            width: width,
            index: index,
            footnoteShape: environment.footnoteShape,
            sizeResolver: environment.sizeResolver
        ).blockHeight
        footnoteBlockHeightCache[key] = height
        return height
    }

    /// 각주 문단의 **텍스트** 높이 — 배치 (HwpFootnoteLayout.measure)와 같은
    /// 기준: 라인 캐시 우선.
    private mutating func measuredFootnoteTextHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment
    ) -> CGFloat {
        if let cachedHeight = HwpParagraphLayout.cachedParagraphHeight(paragraph) {
            return cachedHeight
        }
        let width = environment.contentWidth
        let sizeResolver = environment.sizeResolver?.forFootnoteArea(width: width)
        let key = FootnoteHeightKey(
            paragraph: paragraph,
            widthCenti: Int(width * 100),
            number: number,
            sizeResolver: sizeResolver,
            footnoteShape: environment.footnoteShape
        )
        if let cached = footnoteHeightCache[key] {
            return cached
        }

        let measured = HwpParagraphMeasurer(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: sizeResolver,
            attributeCache: attributeCache
        )
        .measure(
            paragraph,
            width: width,
            options: .init(controlReplacements: HwpTextRunBuilder.autoNumberReplacements(
                in: paragraph,
                number: number,
                footnoteShape: environment.footnoteShape
            ))
        )
        let height = max(1, measured.frame.totalHeight)
        footnoteHeightCache[key] = height
        return height
    }
}

// MARK: - 번호 미리보기 / 배치 계산

extension HwpFootnoteCoordinator {
    /// 본문 문단의 extended 마커 치환: 각주/미주 참조 위치 (ext17)에는
    /// 위 첨자 번호를, 자동 쪽 번호 (atno kind 0)에는 논리 쪽 번호를 넣는다.
    /// 번호 미리보기는 collectFootnotes/collectEndnotes가 부여할 값과 같은
    /// 순서로 계산한다 (컨트롤당 1씩 증가).
    func noteReferenceReplacements(
        for paragraph: CoreHwp.HwpParagraph,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        endnoteShape: CoreHwp.HwpFootnoteShape?,
        pageNumber: Int,
        ordinals: Range<Int>? = nil
    ) -> [Int: HwpControlMarkerReplacement] {
        guard let ctrls = paragraph.ctrlHeaderArray else { return [:] }
        var replacements: [Int: HwpControlMarkerReplacement] = [:]
        var footnotePreview = footnoteCounter
        var endnotePreview = endnoteCounter
        // 조각 범위 밖 컨트롤은 미리보기도 **증가시키지 않는다** (#95): 앞 조각의
        // 몫은 이미 카운터에 반영됐고 뒤 조각의 몫은 아직 아니라, 범위 안만 세어야
        // 수집이 부여할 번호와 같아진다. 그래서 **범위만 훑어도 결과가 같고**,
        // 조각마다 전수 순회하지 않으므로 O(run × 컨트롤)이 되지 않는다.
        for ctrlIndex in ordinals ?? (0 ..< ctrls.count)
            where ctrls.indices.contains(ctrlIndex)
        {
            switch ctrls[ctrlIndex] {
            case .footnote:
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: HwpTextRunBuilder.noteNumberText(
                        number: footnotePreview,
                        footnoteShape: footnoteShape
                    ),
                    isSuperscript: true
                )
                footnotePreview += 1
            case .endnote:
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: HwpTextRunBuilder.noteNumberText(
                        number: endnotePreview,
                        footnoteShape: endnoteShape
                    ),
                    isSuperscript: true
                )
                endnotePreview += 1
            case let .autoNumber(other):
                if let info = other.autoNumberInfo, info.kind == .page {
                    replacements[ctrlIndex] = HwpControlMarkerReplacement(
                        text: HwpNumberFormat.string(
                            for: pageNumber,
                            shape: info.numberShapeRawValue
                        )
                    )
                }
            default:
                continue
            }
        }
        return replacements
    }

    // MARK: 배치 계산 (블록 방출·pending 소비는 paginator — 부수효과 경계)

    /// 대기 각주의 페이지 하단 배치를 계산한다 (HwpFootnoteLayout.place 위임).
    /// pendingFootnotes 소비 (overflow 반영)와 블록 방출은 호출자 몫.
    func placePendingFootnotes(
        onPage geometry: HwpPageGeometry,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        limitsAreaToHalfContent: Bool,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> HwpFootnoteLayout.Placement {
        footnoteLayout.place(
            footnotes: pendingFootnotes,
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape,
            limitsAreaToHalfContent: limitsAreaToHalfContent,
            sizeResolver: sizeResolver
        )
    }

    /// 대기 미주의 흐름 배치를 계산한다 (HwpFootnoteLayout.placeFlow 위임).
    /// pendingEndnotes 소비 (overflow 반영)와 블록 방출은 호출자 몫.
    func placePendingEndnotes(
        from startY: CGFloat,
        in columnFrame: CGRect,
        endnoteShape: CoreHwp.HwpFootnoteShape?,
        drawSeparator: Bool,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> HwpFootnoteLayout.FlowPlacement {
        footnoteLayout.placeFlow(
            footnotes: pendingEndnotes,
            from: startY,
            in: columnFrame,
            index: index,
            footnoteShape: endnoteShape,
            drawSeparator: drawSeparator,
            sizeResolver: sizeResolver
        )
    }
}
