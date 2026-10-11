import CoreGraphics
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `letter-spacing` 쌍의 실물 핀 (#260) — 글자 모양 자간은 글자 크기가 아니라 **그 글자의 전진량**
/// (상대 크기·장평 적용 뒤)의 %이고, 보통·고정폭 빈칸은 라틴 자간을 빈칸 폭의 %로 받으며 묶음 빈칸은
/// 받지 않는다. 줄의 마지막 글자는 자간을 받지 않는다 — 줄 맞춤(8·9번 문단의 첫 줄 단어 수)과 오른쪽
/// 정렬(10·11번 문단의 마지막 글자 자리)이 그 값으로 정해진다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-08, 벡터 글자 원점, 쪽 왼쪽에서
/// pt). 기본 크기 20pt, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo라 결정론
/// resolver(`HwpFontResolver.testDeterministic`)가 같은 글꼴을 고른다 — 그래서 글자 원점을 쪽 좌표 그대로
/// 핀한다. 수정 전(자간 = 글자 크기의 %, 고정 폭 빈칸에 자간 없음, 줄 끝 글자에도 자간)에는 문단 11개
/// 중 10개가 1.2~15.0pt 어긋났고 8·9번 문단의 첫 줄 나눔이 한글과 갈렸다.
///
/// | 문단 | 글자 모양 (한글 / 라틴) | 텍스트 | 가르는 것 |
/// |---|---|---|---|
/// | 1 | 자간 +20% / +20% | `abcd 가나다라` | 글자 전진량 × 1.2, 빈칸 10pt × 1.2 |
/// | 2 | −20% / −20% | `abcd 가나다라` | 글자 × 0.8, 빈칸 8pt |
/// | 3 | 0 / 장평 50%·+20% | `abcd ab` | 장평 적용 뒤 전진량 × 1.2, 빈칸 12pt (장평 무관) |
/// | 4 | 0 / 상대 크기 50%·−20% | `abcd 가` | 줄어든 전진량 × 0.8 |
/// | 5 | +20% / 0 | `가나 다라 ab` | 한글 자간은 빈칸에 닿지 않는다 (10pt) |
/// | 6 | 0 / −10%, 글꼴에 어울리는 빈칸 | `ab cd` | Menlo 빈칸 × 0.9 |
/// | 7 | 0 / +20% | `ab`·`cd`·`ef` | 묶음 빈칸 10pt(자간 없음), 고정폭 빈칸 6pt |
/// | 8 | 0 / −20%, 줄 폭 387.5pt | `aaaaa` × 10 | 첫 줄 6단어 (마지막 글자 자간을 넣고 재면 7단어) |
/// | 9 | 0 / +20%, 줄 폭 407.5pt | `aaaaa` × 6 | 첫 줄 5단어 (넣고 재면 4단어) |
/// | 10 | 0 / −20%, 오른쪽 정렬 | `abcd` | `d`가 오른쪽 끝 − 12.04pt (자간 없는 전진량) |
/// | 11 | 0 / +20%, 오른쪽 정렬 | `abcd` | 같은 자리 |
final class FixtureLetterSpacingTests: XCTestCase {
    /// 한글 PDF의 0.12pt 장치 양자화와 그것이 한 줄에 쌓인 몫.
    private static let tolerance: CGFloat = 0.25
    /// 글자 하나마다 더 허용하는 몫 — 한글은 자간을 HWPUNIT(0.01pt) 단위로 0 쪽으로 버리는 것으로 보인다
    /// (Menlo 20pt `a` 자간 ∓20%의 간격이 9.6417·14.440pt — 정확값 9.6328·14.449pt면 ∓2.408, 버리면
    /// ∓2.40). 조판은 정확값이라 글자마다 0.01pt 미만씩 갈려 8번 문단 첫 줄 끝(24번째 글자)에서 0.21pt가
    /// 쌓인다. 자간만 버리면 한글 음절 줄 맞춤 경계(`probes/260` hfit) 57표본 중 2개가 어긋나 글자 전진량도
    /// 함께 버려야 하는데, 그것은 자간과 무관한 글자 폭 전반의 변경이라 따로 다룬다.
    private static let perGlyphTolerance: CGFloat = 0.01

    private struct Row {
        let paragraph: Int
        /// 줄마다 보이는 글자(꼬리표·빈칸 제외)와 그 쪽 x 원점.
        let lines: [(text: String, origins: [CGFloat])]

        init(_ paragraph: Int, _ lines: [(String, [CGFloat])]) {
            self.paragraph = paragraph
            self.lines = lines.map { (text: $0.0, origins: $0.1) }
        }
    }

    private static func a(_ count: Int) -> String {
        String(repeating: "a", count: count)
    }

    private static let rows = [
        Row(1, [("abcd가나다라", [85.08, 99.48, 114.00, 128.40, 154.80, 175.68, 196.44, 217.20])]),
        Row(2, [("abcd가나다라", [85.08, 94.68, 104.40, 114.00, 131.64, 145.44, 159.36, 173.16])]),
        Row(3, [("abcdab", [85.08, 92.28, 99.48, 106.68, 125.88, 133.08])]),
        Row(4, [("abcd가", [85.08, 89.88, 94.80, 99.60, 112.44])]),
        Row(5, [("가나다라ab", [85.08, 105.84, 136.68, 157.44, 188.28, 200.28])]),
        Row(6, [("abcd", [85.08, 95.88, 117.60, 128.40])]),
        Row(7, [("abcdef", [85.08, 99.48, 123.96, 138.36, 158.88, 173.28])]),
        Row(8, [
            (a(30), [
                122.76, 132.48, 142.08, 151.68, 161.40, 179.04, 188.64, 198.24, 207.96, 217.56,
                235.20, 244.80, 254.52, 264.12, 273.72, 291.36, 301.08, 310.68, 320.28, 330.00,
                347.64, 357.24, 366.84, 376.56, 386.16, 403.80, 413.40, 423.12, 432.72, 442.32,
            ]),
            (a(20), [
                122.76, 132.48, 142.08, 151.68, 161.40, 179.04, 188.64, 198.24, 207.96, 217.56,
                235.20, 244.80, 254.52, 264.12, 273.72, 291.36, 301.08, 310.68, 320.28, 330.00,
            ]),
        ]),
        Row(9, [
            (a(25), [
                102.84, 117.24, 131.64, 146.16, 160.56, 186.96, 201.48, 215.88, 230.28, 244.80,
                271.20, 285.60, 300.12, 314.52, 328.92, 355.44, 369.84, 384.24, 398.76, 413.16,
                439.56, 454.08, 468.48, 482.88, 497.40,
            ]),
            (a(5), [102.84, 117.24, 131.64, 146.16, 160.56]),
        ]),
        Row(10, [("abcd", [469.32, 478.92, 488.64, 498.24])]),
        Row(11, [("abcd", [454.92, 469.32, 483.84, 498.24])]),
    ]

    private static func firstPage(
        _ id: String, hwpx: Bool, file: String = #file
    ) async throws -> HwpPage {
        let url = hwpx
            ? FixtureRoot.url(from: file, subdirectory: "HwpxFixtures")
            .appendingPathComponent(id).appendingPathComponent("document.hwpx")
            : FixtureRoot.url(from: file)
            .appendingPathComponent(id).appendingPathComponent("document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        return try XCTUnwrap(document.pages.first)
    }

    /// 꼬리표(`#k`, 5pt — 줄 앞이든 끝이든) 번호 → 그 문단의 줄마다 보이는 글자와 쪽 x 원점.
    private static func glyphLines(_ page: HwpPage) -> [Int: [[(Character, CGFloat)]]] {
        var rows: [Int: [[(Character, CGFloat)]]] = [:]
        for command in page.paintList.commands {
            guard case let .drawText(attributedString, origin, lineWidth) = command,
                  let paragraph = tag(in: attributedString)
            else { continue }
            let string = attributedString.string as NSString
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            rows[paragraph] = lines.map { line in
                var glyphs: [(Character, CGFloat)] = []
                for run in CTLineGetGlyphRuns(line.line) as? [CTRun] ?? [] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    // 꼬리표(5pt)는 빼고 표본 글자(20pt 계열)만 본다.
                    guard let fontValue = attributes[kCTFontAttributeName],
                          CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID(),
                          CTFontGetSize(unsafeBitCast(fontValue as CFTypeRef, to: CTFont.self)) > 6
                    else { continue }
                    let count = CTRunGetGlyphCount(run)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                    // 위치는 텍스트 공간 값이다 — 장평 행렬을 씌워야 그려지는 자리다.
                    let textMatrix = CTRunGetTextMatrix(run)
                    for (position, index) in zip(positions, indices) {
                        guard let scalar = Unicode.Scalar(string.character(at: index))
                        else { continue }
                        let character = Character(scalar)
                        guard !character.isWhitespace, character != "\u{FFFC}" else { continue }
                        let x = line.baselineOrigin.x + position.applying(textMatrix).x
                        glyphs.append((character, x))
                    }
                }
                return glyphs.sorted { $0.1 < $1.1 }
            }
        }
        return rows
    }

    /// 5pt 글꼴로 조판된 `#` 뒤 숫자 — 문단 꼬리표 번호.
    private static func tag(in attributedString: NSAttributedString) -> Int? {
        let string = attributedString.string as NSString
        var location = 0
        while location < string.length {
            let found = string.range(
                of: "#", range: NSRange(location: location, length: string.length - location)
            )
            guard found.location != NSNotFound else { return nil }
            let font = attributedString.attribute(
                kCTFontAttributeName as NSAttributedString.Key,
                at: found.location, effectiveRange: nil
            )
            if let font, CFGetTypeID(font as CFTypeRef) == CTFontGetTypeID(),
               CTFontGetSize(unsafeBitCast(font as CFTypeRef, to: CTFont.self)) <= 6
            {
                var digits = ""
                var cursor = NSMaxRange(found)
                while cursor < string.length,
                      let scalar = Unicode.Scalar(string.character(at: cursor)),
                      ("0" ... "9").contains(Character(scalar))
                {
                    digits.append(Character(scalar))
                    cursor += 1
                }
                return Int(digits)
            }
            location = NSMaxRange(found)
        }
        return nil
    }

    private func assertRows(id: String, hwpx: Bool) async throws {
        let page = try await Self.firstPage(id, hwpx: hwpx)
        let measured = Self.glyphLines(page)
        let format = hwpx ? "HWPX" : "HWP"
        for row in Self.rows {
            let label = "\(id) \(format) #\(row.paragraph)"
            let lines = try XCTUnwrap(measured[row.paragraph], label)
            expect(lines.count).to(equal(row.lines.count), description: label)
            for (index, (line, expected)) in zip(lines, row.lines).enumerated() {
                let lineLabel = "\(label) 줄 \(index)"
                expect(String(line.map(\.0))).to(equal(expected.text), description: lineLabel)
                for (offset, (glyph, origin)) in zip(line, expected.origins).enumerated() {
                    let within = Self.tolerance + Self.perGlyphTolerance * CGFloat(offset)
                    expect(glyph.1).to(
                        beCloseTo(origin, within: within),
                        description: "\(lineLabel) '\(glyph.0)'"
                    )
                }
            }
        }
    }

    func testLetterSpacingMatchesHancom() async throws {
        try await assertRows(id: "letter-spacing", hwpx: false)
        try await assertRows(id: "letter-spacing", hwpx: true)
    }
}
