import CoreGraphics
import Foundation

/// `HwpSelectionController`가 지오메트리를 새로 만들었다는 사건.
public struct HwpGeometryChange: Sendable, Hashable {
    public let previousPageCount: Int
    public let pageCount: Int
    /// 같은 로드(`loadToken`)의 스냅샷이 페이지를 덧붙이기만 했는가.
    ///
    /// true면 `0 ..< previousPageCount`의 조판·오프셋이 그대로 유효하므로
    /// 소비자는 `previousPageCount ..< pageCount`만 다시 보면 된다. 문서
    /// 교체·nil-token 문서·페이지 감소는 전부 false다.
    public let isProgressiveAppend: Bool

    /// 내용이 같은 문서로 지오메트리만 새로 만든 것인가.
    ///
    /// `==` 는 블록의 텍스트·payload·역할까지 비교하므로 참이면 검색 좌표계
    /// (쪽·블록·단위·오프셋)가 **그대로**다 — 다를 수 있는 것은 색·폰트 같은
    /// 렌더 속성뿐이고 그것은 rect 재계산으로 흡수된다. nil-token 문서는
    /// 위 `setDocument` 의 조기 반환에 걸리지 않아 SwiftUI 업데이트마다 이
    /// 사건이 온다.
    public let isEquivalentRefresh: Bool

    public init(
        previousPageCount: Int,
        pageCount: Int,
        isProgressiveAppend: Bool,
        isEquivalentRefresh: Bool = false
    ) {
        self.previousPageCount = previousPageCount
        self.pageCount = pageCount
        self.isProgressiveAppend = isProgressiveAppend
        self.isEquivalentRefresh = isEquivalentRefresh
    }
}

/// 텍스트 선택 상태 보관 — macOS/iOS 뷰가 공유하는 플랫폼 중립 컨트롤러.
/// 뷰는 입력 (드래그/롱프레스)을 위치로 해석해 begin/extend를 부르고,
/// `onSelectionChanged`에서 하이라이트 오버레이를 갱신한다.
@MainActor
public final class HwpSelectionController {
    public var document: HwpDocument? {
        get { backingDocument }
        set { setDocument(newValue, preservingSelection: false) }
    }

    private var backingDocument: HwpDocument?

    /// 문서를 교체하고 지오메트리를 새로 만든다. preservingSelection이 true면
    /// 활성 선택을 지우지 않는다 — 프로그레시브 스냅샷(같은 로드에 페이지 추가)
    /// 에서 사용자가 잡아 둔 선택을 유지한다 (#5). 기존 오프셋은 추가된
    /// 페이지에서도 유효하므로 지오메트리만 새 문서로 재구성한다.
    public func setDocument(_ newValue: HwpDocument?, preservingSelection: Bool) {
        // nil-token 문서는 얕은 구조 동등성이 렌더/내용 차이를 못 잡으므로
        // 스킵하지 않고 지오메트리를 새로 만든다 (#20). 토큰이 있으면(로더 산출)
        // == 로 안전하게 스킵한다.
        let hasIdentity = newValue == nil || newValue?.metadata.loadToken != nil
        if hasIdentity, backingDocument == newValue {
            return
        }
        let previousPageCount = backingDocument?.pages.count ?? 0
        let previousToken = backingDocument?.metadata.loadToken
        let previousDocument = backingDocument
        backingDocument = newValue
        geometry = newValue.map(HwpSelectionGeometry.init(document:))
        let pageCount = newValue?.pages.count ?? 0
        let token = newValue?.metadata.loadToken
        onGeometryChanged?(HwpGeometryChange(
            previousPageCount: previousPageCount,
            pageCount: pageCount,
            // 같은 로드의 스냅샷이 페이지를 잃지 않은 경우 — 위 doc-comment의
            // 계약대로 기존 페이지의 조판과 오프셋이 그대로 유효하다. 소비자는
            // 늘어난 구간만 다시 보면 된다.
            //
            // 동일 개수도 증분이다. 로더는 마지막 부분 스냅샷 뒤에 최종 스냅샷을
            // 무조건 한 번 더 내는데, 총 쪽수가 방출 지점(1·25·49…)에 정확히
            // 떨어지면 (1쪽 문서는 항상) 토큰도 쪽수도 같고 메타데이터만 다르다.
            // 이때 교체로 보면 전량 재스캔이 돌면서 사용자가 골라 둔 현재 매치가
            // 첫 매치로 되돌아간다. 네이티브 `isProgressiveUpdate` 도 `>=` 다 —
            // 같은 사건을 두 층이 다르게 판정하면 뷰는 스크롤을 지키는데 검색만
            // 리셋된다.
            isProgressiveAppend: previousToken != nil
                && previousToken == token
                && pageCount >= previousPageCount,
            isEquivalentRefresh: newValue != nil && previousDocument == newValue
        ))
        if preservingSelection, selection != nil {
            onSelectionChanged?()
        } else {
            clear()
        }
    }

    public private(set) var selection: HwpTextSelection?
    public private(set) var geometry: HwpSelectionGeometry?
    public var onSelectionChanged: (() -> Void)?

    /// 지오메트리를 새로 만들 때마다 발화한다 — `setDocument`이 **무조건**
    /// 재생성하므로 이 콜백도 무조건 뜬다.
    ///
    /// `onSelectionChanged`로는 이 사건을 알 수 없다. 활성 선택이 없으면
    /// `setDocument`이 `clear()`로 가고 `clear()`는 선택이 nil이면 조기
    /// return하기 때문이다 — 그런데 '선택 없음'이 바로 검색(#75)의 정상
    /// 상태다. 낡은 지오메트리에 좌표를 물으면 죽은 조판이 나온다.
    public var onGeometryChanged: ((HwpGeometryChange) -> Void)? {
        didSet {
            // 직접 대입도 **나중에 붙은 쪽**이다. 소유권을 함께 가져가지 않으면
            // 토큰이 옛 소유자를 가리킨 채 남아, 그쪽의 `detach()` 가 방금 건
            // 이 콜백을 지운다 — 토큰이 오히려 "내 것이 맞다"고 보증해 준다
            // (#75 리뷰 14차).
            geometryObserver = nil
        }
    }

    /// `onGeometryChanged` 슬롯의 현재 소유자.
    ///
    /// 슬롯이 하나뿐이라 나중에 붙은 쪽이 이기는데, **밀려난 쪽은 그 사실을
    /// 모른다** — 자기 `selection` 참조를 그대로 들고 있어 `isAttached(to:)` 도
    /// 계속 true 다. 소유자를 함께 기록하지 않으면 밀려난 컨트롤러의 `detach()`
    /// 가 **현재 소유자의 콜백을 지워**, 그쪽은 붙어 있다고 보고하면서 문서
    /// 교체·프로그레시브 갱신에 영영 재스캔하지 않는다 (#75 리뷰 13차).
    ///
    /// "나중에 붙은 쪽"에는 **직접 대입한 호스트도 든다** — 그래서 슬롯의
    /// `didSet` 이 이 토큰을 비운다 (#75 리뷰 14차).
    private(set) weak var geometryObserver: AnyObject?

    /// 소유자와 함께 지오메트리 콜백을 건다.
    func setGeometryObserver(
        _ observer: AnyObject,
        _ handler: @escaping (HwpGeometryChange) -> Void
    ) {
        // 슬롯을 **먼저** 대입한다 — 그 `didSet` 이 토큰을 비우므로, 순서를
        // 뒤집으면 방금 기록한 소유자가 곧바로 지워진다.
        onGeometryChanged = handler
        geometryObserver = observer
    }

    /// 슬롯이 아직 `observer` 것일 때만 비운다.
    func clearGeometryObserver(_ observer: AnyObject) {
        guard geometryObserver === observer else { return }
        geometryObserver = nil
        onGeometryChanged = nil
    }

    public init() {}

    public var hasSelection: Bool {
        guard let selection else { return false }
        return !selection.isCollapsed
    }

    public func begin(at position: HwpTextPosition) {
        selection = HwpTextSelection(anchor: position, focus: position)
        onSelectionChanged?()
    }

    public func extend(to position: HwpTextPosition) {
        guard var current = selection else {
            begin(at: position)
            return
        }
        guard current.focus != position else { return }
        current.focus = position
        selection = current
        onSelectionChanged?()
    }

    public func selectWord(at position: HwpTextPosition) {
        guard let word = geometry?.wordRange(at: position) else {
            begin(at: position)
            return
        }
        selection = word
        onSelectionChanged?()
    }

    /// 확정된 선택의 **끝점을 다시 잡는다** — 잡은 쪽을 `focus`로, 반대쪽을
    /// `anchor`로 한 번만 바꾼다. 이후 그 끝점을 미는 것은 기존
    /// `extend(to:)` 하나로 끝난다 (`range`가 정규화하므로 교환은
    /// 선택 범위를 바꾸지 않는다). 조정할 선택이 없으면 false.
    ///
    /// **제스처 `.began`에서 딱 한 번** 불러야 한다. `.changed`나 오토스크롤
    /// 틱마다 부르면 매 프레임 anchor/focus가 뒤집혀 끌던 끝점이 제자리를 맴돈다.
    ///
    /// 시작 핸들을 끝 핸들 **너머로** 끌면 `anchor <= focus`가 뒤집혀 잡고
    /// 있던 것이 '끝 핸들'이 된다 (UITextView와 같은 동작). 그래도 손가락을
    /// 따라오는 것은 계속 `focus`라 뷰는 아무 상태도 뒤집지 않는다.
    @discardableResult
    public func beginAdjusting(edge: HwpSelectionEdge) -> Bool {
        guard let current = selection, !current.isCollapsed else { return false }
        let (start, end) = current.range
        let adjusted = edge == .start
            ? HwpTextSelection(anchor: end, focus: start)
            : HwpTextSelection(anchor: start, focus: end)
        // 이미 그 방향이면 통지하지 않는다 — 범위가 그대로인 재도색을 아낀다.
        guard adjusted != current else { return true }
        selection = adjusted
        onSelectionChanged?()
        return true
    }

    /// 문서 전체 선택 (Cmd+A / Select All)
    public func selectAll() {
        guard let all = geometry?.documentSelection() else { return }
        selection = all
        onSelectionChanged?()
    }

    public func clear() {
        guard selection != nil else { return }
        selection = nil
        onSelectionChanged?()
    }

    public func selectedText() -> String? {
        guard let selection, hasSelection else { return nil }
        let text = geometry?.plainText(for: selection)
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// `selectedText()`의 속성 문자열 짝 (#118) — 같은 빈-선택 접기 규약으로
    /// nil을 돌려준다. 속성 계약은 `HwpSelectionGeometry.attributedText(for:)`
    /// 문서 참조 (조판 그대로 — RTF 정규화는 HwpKitNative 몫).
    public func selectedAttributedText() -> NSAttributedString? {
        guard let selection, hasSelection else { return nil }
        guard let text = geometry?.attributedText(for: selection), text.length > 0
        else { return nil }
        return text
    }

    public func highlightRects(forPage pageIndex: Int) -> [CGRect] {
        guard let selection, hasSelection else { return [] }
        return geometry?.highlightRects(pageIndex: pageIndex, selection: selection) ?? []
    }

    /// 선택 양 끝점의 캐럿 — 끌 수 있는 핸들을 그릴 자리다. 선택이 없거나
    /// collapsed면 빈 배열이고, 캐럿을 못 구한 끝점은 그냥 빠진다(부분 결과).
    ///
    /// 문서 순서로 앞이 `.start`, 뒤가 `.end`이며 affinity도 그에 맞춘다 —
    /// 시작은 뒷줄의 처음(downstream), 끝은 앞줄의 마지막(upstream)이라
    /// 줄바꿈 자리에서 핸들이 하이라이트 밖으로 떨어지지 않는다.
    public func selectionCarets() -> [HwpSelectionCaret] {
        guard let selection, hasSelection, let geometry else { return [] }
        let (start, end) = selection.range
        var carets: [HwpSelectionCaret] = []
        if let rect = geometry.caretRect(at: start, affinity: .downstream) {
            carets.append(HwpSelectionCaret(
                edge: .start, pageIndex: start.pageIndex, rect: rect
            ))
        }
        if let rect = geometry.caretRect(at: end, affinity: .upstream) {
            carets.append(HwpSelectionCaret(
                edge: .end, pageIndex: end.pageIndex, rect: rect
            ))
        }
        return carets
    }
}
