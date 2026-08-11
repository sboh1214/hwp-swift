import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpDocumentTests: XCTestCase {
    func testEmptyDocumentPagesCount() {
        expect(HwpDocument.empty.pages.count) == 0
    }

    func testEmptyDocumentUnsupportedElementsCount() {
        expect(HwpDocument.empty.unsupportedElements.count) == 0
    }

    func testBlockKindRoundTrip() {
        let block = AnyHwpBlock(frame: .zero, kind: .text)
        let margins = HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0)
        let page = HwpPage(size: .zero, margins: margins, blocks: [block], pageNumber: 1)
        expect(page.blocks.first?.kind) == .text
    }

    /// 반복 머리행 클론 표식은 `attributedString` 의 **속성**이라 문자열
    /// 비교에 안 걸린다. 동등성에서 빠지면 그 플래그만 뒤집힌 재전달이 "같은
    /// 내용"으로 접혀 검색 목록이 옛 dedup 분류에 머문다 (#75 리뷰 7차).
    func testRepeatedTableHeaderCloneFlagBreaksBlockEquality() {
        func block(clone: Bool) -> AnyHwpBlock {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if clone {
                attributes[HwpAttributedStringKey.repeatedTableHeaderClone] = true
            }
            return AnyHwpBlock(
                frame: .zero,
                kind: .text,
                attributedString: NSAttributedString(string: "header", attributes: attributes)
            )
        }
        expect(block(clone: false)) != block(clone: true)
        expect(block(clone: true)) == block(clone: true)
    }
}
