import Foundation

public struct HwpDocument: Sendable, Hashable {
    public let pages: [HwpPage]
    public let metadata: HwpDocumentMetadata
    public let unsupportedElements: [HwpUnsupportedElement]

    public static let empty = HwpDocument(
        pages: [],
        metadata: HwpDocumentMetadata(pageCount: 0),
        unsupportedElements: []
    )
}
