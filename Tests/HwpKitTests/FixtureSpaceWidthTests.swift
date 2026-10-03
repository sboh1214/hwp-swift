import CoreGraphics
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `space-width`·`ms-word-space-width` 쌍의 실물 핀 (#249) — 빈칸 폭은 라틴 슬롯이 아니라
/// **한글 슬롯** 글자 크기 × 0.5 × 한글 장평이고(`HwpRenderTuning.Text.fixedSpaceEmRatio`),
/// '글꼴에 어울리는 빈칸'은 라틴 글꼴 빈칸 em × 앞 글자 슬롯 크기, MS 워드 호환 문서는 앞뒤가 모두
/// 라틴 부류 글자인 빈칸만 라틴 글꼴 고유 폭이다. 묶음 빈칸은 고정 폭, 고정폭 빈칸은 그 절반이다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-03, 벡터 글자 원점, 쪽 왼쪽에서
/// pt). 기본 크기 20pt, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo라 결정론
/// resolver(`HwpFontResolver.testDeterministic`)가 같은 글꼴을 고르고, 문단마다 한 줄이라 줄 시작이
/// 같다 — 그래서 글자 원점을 쪽 좌표 그대로 핀한다. 수정 전(빈칸 = 라틴 슬롯의 0.5em, 호환 문서는 늘
/// 글꼴 폭)에는 문단 13개 중 11개가 6.0~21.1pt 어긋났고, 수정 뒤에는 두 포맷 모두 0.18pt 안이다
/// (Menlo 10pt 글자 폭이 0.12pt 장치 단위로 쌓인 몫).
///
/// | 문서 | 문단 | 글자 모양 (한글 / 라틴) | 빈칸 |
/// |---|---|---|---|
/// | 한글 | 1 | 50% / 100% | 한글·라틴·숫자 사이 모두 5pt |
/// | 한글 | 2 | 100% / 50% | 10pt |
/// | 한글 | 3 | 50% / 100% | 줄 시작·연속 빈칸 5pt |
/// | 한글 | 4 | 장평 50% / 장평 50% | 한글 장평만 따라 5pt |
/// | 한글 | 5 | 50% / 100%, 글꼴 빈칸 | 한글 뒤 Menlo × 10pt, 라틴 뒤 Menlo × 20pt |
/// | 한글 | 6 | 같은 폭의 다른 글자 모양 run, 글꼴 빈칸 | 새 run 첫 빈칸은 라틴 (Menlo × 20pt) |
/// | 한글 | 7 | 50% / 100% | 묶음 빈칸 5pt·고정폭 빈칸 2.5pt |
/// | MS 워드 | 1 | 50% / 100% | 라틴 사이 Menlo 20pt 고유 폭, 한글 앞뒤 5pt |
/// | MS 워드 | 2 | 50% / 100% | 줄 시작·연속 빈칸 5pt |
/// | MS 워드 | 3 | 100% / 50% | 구두점 뒤 Menlo 10pt 고유 폭, `½` 앞뒤 10pt |
/// | MS 워드 | 4 | 같은 폭의 다른 글자 모양 run | run 경계를 넘은 라틴 이웃도 고유 폭 |
/// | MS 워드 | 5 | 50% / 100%, 글꼴 빈칸 | 한글 문서와 같다 |
/// | MS 워드 | 6 | 50% / 100% | 묶음 빈칸 5pt·고정폭 빈칸 2.5pt |
final class FixtureSpaceWidthTests: XCTestCase {
    /// 한글 PDF의 0.12pt 장치 양자화와 그것이 한 줄에 쌓인 몫 (실측 최대 0.18pt).
    private static let tolerance: CGFloat = 0.25

    private struct Row {
        let paragraph: Int
        let text: String
        let origins: [CGFloat]

        init(_ paragraph: Int, _ text: String, _ origins: [CGFloat]) {
            self.paragraph = paragraph
            self.text = text
            self.origins = origins
        }
    }

    private static let hwpRows = [
        Row(1, "가나abcd12", [85.08, 93.72, 107.40, 119.40, 136.44, 148.44, 165.48, 177.60]),
        Row(2, "abcd가나다라", [85.08, 91.08, 107.16, 113.16, 129.24, 146.52, 173.88, 191.16]),
        Row(3, "abcd", [90.12, 102.12, 124.20, 136.20]),
        Row(4, "abcd가나", [85.08, 91.08, 102.12, 108.12, 119.04, 127.68]),
        Row(5, "가나abcd", [85.08, 93.72, 108.36, 120.48, 144.48, 156.60]),
        Row(6, "가나ab", [85.08, 93.72, 114.36, 126.48]),
        Row(7, "abcdef", [85.08, 97.08, 114.12, 126.24, 140.76, 152.76]),
    ]

    private static let msWordRows = [
        Row(1, "abcd가나ef", [85.08, 97.08, 121.20, 133.20, 150.24, 158.88, 172.56, 184.56]),
        Row(2, "abcd", [90.12, 102.12, 124.20, 136.20]),
        Row(3, "ab,cd½ef", [85.08, 91.08, 97.20, 109.20, 115.32, 131.28, 147.36, 153.36]),
        Row(4, "abcd", [85.08, 97.08, 121.20, 133.20]),
        Row(5, "가나abcd", [85.08, 93.72, 108.36, 120.48, 144.48, 156.60]),
        Row(6, "abcdef", [85.08, 97.08, 114.12, 126.24, 140.76, 152.76]),
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

    /// 문단 꼬리표(` #k`, 5pt) 번호 → 그 문단의 보이는 글자(꼬리표·빈칸 제외)와 쪽 x 원점.
    private static func glyphOrigins(_ page: HwpPage) -> [Int: [(Character, CGFloat)]] {
        var rows: [Int: [(Character, CGFloat)]] = [:]
        for command in page.paintList.commands {
            guard case let .drawText(attributedString, origin, lineWidth) = command else {
                continue
            }
            let string = attributedString.string as NSString
            let tag = string.range(of: " #", options: .backwards)
            guard tag.location != NSNotFound,
                  let paragraph = Int(string.substring(from: NSMaxRange(tag))
                      .trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }
            var glyphs: [(Character, CGFloat)] = []
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            for line in lines {
                for run in CTLineGetGlyphRuns(line.line) as? [CTRun] ?? [] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    // 꼬리표(5pt)는 빼고 표본 글자(20pt)만 본다.
                    guard let fontValue = attributes[kCTFontAttributeName],
                          CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID(),
                          CTFontGetSize(unsafeBitCast(fontValue as CFTypeRef, to: CTFont.self)) > 6
                    else { continue }
                    let count = CTRunGetGlyphCount(run)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                    // 위치는 텍스트 공간 값이다 — 장평 행렬(`CTRunGetTextMatrix`)을 씌워야 그려지는
                    // 자리가 된다 (장평 50% run에서 그대로 쓰면 간격이 두 배로 읽힌다).
                    let textMatrix = CTRunGetTextMatrix(run)
                    for (position, index) in zip(positions, indices) where index < tag.location {
                        let scalar = Unicode.Scalar(string.character(at: index)).map(Character.init)
                        guard let scalar, !scalar.isWhitespace, scalar != "\u{FFFC}" else {
                            continue
                        }
                        let x = line.baselineOrigin.x + position.applying(textMatrix).x
                        glyphs.append((scalar, x))
                    }
                }
            }
            rows[paragraph] = glyphs.sorted { $0.1 < $1.1 }
        }
        return rows
    }

    private func assertRows(_ rows: [Row], id: String, hwpx: Bool) async throws {
        let page = try await Self.firstPage(id, hwpx: hwpx)
        let measured = Self.glyphOrigins(page)
        let format = hwpx ? "HWPX" : "HWP"
        for row in rows {
            let label = "\(id) \(format) #\(row.paragraph)"
            let glyphs = try XCTUnwrap(measured[row.paragraph], label)
            expect(String(glyphs.map(\.0))).to(equal(row.text), description: label)
            for (glyph, expected) in zip(glyphs, row.origins) {
                expect(glyph.1).to(
                    beCloseTo(expected, within: Self.tolerance),
                    description: "\(label) '\(glyph.0)'"
                )
            }
        }
    }

    func testHangulDocumentSpacesMatchHancom() async throws {
        try await assertRows(Self.hwpRows, id: "space-width", hwpx: false)
        try await assertRows(Self.hwpRows, id: "space-width", hwpx: true)
    }

    func testMsWordDocumentSpacesMatchHancom() async throws {
        try await assertRows(Self.msWordRows, id: "ms-word-space-width", hwpx: false)
        try await assertRows(Self.msWordRows, id: "ms-word-space-width", hwpx: true)
    }
}
