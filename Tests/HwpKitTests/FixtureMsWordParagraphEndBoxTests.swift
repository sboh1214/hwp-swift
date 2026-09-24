import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// MS 워드 호환 문서에서 본문보다 높은 문단 끝 글자(CR)·한 줄 끝(LF)과 글자처럼 취급 개체가
/// 줄 상자에 드는 규칙(#223)이 한글이 저장한 자리와 같은지 — `ms-word-paragraph-end-box` 쌍.
///
/// 오라클은 한컴오피스 한글 12.30.0(build 6446)이 2026-09-25에 같은 편집 세션에서 저장한 줄
/// 캐시와 PDF다. 문서는 시스템 글꼴(Apple SD 산돌고딕 Neo·Menlo·Helvetica·Times New Roman)만
/// 쓰므로 기본 resolver(시스템 글꼴, 한컴 번들 off)로 조판한다 — MS 워드 호환 줄 상자는 글꼴
/// 지표의 함수라 결정론 resolver(Menlo 일색)로는 한글의 자리와 견줄 수 없다. 그 글꼴들의 지표가
/// 한글이 잰 값과 다른 기기(다른 판의 글꼴)에서는 건너뛴다.
///
/// 종전(#194의 축별 최댓값)에는 끝 글자·한 줄 끝이 본문보다 높은 줄마다 본문 글자 상자의
/// 베이스라인 아래 몫(Apple SD/Menlo 10pt 4.57pt)만큼 짧아 다음 줄이 그만큼 위로 당겨졌고,
/// 글자 상자 안쪽의 개체 줄은 거꾸로 부풀었다 (Apple SD 20pt 줄 + 25pt 표: 34.12 vs 한글 31.19).
final class FixtureMsWordParagraphEndBoxTests: XCTestCase {
    private static let fixture = "ms-word-paragraph-end-box"

    /// 쪽의 `drawText` 명령 하나가 그린 줄들 — 베이스라인 y와 첫 줄 텍스트(개체 마커를 뺀 첫 12자).
    private struct DrawnBlock {
        let page: Int
        let baselines: [CGFloat]
        let firstText: String
        let lines: [HwpDrawnLine]
        let attributedString: NSAttributedString
    }

    private static func fixtureURL(hwpx: Bool) -> URL {
        hwpx
            ? FixtureRoot.url(from: #file, subdirectory: "HwpxFixtures")
            .appendingPathComponent(fixture).appendingPathComponent("document.hwpx")
            : FixtureRoot.url(from: #file).appendingPathComponent(fixture)
            .appendingPathComponent("document.hwp")
    }

    /// 문서가 쓰는 시스템 글꼴의 MS 워드 상자가 한글이 잰 값과 같은 기기에서만 돈다 (em).
    private func skipUnlessOracleFonts() throws {
        let expected: [(name: String, lineHeight: CGFloat, baseline: CGFloat)] = [
            ("AppleSDGothicNeo-Regular", 1.56, 1.08), ("Menlo-Regular", 1.5132, 1.1028),
            ("Helvetica", 1.1753, 0.9502), ("TimesNewRomanPSMT", 1.1499, 0.9336),
        ]
        for font in expected {
            let ctFont = CTFontCreateWithName(font.name as CFString, 10, nil)
            let box = HwpMsWordLineBox.metrics(of: ctFont)
            try XCTSkipUnless(
                (CTFontCopyPostScriptName(ctFont) as String) == font.name
                    && abs(box.lineHeight - font.lineHeight) < 0.002
                    && abs(box.baseline - font.baseline) < 0.002,
                "\(font.name)의 지표가 한글 실측 기기와 다르다"
            )
        }
    }

    /// 모든 문단(표 셀 안 포함)의 줄 캐시를 지운 사본.
    private static func droppingLineCaches(_ paragraphs: [CoreHwp.HwpParagraph]) -> [CoreHwp.HwpParagraph] {
        paragraphs.map { paragraph in
            var copy = paragraph
            copy.paraLineSeg.paraLineSegInternalArray = []
            copy.ctrlHeaderArray = copy.ctrlHeaderArray?.map { control in
                guard case var .table(table) = control else { return control }
                table.cellArray = table.cellArray.map { cell in
                    var cell = cell
                    cell.paragraphArray = droppingLineCaches(cell.paragraphArray)
                    return cell
                }
                return .table(table)
            }
            return copy
        }
    }

    /// 문서의 모든 쪽에서 그려지는 문단 조각 — `dropCaches`면 줄 캐시 없이 조판한다.
    private static func drawnBlocks(hwpx: Bool, dropCaches: Bool) async throws -> [DrawnBlock] {
        let file = try CoreHwp.HwpFile(fromPath: fixtureURL(hwpx: hwpx).path)
        var sections = file.displaySectionArray
        if dropCaches {
            for index in sections.indices {
                sections[index].paragraph = droppingLineCaches(sections[index].paragraph)
            }
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file),
            fontResolver: HwpFontResolver(usesInstalledHancomFonts: false),
            imageStore: HwpImageStore(from: file)
        )
        var blocks: [DrawnBlock] = []
        var pageIndex = 0
        while let page = try await paginator.page(at: pageIndex) {
            for command in page.paintList.commands {
                guard case let .drawText(attributedString, origin, lineWidth) = command else { continue }
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: attributedString, origin: origin, lineWidth: lineWidth
                )
                guard let first = lines.first else { continue }
                blocks.append(DrawnBlock(
                    page: pageIndex,
                    baselines: lines.map(\.baselineOrigin.y),
                    firstText: String((attributedString.string as NSString)
                        .substring(with: first.stringRange)
                        .replacingOccurrences(of: "\u{FFFC}", with: "").prefix(12)),
                    lines: lines,
                    attributedString: attributedString
                ))
            }
            pageIndex += 1
        }
        return blocks.sorted { ($0.page, $0.baselines[0]) < ($1.page, $1.baselines[0]) }
    }

    /// 캐시를 지우고 다시 조판한 줄이 한글 캐시로 놓인 줄과 같은 쪽·같은 **줄 간격**이다 (HWP·HWPX).
    /// 줄 간격(앞 줄 베이스라인 → 이 줄 베이스라인)으로 견주는 이유는 한글의 글꼴 상자 반올림
    /// (±0.03pt/줄, `HwpMsWordLineBox` #194 남은 격차)이 쪽 아래로 누적되기 때문이다 — 규칙이
    /// 틀리면 끝 글자가 큰 줄마다 4pt 넘게 어긋난다 (종전 코드: A1 → A2가 4.57pt 짧았다).
    func testReflowedFixtureMatchesTheSavedLineCache() async throws {
        try skipUnlessOracleFonts()
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let cached = try await Self.drawnBlocks(hwpx: hwpx, dropCaches: false)
            let reflowed = try await Self.drawnBlocks(hwpx: hwpx, dropCaches: true)
            expect(cached.count).to(beGreaterThanOrEqualTo(25), description: label)
            expect(reflowed.map(\.page)) == cached.map(\.page)
            expect(reflowed.map(\.firstText)) == cached.map(\.firstText)
            expect(reflowed.map(\.baselines.count)) == cached.map(\.baselines.count)
            let freshLines = reflowed.flatMap { block in block.baselines.map { (block.page, $0) } }
            let savedLines = cached.flatMap { block in block.baselines.map { (block.page, $0) } }
            var compared = 0
            for index in freshLines.indices.dropFirst() where index < savedLines.count {
                guard freshLines[index].0 == freshLines[index - 1].0,
                      savedLines[index].0 == savedLines[index - 1].0
                else { continue }
                compared += 1
                let freshGap = freshLines[index].1 - freshLines[index - 1].1
                let savedGap = savedLines[index].1 - savedLines[index - 1].1
                expect(freshGap).to(
                    beCloseTo(savedGap, within: 0.2), description: "\(label) 줄 \(index)"
                )
            }
            expect(compared).to(beGreaterThanOrEqualTo(25), description: label)
        }
    }

    /// 한글 PDF 실측 표본 — 쪽 번호(0-기준)·베이스라인 y (쪽 위에서부터, 0.12pt 장치 양자화).
    private struct PdfSample {
        let prefix: String
        let page: Int
        let baseline: CGFloat
    }

    /// 캐시 없이 조판한 줄의 절대 자리가 한글 PDF와 같다 — 쪽 첫머리에서 가까운 줄만 핀한다(글꼴 상자
    /// 반올림 누적을 피한다). A1 줄(28.79pt 상자) 뒤의 A2가 종전보다 4.57pt 아래, 개체 줄 O1·O2
    /// 뒤와 글자 상자 안쪽 개체 줄(오삼) 뒤가 한글 자리다.
    func testReflowedFixtureMatchesTheHancomPdf() async throws {
        try skipUnlessOracleFonts()
        let samples = [
            PdfSample(prefix: "A1 ", page: 0, baseline: 132.00),
            PdfSample(prefix: "A2 ", page: 0, baseline: 168.84),
            PdfSample(prefix: "A3 ", page: 0, baseline: 193.68),
            PdfSample(prefix: "L4 ", page: 1, baseline: 116.88),
            PdfSample(prefix: "L5 ", page: 1, baseline: 173.28),
            PdfSample(prefix: "O1 ", page: 2, baseline: 129.24),
            PdfSample(prefix: "O2 ", page: 2, baseline: 174.36),
            PdfSample(prefix: "오삼", page: 2, baseline: 218.52),
            PdfSample(prefix: "U1 ", page: 2, baseline: 300.12),
        ]
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let reflowed = try await Self.drawnBlocks(hwpx: hwpx, dropCaches: true)
            for sample in samples {
                let block = reflowed.first { $0.page == sample.page && $0.firstText.hasPrefix(sample.prefix) }
                expect(block).toNot(beNil(), description: "\(label) \(sample.prefix)")
                guard let block else { continue }
                expect(block.baselines[0]).to(
                    beCloseTo(sample.baseline, within: 0.25), description: "\(label) \(sample.prefix)"
                )
            }
        }
    }

    /// 밑줄 표본 — 한글 PDF의 밑줄 중심이 베이스라인에서 떨어진 거리(아래 +, 위 −)와 두께.
    private struct UnderlineSample {
        let prefix: String
        let above: Bool
        let offset: CGFloat
        let thickness: CGFloat
    }

    /// 밑줄은 줄 상자의 가장자리에서 **글자 상자의** cell × 0.129만큼 안쪽이다 — 끝 글자가 쌓인 줄
    /// (U1 9.60 아래·U2 7.08 아래), 30pt 표 줄의 위 밑줄(U3 28.56 위 = 표 윗변 아래), 글자 상자
    /// 안쪽 개체가 베이스라인을 상자 바닥 가까이 내린 줄(유사: 밑줄이 베이스라인 **위** 1.80). 종전
    /// 산식은 U1 4.1 아래·U3 11.0 위·유사 5.2 아래였다.
    func testUnderlinesSitOnTheLineBoxEdgesWithTheTextCell() async throws {
        try skipUnlessOracleFonts()
        let samples = [
            UnderlineSample(prefix: "U1 ", above: false, offset: 9.60, thickness: 0.60),
            UnderlineSample(prefix: "U2 ", above: false, offset: 7.08, thickness: 0.60),
            UnderlineSample(prefix: "U3 ", above: true, offset: -28.56, thickness: 0.60),
            UnderlineSample(prefix: "유사", above: false, offset: -1.80, thickness: 1.20),
        ]
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let reflowed = try await Self.drawnBlocks(hwpx: hwpx, dropCaches: true)
            for sample in samples {
                let block = reflowed.first { $0.firstText.hasPrefix(sample.prefix) }
                let line = try XCTUnwrap(block?.lines.first, "\(label) \(sample.prefix)")
                let box = try XCTUnwrap(
                    HwpDrawnTextLayout.msWordLineBox(of: line.line, endsParagraph: line.endsParagraph),
                    "\(label) \(sample.prefix)"
                )
                let geometry = sample.above
                    ? HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box)
                    : HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
                // 기하의 중심은 위가 +다 — 표본은 쪽 좌표(아래가 +)라 부호를 뒤집는다.
                expect(-geometry.center).to(
                    beCloseTo(sample.offset, within: 0.15), description: "\(label) \(sample.prefix)"
                )
                expect(geometry.thickness).to(
                    beCloseTo(sample.thickness, within: 0.07), description: "\(label) \(sample.prefix) 두께"
                )
            }
        }
    }
}
