import CoreGraphics
import Foundation

/// 텍스트 선택 상태 보관 — macOS/iOS 뷰가 공유하는 플랫폼 중립 컨트롤러.
/// 뷰는 입력 (드래그/롱프레스)을 위치로 해석해 begin/extend를 부르고,
/// `onSelectionChanged`에서 하이라이트 오버레이를 갱신한다.
@MainActor
public final class HwpSelectionController {
    public var document: HwpDocument? {
        didSet {
            guard document != oldValue else { return }
            geometry = document.map(HwpSelectionGeometry.init(document:))
            clear()
        }
    }

    public private(set) var selection: HwpTextSelection?
    public private(set) var geometry: HwpSelectionGeometry?
    public var onSelectionChanged: (() -> Void)?

    public init() {}

    public var hasSelection: Bool {
        guard let selection else { return false }
        return !selection.isCollapsed
    }

    public func begin(at position: HwpTextPosition) {
        selection = HwpTextSelection(anchor: position, focus: position)
        onSelectionChanged?()
    }

    public func extend(to position: HwpTextPosition) {
        guard var current = selection else {
            begin(at: position)
            return
        }
        guard current.focus != position else { return }
        current.focus = position
        selection = current
        onSelectionChanged?()
    }

    public func selectWord(at position: HwpTextPosition) {
        guard let word = geometry?.wordRange(at: position) else {
            begin(at: position)
            return
        }
        selection = word
        onSelectionChanged?()
    }

    /// 문서 전체 선택 (Cmd+A / Select All)
    public func selectAll() {
        guard let all = geometry?.documentSelection() else { return }
        selection = all
        onSelectionChanged?()
    }

    public func clear() {
        guard selection != nil else { return }
        selection = nil
        onSelectionChanged?()
    }

    public func selectedText() -> String? {
        guard let selection, hasSelection else { return nil }
        let text = geometry?.plainText(for: selection)
        return (text?.isEmpty ?? true) ? nil : text
    }

    public func highlightRects(forPage pageIndex: Int) -> [CGRect] {
        guard let selection, hasSelection else { return [] }
        return geometry?.highlightRects(pageIndex: pageIndex, selection: selection) ?? []
    }
}
