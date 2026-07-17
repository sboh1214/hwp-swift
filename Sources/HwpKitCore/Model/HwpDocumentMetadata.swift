import Foundation

public struct HwpDocumentMetadata: Sendable, Hashable {
    public let title: String?
    public let pageCount: Int
    public let previewText: String?
    /// 로드 식별/연속성 토큰 — 프로그레시브 스냅샷은 같은 토큰 + 페이지 증가로
    /// 뷰가 스크롤 리셋 없이 증분 적용하고, 서로 다른 로드는 다른 토큰이라
    /// 내용이 우연히 같아도 뷰 갱신 가드가 구분한다. 기본값(빈 문서)만 nil.
    public let loadToken: UUID?
    /// 페이지가 전부 확정된 문서인지 — 프로그레시브 중간 스냅샷만 false.
    /// 뷰가 범위 밖 페이지 요청을 "아직 로드 전"(대기)과 "최종 문서에 없음"
    /// (클램프 반영)으로 구분하는 데 쓴다.
    public let isComplete: Bool

    public init(
        title: String? = nil,
        pageCount: Int,
        previewText: String? = nil,
        loadToken: UUID? = nil,
        isComplete: Bool = true
    ) {
        self.title = title
        self.pageCount = pageCount
        self.previewText = previewText
        self.loadToken = loadToken
        self.isComplete = isComplete
    }
}
