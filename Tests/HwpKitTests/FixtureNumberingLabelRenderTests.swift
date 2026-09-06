import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 문단 번호·개요 번호 라벨 렌더의 **실물 픽스처 핀** (#154).
///
/// 라벨 문자열 자체는 `HwpParagraphNumberingFixtureTests`(스냅샷·복사 텍스트)가
/// 잠그고, 여기서는 조판 문자열에 실린 라벨이 쪽 블록·복사 소스·줄 수에 어떻게
/// 나타나는지를 본다. 좌표는 `HwpFontResolver.testDeterministic`(Menlo)이라 기기
/// 독립이다.
final class FixtureNumberingLabelRenderTests: XCTestCase {
    private static func fixtureURL(_ id: String, hwpx: Bool = false) -> URL {
        FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
            .appendingPathComponent(id)
            .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
    }

    private static func load(_ id: String, hwpx: Bool = false) async throws -> HwpDocument {
        try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixtureURL(id, hwpx: hwpx))
    }

    private static func isLabelled(_ text: NSAttributedString) -> Bool {
        text.attribute(HwpAttributedStringKey.numberingLabel, at: 0, effectiveRange: nil) != nil
    }

    /// 문서 순서의 라벨 목록 — 라벨 표식이 붙은 블록의 라벨 글자(빈칸 제외).
    private static func labels(in document: HwpDocument) -> [String] {
        document.pages.flatMap(\.blocks).compactMap { block -> String? in
            guard let text = block.attributedString, text.length > 0 else { return nil }
            var range = NSRange(location: NSNotFound, length: 0)
            let marked = text.attribute(
                HwpAttributedStringKey.numberingLabel, at: 0,
                longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length)
            )
            guard marked != nil else { return nil }
            return (text.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// `numbering-sequence` 쌍: 최상위 문단 18개의 라벨이 한글.app 복사 텍스트
    /// (픽스처 README의 표)와 같은 순서·같은 글자로 쪽에 실린다 — HWP·HWPX 동일.
    /// 표 셀의 `9.`·`10.`은 컨테이너 문단이라 아직 라벨이 없다(#151 후속).
    func testNumberingSequenceLabelsMatchHancomInBothFormats() async throws {
        let expected = [
            "1.", "가.", "1.", "2.", "3.", "나.", "가)", "1.", "1)", "나.", "2.", "3.", "2.",
            "7.", "4.", "5.", "6.", "11.",
        ]
        for hwpx in [false, true] {
            let document = try await Self.load("numbering-sequence", hwpx: hwpx)
            expect(Self.labels(in: document)).to(
                equal(expected), description: hwpx ? "HWPX" : "HWP"
            )
            let headingHints = document.unsupportedElements.map(\.hint)
                .filter { $0.contains("번호 문단 머리") }
            expect(headingHints).to(beEmpty(), description: hwpx ? "HWPX" : "HWP")
        }
    }

    /// `outline-numbering` 쌍: 개요 3수준 + 문단 번호 2개. 1수준 정의는 오른쪽
    /// 정렬·너비 조정 2pt·HWPUNIT 10pt·자동 내어쓰기 해제라 둘째 줄 들여쓰기
    /// 표식이 없고, 2수준부터는 기본값(자동 내어쓰기)이라 표식이 있다.
    func testOutlineNumberingLabelsAndAutoIndentMarks() async throws {
        for hwpx in [false, true] {
            let document = try await Self.load("outline-numbering", hwpx: hwpx)
            expect(Self.labels(in: document)).to(
                equal(["I.", "가.", "1)", "1.", "2."]), description: hwpx ? "HWPX" : "HWP"
            )
            let marks = document.pages.flatMap(\.blocks).compactMap { block -> Bool? in
                guard let text = block.attributedString, text.length > 0,
                      Self.isLabelled(text)
                else { return nil }
                return text.attribute(
                    HwpAttributedStringKey.numberingHeadIndent, at: 0, effectiveRange: nil
                ) != nil
            }
            expect(marks).to(
                equal([false, true, true, true, true]), description: hwpx ? "HWPX" : "HWP"
            )
        }
    }

    /// 접근성 낭독에는 라벨이 들어가되 개요 제목 대조는 라벨을 뗀 본문으로 한다 —
    /// 개요 문단 3개가 VoiceOver 제목으로 남고, 문단 번호 문단은 제목이 아니다.
    func testAccessibilityReadsLabelsButStillDetectsHeadings() async throws {
        let document = try await Self.load("outline-numbering")
        let page = try XCTUnwrap(document.pages.first)
        let titles = document.metadata.outline.map(\.title)
        expect(titles) == ["Outline level one", "Outline level two", "Outline level three"]

        let units = HwpAccessibilityContent.pageUnits(
            page: page, bodyUnits: HwpSelectableText.units(in: page), headingTitles: titles
        )
        let spoken = units.filter { $0.kind == .body }.map { ($0.label, $0.isHeading) }
        expect(spoken.map(\.0)) == [
            "Hello CoreHwp plain text fixture.", "I. Outline level one", "가. Outline level two",
            "1) Outline level three", "Plain body paragraph", "1. Numbered item one",
            "2. Numbered item two",
        ]
        expect(spoken.map(\.1)) == [false, true, true, true, false, false, false]
    }

    /// 복사 텍스트에 라벨이 들어간다 — 한글.app도 자동 번호 라벨을 복사한다
    /// (문단 경계 복사 실측: `\\r\\n1. Nu`).
    func testCopiedTextIncludesLabels() async throws {
        let document = try await Self.load("outline-numbering")
        let geometry = HwpSelectionGeometry(document: document)
        let selection = try XCTUnwrap(geometry.documentSelection())
        let lines = geometry.plainText(for: selection).components(separatedBy: "\n")
        expect(lines).to(contain(
            "I. Outline level one", "가. Outline level two", "1. Numbered item one"
        ))
    }

    /// 헌법주석: 라벨을 붙여도 절대 캐시 한 줄 문단이 두 줄로 접히지 않는다 —
    /// 쪽 수는 캐시 y로 정해져 1,030쪽 핀과 각주 예산이 이 회귀를 못 잡으므로,
    /// 라벨 문단(첫 조각)마다 그려지는 줄 수가 한글이 저장한 줄 수를 넘는 문단을
    /// 직접 센다. 결정론 폰트(Menlo, 고정폭이라 실폰트보다 넓다)에서는 591쪽의
    /// `(나) Keyishian v. Board of Regents…`(s23/p199) 한 문단만 걸린다 — 단 폭
    /// 408.2pt에 라벨 포함 자연 폭 459.0pt라 slight-overflow 허용폭(6%)을 라벨만큼
    /// 넘어 두 줄이 된다. 배포 기본(시스템 폴백)·한컴 폰트 모드에서는 0건이다
    /// (2026-09-06 실측). 목록이 늘면 라벨 폭·거리가 실물보다 커진 회귀다.
    func testLegacyLabelsNeverAddLinesBeyondTheCachedSegments() async throws {
        let document = try await Self.load("legacy-common-control-property")
        let file = try CoreHwp.HwpFile(
            fromPath: Self.fixtureURL("legacy-common-control-property").path
        )
        let sections = file.displaySectionArray

        var labelled = 0
        var overflowing: [String] = []
        for page in document.pages {
            for block in page.blocks {
                guard let text = block.attributedString, text.length > 0,
                      Self.isLabelled(text), let key = block.source?.paragraphKey
                else { continue }
                labelled += 1
                let cached = sections[key.sectionIndex].paragraph[key.paragraphIndex]
                    .paraLineSeg.paraLineSegInternalArray.count
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: text, origin: .zero, lineWidth: block.frame.width
                ).count
                if drawn > cached {
                    overflowing.append(
                        "s\(key.sectionIndex)/p\(key.paragraphIndex) \(drawn)>\(cached)"
                    )
                }
            }
        }
        expect(labelled) == 1944
        expect(overflowing) == ["s23/p199 2>1"]
        expect(document.pages.count) == 1030
    }
}
