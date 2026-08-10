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
public struct HwpSearchMatch: Sendable, Hashable, Comparable, Identifiable {
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

    public static func < (lhs: HwpSearchMatch, rhs: HwpSearchMatch) -> Bool {
        lhs.selection.range.start < rhs.selection.range.start
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
