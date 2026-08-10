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

    public init(previousPageCount: Int, pageCount: Int, isProgressiveAppend: Bool) {
        self.previousPageCount = previousPageCount
        self.pageCount = pageCount
        self.isProgressiveAppend = isProgressiveAppend
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
                && pageCount >= previousPageCount
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
    public var onGeometryChanged: ((HwpGeometryChange) -> Void)?

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

    public func highlightRects(forPage pageIndex: Int) -> [CGRect] {
        guard let selection, hasSelection else { return [] }
        return geometry?.highlightRects(pageIndex: pageIndex, selection: selection) ?? []
    }
}
