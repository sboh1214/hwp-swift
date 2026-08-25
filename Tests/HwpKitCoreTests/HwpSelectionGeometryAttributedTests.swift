import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 범위 → 속성 문자열 (#118) — `plainText`와의 문자열 파리티(같은 조각·같은
/// 개행 규칙), U+FFFC 마커 run 제거, 개행의 속성 상속.
final class HwpSelectionGeometryAttributedTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    private let boldFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)

    private func attributed(
        _ text: String, extra: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
        ]
        for (key, value) in extra {
            attributes[key] = value
        }
        return NSAttributedString(string: text, attributes: attributes)
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

    private func block(
        _ attributed: NSAttributedString,
        frame: CGRect,
        paragraphId: UInt32? = nil
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: attributed,
            source: paragraphId.map { HwpBlockSource(paragraphId: $0) }
        )
    }

    // MARK: - plainText 파리티 — dedup·join 전 갈래에서 .string이 같다

    func testStringMatchesPlainTextAcrossDedupAndJoinBranches() {
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        // 1쪽: 원본 머리행(paraId 7) + 본문, 2쪽: 클론(제외) + 같은 paraId 연속
        // 조각 + 표식 폴백 조각(paraId 없음) — dedup과 join 갈래를 한 문서에 담는다.
        let marked = HwpTableSplitter.markedAsContinuedFragment(attributed("seg"))
        let document = makeDocument(pages: [
            [
                block(attributed("헤더"), frame: row, paragraphId: 7),
                block(attributed("이어지는"), frame: below, paragraphId: 5),
            ],
            [
                block(
                    markedAsRepeatedHeaderClone(attributed("헤더")),
                    frame: row, paragraphId: 7
                ),
                block(attributed("문단"), frame: below, paragraphId: 5),
            ],
            [
                block(marked, frame: row),
                block(attributed("ment"), frame: below),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        let attributedText = geometry.attributedText(for: selection)

        expect(attributedText.string) == geometry.plainText(for: selection)
        expect(attributedText.string) == "헤더\n이어지는문단\nsegment"
    }

    func testCollapsedSelectionYieldsEmptyString() {
        let document = makeDocument(pages: [[
            block(attributed("body"), frame: CGRect(x: 50, y: 100, width: 200, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        let caret = HwpTextPosition(
            pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 2
        )
        let selection = HwpTextSelection(anchor: caret, focus: caret)

        expect(geometry.attributedText(for: selection).length) == 0
    }

    // MARK: - U+FFFC 마커 run 제거

    func testMarkerRemovalDropsMarkerOnlyAttributes() {
        // 마커 문자가 사라지면 run delegate·controlIndex 같은 마커 전용
        // 속성도 함께 사라지고, 남은 글자에는 어떤 잔재도 없어야 한다.
        let mutable = NSMutableAttributedString()
        mutable.append(attributed("a"))
        mutable.append(attributed("\u{FFFC}", extra: [
            HwpAttributedStringKey.controlIndex: NSNumber(value: 3),
            HwpAttributedStringKey.inlineObjectHeight: NSNumber(value: 24.0),
        ]))
        mutable.append(attributed("b"))

        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(mutable)

        expect(stripped.string) == "ab"
        var found = false
        stripped.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: stripped.length)
        ) { value, _, _ in
            found = found || value != nil
        }
        expect(found) == false
    }

    func testMarkerRemovalContractsWrappingHyperlinkRange() {
        // 링크가 U+FFFC run을 감싸도(필드가 개체를 포함) 마커를 지운 뒤
        // 링크 범위가 남은 글자에 정확히 붙는다 — 번지거나 잘리면 안 된다.
        let mutable = NSMutableAttributedString()
        mutable.append(attributed("전"))
        let linked = NSMutableAttributedString()
        linked.append(attributed("링\u{FFFC}크"))
        linked.addAttribute(
            HwpAttributedStringKey.hyperlink,
            value: "https://example.com",
            range: NSRange(location: 0, length: linked.length)
        )
        mutable.append(linked)
        mutable.append(attributed("후"))

        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(mutable)

        expect(stripped.string) == "전링크후"
        var linkRange = NSRange(location: NSNotFound, length: 0)
        let value = stripped.attribute(
            HwpAttributedStringKey.hyperlink, at: 1,
            longestEffectiveRange: &linkRange,
            in: NSRange(location: 0, length: stripped.length)
        )
        expect(value as? String) == "https://example.com"
        expect(linkRange) == NSRange(location: 1, length: 2)
    }

    func testMarkerOnlyFragmentContributesEmptyText() {
        // 마커뿐인 조각은 평문처럼 빈 기여로 남는다 — 파리티 유지.
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [[
            block(attributed("본문"), frame: row, paragraphId: 1),
            block(attributed("\u{FFFC}"), frame: below, paragraphId: 2),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        let attributedText = geometry.attributedText(for: selection)

        expect(attributedText.string) == geometry.plainText(for: selection)
        expect(attributedText.string) == "본문\n"
    }

    // MARK: - 조판 속성 보존과 개행 속성 상속

    func testRunAttributesSurviveAssembly() throws {
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [[
            block(
                attributed("밑줄", extra: [
                    HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
                ]),
                frame: row, paragraphId: 1
            ),
            block(
                NSAttributedString(string: "굵게", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: boldFont,
                ]),
                frame: below, paragraphId: 2
            ),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        let attributedText = geometry.attributedText(for: selection)

        expect(attributedText.string) == "밑줄\n굵게"
        expect(
            attributedText.attribute(
                HwpAttributedStringKey.underlineStyle, at: 0, effectiveRange: nil
            ) as? NSNumber
        ) == NSNumber(value: 1)
        // 개행(오프셋 2)은 앞 문단 마지막 글자의 속성을 입는다 — 문단 스타일이
        // 종결 개행까지 적용되는 Cocoa 규약 대비.
        expect(
            attributedText.attribute(
                HwpAttributedStringKey.underlineStyle, at: 2, effectiveRange: nil
            ) as? NSNumber
        ) == NSNumber(value: 1)
        // CF 타입은 as? 다운캐스트가 항상 성공한다는 컴파일 에러를 내므로
        // 캐스트 없이 CFEqual로 폰트 값 자체를 비교한다.
        let fontAt3 = try XCTUnwrap(attributedText.attribute(
            kCTFontAttributeName as NSAttributedString.Key, at: 3, effectiveRange: nil
        ))
        let expected = boldFont
        expect(CFEqual(fontAt3 as CFTypeRef, expected)) == true
    }
}
