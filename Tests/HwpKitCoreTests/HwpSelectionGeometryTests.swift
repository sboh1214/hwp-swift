import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 점→위치 스냅, 범위→하이라이트 rect, 범위→텍스트 직렬화 테스트.
final class HwpSelectionGeometryTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func textBlock(
        _ text: String,
        frame: CGRect,
        role: HwpBlockRole = .body
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            role: role
        )
    }

    private func makeDocument(pages: [[AnyHwpBlock]]) -> HwpDocument {
        HwpDocument(
            pages: pages.enumerated().map { index, blocks in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: blocks,
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pages.count),
            unsupportedElements: []
        )
    }

    func testUnitsExcludePageChrome() {
        let document = makeDocument(pages: [[
            textBlock("body", frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
            textBlock(
                "- 1 -",
                frame: CGRect(x: 50, y: 800, width: 200, height: 20),
                role: .pageChrome
            ),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let units = geometry.units(forPage: 0)

        expect(units.count) == 1
        expect(units[0].attributedString.string) == "body"
    }

    func testPositionSnapsInsideLine() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let start = geometry.position(nearest: CGPoint(x: 50, y: 108), pageIndex: 0)
        let beyondEnd = geometry.position(nearest: CGPoint(x: 590, y: 108), pageIndex: 0)

        expect(start?.characterOffset) == 0
        expect(beyondEnd?.characterOffset) == 11
    }

    func testPositionSnapsFromEmptySpace() {
        let document = makeDocument(pages: [[
            textBlock("above", frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
            textBlock("below", frame: CGRect(x: 50, y: 300, width: 200, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        // 본문 아래 빈 공간 → 마지막 단위로 스냅
        let below = geometry.position(nearest: CGPoint(x: 60, y: 700), pageIndex: 0)

        expect(below?.blockIndex) == 1
    }

    func testHighlightRectsForPartialLine() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        let selection = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ),
            focus: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 5
            )
        )

        let rects = geometry.highlightRects(pageIndex: 0, selection: selection)

        expect(rects.count) == 1
        expect(rects[0].minX).to(beCloseTo(50, within: 0.5))
        // "Hello"의 폭은 "Hello world" 전체 폭보다 좁아야 한다
        let fullWidth = (NSAttributedString(
            string: "Hello world",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        ).size()).width
        expect(rects[0].width) < fullWidth
        expect(rects[0].width) > 10
    }

    func testPlainTextJoinsUnitsAcrossPages() {
        let document = makeDocument(pages: [
            [textBlock("first page", frame: CGRect(x: 50, y: 100, width: 200, height: 20))],
            [textBlock("second page", frame: CGRect(x: 50, y: 100, width: 200, height: 20))],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        let selection = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 6
            ),
            focus: HwpTextPosition(
                pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 6
            )
        )

        expect(geometry.plainText(for: selection)) == "page\nsecond"
    }

    func testPlainTextStripsControlMarkers() {
        expect(HwpSelectionGeometry.strippingControlMarkers("a\u{FFFC}b")) == "ab"
    }

    func testContinuationMarkerDoesNotJoinDifferentParagraphs() {
        // 분할 표 행은 서로 다른 셀의 top 조각이 연달아 온다 — '이어짐' 표식이
        // 있어도 paraId가 다르면 다음 조각 앞 개행을 유지해야 한다 (#7).
        let markedA = HwpTableSplitter.markedAsContinuedFragment(NSAttributedString(
            string: "atop",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        ))
        let cellA = AnyHwpBlock(
            frame: CGRect(x: 50, y: 100, width: 200, height: 20),
            kind: .text,
            attributedString: markedA,
            source: HwpBlockSource(paragraphId: 1)
        )
        let cellB = AnyHwpBlock(
            frame: CGRect(x: 50, y: 130, width: 200, height: 20),
            kind: .text,
            attributedString: NSAttributedString(
                string: "btop",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            source: HwpBlockSource(paragraphId: 2)
        )
        let document = makeDocument(pages: [[cellA, cellB]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        expect(geometry.plainText(for: selection)) == "atop\nbtop"
    }

    // MARK: - 반복 제목 행 클론 dedup (#8) — 공통 순회 추출(#118)의 회귀 그물.

    // 클론 판정·조립 정책이 attributedText 경로와 갈라지면 여기가 빨개진다.

    /// 분할 표 클론과 같은 표식을 단 사본 (`HwpTableSplitter.markRepeatedHeader`와
    /// 동일 산식 — private라 테스트가 직접 단다).
    private func markedAsRepeatedHeaderClone(
        _ attributed: NSAttributedString
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(
            HwpAttributedStringKey.repeatedTableHeaderClone,
            value: NSNumber(value: true),
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    private func sourcedBlock(
        _ attributed: NSAttributedString,
        frame: CGRect,
        paragraphId: UInt32,
        paragraphKey: HwpParagraphKey? = nil
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: attributed,
            source: HwpBlockSource(
                paragraphId: paragraphId,
                sectionIndex: paragraphKey?.sectionIndex,
                paragraphIndex: paragraphKey?.paragraphIndex
            )
        )
    }

    func testPlainTextSkipsRepeatedHeaderCloneWhenOriginalContributed() {
        // 원본 머리행(paraId 7)이 이미 기여했으면 뒷페이지의 클론은 빠진다 (#8).
        let header = NSAttributedString(
            string: "헤더",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let bodyA = NSAttributedString(
            string: "본문A",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let bodyB = NSAttributedString(
            string: "본문B",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [
            [
                sourcedBlock(header, frame: row, paragraphId: 7),
                sourcedBlock(bodyA, frame: below, paragraphId: 8),
            ],
            [
                sourcedBlock(
                    markedAsRepeatedHeaderClone(header), frame: row, paragraphId: 7
                ),
                sourcedBlock(bodyB, frame: below, paragraphId: 9),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        expect(geometry.plainText(for: selection)) == "헤더\n본문A\n본문B"
    }

    func testPlainTextKeepsCloneWhenOriginalOutsideSelection() {
        // 원본이 선택 밖(뒷페이지 클론만 선택)이면 클론이 기여해야 복사가
        // 비지 않는다 (#8, #21 보정).
        let header = NSAttributedString(
            string: "헤더",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let bodyB = NSAttributedString(
            string: "본문B",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [
            [sourcedBlock(header, frame: row, paragraphId: 7)],
            [
                sourcedBlock(
                    markedAsRepeatedHeaderClone(header), frame: row, paragraphId: 7
                ),
                sourcedBlock(bodyB, frame: below, paragraphId: 9),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        let selection = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ),
            focus: HwpTextPosition(
                pageIndex: 1, blockIndex: 1, unitIndex: 0, characterOffset: 3
            )
        )

        expect(geometry.plainText(for: selection)) == "헤더\n본문B"
    }

    func testPlainTextJoinsSameParagraphAcrossPagesWithoutNewline() {
        // 같은 위치 열쇠의 조각은 쪽 경계를 건너도 개행 없이 이어진다 (#9, #145).
        let first = NSAttributedString(
            string: "이어지는",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let second = NSAttributedString(
            string: "문단",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let key = HwpParagraphKey(sectionIndex: 0, paragraphIndex: 3)
        let document = makeDocument(pages: [
            [sourcedBlock(first, frame: row, paragraphId: 5, paragraphKey: key)],
            [sourcedBlock(second, frame: row, paragraphId: 5, paragraphKey: key)],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        expect(geometry.plainText(for: selection)) == "이어지는문단"
    }

    func testSameParagraphIdAloneNoLongerJoinsParagraphs() {
        // paraId는 한글.app 저장본에서 문단마다 고유하지 않다 (noori 65문단 중
        // 고유 값 2개) — 같은 paraId만으로 이으면 서로 다른 문단이 한 줄로 붙는다
        // (#145). 열쇠도 표식도 없으면 개행을 유지한다.
        let first = NSAttributedString(
            string: "첫 문단",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let second = NSAttributedString(
            string: "둘째 문단",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [[
            sourcedBlock(first, frame: row, paragraphId: 0),
            sourcedBlock(second, frame: below, paragraphId: 0),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        expect(geometry.plainText(for: selection)) == "첫 문단\n둘째 문단"
    }

    func testContinuationMarkerJoinsWhenParagraphIdentityUnknown() {
        // paraId를 모르는 조각은 '이어짐' 표식이 폴백으로 개행을 막는다 (#7, #9).
        let marked = HwpTableSplitter.markedAsContinuedFragment(NSAttributedString(
            string: "seg",
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        ))
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let document = makeDocument(pages: [
            [
                AnyHwpBlock(
                    frame: row, kind: .text, attributedString: marked
                ),
            ],
            [
                AnyHwpBlock(
                    frame: row,
                    kind: .text,
                    attributedString: NSAttributedString(
                        string: "ment",
                        attributes: [
                            kCTFontAttributeName as NSAttributedString.Key: font,
                        ]
                    )
                ),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        expect(geometry.plainText(for: selection)) == "segment"
    }

    func testDocumentSelectionSpansAllBodyText() throws {
        // 첫 페이지는 크롬만 → 전체 선택은 텍스트가 있는 페이지 범위로 수렴
        let document = makeDocument(pages: [
            [textBlock(
                "- 1 -",
                frame: CGRect(x: 50, y: 800, width: 200, height: 20),
                role: .pageChrome
            )],
            [textBlock("first", frame: CGRect(x: 50, y: 100, width: 200, height: 20))],
            [
                textBlock("second", frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
                textBlock("third", frame: CGRect(x: 50, y: 300, width: 200, height: 20)),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)

        let selection = geometry.documentSelection()

        expect(selection?.range.start) == HwpTextPosition(
            pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 0
        )
        expect(selection?.range.end) == HwpTextPosition(
            pageIndex: 2, blockIndex: 1, unitIndex: 0, characterOffset: 5
        )
        expect(geometry.plainText(for: try XCTUnwrap(selection))) == "first\nsecond\nthird"
    }

    func testDocumentSelectionIsNilWithoutBodyText() {
        let document = makeDocument(pages: [[
            textBlock(
                "- 1 -",
                frame: CGRect(x: 50, y: 800, width: 200, height: 20),
                role: .pageChrome
            ),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        expect(geometry.documentSelection()).to(beNil())
    }

    func testWordRangeAtPosition() {
        let document = makeDocument(pages: [[
            textBlock("Hello world", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let word = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 7
        ))

        expect(word?.range.start.characterOffset) == 6
        expect(word?.range.end.characterOffset) == 11
    }

    /// 구두점은 단어 경계다 — foo,bar 더블클릭이 두 단어를 함께 선택하지
    /// 않는다 (한글.app 동작, R33 #3).
    func testWordRangeStopsAtPunctuation() {
        let document = makeDocument(pages: [[
            textBlock("foo,bar", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        let first = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 1
        ))
        expect(first?.range.start.characterOffset) == 0
        expect(first?.range.end.characterOffset) == 3

        let second = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 5
        ))
        expect(second?.range.start.characterOffset) == 4
        expect(second?.range.end.characterOffset) == 7

        // 구두점 자체를 짚으면 단어가 아니다
        let comma = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 3
        ))
        expect(comma).to(beNil())
    }

    /// 비-BMP 기호 (이모지)도 단어 경계다 — 서로게이트 쌍을 결합해
    /// 판정하므로 foo😀bar가 통째로 선택되지 않는다 (R34 #3).
    func testWordRangeStopsAtEmoji() {
        let document = makeDocument(pages: [[
            textBlock("foo😀bar", frame: CGRect(x: 50, y: 100, width: 300, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)

        // "foo" = 0-2, 😀 = 3-4 (서로게이트 2단위), "bar" = 5-7
        let first = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 1
        ))
        expect(first?.range.start.characterOffset) == 0
        expect(first?.range.end.characterOffset) == 3

        let second = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 6
        ))
        expect(second?.range.start.characterOffset) == 5
        expect(second?.range.end.characterOffset) == 8

        let emoji = geometry.wordRange(at: HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 3
        ))
        expect(emoji).to(beNil())
    }
}
