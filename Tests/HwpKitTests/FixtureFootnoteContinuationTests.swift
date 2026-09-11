import CoreGraphics
@testable import HwpKit
@testable import HwpKitCore
import Nimble
import XCTest

/// 헌법주석 (`legacy-common-control-property`) 의 각주 이어짐 실측 핀 (#165).
///
/// 한글 12.30이 내보낸 PDF (2026-09-10) 를 쪽마다 대조한 값이다 — 인쇄 749~752쪽
/// (렌더 인덱스 760~763). 한글은 인쇄 749쪽에 215)~219)만 싣고 220)은 통째로 750쪽으로
/// 옮기며, 750쪽에는 224)의 첫 세 줄만 싣고 나머지 아홉 줄을 751쪽 첫 각주로 잇는다
/// (줄 캐시 `0, 1172, 2344, 0, 1172, …`). 751쪽 끝의 227)도 세 줄 뒤 752쪽으로 이어진다.
/// 좌표는 `HwpFontResolver.testDeterministic`으로 기기 독립이다 — 각주 줄 높이는 줄
/// 캐시 (900 + 272 HWPUNIT) 에서 오므로 폰트와 무관하다.
final class FixtureFootnoteContinuationTests: XCTestCase {
    /// 각주 줄 피치 (900 + 272 HWPUNIT) 와 마지막 줄 상자 (900 HWPUNIT)
    private static let pitch: CGFloat = 11.72
    private static let box: CGFloat = 9.0

    private static var document: HwpDocument?

    private func loadDocument() async throws -> HwpDocument {
        if let document = Self.document {
            return document
        }
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("legacy-common-control-property")
            .appendingPathComponent("document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        Self.document = document
        return document
    }

    private func footnotes(_ document: HwpDocument, page index: Int) throws -> [HwpFootnoteBlock] {
        let page = try XCTUnwrap(document.pages.indices.contains(index) ? document.pages[index] : nil)
        return page.blocks.compactMap { block in
            if case let .footnote(note) = block.payload, block.role == .body {
                return note
            }
            return nil
        }
    }

    private func text(_ block: HwpFootnoteBlock) -> String {
        block.paragraphs.map(\.attributedString.string).joined()
    }

    private func contentBottom(_ document: HwpDocument, page index: Int) -> CGFloat {
        document.pages[index].size.height - document.pages[index].margins.bottom
    }

    /// 인쇄 749쪽 — 220)은 자리가 없어 통째로 다음 쪽이다 (분할 지점 없는 한 줄 각주).
    func testNoteWithoutRoomMovesWholeToTheNextPage() async throws {
        let document = try await loadDocument()
        let blocks = try footnotes(document, page: 760)
        expect(blocks.map(\.number)) == [215, 216, 217, 218, 219]
        expect(blocks.map { self.text($0).hasPrefix("\($0.number))") }) == Array(repeating: true, count: 5)
        expect(blocks.last?.frame.maxY).to(beCloseTo(contentBottom(document, page: 760), within: 0.05))
    }

    /// 인쇄 750쪽 — 220)이 첫 각주로 오고 224)는 첫 세 줄만 실린다. 구분선 가운데 513.36pt·
    /// 첫 각주 baseline 526.68pt (한글 PDF) 와 0.2pt 안에서 맞는다.
    func testNoteSplitsAtTheCachedPageBreak() async throws {
        let document = try await loadDocument()
        let blocks = try footnotes(document, page: 761)
        expect(blocks.map(\.number)) == [220, 221, 222, 223, 224]
        let head = try XCTUnwrap(blocks.last)
        expect(self.text(head).hasPrefix("224)")) == true
        expect(head.frame.height).to(beCloseTo(2 * Self.pitch + Self.box, within: 0.05))
        expect(head.frame.maxY).to(beCloseTo(contentBottom(document, page: 761), within: 0.05))
        let first = try XCTUnwrap(blocks.first)
        expect(first.separatorLine.midY).to(beCloseTo(513.36, within: 0.2))
        // 첫 줄 baseline = 줄 상자 위 + baselineDistance 765 HWPUNIT
        expect(first.frame.minY + 7.65).to(beCloseTo(526.68, within: 0.2))
        // 각주 사이 피치 = 마지막 줄 상자 + 사이 여백 283 HWPUNIT (줄 간격을 대체한다)
        expect(blocks[1].frame.minY - blocks[0].frame.minY).to(beCloseTo(Self.box + 2.83, within: 0.01))
    }

    /// 인쇄 751쪽 — 224)의 나머지 아홉 줄이 번호 없이 첫 각주로 이어지고 구분선이 다시
    /// 그려진다 (한글 PDF 구분선 가운데 267.36pt). 227)은 세 줄 뒤 다시 다음 쪽이다.
    func testContinuationLeadsTheNextPageWithoutALabel() async throws {
        let document = try await loadDocument()
        let blocks = try footnotes(document, page: 762)
        expect(blocks.map(\.number)) == [224, 225, 226, 227]
        let continuation = try XCTUnwrap(blocks.first)
        expect(self.text(continuation).hasPrefix("224)")) == false
        expect(continuation.frame.height).to(beCloseTo(8 * Self.pitch + Self.box, within: 0.05))
        expect(continuation.separatorLine.midY).to(beCloseTo(267.36, within: 0.2))
        expect(continuation.frame.minY).to(beCloseTo(continuation.separatorLine.midY + 5.67, within: 0.05))
        let tail = try XCTUnwrap(blocks.last)
        expect(self.text(tail).hasPrefix("227)")) == true
        expect(tail.frame.height).to(beCloseTo(2 * Self.pitch + Self.box, within: 0.05))
        expect(tail.frame.maxY).to(beCloseTo(contentBottom(document, page: 762), within: 0.05))

        let next = try footnotes(document, page: 763)
        expect(next.map(\.number)) == [227, 228, 229]
        let nextFirst = try XCTUnwrap(next.first)
        expect(self.text(nextFirst).hasPrefix("227)")) == false
        expect(next.first?.frame.height).to(beCloseTo(10 * Self.pitch + Self.box, within: 0.05))
    }

    /// 문서 전체 — 쪽수는 1,030 그대로고, 앞 쪽 각주가 이어져 시작하는 쪽은 한글과 같은
    /// 64쪽이다 (앞 쪽 마지막 각주와 번호가 같고 라벨이 없는 첫 블록).
    func testContinuationPageCountMatchesHancom() async throws {
        let document = try await loadDocument()
        expect(document.pages.count) == 1030
        var continuations = 0
        var previousLast: HwpFootnoteBlock?
        for index in document.pages.indices {
            let blocks = try footnotes(document, page: index)
            if let first = blocks.first, let previousLast,
               first.number == previousLast.number,
               !text(first).hasPrefix("\(first.number))")
            {
                continuations += 1
            }
            previousLast = blocks.last
        }
        expect(continuations) == 64
    }
}
