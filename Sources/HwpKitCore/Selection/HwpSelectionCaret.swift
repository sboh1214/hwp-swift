import CoreGraphics
import Foundation

/// 선택 범위의 두 끝점 — 문서 순서로 앞이 `start`, 뒤가 `end`다.
///
/// `anchor`/`focus`가 **아니다**. 역방향 드래그도 `HwpTextSelection.range`가
/// 문서 순서로 정규화하므로, 화면에 보이는 두 핸들은 언제나 이 둘이다.
public enum HwpSelectionEdge: Sendable, Hashable {
    case start
    case end
}

/// 줄 경계에 걸친 오프셋의 캐럿을 어느 줄에 그릴지.
///
/// 줄 끝 오프셋과 다음 줄 첫 오프셋은 **같은 값**이라 캐럿 자리가 둘이다.
/// `HwpTextPosition`에 affinity를 넣으면 정규화·비교(`Comparable`) 규약까지
/// 바뀌므로 **질의 인자**로만 둔다 — 위치 값 자체는 그대로다.
public enum HwpCaretAffinity: Sendable, Hashable {
    /// 뒤쪽 줄의 시작 — 선택 **시작** 핸들이 쓴다.
    case downstream
    /// 앞쪽 줄의 끝 — 선택 **끝** 핸들이 쓴다.
    case upstream
}

/// 선택 끝점 하나의 캐럿 — 핸들 배치 입력.
public struct HwpSelectionCaret: Hashable {
    public let edge: HwpSelectionEdge
    public let pageIndex: Int
    /// 페이지 로컬 top-down, **폭 0**.
    ///
    /// 하이라이트 경로는 폭 0을 두 번 버린다 (`highlightRects`의 collapsed
    /// 가드, `highlightRect`의 빈 범위·폭 가드) — 그래서 끝점 캐럿은 그쪽을
    /// 재사용할 수 없고 `caretRect(at:affinity:)`가 따로 있다.
    public let rect: CGRect

    public init(edge: HwpSelectionEdge, pageIndex: Int, rect: CGRect) {
        self.edge = edge
        self.pageIndex = pageIndex
        self.rect = rect
    }
}
