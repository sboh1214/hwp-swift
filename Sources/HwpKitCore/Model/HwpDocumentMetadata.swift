import Foundation

public struct HwpDocumentMetadata: Sendable, Hashable {
    public let title: String?
    public let pageCount: Int
    public let previewText: String?

    public init(title: String? = nil, pageCount: Int, previewText: String? = nil) {
        self.title = title
        self.pageCount = pageCount
        self.previewText = previewText
    }
}
