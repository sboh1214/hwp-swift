import Foundation

/// 조판이 끝난 HWP 문서의 페이지 단위 표현 — `HwpDocumentLoader`(HwpKit)
/// 또는 `HwpDocumentActor`(HwpKitNative)가 만들어 주고, `HwpDocumentView`와
/// 각 렌더러가 입력으로 받는다. 페이지 배열과 메타데이터, 렌더링이
/// 지원하지 못한 요소 목록(`unsupportedElements`), 지연 디코딩용 이미지
/// 저장소를 담는 불변 값이다.
public struct HwpDocument: Sendable, Hashable {
    public let pages: [HwpPage]
    public let metadata: HwpDocumentMetadata
    public let unsupportedElements: [HwpUnsupportedElement]
    /// 문서에 첨부된 이미지 바이트 (BinItem id → payload). 지연 디코딩용.
    public let imageStore: HwpImageStore

    public init(
        pages: [HwpPage],
        metadata: HwpDocumentMetadata,
        unsupportedElements: [HwpUnsupportedElement],
        imageStore: HwpImageStore = HwpImageStore()
    ) {
        self.pages = pages
        self.metadata = metadata
        self.unsupportedElements = unsupportedElements
        self.imageStore = imageStore
    }

    public static let empty = HwpDocument(
        pages: [],
        metadata: HwpDocumentMetadata(pageCount: 0),
        unsupportedElements: []
    )

    /// imageStore hash는 key + byte 수만 반영한다 (대용량 바이트 해시 회피).
    /// ==는 이미지 내용까지 정확 비교한다 (뷰 갱신 가드가 이미지 변경을 놓치지 않도록).
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pages)
        hasher.combine(metadata)
        hasher.combine(unsupportedElements)
        for key in imageStore.dataByBinItemId.keys.sorted() {
            hasher.combine(key)
            hasher.combine(imageStore.dataByBinItemId[key]?.count ?? 0)
        }
    }

    public static func == (lhs: HwpDocument, rhs: HwpDocument) -> Bool {
        lhs.pages == rhs.pages
            && lhs.metadata == rhs.metadata
            && lhs.unsupportedElements == rhs.unsupportedElements
            && lhs.imageStore.dataByBinItemId == rhs.imageStore.dataByBinItemId
    }
}
