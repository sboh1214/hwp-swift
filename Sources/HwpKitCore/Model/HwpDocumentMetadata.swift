import Foundation

public struct HwpDocumentMetadata: Sendable, Hashable {
    public let title: String?
    public let pageCount: Int
    public let previewText: String?
    /// 로드 식별/연속성 토큰 — 프로그레시브 스냅샷은 같은 토큰 + 페이지 증가로
    /// 뷰가 스크롤 리셋 없이 증분 적용하고, 서로 다른 로드는 다른 토큰이라
    /// 내용이 우연히 같아도 뷰 갱신 가드가 구분한다. 기본값(빈 문서)만 nil.
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
