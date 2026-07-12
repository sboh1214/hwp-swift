import Foundation

public struct HwpDocumentMetadata: Sendable, Hashable {
    public let title: String?
    public let pageCount: Int
    public let previewText: String?
    /// 프로그레시브 로딩의 스냅샷 연속성 토큰 — 같은 토큰 + 페이지 증가면
    /// 뷰가 스크롤 리셋 없이 증분 적용한다. 일괄 로드는 nil.
    public let loadToken: UUID?

    public init(
        title: String? = nil,
        pageCount: Int,
        previewText: String? = nil,
        loadToken: UUID? = nil
    ) {
        self.title = title
        self.pageCount = pageCount
        self.previewText = previewText
        self.loadToken = loadToken
    }
}
