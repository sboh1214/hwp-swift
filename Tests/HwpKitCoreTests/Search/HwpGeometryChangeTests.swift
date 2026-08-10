import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// `HwpSelectionController.onGeometryChanged` (#75) — 검색의 재스캔 트리거.
@MainActor
final class HwpGeometryChangeTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func textBlock(_ text: String) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            role: .body
        )
    }

    private func makeDocument(pageCount: Int, loadToken: UUID? = nil) -> HwpDocument {
        HwpDocument(
            pages: (0 ..< pageCount).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [textBlock("page \(index)")],
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pageCount, loadToken: loadToken),
            unsupportedElements: []
        )
    }

    /// 이 테스트가 이 콜백의 존재 이유다 — 선택이 없으면 `clear()`가 조기
    /// return해 `onSelectionChanged`는 뜨지 않지만 지오메트리는 교체된다.
    func testFiresWithoutActiveSelectionWhereSelectionCallbackDoesNot() {
        let controller = HwpSelectionController()
        var geometryChanges = 0
        var selectionChanges = 0
        controller.onGeometryChanged = { _ in geometryChanges += 1 }
        controller.onSelectionChanged = { selectionChanges += 1 }

        controller.setDocument(makeDocument(pageCount: 2), preservingSelection: true)

        expect(geometryChanges) == 1
        expect(selectionChanges) == 0
    }

    func testReportsProgressiveAppendForSameLoadToken() {
        let token = UUID()
        let controller = HwpSelectionController()
        controller.setDocument(makeDocument(pageCount: 2, loadToken: token),
                               preservingSelection: true)
        var change: HwpGeometryChange?
        controller.onGeometryChanged = { change = $0 }

        controller.setDocument(makeDocument(pageCount: 5, loadToken: token),
                               preservingSelection: true)

        expect(change?.isProgressiveAppend) == true
        expect(change?.previousPageCount) == 2
        expect(change?.pageCount) == 5
    }

    func testDifferentLoadTokenIsNotProgressiveAppend() {
        let controller = HwpSelectionController()
        controller.setDocument(makeDocument(pageCount: 2, loadToken: UUID()),
                               preservingSelection: true)
        var change: HwpGeometryChange?
        controller.onGeometryChanged = { change = $0 }

        controller.setDocument(makeDocument(pageCount: 5, loadToken: UUID()),
                               preservingSelection: true)

        expect(change?.isProgressiveAppend) == false
    }

    /// nil-token 문서는 구조 동등성으로 스킵하지 않고 매번 재생성한다 —
    /// 접두 동일성을 보장할 수 없으므로 증분으로 볼 수 없다.
    func testNilLoadTokenIsNeverProgressiveAppend() {
        let controller = HwpSelectionController()
        controller.setDocument(makeDocument(pageCount: 2), preservingSelection: true)
        var change: HwpGeometryChange?
        controller.onGeometryChanged = { change = $0 }

        controller.setDocument(makeDocument(pageCount: 5), preservingSelection: true)

        expect(change?.isProgressiveAppend) == false
        expect(change?.pageCount) == 5
    }

    func testPageCountDecreaseIsNotProgressiveAppend() {
        let token = UUID()
        let controller = HwpSelectionController()
        controller.setDocument(makeDocument(pageCount: 5, loadToken: token),
                               preservingSelection: true)
        var change: HwpGeometryChange?
        controller.onGeometryChanged = { change = $0 }

        controller.setDocument(makeDocument(pageCount: 2, loadToken: token),
                               preservingSelection: true)

        expect(change?.isProgressiveAppend) == false
    }

    /// 같은 토큰 + 같은 내용이면 `setDocument`이 조기 return한다 —
    /// 지오메트리를 만들지 않으므로 콜백도 뜨지 않아야 한다.
    func testIdenticalDocumentDoesNotFire() {
        let token = UUID()
        let document = makeDocument(pageCount: 2, loadToken: token)
        let controller = HwpSelectionController()
        controller.setDocument(document, preservingSelection: true)
        var fired = 0
        controller.onGeometryChanged = { _ in fired += 1 }

        controller.setDocument(document, preservingSelection: true)

        expect(fired) == 0
    }

    func testClearingDocumentReportsZeroPages() {
        let controller = HwpSelectionController()
        controller.setDocument(makeDocument(pageCount: 3, loadToken: UUID()),
                               preservingSelection: true)
        var change: HwpGeometryChange?
        controller.onGeometryChanged = { change = $0 }

        controller.setDocument(nil, preservingSelection: false)

        expect(change?.pageCount) == 0
        expect(change?.previousPageCount) == 3
        expect(change?.isProgressiveAppend) == false
    }
}
