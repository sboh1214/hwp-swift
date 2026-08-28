import Foundation

/// `HwpDocument`의 제목, 현재까지 확정된 쪽 수, 미리 보기 텍스트와 개요·책갈피
/// 탐색 목록 등을 담는다. 프로그레시브 로딩에서는 `loadToken`으로 같은 로드에서
/// 나온 스냅샷인지 판별하고, `isComplete`로 모든 페이지의 확정 여부를 확인한다.
/// `outline`은 사이드바나 목차 탐색에 사용할 수 있다.
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
    /// 개요·책갈피 탐색 목록 (문서 순서). 조판이 확정한 쪽을 들고 있어
    /// 호스트가 사이드바·목차에서 그 쪽으로 바로 이동할 수 있다 (#77).
    ///
    /// **프로그레시브 중간 스냅샷도 지금까지 확정된 접두를 담는다** —
    /// `unsupportedElements`가 최종 스냅샷에만 오는 것과 다르다. 사이드바는
    /// 로딩 중에 쓰라고 있는 물건이라 1,030쪽이 다 배치될 때까지 비워 두면
    /// 쓸모가 없고, 수집이 append-only라 항목의 `ordinal`이 스냅샷 사이에서
    /// 움직이지 않아 목록 신원이 흔들리지도 않는다.
    ///
    /// 이 필드는 프로그레시브 증분 판정
    /// (`HwpDocumentViewSupport.isProgressiveUpdate`)에 영향을 주지 않는다 —
    /// 그 판정은 `loadToken`과 페이지 수만 본다.
    public let outline: [HwpOutlineItem]
    /// `outline`이 자원 상한에 걸려 **잘렸는가** (#77). true면 목록에 없는
    /// 목적지가 있다 — 호스트가 완전한 탐색 수단으로 오인하지 않게 표시할 수 있다.
    /// 책갈피는 `unsupportedElements`에도 뜨지 않으므로 이 값이 유일한 흔적이다.
    ///
    /// 프로그레시브 중간 스냅샷의 접두 자르기는 여기 해당하지 않는다 — 그쪽은
    /// 조판이 끝나면 나온다.
    public let isOutlineTruncated: Bool

    public init(
        title: String? = nil,
        pageCount: Int,
        previewText: String? = nil,
        loadToken: UUID? = nil,
        isComplete: Bool = true,
        outline: [HwpOutlineItem] = [],
        isOutlineTruncated: Bool = false
    ) {
        self.title = title
        self.pageCount = pageCount
        self.previewText = previewText
        self.loadToken = loadToken
        self.isComplete = isComplete
        self.outline = outline
        self.isOutlineTruncated = isOutlineTruncated
    }
}
