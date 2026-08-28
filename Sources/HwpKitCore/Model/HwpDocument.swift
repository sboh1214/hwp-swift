import Foundation

/// HWP 문서의 조판 결과를 페이지 단위로 담는 불변 값이다. 프로그레시브
/// 로딩 중에는 문서의 첫 페이지부터 지금까지 확정된 페이지만 담을 수 있으며,
/// 완료 여부는 `metadata.isComplete`로 확인한다. 페이지·메타데이터·지원되지
/// 않거나 플레이스홀더로 대체된 요소(`unsupportedElements`)·지연 디코딩용
/// 이미지 저장소를 함께 보관한다. `HwpDocumentLoader`(HwpKit) 또는
/// `HwpDocumentActor`(HwpKitNative)가 만들며, `HwpDocumentView`와 렌더러가 이를
/// 입력으로 사용한다.
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
