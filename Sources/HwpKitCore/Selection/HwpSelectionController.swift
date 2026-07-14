import CoreGraphics
import Foundation

/// 텍스트 선택 상태 보관 — macOS/iOS 뷰가 공유하는 플랫폼 중립 컨트롤러.
/// 뷰는 입력 (드래그/롱프레스)을 위치로 해석해 begin/extend를 부르고,
/// `onSelectionChanged`에서 하이라이트 오버레이를 갱신한다.
@MainActor
public final class HwpSelectionController {
    public var document: HwpDocument? {
        get { backingDocument }
        set { setDocument(newValue, preservingSelection: false) }
    }

    private var backingDocument: HwpDocument?

    /// 문서를 교체하고 지오메트리를 새로 만든다. preservingSelection이 true면
    /// 활성 선택을 지우지 않는다 — 프로그레시브 스냅샷(같은 로드에 페이지 추가)
    /// 에서 사용자가 잡아 둔 선택을 유지한다 (#5). 기존 오프셋은 추가된
    /// 페이지에서도 유효하므로 지오메트리만 새 문서로 재구성한다.
    public func setDocument(_ newValue: HwpDocument?, preservingSelection: Bool) {
        guard backingDocument != newValue else { return }
        backingDocument = newValue
        geometry = newValue.map(HwpSelectionGeometry.init(document:))
        if preservingSelection, selection != nil {
            onSelectionChanged?()
        } else {
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
