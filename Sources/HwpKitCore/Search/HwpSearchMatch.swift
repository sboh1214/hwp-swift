import Foundation

/// 결과 목록에 보여 줄 매치 주변 텍스트.
public struct HwpSearchSnippet: Sendable, Hashable {
    public let text: String
    /// `text`의 UTF-16 오프셋 기준 매치 범위 — 호스트가 이 구간만 강조한다.
    public let matchRange: Range<Int>

    public init(text: String, matchRange: Range<Int>) {
        self.text = text
        self.matchRange = matchRange
    }
}

/// 검색 매치 하나.
///
/// 경계를 `HwpTextSelection`으로 표현해 하이라이트 경로를 선택과 그대로
/// 공유하되, dedup 판정에 필요한 두 값을 **덧붙인다**. `HwpTextSelection`은
/// 위치 쌍뿐이라 `paragraphId`도 클론 여부도 담을 수 없고, 그러면 '목록은
/// dedup / 하이라이트는 전부'라는 기존 `plainText(for:)` 정책을 표현할
/// 방법이 없다.
///
/// 매치는 **하나의 `HwpTextUnit` 안에서만** 성립한다 — anchor/focus의
/// (pageIndex, blockIndex, unitIndex)가 같다. 단·쪽 분할로 갈라진 문단이나
/// 표 셀 경계를 가로지르는 질의는 잡히지 않는다 (v1 한계).
/// **`Comparable` 은 채택하지 않는다.** 자연스러운 순서는 `start` 하나뿐인데
/// 동등성은 네 축(선택·paraId·클론 표식·스니펫)을 보므로, `<` 를 start 로만
/// 정의하면 "둘 다 작지 않은데 같지도 않은" 쌍이 생겨 `Comparable` 이 요구하는
/// **전순서**가 깨진다 (#75 리뷰 12차). 나머지 축까지 tie-break 하면 스니펫
/// 문자열에 의미 없는 순서를 새기고, `==` 에 필드가 늘 때마다 `<` 도 함께
/// 고쳐야 하는 함정이 남는다. 문서 순서가 필요하면 `start` 로 비교할 것 —
/// `HwpTextPosition` 은 네 필드를 모두 보는 온전한 전순서다
/// (`sorted { $0.start < $1.start }`).
public struct HwpSearchMatch: Sendable, Hashable, Identifiable {
    public let selection: HwpTextSelection
    /// 출처 문단 식별자 — 반복 표 머리행 dedup의 판정 키.
    public let paragraphId: UInt32?
    /// 쪽에 걸친 표의 반복 머리행 클론에서 나온 매치인가.
    public let isRepeatedTableHeaderClone: Bool
    /// `snippetPadding > 0`으로 스캔했을 때만 채워진다. 기본이 nil인 이유:
    /// 매치당 `String` 하나는 스캔(문자열 순회) 비용을 압도한다.
    public let snippet: HwpSearchSnippet?

    public init(
        selection: HwpTextSelection,
        paragraphId: UInt32? = nil,
        isRepeatedTableHeaderClone: Bool = false,
        snippet: HwpSearchSnippet? = nil
    ) {
        self.selection = selection
        self.paragraphId = paragraphId
        self.isRepeatedTableHeaderClone = isRepeatedTableHeaderClone
        self.snippet = snippet
    }

    public var id: HwpTextPosition {
        selection.range.start
    }

    public var start: HwpTextPosition {
        selection.range.start
    }

    public var end: HwpTextPosition {
        selection.range.end
    }

    /// **0-기반** — `HwpTextPosition.pageIndex`·네이티브 뷰와 같은 좌표계.
    public var pageIndex: Int {
        selection.range.start.pageIndex
    }

    /// **1-기반** — `HwpPageNavigator.currentPage`와 같은 공개 규약.
    /// 호스트가 결과 목록에 "p. 12"를 찍을 때 +1을 직접 하지 않아도 된다.
    public var pageNumber: Int {
        pageIndex + 1
    }

    /// 이 매치가 속한 텍스트 단위. 반복 머리행 dedup이 **단위 단위**로
    /// 판정해야 해서 필요하다.
    var unitKey: UnitKey {
        let start = selection.range.start
        return UnitKey(
            pageIndex: start.pageIndex,
            blockIndex: start.blockIndex,
            unitIndex: start.unitIndex
        )
    }

    struct UnitKey: Hashable {
        let pageIndex: Int
        let blockIndex: Int
        let unitIndex: Int
    }
}
