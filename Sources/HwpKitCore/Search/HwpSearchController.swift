import CoreGraphics
import Foundation
import Observation

/// 스캔 진행 상태.
///
/// `isScanning: Bool` 하나로는 "결과 0" / "아직 스캔 중" / "상한에 걸려 잘림"을
/// 호스트가 가를 수 없다 — 셋은 UI에서 서로 다른 문구다.
public enum HwpSearchPhase: Sendable, Hashable {
    case idle
    case scanning
    case complete
    /// `matchLimit`에 걸려 잘렸다. 표시된 개수가 전부가 아니다.
    case truncated
}

/// 문서 검색 세션 — 호스트가 소유하고 뷰와 검색 UI에 **같은 인스턴스**를 넘긴다.
///
/// **선택 상태와 완전히 별개다.** 현재 매치를
/// `HwpSelectionController.selection`에 밀어 넣으면 Cmd+C 복사 대상과 선택
/// 하이라이트가 검색 매치로 덮인다.
///
/// **지오메트리 참조를 캐싱하지 않는다.** `attach(to:)`로 받은 선택 컨트롤러의
/// 것을 매번 읽는다 — `setDocument`이 무조건 새 인스턴스를 만들므로, 참조를
/// 들고 있으면 죽은 조판으로 좌표를 만드는 상태가 존재하게 된다.
///
/// **통지가 두 갈래인 것은 역할이 달라서다.** 클로저 콜백은 뷰의 명령형
/// 부수효과(오버레이 갱신·스크롤) 전용이고 구독자가 하나뿐이라 기존
/// `HwpSelectionController.onSelectionChanged` 규약과 같다. `@Observable`
/// 프로퍼티는 호스트 UI(다중 구독자)용이라, 호스트가 검색 바를 직접 만들어도
/// 배선 코드가 0이다.
@MainActor
@Observable
public final class HwpSearchController {
    public init(
        query: HwpSearchQuery = .empty,
        style: HwpSearchHighlightStyle = .default
    ) {
        storedQuery = query
        self.style = style
    }

    /// 커스텀 네이티브 뷰 경로 — 생성과 동시에 붙인다.
    public convenience init(
        selection: HwpSelectionController,
        query: HwpSearchQuery = .empty,
        style: HwpSearchHighlightStyle = .default
    ) {
        self.init(query: query, style: style)
        attach(to: selection)
    }

    // MARK: - 질의

    private var storedQuery: HwpSearchQuery

    /// 대입하면 진행 중 스캔을 취소하고 새로 시작한다. 읽기·쓰기가 대칭이라
    /// `controller.query = ...` 첫 시도가 실패하지 않는다.
    public var query: HwpSearchQuery {
        get { storedQuery }
        set { search(newValue) }
    }

    public func search(_ query: HwpSearchQuery) {
        guard storedQuery != query else { return }
        storedQuery = query
        restartScan()
    }

    public func search(text: String) {
        search(HwpSearchQuery(text: text, options: storedQuery.options))
    }

    /// 하이라이트 색. 대입은 뷰에 다시 칠하라는 통지를 겸한다.
    ///
    /// 통지가 붙어 있어야 하는 이유: 뷰는 이 프로퍼티를 관찰하지 않는다.
    /// 네이티브 배선은 매치 콜백 둘만 듣고, SwiftUI wrapper는 컨트롤러
    /// **신원**만 넘기며 그 대입조차 동일성 가드가 막는다. 색만 바뀐 순간에는
    /// 아무도 다시 칠하지 않아 다음 스크롤·검색 이벤트까지 옛 색이 남는다.
    public var style: HwpSearchHighlightStyle {
        didSet {
            guard style != oldValue else { return }
            onMatchesChanged?()
        }
    }

    // MARK: - 예산 (성능 — 결과의 의미를 바꾸지 않는다)

    /// 0이면 무제한. 기본 5,000 — 1,030쪽에서 "의" 같은 질의는 수만 매치를
    /// 만들고, 각주 자동 번호가 실제 문자로 치환돼 들어오므로 짧은 질의의
    /// 폭발은 가설이 아니다. 상한에 닿으면 `phase == .truncated`가 된다.
    public var matchLimit: Int = 5000 {
        didSet {
            if matchLimit != oldValue {
                restartScan()
            }
        }
    }

    /// 0이면 스니펫 미수집(기본). 결과 목록 UI를 만들 때만 켠다.
    public var snippetPadding: Int = 0 {
        didSet {
            if snippetPadding != oldValue {
                restartScan()
            }
        }
    }

    /// 스캔 중 발행 최소 간격. 페이지마다 발행하면 1,030쪽에서 관찰자 갱신이
    /// 1,030회다. **첫 발행·스캔 완료·현재 매치 변경은 이 간격과 무관하게
    /// 즉시 반영한다.**
    public var publishInterval: Duration = .milliseconds(50)

    /// 스캔 중 유지할 페이지 범위를 알려 주는 훅.
    ///
    /// 전 문서 스캔은 1,030쪽 전부의 단위 배열을 지오메트리 캐시에 남긴다.
    /// 유지 범위를 아는 것은 가상화를 하는 뷰 계층뿐이므로 그쪽이 이 훅을
    /// 채운다. **nil이면 축출하지 않는다** — 엔진만 쓰는 배치 인덱싱은 전량
    /// 상주가 오히려 맞다.
    public var retainedPageRange: (@MainActor () -> Range<Int>)?

    // MARK: - 출력

    /// 탐색·카운트 기준 — 문서 순서, 반복 머리행 클론 dedup 적용.
    /// `currentMatchIndex`는 이 배열의 인덱스다.
    public private(set) var matches: [HwpSearchMatch] = []

    /// 하이라이트 기준 — 클론 포함 전량. `matches`는 이것의 부분열이다.
    public private(set) var highlightMatches: [HwpSearchMatch] = []

    /// `matches`의 0-기반 인덱스. 매치가 없으면 nil.
    public private(set) var currentMatchIndex: Int?

    public private(set) var phase: HwpSearchPhase = .idle

    /// 지금까지 스캔한 페이지 수 — 진행률 표시용.
    public private(set) var scannedPageCount: Int = 0

    /// 스캔 대상 페이지 수.
    public private(set) var pageCount: Int = 0

    /// 발행 일련번호(단조 증가). 뷰가 '같은 발행인가'를 O(1)로 판정해
    /// 불필요한 오버레이 재계산을 막는다.
    public private(set) var revision: UInt64 = 0

    public var matchCount: Int {
        matches.count
    }

    public var currentMatch: HwpSearchMatch? {
        guard let currentMatchIndex, matches.indices.contains(currentMatchIndex) else {
            return nil
        }
        return matches[currentMatchIndex]
    }

    // MARK: - 명령

    public func next() {
        step(by: 1)
    }

    public func previous() {
        step(by: -1)
    }

    /// 범위 밖 인덱스는 클램프한다. 공개 진입점이라 임의 값이 들어온다는
    /// 전제로 방어한다 — 클램프를 산술보다 **먼저** 해 `Int.min`/`Int.max`가
    /// 트랩하지 않게 한다.
    public func select(matchIndex: Int) {
        guard !matches.isEmpty else { return }
        let clamped = max(0, min(matchIndex, matches.count - 1))
        guard clamped != currentMatchIndex else { return }
        currentMatchIndex = clamped
        bumpRevision()
        onCurrentMatchChanged?(currentMatch)
    }

    /// 질의와 결과를 전부 비운다.
    public func clear() {
        scanTask?.cancel()
        scanTask = nil
        storedQuery = .empty
        matches = []
        highlightMatches = []
        currentMatchIndex = nil
        phase = .idle
        scannedPageCount = 0
        publishedPageUpperBound = 0
        bumpRevision()
        onMatchesChanged?()
        onCurrentMatchChanged?(nil)
    }

    // MARK: - 통지 (뷰가 소유한다)

    /// 매치 목록이나 하이라이트 색이 바뀌었다 — 뷰는 오버레이를 다시 그린다.
    public var onMatchesChanged: (() -> Void)?
    /// 현재 매치가 바뀌었다 — 뷰는 그 매치가 보이도록 스크롤한다.
    public var onCurrentMatchChanged: ((HwpSearchMatch?) -> Void)?

    // MARK: - 하이라이트 (커스텀 네이티브 뷰용)

    /// 그 페이지의 **전체 매치** rect (페이지 로컬 top-down).
    public func highlightRects(forPage pageIndex: Int) -> [CGRect] {
        guard let geometry else { return [] }
        let selections = highlightMatches
            .filter { $0.pageIndex == pageIndex }
            .map(\.selection)
        return geometry.highlightRects(pageIndex: pageIndex, selections: selections)
    }

    /// 그 페이지의 **현재 매치** rect.
    public func currentMatchRects(forPage pageIndex: Int) -> [CGRect] {
        guard let geometry, let currentMatch, currentMatch.pageIndex == pageIndex else {
            return []
        }
        return geometry.highlightRects(
            pageIndex: pageIndex, selections: [currentMatch.selection]
        )
    }

    // MARK: - 연결 (뷰가 부른다)

    /// 선택 컨트롤러에 붙어 지오메트리를 공유한다 (단위 캐시 이중화 금지).
    ///
    /// 붙는 즉시 `onGeometryChanged`를 걸어 문서 교체·프로그레시브 스냅샷에서
    /// 자동 재스캔한다. 같은 컨트롤러 재-attach는 멱등이다.
    ///
    /// 한 선택 컨트롤러에는 검색 컨트롤러 하나만 붙는다 — `onGeometryChanged`가
    /// 단일 콜백 슬롯이라 나중에 붙은 쪽이 이긴다.
    public func attach(to selection: HwpSelectionController) {
        guard self.selection !== selection else { return }
        detach()
        self.selection = selection
        selection.onGeometryChanged = { [weak self] change in
            self?.geometryDidChange(change)
        }
        restartScan()
    }

    /// 붙은 지오메트리를 놓고 **결과까지 되돌린 뒤** idle 을 발행한다.
    ///
    /// 결과를 남기면 호스트 검색 바가 문서를 닫은 뒤에도 "3 of 12" 를 보여 주고
    /// 이전/다음 버튼도 살아 있는데, 지오메트리가 없어 하이라이트는 빈 배열이라
    /// 카운터만 거짓말을 한다. 스캔 도중 해체면 그것을 끝낼 유일한 태스크가
    /// 취소되므로 `.scanning` 이 영영 남는다. 질의는 지우지 않는다 — 그건 호스트
    /// 검색 필드의 텍스트이고, 함께 비우는 것은 `clear()` 의 몫이다.
    public func detach() {
        scanTask?.cancel()
        scanTask = nil
        selection?.onGeometryChanged = nil
        selection = nil
        pageCount = 0
        scannedPageCount = 0
        publishedPageUpperBound = 0
        matches = []
        highlightMatches = []
        currentMatchIndex = nil
        phase = .idle
        bumpRevision()
        onMatchesChanged?()
        onCurrentMatchChanged?(nil)
    }

    /// 이 세션이 그 선택 컨트롤러에 붙어 있는가.
    ///
    /// 뷰 해체가 **자기 것만** 떼기 위한 질의다. SwiftUI 가 새 뷰를 먼저 만들고
    /// 옛 뷰를 나중에 해체할 수 있으므로, 옛 뷰가 무조건 `detach()` 하면 이미
    /// 새 뷰에 붙은 살아 있는 세션이 끊긴다.
    public func isAttached(to selection: HwpSelectionController) -> Bool {
        self.selection === selection
    }

    /// 전량 재스캔을 강제한다.
    public func rescan() {
        restartScan()
    }

    // MARK: - 내부

    /// 붙은 선택 컨트롤러를 **강하게** 잡는다.
    ///
    /// 순환이 되지 않는다 — 되돌아오는 참조인 `selection.onGeometryChanged`
    /// 클로저가 `self`를 weak으로 캡처한다. 약하게 잡으면 호스트가 선택
    /// 컨트롤러를 따로 붙들지 않는 순간 검색 세션이 아무 신호 없이 죽는다
    /// (지오메트리가 nil이 되어 모든 스캔이 조용히 idle로 끝난다).
    @ObservationIgnored
    private var selection: HwpSelectionController?

    @ObservationIgnored
    private var scanTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastPublish: ContinuousClock.Instant?

    /// publish된 결과가 담고 있는 **연속 접두**의 끝 (배타적).
    ///
    /// 프로그레시브 append 가 다시 훑기 시작할 지점이다. `previousPageCount`
    /// 부터 시작하면 안 된다 — append 는 진행 중 스캔을 취소하는데 `runScan` 은
    /// 마지막으로 **publish된** 결과를 이어받으므로, 아직 안 훑은 페이지와
    /// 스로틀에 걸려 아직 publish되지 않은 페이지의 매치가 통째로 사라진다.
    /// 로더 배치(24)가 양보 간격(16)보다 커서 그 창은 배치마다 열린다.
    @ObservationIgnored
    private var publishedPageUpperBound = 0

    private var geometry: HwpSelectionGeometry? {
        selection?.geometry
    }

    /// 몇 페이지마다 협조적으로 양보할지. 스캔은 메인 격리라 이 값이 곧
    /// 타이핑 응답성이다.
    private static let yieldInterval = 16

    private func geometryDidChange(_ change: HwpGeometryChange) {
        if change.isProgressiveAppend, !storedQuery.isEmpty, phase != .idle {
            // 기존 페이지의 조판·오프셋은 그대로 유효하다 — 늘어난 구간만 본다.
            // 프로그레시브 로딩은 스냅샷이 수십 회 오므로, 여기서 전량
            // 재스캔하면 1,030쪽 전개가 그만큼 반복된다.
            startScan(pages: change.previousPageCount ..< change.pageCount, appending: true)
        } else {
            restartScan()
        }
    }

    private func restartScan() {
        startScan(pages: nil, appending: false)
    }

    private func startScan(pages: Range<Int>?, appending: Bool) {
        scanTask?.cancel()
        scanTask = nil
        lastPublish = nil

        guard let geometry, !storedQuery.isEmpty else {
            matches = []
            highlightMatches = []
            currentMatchIndex = nil
            phase = .idle
            scannedPageCount = 0
            pageCount = geometry?.pageCount ?? 0
            bumpRevision()
            onMatchesChanged?()
            onCurrentMatchChanged?(nil)
            return
        }

        pageCount = geometry.pageCount
        if !appending {
            matches = []
            highlightMatches = []
            currentMatchIndex = nil
            scannedPageCount = 0
            publishedPageUpperBound = 0
        }
        phase = .scanning
        let requested = pages ?? 0 ..< pageCount
        let lowerBound = appending
            ? min(publishedPageUpperBound, requested.lowerBound)
            : requested.lowerBound
        let range = (lowerBound ..< max(lowerBound, requested.upperBound))
            .clamped(to: 0 ..< pageCount)
        scanTask = Task { [weak self] in
            await self?.runScan(pages: range, appending: appending)
        }
    }

    private func runScan(pages: Range<Int>, appending: Bool) async {
        guard let geometry else { return }
        var collected = appending ? highlightMatches : []
        let query = storedQuery
        var scannedThrough = pages.lowerBound

        for (step, pageIndex) in pages.enumerated() {
            if Task.isCancelled {
                return
            }
            let remaining = matchLimit > 0 ? matchLimit - collected.count : 0
            if matchLimit > 0, remaining <= 0 {
                break
            }

            collected += HwpTextSearcher.matches(
                in: geometry.units(forPage: pageIndex),
                pageIndex: pageIndex,
                query: query,
                matchLimit: remaining,
                snippetPadding: snippetPadding
            )
            scannedPageCount = pageIndex + 1
            scannedThrough = pageIndex + 1

            if shouldPublishNow() {
                publish(collected, phase: .scanning, scannedThrough: scannedThrough)
            }
            if step % Self.yieldInterval == Self.yieldInterval - 1 {
                evictScannedUnits()
                await Task.yield()
            }
        }

        if Task.isCancelled {
            return
        }
        evictScannedUnits()
        publish(
            collected,
            phase: matchLimit > 0 && collected.count >= matchLimit ? .truncated : .complete,
            scannedThrough: scannedThrough
        )
    }

    /// 스캔이 채운 단위 캐시를 뷰가 요구한 범위로 되돌린다.
    private func evictScannedUnits() {
        guard let retainedPageRange, let geometry else { return }
        geometry.evictUnits(keeping: retainedPageRange())
    }

    private func shouldPublishNow() -> Bool {
        guard let lastPublish else { return true }
        return ContinuousClock.now - lastPublish >= publishInterval
    }

    private func publish(
        _ collected: [HwpSearchMatch],
        phase: HwpSearchPhase,
        scannedThrough: Int
    ) {
        lastPublish = ContinuousClock.now
        publishedPageUpperBound = scannedThrough
        highlightMatches = collected
        let deduped = HwpTextSearcher.deduplicatingRepeatedTableHeaders(collected)
        let previousCurrent = currentMatch
        matches = deduped
        self.phase = phase

        // 스캔 중에는 현재 매치를 **재배치하지 않는다** — 앞 페이지 결과가
        // 뒤에 붙는 구조라 인덱스가 흔들리지 않고, 사용자가 이미 골라 둔
        // 매치를 스캔 진행이 빼앗지 않는다.
        if let previousCurrent, let index = deduped.firstIndex(of: previousCurrent) {
            currentMatchIndex = index
        } else if currentMatchIndex != nil, deduped.isEmpty {
            currentMatchIndex = nil
        } else if currentMatchIndex == nil, !deduped.isEmpty {
            currentMatchIndex = 0
            bumpRevision()
            onMatchesChanged?()
            onCurrentMatchChanged?(currentMatch)
            return
        }
        bumpRevision()
        onMatchesChanged?()
    }

    private func step(by offset: Int) {
        guard !matches.isEmpty else { return }
        let base = currentMatchIndex ?? 0
        // 순환 — 마지막에서 next는 첫 매치로, 첫 매치에서 previous는 마지막으로.
        let count = matches.count
        let target = ((base + offset) % count + count) % count
        guard target != currentMatchIndex else { return }
        currentMatchIndex = target
        bumpRevision()
        onCurrentMatchChanged?(currentMatch)
    }

    private func bumpRevision() {
        revision &+= 1
    }
}
