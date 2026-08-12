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

    /// 동등성은 정규 동치가 아니라 **UTF-16 동일성**이다. Swift `String ==` 로
    /// 비교하면 NFC/NFD 가 같다고 나오는데, `characterOffset` 은 UTF-16
    /// 오프셋이라 그 둘 사이에서 밀린다 (#75 리뷰 9차).
    func testNormalizationDifferenceBreaksBlockEquality() {
        func block(_ text: String) -> AnyHwpBlock {
            AnyHwpBlock(
                frame: .zero,
                kind: .text,
                attributedString: NSAttributedString(string: text)
            )
        }
        let precomposed = "가나다"
        let decomposed = precomposed.decomposedStringWithCanonicalMapping
        expect(precomposed) == decomposed
        expect(precomposed.utf16.count) != decomposed.utf16.count

        expect(block(precomposed)) != block(decomposed)
        // hash 는 정규 해시 그대로 둔다 — == 가 더 엄격하므로
        // (동일 ⟹ 정규 동치 ⟹ 같은 해시) Hashable 계약은 유지된다
        expect(block(precomposed).hashValue) == block(decomposed).hashValue
    }

    /// 같은 계약이 **페이로드 안 문단**에도 서야 한다. 프로덕션에서 표·글상자
    /// 텍스트는 top-level `attributedString` 이 아니라 여기 산다 — 위 층만
    /// 잠그면 존재하지 않는 경로를 지킨다 (#75 리뷰 8차의 교훈).
    func testNormalizationDifferenceBreaksPayloadEquality() {
        func block(_ text: String) -> AnyHwpBlock {
            AnyHwpBlock(
                frame: .zero,
                kind: .textbox,
                payload: .textbox(HwpTextboxFrame(
                    outerFrame: .zero,
                    paragraphs: [HwpLaidOutParagraph(
                        attributedString: NSAttributedString(string: text),
                        frame: HwpParagraphFrame(totalHeight: 14, lines: []),
                        rect: .zero,
                        paragraphId: 7
                    )],
                    borderColor: nil,
                    borderWidth: 0,
                    fillColor: nil
                ))
            )
        }
        let precomposed = "가나다"
        let decomposed = precomposed.decomposedStringWithCanonicalMapping

        expect(block(precomposed)) != block(decomposed)
    }
}
