import Foundation

/// "3 / 12"의 3 — 사용자에게 보이는 **1-기반** 매치 번호.
///
/// 파일 최상단 자유 함수인 것은 `hwpScrollPageIndex(fromOneBased:)`·
/// `hwpZoomNeedsWriteback`과 같은 관례다. `@MainActor`가 없는 순수 함수라
/// 격리 없이 단위 테스트로 직접 부를 수 있다.
///
/// **클램프를 덧셈보다 먼저** 한다. `currentIndex + 1`을 먼저 하면 호스트가
/// 넘긴 `Int.max`에서 오버플로 트랩이다 — `hwpScrollPageIndex`가 클램프를
/// 뺄셈보다 먼저 해야 했던 것과 같은 함정이다.
func hwpDisplayMatchNumber(currentIndex: Int?, matchCount: Int) -> Int {
    guard matchCount > 0, let currentIndex else { return 0 }
    let clamped = max(0, min(currentIndex, matchCount - 1))
    return clamped + 1
}
