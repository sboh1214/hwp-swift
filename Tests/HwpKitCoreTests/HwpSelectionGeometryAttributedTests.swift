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

    func testLeadingMarkerOnlyFragmentDoesNotCrashNewlineAttributes() {
        // 첫 조각이 마커뿐이라 빈 문자열로 남으면, 다음 조각 앞 개행이
        // attributes(at: -1)을 묻지 않아야 한다 — result.length 가드의 회귀 그물.
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [[
            block(attributed("\u{FFFC}"), frame: row, paragraphId: 1),
            block(attributed("본문"), frame: below, paragraphId: 2),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        let attributedText = geometry.attributedText(for: selection)

        expect(attributedText.string) == geometry.plainText(for: selection)
        expect(attributedText.string) == "\n본문"
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

    private func paragraphStyle(_ alignment: CTTextAlignment) -> CTParagraphStyle {
        var value = alignment
        return withUnsafeMutablePointer(to: &value) { pointer in
            let settings = [CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointer
            )]
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }

    private func alignment(
        of attributed: NSAttributedString, at index: Int
    ) -> CTTextAlignment.RawValue? {
        guard let raw = attributed.attribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            at: index, effectiveRange: nil
        ) else { return nil }
        let reference = raw as CFTypeRef
        guard CFGetTypeID(reference) == CTParagraphStyleGetTypeID() else { return nil }
        var value = CTTextAlignment.natural
        CTParagraphStyleGetValueForSpecifier(
            unsafeBitCast(reference, to: CTParagraphStyle.self),
            .alignment, MemoryLayout<CTTextAlignment>.size, &value
        )
        return value.rawValue
    }

    /// 개체만 있는 문단은 마커를 지우면 기여가 비는데, 그 문단을 종결하는 개행이
    /// 스타일을 잃으면 RTF에서 그 빈 문단의 정렬·들여쓰기·폰트가 통째로 사라진다
    /// (선두면 무속성, 중간이면 **앞 문단**의 스타일 — #124 리뷰).
    func testNewlineAfterMarkerOnlyParagraphCarriesThatParagraphStyle() {
        let markerOnly = attributed("\u{FFFC}", extra: [
            kCTParagraphStyleAttributeName as NSAttributedString.Key:
                paragraphStyle(.center),
            kCTFontAttributeName as NSAttributedString.Key: boldFont,
        ])
        let leading = attributed("가", extra: [
            kCTParagraphStyleAttributeName as NSAttributedString.Key:
                paragraphStyle(.right),
        ])
        let rows = (0 ..< 3).map {
            CGRect(x: 50, y: 100 + CGFloat($0) * 30, width: 200, height: 20)
        }

        let first = HwpSelectionGeometry(document: makeDocument(pages: [[
            block(markerOnly, frame: rows[0], paragraphId: 1),
            block(attributed("본문"), frame: rows[1], paragraphId: 2),
        ]]))
        guard let firstSelection = first.documentSelection() else {
            return fail("expected selection")
        }
        let firstText = first.attributedText(for: firstSelection)

        let firstNewlineAlignment = alignment(of: firstText, at: 0)
        expect(firstText.string) == "\n본문"
        expect(firstNewlineAlignment) == CTTextAlignment.center.rawValue
        expect(firstText.attribute(
            kCTFontAttributeName as NSAttributedString.Key, at: 0, effectiveRange: nil
        )).toNot(beNil())

        let middle = HwpSelectionGeometry(document: makeDocument(pages: [[
            block(leading, frame: rows[0], paragraphId: 1),
            block(markerOnly, frame: rows[1], paragraphId: 2),
            block(attributed("나"), frame: rows[2], paragraphId: 3),
        ]]))
        guard let middleSelection = middle.documentSelection() else {
            return fail("expected selection")
        }
        let middleText = middle.attributedText(for: middleSelection)

        let leadingParagraphTerminator = alignment(of: middleText, at: 1)
        let markerParagraphTerminator = alignment(of: middleText, at: 2)
        expect(middleText.string) == "가\n\n나"
        expect(leadingParagraphTerminator) == CTTextAlignment.right.rawValue
        expect(markerParagraphTerminator) == CTTextAlignment.center.rawValue
    }

    func testNewlineDoesNotInheritHyperlink() {
        // 링크로 끝나는 문단 + 다음 문단 — 개행이 hwp.hyperlink를 상속하면
        // RTF의 HYPERLINK 필드가 원문에 없던 문단 나눔 문자까지 덮는다.
        let row = CGRect(x: 50, y: 100, width: 200, height: 20)
        let below = CGRect(x: 50, y: 130, width: 200, height: 20)
        let document = makeDocument(pages: [[
            block(
                attributed("링크", extra: [
                    HwpAttributedStringKey.hyperlink: "https://example.com",
                ]),
                frame: row, paragraphId: 1
            ),
            block(attributed("본문"), frame: below, paragraphId: 2),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else {
            return fail("expected selection")
        }

        let attributedText = geometry.attributedText(for: selection)

        expect(attributedText.string) == "링크\n본문"
        expect(
            attributedText.attribute(
                HwpAttributedStringKey.hyperlink, at: 1, effectiveRange: nil
            ) as? String
        ) == "https://example.com"
        expect(attributedText.attribute(
            HwpAttributedStringKey.hyperlink, at: 2, effectiveRange: nil
        )).to(beNil())
    }

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
        // 개행(오프셋 2)은 앞 문단 마지막 글자에서 문단 스타일·폰트만 입는다 —
        // 밑줄 같은 글자 장식이 상속되면 원문에 없던 개행까지 서식이 번진다.
        expect(attributedText.attribute(
            HwpAttributedStringKey.underlineStyle, at: 2, effectiveRange: nil
        )).to(beNil())
        expect(attributedText.attribute(
            kCTFontAttributeName as NSAttributedString.Key, at: 2, effectiveRange: nil
        )).toNot(beNil())
        // CF 타입은 as? 다운캐스트가 항상 성공한다는 컴파일 에러를 내므로
        // 캐스트 없이 CFEqual로 폰트 값 자체를 비교한다.
        let fontAt3 = try XCTUnwrap(attributedText.attribute(
            kCTFontAttributeName as NSAttributedString.Key, at: 3, effectiveRange: nil
        ))
        let expected = boldFont
        expect(CFEqual(fontAt3 as CFTypeRef, expected)) == true
    }

    // MARK: - 마커 제거 선형성

    /// 이전 형태는 마커마다 `deleteCharacters`를 불러 남은 접미를 매번 밀었다
    /// (2026-08-26 로컬 릴리스, 마커당 텍스트 4자: 2,500개 0.36초 · 5,000개
    /// 1.48초 · 10,000개 5.90초 · 20,000개 23.49초 — 배가 될 때마다 4배).
    /// 복사가 `@MainActor`에서 도는 만큼 그대로 화면이 멈춘다.
    ///
    /// `mutableString.replaceOccurrences`로는 못 고친다 — 상수만 215배 작을 뿐
    /// 여전히 제자리 삭제라 4배씩 는다 (10,000개 0.027초 → 80,000개 1.82초).
    /// 비마커 구간 append만 2.0배/배로 선형이다 (10,000개 0.017초 → 80,000개
    /// 0.129초).
    func testMarkerStrippingStaysLinear() {
        let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
        let markers = full ? 40000 : 5000
        let source = NSMutableAttributedString()
        for index in 0 ..< markers {
            source.append(attributed("본문\(index % 10) "))
            source.append(attributed("\u{FFFC}", extra: [
                HwpAttributedStringKey.controlIndex: NSNumber(value: index),
            ]))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(source)
        let elapsed = clock.now - start

        expect(stripped.length) == markers * 4
        expect(stripped.string.contains("\u{FFFC}")) == false
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("HWP_PERF marker-strip: N=\(markers) time=\(String(format: "%.3f", seconds))s")
        // 임계 = 선형 실측 + 넉넉한 여유. 이차로 되돌아가면 넘는다 —
        // 이전 형태는 기본 N=5,000에서 이미 1.48초다.
        expect(seconds) < (full ? 2.0 : 0.5)
    }
}
