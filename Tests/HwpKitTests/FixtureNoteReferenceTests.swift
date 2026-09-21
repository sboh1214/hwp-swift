import CoreGraphics
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 본문의 각주·미주 참조 번호가 한글이 그리는 크기·자리에 놓이는지 (#204) — `footnote-endnote`
/// HWP·HWPX 쌍.
///
/// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-21)이 이 픽스처의 HWP를 열어 내보낸 PDF의
/// 벡터 좌표다: 본문 첫 줄 베이스라인 107.76pt(줄 캐시 107.7), 각주 참조 `1)`과 미주 참조 `1)`
/// 모두 글꼴 7.56pt(장치 0.12pt 양자화 — 본문 10pt의 0.75배)로 베이스라인 105.60pt(2.16 위 —
/// 설정 크기의 0.21배). 각주 내용의 번호는 구역 각주 모양이 위 첨자가 아니라 9pt 보통이다.
/// 종전(글자 모양 위 첨자 규칙 0.67배·0.33em, #204 전)에는 6.7pt로 3.3pt 위였고, 글자 모양
/// 첨자 규칙(0.64배·0.44em)을 그대로 쓰면 6.4pt로 4.4pt 위다 — 한글은 참조 번호에 다른 규칙을
/// 쓴다 (`HwpTextRunBuilder.noteReferenceScale`).
///
/// 폰트는 `HwpFontResolver.testDeterministic`이다 — 참조 번호의 글꼴 크기·이동량은 글꼴 지표의
/// 함수가 아니므로 기기·CI가 같은 값을 낸다.
final class FixtureNoteReferenceTests: XCTestCase {
    private static let hancomBaseline: CGFloat = 105.60
    private static let hancomFontSize: CGFloat = 7.56
    /// 한글 PDF의 장치 양자화(0.12pt)의 절반 + 우리 줄 캐시 반올림 몫(107.7 vs 107.76).
    private static let tolerance: CGFloat = 0.13

    func testHwpNoteReferencesSitWhereHancomDrawsThem() async throws {
        try await Self.assertReferences(hwpx: false)
    }

    func testHwpxNoteReferencesSitWhereHancomDrawsThem() async throws {
        try await Self.assertReferences(hwpx: true)
    }

    /// 각주·미주 내용 첫머리의 번호는 위 첨자가 아니다 — 번호 컨트롤(atno)의 위 첨자 플래그
    /// (표 143 bit 12, 한글이 저장한 실물에서는 구역 각주·미주 모양의 표 134 bit 12와 같다)가
    /// 0이라 9pt 보통 글꼴이고 옮겨지지 않는다 (한글 PDF도 `1) CoreHwp footnote fixture`가
    /// 한 9pt span이다).
    func testNoteBodyNumbersStayPlainWhenTheSectionShapeIsNotSuperscript() async throws {
        let references = try await Self.references(hwpx: false, superscriptOnly: false)
        let plain = references.filter { $0.offset == 0 }
        expect(plain.count) == 2
        for reference in plain {
            expect(reference.fontSize).to(beCloseTo(9, within: 0.001))
            expect(reference.scriptOffset) == 0
        }
    }

    // MARK: 헬퍼

    private struct Reference {
        let text: String
        let fontSize: CGFloat
        /// 합산 키(글자 위치 + 첨자, 양수 = 위)
        let offset: CGFloat
        /// 첨자 몫 키
        let scriptOffset: CGFloat
        /// 줄 베이스라인 − 오프셋 = 글리프 베이스라인 (쪽 좌표)
        let glyphBaseline: CGFloat
    }

    private static func assertReferences(hwpx: Bool) async throws {
        let references = try await references(hwpx: hwpx, superscriptOnly: true)
        // 본문 첫 줄의 각주 참조 + 미주 참조.
        expect(references.count) == 2
        for reference in references {
            expect(reference.text) == "1)"
            expect(reference.fontSize).to(
                beCloseTo(hancomFontSize, within: 0.07), description: reference.text
            )
            // 본문 10pt × 0.75 · × 0.21 (`HwpTextRunBuilder.noteReferenceScale`·
            // `noteReferenceBaselineRatio`).
            expect(reference.fontSize).to(beCloseTo(7.5, within: 0.001))
            expect(reference.offset).to(beCloseTo(2.1, within: 0.001))
            expect(reference.scriptOffset).to(beCloseTo(reference.offset, within: 0.001))
            expect(reference.glyphBaseline).to(
                beCloseTo(hancomBaseline, within: tolerance), description: reference.text
            )
        }
    }

    /// 모든 쪽의 drawText 줄에서 마커 치환 run(`hwp.controlIndex`가 있고 텍스트가 U+FFFC가
    /// 아닌 run)을 모은다 — `superscriptOnly`면 첨자 키가 실린 run만 (본문 참조 둘은 1쪽,
    /// 각주 내용의 번호는 1쪽, 미주 내용의 번호는 2쪽이다).
    private static func references(hwpx: Bool, superscriptOnly: Bool) async throws -> [Reference] {
        let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
            .appendingPathComponent("footnote-endnote")
            .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 2
        var result: [Reference] = []
        for command in document.pages.flatMap(\.paintList.commands) {
            guard case let .drawText(attributedString, origin, lineWidth) = command else {
                continue
            }
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            for line in lines {
                guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { continue }
                for run in runs {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard attributes[HwpAttributedStringKey.controlIndex] != nil else { continue }
                    let range = CTRunGetStringRange(run)
                    let text = (attributedString.string as NSString).substring(
                        with: NSRange(location: range.location, length: range.length)
                    )
                    guard text != "\u{FFFC}" else { continue }
                    let offset = Self.offset(attributes, HwpAttributedStringKey.glyphBaselineOffset)
                    let scriptOffset = Self.offset(
                        attributes, HwpAttributedStringKey.scriptBaselineOffset
                    )
                    if superscriptOnly, scriptOffset == 0 {
                        continue
                    }
                    let fontValue = try XCTUnwrap(attributes[kCTFontAttributeName])
                    let ref = fontValue as CFTypeRef
                    expect(CFGetTypeID(ref)) == CTFontGetTypeID()
                    let font = unsafeBitCast(ref, to: CTFont.self)
                    result.append(Reference(
                        text: text,
                        fontSize: CTFontGetSize(font),
                        offset: offset,
                        scriptOffset: scriptOffset,
                        glyphBaseline: line.baselineOrigin.y - offset
                    ))
                }
            }
        }
        return result
    }

    private static func offset(
        _ attributes: NSDictionary, _ key: NSAttributedString.Key
    ) -> CGFloat {
        (attributes[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    }
}
