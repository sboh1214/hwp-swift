import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 빈 문단 앵커의 선택·복사·캐럿·검색·낭독 규약 (#145) — 손으로 만든 블록으로
/// 지오메트리 계약만 잠근다. 실제 조판(페이지네이터)은
/// `HwpEmptyParagraphCopyTests`가 태운다.
final class HwpEmptyParagraphSelectionTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    private let largeFont = CTFontCreateWithName("Helvetica" as CFString, 20, nil)

    private func textBlock(
        _ text: String,
        frame: CGRect,
        paragraphId: UInt32? = 0
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            source: paragraphId.map { HwpBlockSource(paragraphId: $0) }
        )
    }

    /// 빈 문단 앵커 블록 — 조판이 내는 것과 같은 모양(표식 붙은 빈칸 1자, 글꼴,
    /// 문단 스타일). paraId는 이웃과 같은 0으로 두어 id 동일성이 접합 근거가
    /// 아님을 함께 태운다.
    private func emptyParagraphBlock(
        frame: CGRect,
        font: CTFont? = nil,
        paragraphStyle: CTParagraphStyle? = nil
    ) -> AnyHwpBlock {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font ?? self.font,
            HwpAttributedStringKey.emptyLineAnchor: true,
        ]
        if let paragraphStyle {
            attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] = paragraphStyle
        }
        return AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(string: " ", attributes: attributes),
            source: HwpBlockSource(paragraphId: 0)
        )
    }

    private func makeDocument(_ blocks: [AnyHwpBlock]) -> HwpDocument {
        HwpDocument(
            pages: [HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks,
                pageNumber: 1
            )],
            metadata: HwpDocumentMetadata(pageCount: 1),
            unsupportedElements: []
        )
    }

    private func position(block: Int, offset: Int) -> HwpTextPosition {
        HwpTextPosition(pageIndex: 0, blockIndex: block, unitIndex: 0, characterOffset: offset)
    }

    private func rows(_ count: Int) -> [CGRect] {
        (0 ..< count).map { CGRect(x: 50, y: 100 + CGFloat($0) * 30, width: 300, height: 20) }
    }

    // MARK: - 복사

    func testEmptyParagraphKeepsItsLineInPlainAndAttributedCopy() throws {
        let row = rows(3)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1]),
            textBlock("B", frame: row[2]),
        ]))
        let selection = try XCTUnwrap(geometry.documentSelection())

        // 앵커 글자는 떨어지고 문단 경계 개행만 남는다 — 두 조립 경로가 같다.
        expect(geometry.units(forPage: 0).count) == 3
        expect(geometry.plainText(for: selection)) == "A\n\nB"
        expect(geometry.attributedText(for: selection).string) == "A\n\nB"
    }

    func testConsecutiveEmptyParagraphsEachKeepALine() throws {
        let row = rows(4)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1]),
            emptyParagraphBlock(frame: row[2]),
            textBlock("B", frame: row[3]),
        ]))
        let selection = try XCTUnwrap(geometry.documentSelection())

        expect(geometry.plainText(for: selection)) == "A\n\n\nB"
    }

    func testSelectionTouchingAnEmptyParagraphCarriesItsLine() {
        // 빈 문단은 캐럿 자리가 하나라 (P,0)과 (P,1)이 같은 자리다 — 선택이
        // 닿기만 하면 그 줄이 실린다. 비어 있지 않은 단위도 닿으면 빈 조각으로
        // 실려 지나온 문단 경계가 개행으로 남는다 (`HwpParagraphBoundaryCopyTests`).
        let row = rows(3)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1]),
            textBlock("B", frame: row[2]),
        ]))
        let aStart = position(block: 0, offset: 0)
        let emptyStart = position(block: 1, offset: 0)
        let emptyEnd = position(block: 1, offset: 1)
        let bStart = position(block: 2, offset: 0)
        let bEnd = position(block: 2, offset: 1)
        func plain(_ start: HwpTextPosition, _ end: HwpTextPosition) -> String {
            geometry.plainText(for: HwpTextSelection(anchor: start, focus: end))
        }

        // A에서 빈 줄까지 — A의 종결자가 실린다 (TextEdit의 "A\n"과 같다).
        expect(plain(aStart, emptyStart)) == "A\n"
        expect(plain(aStart, emptyEnd)) == "A\n"
        // 빈 줄에서 B까지 — 빈 줄이 앞선다.
        expect(plain(emptyStart, bEnd)) == "\nB"
        expect(plain(emptyEnd, bEnd)) == "\nB"
        // 빈 줄만 고르면 글자가 없다.
        expect(plain(emptyStart, emptyEnd)) == ""
        // B 시작에서 끝나면 A의 문단 부호와 빈 문단의 부호를 둘 다 지난다 — 개행 둘.
        expect(plain(aStart, bStart)) == "A\n\n"
    }

    func testNewlineAfterEmptyParagraphInheritsTheAnchorStyle() throws {
        // 빈 문단을 종결하는 개행은 앵커 run(글꼴·문단 스타일)에서 속성을
        // 상속한다 — RTF에서 빈 문단의 정렬·글자 크기가 남는 근거다 (#124 폴백).
        var alignment = CTTextAlignment.center
        let setting = CTParagraphStyleSetting(
            spec: .alignment,
            valueSize: MemoryLayout<CTTextAlignment>.size,
            value: &alignment
        )
        let centered = CTParagraphStyleCreate([setting], 1)
        let row = rows(3)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1], font: largeFont, paragraphStyle: centered),
            textBlock("B", frame: row[2]),
        ]))
        let selection = try XCTUnwrap(geometry.documentSelection())

        let attributed = geometry.attributedText(for: selection)
        expect(attributed.string) == "A\n\nB"
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        let styleKey = kCTParagraphStyleAttributeName as NSAttributedString.Key
        // 첫 개행은 A의 종결자 (12pt), 둘째 개행은 빈 문단의 종결자 (20pt·가운데).
        let afterA = attributed.attributes(at: 1, effectiveRange: nil)
        let afterEmpty = attributed.attributes(at: 2, effectiveRange: nil)
        // CF 타입은 `as?`가 항상 성공한다고 컴파일러가 막으므로 CFEqual로 대조한다.
        let smallMatches = CFEqual(afterA[fontKey] as AnyObject, font)
        let largeMatches = CFEqual(afterEmpty[fontKey] as AnyObject, largeFont)
        expect(smallMatches) == true
        expect(largeMatches) == true
        expect(afterEmpty[styleKey]).notTo(beNil())
    }

    // MARK: - 캐럿·히트

    func testCaretRectOnEmptyParagraphAnchor() throws {
        let row = rows(3)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1]),
            textBlock("B", frame: row[2]),
        ]))

        let start = try XCTUnwrap(
            geometry.caretRect(at: position(block: 1, offset: 0), affinity: .downstream)
        )
        let end = try XCTUnwrap(
            geometry.caretRect(at: position(block: 1, offset: 1), affinity: .upstream)
        )
        expect(start.width) == 0
        expect(start.height) > 0
        // 빈 줄의 두 오프셋은 같은 자리다 — 앵커 빈칸의 진행 폭은 하이라이트 폭
        // (후행 공백 제외)으로 클램프된다.
        expect(end.minX).to(beCloseTo(start.minX, within: 0.01))
        expect(start.minY).to(beGreaterThanOrEqualTo(row[1].minY - 0.01))
    }

    func testHitOnEmptyLineSnapsToTheAnchorUnit() {
        let row = rows(3)
        let geometry = HwpSelectionGeometry(document: makeDocument([
            textBlock("A", frame: row[0]),
            emptyParagraphBlock(frame: row[1]),
            textBlock("B", frame: row[2]),
        ]))

        let hit = geometry.position(nearest: CGPoint(x: 200, y: row[1].midY), pageIndex: 0)
        expect(hit?.blockIndex) == 1
    }

    // MARK: - 검색·낭독

    func testEmptyParagraphAnchorIsNotSearchable() {
        // 앵커 빈칸은 원문에 없는 글자다 — 두 겹으로 검색 결과가 될 수 없다:
        // 공백만인 질의는 빈 질의라 아무것도 찾지 않고(`HwpSearchQuery.isEmpty`),
        // 앵커 전용 단위는 스캔에서 빠진다. 앵커 단위가 끼어도 이웃 검색은 그대로다.
        let row = rows(2)
        let page = makeDocument([
            emptyParagraphBlock(frame: row[0]),
            textBlock("a b", frame: row[1]),
        ]).pages[0]
        func matches(_ text: String) -> [HwpSearchMatch] {
            HwpTextSearcher.matches(
                in: page,
                pageIndex: 0,
                query: HwpSearchQuery(text: text, options: .default),
                matchLimit: 0,
                snippetPadding: 0
            )
        }

        expect(HwpSearchQuery(text: " ").isEmpty) == true
        expect(matches(" ")).to(beEmpty())
        expect(matches("a b").map(\.selection.range.start.blockIndex)) == [1]
    }

    func testEmptyParagraphAnchorDoesNotCreateAReadableUnit() {
        let row = rows(2)
        let page = makeDocument([
            emptyParagraphBlock(frame: row[0]),
            textBlock("본문", frame: row[1]),
        ]).pages[0]

        let units = HwpAccessibilityContent.pageUnits(
            page: page, bodyUnits: HwpSelectableText.units(in: page)
        )
        expect(units.map(\.label)) == ["본문"]
    }
}
