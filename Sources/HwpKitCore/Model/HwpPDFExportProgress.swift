import Foundation

/// PDF 내보내기 진행 상황 — 페이지 하나를 기록할 때마다 한 번 보고된다.
///
/// 렌더러는 HwpKitNative, 공개 API는 HwpKit인데 이 값 타입은 플랫폼 중립이라
/// 양쪽이 공유하도록 코어에 둔다 (호스트 앱이 `import HwpKitNative` 없이
/// 진행률 콜백을 쓸 수 있게 하는 것이 요점이다).
public struct HwpPDFExportProgress: Sendable, Hashable {
    /// 방금 기록을 마친 페이지 (0-based)
    public let pageIndex: Int
    /// 전체 페이지 수
    public let pageCount: Int

    public init(pageIndex: Int, pageCount: Int) {
        self.pageIndex = pageIndex
        self.pageCount = pageCount
    }

    /// 0...1 진행률
    public var fractionCompleted: Double {
        guard pageCount > 0 else { return 1 }
        return min(1, Double(pageIndex + 1) / Double(pageCount))
    }
}
