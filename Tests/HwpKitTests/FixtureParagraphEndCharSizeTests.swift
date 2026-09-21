import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 줄 캐시 없이 다시 조판한 문단이 문단 끝 글자(CR)의 글자 모양 크기를 마지막 줄에 반영해
/// 한글이 저장한 자리에 놓이는지 (#206).
///
/// 오라클은 한글이 저장한 줄 캐시(`PARA_LINE_SEG` — 한글이 배치한 절대 자리)다. 둘을 잰다:
/// ① `paragraph-end-char-size` 쌍(한글 12.30.0이 2026-09-21에 저장, 문단 끝 글자 모양이 본문과
/// 다른 48문단 + 셀 5문단, 5쪽) — 모든 문단의 캐시를 지우고 조판한 줄의 베이스라인이 캐시로 놓인
/// 줄과 쪽·자리 모두 같아야 한다 (한글 PDF 베이스라인과도 0.10pt 안). ② 이슈의 재현 조건 —
/// `noori` 첫 구역의 최상위 문단들에서 줄 캐시를 지우고 첫 쪽을 조판하면 2번째 문단(68.69pt
/// 글자처럼 취급 표 마커 10pt + 문단 끝 글자 16pt, 비율 170%)의 전진량이 79.89pt(= 68.69 +
/// 16 × 0.7)라 그 아래 제목 표의 상단이 227.00pt다. 종전에는 마커의 10pt만 보아 75.69pt →
/// 제목 표가 222.80pt로 4.20pt 올라갔다 (이슈 본문의 비교 화면). 폰트는 `testDeterministic` —
/// 줄 상자는 글꼴 지표의 함수가 아니다.
final class FixtureParagraphEndCharSizeTests: XCTestCase {
    /// 쪽의 `drawText` 명령(문단 조각) 하나가 그린 줄들 — 베이스라인 y(0.01pt 반올림)와 첫 줄
    /// 텍스트(개체 마커 U+FFFC를 뺀 첫 12자).
    private struct DrawnBlock {
        let page: Int
        let baselines: [Double]
        let firstText: String
    }

    private static func fixtureURL(_ id: String, hwpx: Bool) -> URL {
        hwpx
            ? FixtureRoot.url(from: #file, subdirectory: "HwpxFixtures")
            .appendingPathComponent(id).appendingPathComponent("document.hwpx")
            : FixtureRoot.url(from: #file).appendingPathComponent(id).appendingPathComponent("document.hwp")
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
    private static func drawnBlocks(_ id: String, hwpx: Bool, dropCaches: Bool) async throws -> [DrawnBlock] {
        let file = try CoreHwp.HwpFile(fromPath: fixtureURL(id, hwpx: hwpx).path)
        var sections = file.displaySectionArray
        if dropCaches {
            for index in sections.indices {
                sections[index].paragraph = droppingLineCaches(sections[index].paragraph)
            }
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file), fontResolver: .testDeterministic,
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
                    baselines: lines.map { (Double($0.baselineOrigin.y) * 100).rounded() / 100 },
                    firstText: String((attributedString.string as NSString)
                        .substring(with: first.stringRange)
                        .replacingOccurrences(of: "\u{FFFC}", with: "").prefix(12))
                ))
            }
            pageIndex += 1
        }
        return blocks
    }

    /// 문단 첫 12자(보이는 글자) → 한글이 저장한 줄 캐시의 줄 수 — 최상위 문단과 표 셀 안 문단.
    private static func cacheLineCounts(_ file: CoreHwp.HwpFile) -> [String: Int] {
        var counts: [String: Int] = [:]
        func walk(_ paragraphs: [CoreHwp.HwpParagraph]) {
            for paragraph in paragraphs {
                // 제어 문자(문단 끝 13·한 줄 끝 10)와 개체 마커는 뺀다 — 그려진 줄 텍스트도 마커
                // (U+FFFC)만 남기므로 첫 12자 열쇠에서 마커를 함께 지운다.
                let text = (paragraph.paraText?.charArray ?? []).compactMap { char -> String? in
                    guard char.type == .char, char.value >= 32, let scalar = UnicodeScalar(char.value)
                    else { return nil }
                    return String(scalar)
                }.joined()
                let key = String(text.prefix(12))
                if !key.isEmpty, counts[key] == nil {
                    counts[key] = paragraph.paraLineSeg.paraLineSegInternalArray.count
                }
                for control in paragraph.ctrlHeaderArray ?? [] {
                    guard case let .table(table) = control else { continue }
                    walk(table.cellArray.flatMap(\.paragraphArray))
                }
            }
        }
        walk(file.displaySectionArray.flatMap(\.paragraph))
        return counts
    }

    /// `paragraph-end-char-size` — 모든 문단의 캐시를 지우고 조판한 줄이 캐시로 놓인 줄과 같은 자리다
    /// (HWP·HWPX). 결정론 글꼴은 함초롬바탕과 줄바꿈이 달라 여러 줄 문단(A7·T1)의 줄 수가 한글 캐시와
    /// 다르므로(캐시 경로는 그 뒤 문단을 캐시 절대 자리에 두고 재조판은 줄 수만큼 당겨진다), CT 줄 수가
    /// 캐시 줄 수와 같은 문단 안의 줄 간격과 그런 문단 사이의 간격(앞 문단 마지막 줄 → 뒤 문단 첫 줄)만
    /// 견준다 — 줄 상자·전진량·문단 간격은 글꼴과 무관해서 이 값들은 정확히 같아야 한다. 종전에는
    /// `A1`부터 문단 끝 글자 크기만큼(16pt CR 5.1pt·40pt CR 25.6pt) 어긋났다.
    func testReflowedFixtureMatchesTheSavedLineCache() async throws {
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let file = try CoreHwp.HwpFile(fromPath: Self.fixtureURL("paragraph-end-char-size", hwpx: hwpx).path)
            let counts = Self.cacheLineCounts(file)
            let cachedBlocks = try await Self.drawnBlocks("paragraph-end-char-size", hwpx: hwpx, dropCaches: false)
            let reflowedBlocks = try await Self.drawnBlocks("paragraph-end-char-size", hwpx: hwpx, dropCaches: true)
            // 조각은 쪽 안에서 첫 줄 자리 순으로 본다 — 표 셀·호스트 문단의 방출 순서가 두 경로에서 다르다.
            let cached = cachedBlocks.sorted { ($0.page, $0.baselines[0]) < ($1.page, $1.baselines[0]) }
            let reflowed = reflowedBlocks.sorted { ($0.page, $0.baselines[0]) < ($1.page, $1.baselines[0]) }
            expect(cached.count).to(beGreaterThanOrEqualTo(55), description: label)
            expect(cached.map(\.page).max()) == 4
            expect(reflowed.count) == cached.count
            expect(reflowed.map(\.page)) == cached.map(\.page)
            // 문단 첫 줄 텍스트로 캐시 줄 수를 찾는다 — CT 줄 수가 캐시와 같은 문단만 견준다.
            func matchesCache(_ block: DrawnBlock) -> Bool {
                counts[block.firstText] == block.baselines.count
            }
            var comparedBlocks = 0
            var comparedGaps = 0
            for (index, pair) in zip(reflowed, cached).enumerated() {
                let (fresh, saved) = pair
                guard matchesCache(fresh), matchesCache(saved) else { continue }
                expect(fresh.firstText) == saved.firstText
                comparedBlocks += 1
                let deltas = { (block: DrawnBlock) in
                    zip(block.baselines.dropFirst(), block.baselines).map { $0 - $1 }
                }
                expect(deltas(fresh)).to(
                    beCloseTo(deltas(saved), within: 0.011), description: "\(label) \(fresh.firstText) 줄 간격"
                )
                guard index + 1 < reflowed.count, reflowed[index + 1].page == fresh.page,
                      matchesCache(reflowed[index + 1]), matchesCache(cached[index + 1]),
                      let lastFresh = fresh.baselines.last, let lastSaved = saved.baselines.last,
                      let nextFresh = reflowed[index + 1].baselines.first,
                      let nextSaved = cached[index + 1].baselines.first
                else { continue }
                comparedGaps += 1
                expect(nextFresh - lastFresh).to(
                    beCloseTo(nextSaved - lastSaved, within: 0.011),
                    description: "\(label) \(fresh.firstText) → \(reflowed[index + 1].firstText)"
                )
            }
            expect(comparedBlocks).to(beGreaterThanOrEqualTo(40), description: label)
            expect(comparedGaps).to(beGreaterThanOrEqualTo(30), description: label)
        }
    }

    /// 한글 PDF 실측 표본 — 쪽 번호(0-기준)와 베이스라인 y.
    private struct PdfSample {
        let prefix: String
        let page: Int
        let baseline: Double
    }

    /// 캐시 없이 조판한 줄의 절대 자리가 한글 PDF와 같다 (= 본문 상단 99.2 + `vertpos` +
    /// `baseline`, 0.12pt 장치 양자화). 여러 줄 문단 뒤의 절대 자리는 결정론 글꼴의 줄바꿈 차로
    /// 한글과 다르므로, 여러 줄 문단 앞이거나 쪽 나눔 뒤인 줄만 핀한다: A1 128.88(1쪽) · B9
    /// 112.80 · C6 282.60 · D1 첫 줄 308.52 · E4 558.12 · F5 681.48(2쪽) · G1 cell 114.24 · H1
    /// 176.28(3쪽) · T1 첫 줄 107.76(4쪽).
    func testReflowedFixtureMatchesTheHancomPdf() async throws {
        let samples = [
            PdfSample(prefix: "A1 ", page: 0, baseline: 128.88),
            PdfSample(prefix: "B9 ", page: 1, baseline: 112.80),
            PdfSample(prefix: "C6 ", page: 1, baseline: 282.60),
            PdfSample(prefix: "D1 ", page: 1, baseline: 308.52),
            PdfSample(prefix: "E4 ", page: 1, baseline: 558.12),
            PdfSample(prefix: "F5 ", page: 1, baseline: 681.48),
            PdfSample(prefix: "G1 cell 10", page: 2, baseline: 114.24),
            PdfSample(prefix: "H1 ", page: 2, baseline: 176.28),
            PdfSample(prefix: "T1 ", page: 3, baseline: 107.76),
        ]
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let reflowed = try await Self.drawnBlocks("paragraph-end-char-size", hwpx: hwpx, dropCaches: true)
            for sample in samples {
                let block = reflowed.first {
                    $0.page == sample.page && $0.firstText.hasPrefix(sample.prefix)
                }
                expect(block?.baselines.first).to(
                    beCloseTo(sample.baseline, within: 0.13), description: "\(label) \(sample.prefix)"
                )
            }
        }
    }

    private static func nooriFile(hwpx: Bool) throws -> CoreHwp.HwpFile {
        try CoreHwp.HwpFile(fromPath: fixtureURL("noori", hwpx: hwpx).path)
    }

    /// 첫 구역 최상위 문단들의 줄 캐시를 지운 첫 쪽 — 표 셀 안 문단의 캐시는 그대로다
    /// (이슈의 재현 조건).
    private static func reflowedFirstPage(hwpx: Bool) async throws -> HwpPage {
        let file = try nooriFile(hwpx: hwpx)
        var sections = file.displaySectionArray
        for index in sections[0].paragraph.indices {
            sections[0].paragraph[index].paraLineSeg.paraLineSegInternalArray = []
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file), fontResolver: .testDeterministic,
            imageStore: HwpImageStore(from: file)
        )
        let page = try await paginator.page(at: 0)
        return try XCTUnwrap(page)
    }

    private static func tableTops(_ page: HwpPage) -> [Double] {
        page.blocks.filter { $0.kind == .table }.map { Double($0.frame.minY) }
    }

    /// 캐시 없이 조판한 첫 쪽의 두 표 상단이 저장 캐시의 자리(140.59·227.00)와 같다 — 2번째
    /// 문단 블록의 높이가 전진량 79.89pt다. HWP·HWPX 둘 다.
    func testReflowedNooriKeepsTheTitleTableWhereTheSavedCachePutIt() async throws {
        for hwpx in [false, true] {
            let page = try await Self.reflowedFirstPage(hwpx: hwpx)
            let tops = Self.tableTops(page)
            expect(tops.count).to(beGreaterThanOrEqualTo(2), description: hwpx ? "HWPX" : "HWP")
            guard tops.count >= 2 else { continue }
            expect(tops[0]).to(beCloseTo(140.59, within: 0.01), description: hwpx ? "HWPX" : "HWP")
            expect(tops[1]).to(beCloseTo(227.0, within: 0.01), description: hwpx ? "HWPX" : "HWP")
            let host = page.blocks.first {
                $0.kind == .text && abs(Double($0.frame.minY) - 140.59) < 0.01
            }
            expect(host.map { Double($0.frame.height) }).to(beCloseTo(79.89, within: 0.01))
        }
    }

    /// 대조군 — 저장 캐시로 놓인 같은 쪽의 표 상단이 같은 값이다 (캐시 경로는 이 수정과
    /// 무관하게 종전부터 227.00이었다).
    func testCachedNooriTitleTableTop() async throws {
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("noori").appendingPathComponent("document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        let page = try XCTUnwrap(document.pages.first)
        let tops = Self.tableTops(page)
        expect(Array(tops.prefix(2))).to(beCloseTo([140.59, 227.0], within: 0.01))
    }
}
