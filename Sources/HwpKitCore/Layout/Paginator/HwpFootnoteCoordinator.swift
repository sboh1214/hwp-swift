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

        /// 각주 모양만 바꾼 사본 — 이월 각주를 재예약할 때 그 각주를 **처음 잰** 구역의
        /// 모양으로 되돌린다 (#165 리뷰). 현재 구역 모양으로 재면 라벨 길이가 달라져
        /// 배치(`Input.footnoteShape`)와 갈린다.
        func withFootnoteShape(_ shape: CoreHwp.HwpFootnoteShape?) -> Environment {
            Environment(
                contentWidth: contentWidth,
                footnoteShape: shape,
                sizeResolver: sizeResolver
            )
        }
    }

    /// paragraph-bearing 컨테이너의 단일 traversal 지점 주입
    /// (HwpPaginator.childParagraphs(of:) — unsupported walk/렌더 경로와 공유).
    typealias ChildParagraphs = (CoreHwp.HwpCtrlId) -> [(CoreHwp.HwpParagraph, HwpBlockKind)]

    let index: HwpIndex
    /// 예약 측정(`HwpFootnoteCoordinatorMeasurement.swift`)이 같은 해석기를 써야 하므로
    /// 모듈 안에서 보인다.
    let fontResolver: HwpFontResolver
    /// 글자 모양별 속성 캐시 (소유는 `HwpPaginator`) — 각주 측정도 본문과 공유한다.
    let attributeCache: HwpTextAttributeCache?
    let footnoteLayout: HwpFootnoteLayout

    /// 이 페이지에 배치할 각주 (문단 + 문서 순서 번호)
    /// 대기 각주 — 배치가 돌려준 이월 **슬라이스**를 그대로 든다 (#165 리뷰): 쪽마다 남은
    /// 각주를 새 배열로 뜨면 그 복사가 쪽 수 × N이다. 새 각주는 뒤에 붙인다 (슬라이스 뒤에
    /// 붙일 때만 그 남은 몫이 한 번 복사된다).
    var pendingFootnotes: ArraySlice<HwpFootnoteLayout.Input> = []
    /// 문서/구역 끝에 배치할 미주 (표 134 bits 8-9)
    var pendingEndnotes: ArraySlice<HwpFootnoteLayout.Input> = []
    /// 각주 영역이 차지할 높이 (본문 overflow 검사에 반영)
    var footnoteReservedHeight: CGFloat = 0
    var footnoteCounter = 0
    /// 미주 번호 (각주와 별도 카운터, endNoteShape.startingNumber부터)
    var endnoteCounter = 0
    /// (문단, 폭)별 각주 문단 높이 캐시 — anticipated/collect/이월 예약 경로가
    /// 같은 각주를 반복 CT 레이아웃하지 않게 한다.
    var footnoteHeightCache: [FootnoteHeightKey: CGFloat] = [:]
    /// 개체를 담는 각주의 블록 높이 캐시 — 위 텍스트 높이 캐시와 값의 의미가
    /// 달라 (개체 하한 포함) 사전을 나눈다.
    var footnoteBlockHeightCache: [FootnoteHeightKey: CGFloat] = [:]
    /// 배치를 미룬 컨테이너 안 각주 — top-level 컨트롤 서수별. 번호는 앞 조각에서
    /// 문서 순서대로 받아 두고 **배치만** 마지막 조각으로 미룬다. 열쇠(서수)가
    /// 문단 안에서만 유일하므로 문단마다 비운다 (`resetDeferredNestedFootnotes`).
    private var deferredNestedFootnotes: [Int: [DeferredNote]] = [:]
    /// 각주·미주 식별자 일련번호 (#165 리뷰) — **절대 리셋하지 않는다**. 표시 번호는
    /// 쪽마다 새로 시작할 수 있어 (표 134 모드 2) 이월된 각주와 새 각주가 같은 값을
    /// 갖는데, 배치는 "같은 각주의 이어지는 문단"을 그 값으로 가르기 때문이다.
    private var noteSequence = 0
    /// 지금 걷는 중인 컨테이너의 서수 — nil이 아니면 각주가 위 버퍼로 간다.
    /// 미주는 페이지 몫이 아니라 (문서·구역 끝 `placeFlow`) 이 우회로를 타지 않는다.
    private var deferralSink: Int?

    /// 번호만 앞 조각에서 확정하고 배치를 미룬 각주 하나. 해석기를 싣지 않는 것이
    /// 요점이다 — 예약도 배치도 **실릴 페이지**에서 일어나므로 그 시점 값을 써야
    /// 둘이 같은 기하를 본다 (R44 #1 · R45 #1).
    private struct DeferredNote {
        let paragraphs: [CoreHwp.HwpParagraph]
        let number: Int
        /// 표시 번호와 별개인 각주 식별자 (#165 리뷰)
        let noteId: Int
        /// 문단마다의 번호 열쇠 (#158) — 미룬 배치도 같은 라벨을 붙인다.
        let numbering: [HwpNumberingScope?]
    }

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
    ///
    /// numbering: 이 문단의 문단 번호·개요 번호 열쇠 (#158) — 각주·미주 문단과 그 안
    /// 컨테이너 문단이 컨트롤 서수·자식 서수로 자기 번호를 찾는다. nil이면 라벨 없다.
    mutating func collectFootnotes(
        from paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        includeTableCells: Bool = true,
        ordinals: Range<Int>? = nil,
        collectsNested: Bool = true,
        environment: Environment,
        childParagraphs: ChildParagraphs,
        numbering: HwpNumberingScope? = nil
    ) {
        guard let ctrls = paragraph.ctrlHeaderArray else { return }
        func collectDirectNote(_ ctrl: CoreHwp.HwpCtrlId, ordinal: Int) {
            let container = numbering?.container(controlIndex: ordinal)
            switch ctrl {
            case let .footnote(list):
                collectFootnotes(list, environment: environment, numbering: container)
            case let .endnote(list):
                collectEndnotes(list, numbering: container)
            default:
                break
            }
        }
        func walkChildren(of ctrl: CoreHwp.HwpCtrlId, ordinal: Int) {
            let container = numbering?.container(controlIndex: ordinal)
            // 자식 서수는 필터 **앞**에서 센다 — 컨트롤 없는 문단도 서수를 차지한다.
            for (childIndex, (nested, _)) in childParagraphs(ctrl).enumerated()
                where nested.ctrlHeaderArray != nil
            {
                collectFootnotes(
                    from: nested,
                    depth: depth + 1,
                    includeTableCells: includeTableCells,
                    environment: environment,
                    childParagraphs: childParagraphs,
                    numbering: container?.paragraph(childIndex: childIndex)
                )
            }
        }
        /// 각주는 이 조각이 곧바로 배치하므로 (`cacheCurrentPage` → `place`)
        /// **안쪽 노트도 지금** 걷어야 참조와 같은 쪽에 실리고 번호도 안 밀린다.
        ///
        /// **미주는 아니다**: 문서·구역 끝에서 `placeFlow`로 배치되므로 이 조각이
        /// 그리지 않는다 — 안쪽 각주를 지금 걷으면 참조는 문서 끝에, 각주는 본문
        /// 쪽에 남는다. 그래서 미주 자손은 글상자·도형과 같이 마지막 조각으로
        /// 미룬다. 미주와 **함께** 가는 것이 옳지만 `pendingFootnotes`가 페이지
        /// 단위라 통로가 없다 (남은 격차 — AGENTS.md).
        func isPlacedByThisFragment(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
            if case .footnote = ctrl {
                return true
            }
            return false
        }
        /// 배치는 마지막 조각으로 미루되 **번호는 지금** 받는다 (#95 리뷰).
        /// 번호가 수집 순서라 미루면 뒤에 오는 직접 각주가 먼저 번호를 가져가
        /// 문서 순서와 뒤집힌다. 자손 전체가 이 서수의 버퍼로 흐른다.
        func deferNestedNotes(of ctrl: CoreHwp.HwpCtrlId, ordinal: Int) {
            let outer = deferralSink
            deferralSink = ordinal
            walkChildren(of: ctrl, ordinal: ordinal)
            deferralSink = outer
        }
        // 쪽마다 새로 시작 (표 134 numberingMode 2) 하면 번호가 **그려질 쪽**의
        // 함수라 앞 조각에서 미리 받을 수 없다 — run 사이 `cacheCurrentPage`가
        // 카운터를 시작 번호로 되돌리므로 미리 받은 번호는 그 쪽 첫 각주와 겹친다.
        // 그 모드엔 보존할 순서 관계도 없어 (쪽마다 1로 되돌아간다) 컨테이너를
        // 마지막 조각이 걷게 두면 번호가 제 쪽 카운터에서 나온다.
        let restartsNumberingPerPage = environment.footnoteShape?.numberingModeRawValue == 2
        // 중첩을 안 걷는 조각은 **요청된 범위만** 훑는다 — 조각마다 전수 순회하면
        // O(run × 컨트롤)이라 조작 문서 (run·컨트롤 각 10,000, 파일은 수백 KB) 가
        // 페이지네이션을 세운다. 마지막 조각의 전수 순회는 문단당 한 번이라
        // 이차가 아니다.
        if let ordinals, !collectsNested {
            for ordinal in ordinals where ctrls.indices.contains(ordinal) {
                let ctrl = ctrls[ordinal]
                collectDirectNote(ctrl, ordinal: ordinal)
                guard depth < 3 else { continue }
                if !includeTableCells, case .table = ctrl {
                    continue
                }
                if isPlacedByThisFragment(ctrl) {
                    walkChildren(of: ctrl, ordinal: ordinal)
                } else if !restartsNumberingPerPage {
                    deferNestedNotes(of: ctrl, ordinal: ordinal)
                }
            }
            return
        }
        for (ordinal, ctrl) in ctrls.enumerated() {
            let inFragment = depth > 0 || (ordinals?.contains(ordinal) ?? true)
            if inFragment {
                collectDirectNote(ctrl, ordinal: ordinal)
            }
            guard depth < 3 else { continue }
            if !includeTableCells, case .table = ctrl {
                continue
            }
            // 앞 조각이 번호를 매겨 둔 컨테이너는 다시 걷지 않고 그 버퍼를 푼다 —
            // 다시 걸으면 번호를 두 번 받아 문서 순서가 어긋난다.
            if depth == 0, flushDeferredNestedNotes(at: ordinal, environment: environment) {
                continue
            }
            // 이 조각이 배치하는 컨테이너(각주)의 자식은 **그 조각**이 걷는다 —
            // 마지막 조각이 또 걷으면 같은 각주를 두 번 센다. 나머지(미주·글상자
            // ·도형)는 이 조각이 안 그리므로 마지막 조각 몫이다.
            guard isPlacedByThisFragment(ctrl) ? inFragment : collectsNested
            else { continue }
            walkChildren(of: ctrl, ordinal: ordinal)
        }
    }

    /// 표 셀 각주를 수집한다. rows가 nil이면 전체, 아니면 해당 grid 행만
    /// (행 주소 없는 셀은 첫 세그먼트에서 수집).
    /// numbering: 이 표의 셀 문단 열쇠 (#158) — `cellArray` 서수와 문단 서수로 푼다.
    mutating func collectTableCellFootnotes(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>?,
        environment: Environment,
        childParagraphs: ChildParagraphs,
        numbering: HwpNumberingScope.TableCells? = nil
    ) {
        for (cellIndex, cell) in Self.cellsInRows(cellsByRow, rows: rows) {
            for (paragraphIndex, paragraph) in cell.paragraphArray.enumerated() {
                collectFootnotes(
                    from: paragraph,
                    depth: 1,
                    environment: environment,
                    childParagraphs: childParagraphs,
                    numbering: numbering?.paragraph(
                        cellIndex: cellIndex, paragraphIndex: paragraphIndex
                    )
                )
            }
        }
    }

    /// 행 범위(nil이면 전체)의 셀을 행 오름차순 + 버킷 내 cellArray 순서로
    /// 훑는다 — 행 우선 저장 표에서 문서 순서와 동일하다 (각주 번호 보존).
    static func cellsInRows(
        _ cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>?
    ) -> [(index: Int, cell: CoreHwp.HwpTableCell)] {
        let orderedRows = rows.map(Array.init) ?? cellsByRow.keys.sorted()
        // 원래 cellArray 인덱스로 재정렬해 문서 순서(=각주 번호 순서)를 정확히
        // 복원한다 — 행 우선 저장이 아니어도 기존 전수 스캔과 동일한 순서.
        return orderedRows
            .flatMap { cellsByRow[$0] ?? [] }
            .sorted { $0.index < $1.index }
    }

    private mutating func collectFootnotes(
        _ list: CoreHwp.HwpListControl,
        environment: Environment,
        numbering: HwpNumberingScope.Container?
    ) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        // 각주 문단의 번호 경로 서수는 리스트를 펼친 평면 서수다 (#158).
        let scopes = paragraphs.indices.map { numbering?.paragraph(childIndex: $0) }
        // 번호는 각주 컨트롤당 하나다 (한글과 동일). 여러 문단짜리 각주는
        // 같은 번호를 공유하고 첫 문단의 ext18 마커만 번호로 치환된다.
        let number = footnoteCounter
        footnoteCounter += 1
        noteSequence += 1
        let noteId = noteSequence
        // 카운터 증가가 sink 분기보다 **앞**이어야 한다 — 번호는 문서 순서고
        // 미루는 것은 배치뿐이다 (예약도 배치와 함께 그 페이지에서 잡힌다).
        if let sink = deferralSink {
            deferredNestedFootnotes[sink, default: []].append(
                DeferredNote(
                    paragraphs: paragraphs, number: number, noteId: noteId, numbering: scopes
                )
            )
            return
        }
        appendPendingFootnote(
            paragraphs: paragraphs, number: number, noteId: noteId,
            environment: environment, numbering: scopes
        )
    }

    /// 각주 하나를 이 페이지 스택에 올린다 — 수집 시점과 미룬 배치가 **같은
    /// 산식**을 쓰도록 한 곳에 둔다. 예약은 실제 배치 (place의 스택 산식)와
    /// 동형: 페이지 첫 노트는 구분선 오버헤드, 이후 노트는 노트 사이 간격 1회
    /// (같은 번호의 이어지는 문단은 간격 0 — stackBlocks와 동일).
    private mutating func appendPendingFootnote(
        paragraphs: [CoreHwp.HwpParagraph],
        number: Int,
        noteId: Int,
        environment: Environment,
        numbering: [HwpNumberingScope?]
    ) {
        // 개체 판정은 **각주 단위**다 (#165 리뷰) — 예약이 배치(`HwpFootnoteLayout.measure`)와
        // 같은 범위를 봐야 개체를 담은 각주의 앞 문단 높이가 갈리지 않는다.
        let noteCarriesObjects = paragraphs.contains {
            HwpParagraphObjectCollector.hasCollectibleObject(
                in: $0, collectsTextboxes: true, collectsTables: true
            )
        }
        let isFirstOnPage = pendingFootnotes.isEmpty
        let metrics = footnoteReservationMetrics(environment: environment)
        footnoteReservedHeight += isFirstOnPage
            ? metrics.separatorOverhead
            : metrics.spacingBetweenNotes
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let scope = numbering.indices.contains(paragraphIndex) ? numbering[paragraphIndex] : nil
            // 바로 아래 예약이 쓰는 해석기를 그대로 실어 배치까지 들고 간다 —
            // 배치 시점에 다시 읽으면 그 사이 단이 바뀌었을 때 갈린다 (R44 #1).
            // 번호 열쇠도 같이 실어 배치가 예약과 같은 라벨을 붙인다 (#158).
            pendingFootnotes.append(HwpFootnoteLayout.Input(
                paragraph: paragraph,
                number: number,
                sizeResolver: environment.sizeResolver,
                numbering: scope,
                noteId: noteId,
                // 각주 모양도 수집 시점에 **각인**한다 (#165 리뷰) — 바로 아래 예약이 이 모양으로
                // 재고, 배치는 각인된 모양을 쓰므로 예약 ≡ 배치다. 배치가 쪽마다 대기 각주 전부에
                // 각인하던 일(쪽 수 × N)도 없어진다. 기본 모양(nil)도 확정이다.
                measuredShape: .init(footnoteShape: environment.footnoteShape)
            ))
            footnoteReservedHeight += measuredFootnoteHeight(
                of: paragraph,
                number: number,
                environment: environment,
                numbering: scope,
                isNoteEnd: paragraphIndex == paragraphs.count - 1,
                noteCarriesObjects: noteCarriesObjects
            )
        }
    }

    /// 미룬 각주를 이 페이지 스택에 푼다. 푼 것이 있으면 true — 호출자는 그
    /// 컨테이너를 다시 걷지 않는다 (걸으면 번호를 두 번 받는다).
    private mutating func flushDeferredNestedNotes(
        at ordinal: Int,
        environment: Environment
    ) -> Bool {
        guard let deferred = deferredNestedFootnotes.removeValue(forKey: ordinal) else {
            return false
        }
        for note in deferred {
            appendPendingFootnote(
                paragraphs: note.paragraphs, number: note.number, noteId: note.noteId,
                environment: environment, numbering: note.numbering
            )
        }
        return true
    }

    /// 미룬 각주 버퍼를 비운다 — 열쇠인 서수가 **문단 안에서만** 유일하므로
    /// 문단마다 호출해야 앞 문단의 잔여가 다른 컨테이너로 새지 않는다.
    /// 정상 경로에서는 마지막 조각의 전수 순회가 모든 서수를 방문해 이미
    /// 비어 있다 (빈 run으로 그 순회를 건너뛴 문단만 잔여가 남는다).
    mutating func resetDeferredNestedFootnotes() {
        deferredNestedFootnotes.removeAll(keepingCapacity: true)
    }

    /// 미주는 페이지 하단이 아니라 문서/구역 끝에 모아 배치한다 (표 134 bits 8-9).
    /// 각주와 별도 카운터를 쓴다.
    private mutating func collectEndnotes(
        _ list: CoreHwp.HwpListControl,
        numbering: HwpNumberingScope.Container?
    ) {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return }
        let number = endnoteCounter
        endnoteCounter += 1
        noteSequence += 1
        let noteId = noteSequence
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            pendingEndnotes.append(HwpFootnoteLayout.Input(
                paragraph: paragraph,
                number: number,
                sizeResolver: nil,
                numbering: numbering?.paragraph(childIndex: paragraphIndex),
                noteId: noteId
            ))
        }
    }
}
