import Foundation

public struct HwpUnsupportedElement: Sendable, Hashable, Error {
    public let kind: HwpBlockKind
    public let page: Int
    public let hint: String

    public init(kind: HwpBlockKind, page: Int, hint: String) {
        self.kind = kind
        self.page = page
        self.hint = hint
    }
}
