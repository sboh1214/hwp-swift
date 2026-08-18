import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 선택 끝점 캐럿 rect (폭 0) — 줄 경계 affinity·클램프·미존재 단위 (#84).
///
/// 하이라이트 경로는 폭 0을 두 번 버리므로 (`highlightRects`의 collapsed 가드,
/// `highlightRect`의 빈 범위·폭 가드) 이 값들은 그쪽 테스트로 대체되지 않는다.
final class HwpSelectionCaretTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func textBlock(_ text: String, frame: CGRect) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
        )
    }

    private func makeGeometry(_ blocks: [AnyHwpBlock]) -> HwpSelectionGeometry {
        HwpSelectionGeometry(document: HwpDocument(
            pages: [HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks,
                pageNumber: 1
            )],
            metadata: HwpDocumentMetadata(pageCount: 1),
            unsupportedElements: []
        ))
    }

    private func position(_ offset: Int) -> HwpTextPosition {
        HwpTextPosition(pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: offset)
    }

    func testCaretIsZeroWidthAndSpansTheLine() throws {
        let geometry = makeGeometry([
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ])

        let caret = try XCTUnwrap(geometry.caretRect(at: position(0), affinity: .downstream))
        let line = try XCTUnwrap(geometry.drawnLines(pageIndex: 0, unitOrdinal: 0).first)

        expect(caret.width) == 0
        expect(caret.height) > 0
        expect(caret.minY).to(beCloseTo(line.selectionRect.minY, within: 0.01))
        expect(caret.maxY).to(beCloseTo(line.selectionRect.maxY, within: 0.01))
    }

    /// 끝점 캐럿은 하이라이트의 양 끝과 같은 x에 선다 — 어긋나면 핸들이
    /// 파란 칠 밖에 떠 있게 된다.
    func testCaretMatchesHighlightEdges() throws {
        let geometry = makeGeometry([
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ])
        let selection = HwpTextSelection(anchor: position(0), focus: position(11))
        let highlight = try XCTUnwrap(
            geometry.highlightRects(pageIndex: 0, selection: selection).first
        )

        let start = try XCTUnwrap(geometry.caretRect(at: position(0), affinity: .downstream))
        let end = try XCTUnwrap(geometry.caretRect(at: position(11), affinity: .upstream))

        expect(start.minX).to(beCloseTo(highlight.minX, within: 0.5))
        expect(end.minX).to(beCloseTo(highlight.maxX, within: 0.5))
    }

    /// 줄 끝 오프셋과 다음 줄 첫 오프셋은 **같은 값**이다. affinity가 없으면
    /// 끝 핸들이 다음 줄 머리로 내려가 선택 밖에 선다.
    func testAffinitySplitsWrappedLineBoundary() throws {
        let geometry = makeGeometry([
            textBlock(
                "Hello wrapped world", frame: CGRect(x: 50, y: 100, width: 40, height: 200)
            ),
        ])
        let lines = geometry.drawnLines(pageIndex: 0, unitOrdinal: 0)
        try XCTSkipIf(lines.count < 2, "조판이 줄바꿈을 만들지 않았다")
        let boundary = lines[0].stringRange.location + lines[0].stringRange.length

        let upstream = try XCTUnwrap(
            geometry.caretRect(at: position(boundary), affinity: .upstream)
        )
        let downstream = try XCTUnwrap(
            geometry.caretRect(at: position(boundary), affinity: .downstream)
        )

        expect(upstream.minY).to(beCloseTo(lines[0].selectionRect.minY, within: 0.01))
        expect(downstream.minY).to(beCloseTo(lines[1].selectionRect.minY, within: 0.01))
        expect(upstream.minY) < downstream.minY
    }

    /// 줄 안쪽 오프셋은 affinity와 무관하게 같은 자리다 — 후보 줄이 하나뿐이다.
    func testAffinityIsIrrelevantInsideALine() throws {
        let geometry = makeGeometry([
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ])

        let upstream = try XCTUnwrap(geometry.caretRect(at: position(5), affinity: .upstream))
        let downstream = try XCTUnwrap(
            geometry.caretRect(at: position(5), affinity: .downstream)
        )

        expect(upstream) == downstream
    }

    func testOffsetOutsideUnitIsClamped() throws {
        let geometry = makeGeometry([
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ])

        let negative = try XCTUnwrap(
            geometry.caretRect(at: position(-40), affinity: .downstream)
        )
        let beyond = try XCTUnwrap(
            geometry.caretRect(at: position(9999), affinity: .upstream)
        )
        let first = try XCTUnwrap(geometry.caretRect(at: position(0), affinity: .downstream))
        let last = try XCTUnwrap(geometry.caretRect(at: position(11), affinity: .upstream))

        expect(negative) == first
        expect(beyond) == last
    }

    func testMissingUnitGivesNoCaret() {
        let geometry = makeGeometry([
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ])

        let missingUnit = geometry.caretRect(
            at: HwpTextPosition(
                pageIndex: 0, blockIndex: 7, unitIndex: 0, characterOffset: 0
            ),
            affinity: .downstream
        )
        let missingPage = geometry.caretRect(
            at: HwpTextPosition(
                pageIndex: 9, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ),
            affinity: .downstream
        )

        expect(missingUnit).to(beNil())
        expect(missingPage).to(beNil())
    }

    /// 줄바꿈으로 끊긴 줄은 후행 공백이 타이포그래픽 폭에 남는다 — 클램프가
    /// 없으면 끝 핸들만 하이라이트 오른쪽 밖에 뜬다.
    func testCaretClampsIntoTheHighlightWidth() throws {
        let geometry = makeGeometry([
            textBlock(
                "Hello wrapped world", frame: CGRect(x: 50, y: 100, width: 40, height: 200)
            ),
        ])
        let lines = geometry.drawnLines(pageIndex: 0, unitOrdinal: 0)
        try XCTSkipIf(lines.count < 2, "조판이 줄바꿈을 만들지 않았다")
        let boundary = lines[0].stringRange.location + lines[0].stringRange.length

        // 이 픽스처가 실제로 클램프가 필요한 상황인지 먼저 고정한다 —
        // 후행 공백이 없으면 아래 단언이 통과해도 아무것도 증명하지 못한다.
        let ctRange = CTLineGetStringRange(lines[0].line)
        let unclamped = lines[0].baselineOrigin.x + CTLineGetOffsetForStringIndex(
            lines[0].line, boundary - lines[0].stringRange.location + ctRange.location, nil
        )
        expect(unclamped) > lines[0].selectionRect.maxX

        let caret = try XCTUnwrap(
            geometry.caretRect(at: position(boundary), affinity: .upstream)
        )

        expect(caret.minX).to(beCloseTo(lines[0].selectionRect.maxX, within: 0.01))
    }
}
