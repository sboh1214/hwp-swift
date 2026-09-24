import CoreGraphics
@testable import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 글자처럼 취급 개체를 실은 마커의 글자 모양 크기가 줄 상자에 들지 않는지 (#217) —
/// `inline-object-marker-size` HWP·HWPX 쌍.
///
/// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-24)이 같은 편집 세션에서 저장한 줄 캐시
/// (`PARA_LINE_SEG` — 본문 상단 99.2 + `vertpos` + `baseline`)와 내보낸 PDF다 — 둘은 0.10pt
/// (한글 PDF의 장치 양자화) 안에서 같다 (`Fixtures/inline-object-marker-size/README.md`의 표).
/// 함초롬바탕 10pt 글에 40pt(대부분) 글자 모양 마커로 그림·표를 넣은 문단들이고, 한글은 그 마커
/// 크기를 줄 상자에 넣지 않고 비율 여분의 기준에만 넣는다. 종전에는 마커 크기가 상자였다 —
/// K3(20pt 그림) 줄 자신은 베이스라인이 17pt 아래였고 뒤 문단은 그런 줄마다 줄 상자 차이(K3 20pt·
/// K7 30pt)만큼 밀려 누적됐으며, 한글이 저장한 캐시보다 높게 잰 줄이 낡은 캐시로 판정돼 버려지면서
/// **캐시가 있는 저장본도** 2쪽이 3쪽이 됐다.
///
/// 네 경로를 모두 잰다: 두 포맷 × 저장된 줄 캐시로 놓기 · 캐시를 지우고 다시 조판하기. 폰트는
/// `HwpFontResolver.testDeterministic`이다 — 한글 문서의 줄 상자는 글꼴 지표의 함수가 아니고,
/// 이 문서의 줄바꿈은 글꼴과 무관하게 같다 (40pt 글의 `C5`만 그림이 다음 줄로 넘어가지만 두 줄
/// 모두 40pt 상자라 베이스라인은 같다).
final class FixtureInlineObjectMarkerSizeTests: XCTestCase {
    private static let id = "inline-object-marker-size"

    /// 한글 줄 캐시의 베이스라인 — 쪽(0-기준), 쪽 좌표 y, 그 줄의 첫 보이는 글자(개체 마커 U+FFFC는
    /// 뺀다, 개체만 있는 줄은 빈 문자열, nil은 글꼴에 따라 줄 내용이 달라 보지 않는 줄 — `C5`의
    /// 둘째 줄은 결정론 글꼴에서 그림을 함께 싣는다). 표 셀 안 `X1`~`X3`은 셀 문단 캐시에 표 자리를
    /// 더한 값이고 한글 PDF로는 500.16·542.64·578.16이다.
    private static let hancomLines: [Line] = [
        Line(0, 107.7, "#217"), Line(0, 143.2, "K1 "), Line(0, 190.2, "K3 "), Line(0, 251.2, ""),
        Line(0, 289.7, "K7 "), Line(0, 323.7, "K9 "), Line(0, 362.7, "M1 "), Line(0, 408.2, "T1 "),
        Line(0, 443.7, "R1 "), Line(0, 479.4, "W1 "), Line(0, 539.2, "F1 "), Line(0, 603.2, "E1 "),
        Line(0, 641.7, ""), Line(0, 701.2, ""),
        Line(1, 107.7, "N1 "), Line(1, 140.0, ""), Line(1, 173.7, " 뒤"),
        Line(1, 207.7, "N2 "), Line(1, 222.0, ""), Line(1, 237.7, " 뒤"),
        Line(1, 262.2, "S1 "), Line(1, 292.2, "S2 "), Line(1, 308.7, "S3 "), Line(1, 329.2, "S4 "),
        Line(1, 359.2, "S5 "), Line(1, 396.2, "C5 "), Line(1, 460.2, nil),
        Line(1, 500.11, "X1 "), Line(1, 542.61, "X2 "), Line(1, 578.11, "X3 "),
        Line(1, 589.52, "H1 "), Line(1, 599.52, "Z "),
    ]

    /// 한글 PDF의 그림 상단 (쪽, y) — 문서 순서, 같은 줄의 그림은 한 번만. `C5`의 그림은
    /// 결정론 글꼴에서 다음 줄로 넘어가므로 뺀다. 개체 상단 = 베이스라인 − 0.85 × 바깥 상자
    /// (#195)라 줄 자리가 맞으면 따라온다 — K3 173.27 · K7 282.95 · 개체만 있는 `N1` 가운데
    /// 줄 133.19 · 셀 안 `X2` 525.58.
    private static let hancomImageTops: [(page: Int, top: Double)] = [
        (0, 173.27), (0, 282.95), (0, 316.91), (0, 344.27), (0, 436.90), (0, 469.18),
        (0, 472.66), (0, 505.18), (0, 596.38), (0, 634.89), (0, 694.41),
        (1, 100.92), (1, 133.19), (1, 166.91), (1, 200.99), (1, 215.27), (1, 230.99),
        (1, 245.27), (1, 275.27), (1, 301.91), (1, 312.23), (1, 342.23),
        (1, 493.30), (1, 525.58),
    ]

    /// 한글 PDF의 장치 양자화(0.12pt) + 우리 반올림 몫.
    private static let tolerance = 0.13

    func testCachedHwpLinesSitWhereHancomSavedThem() async throws {
        try await Self.assertLines(hwpx: false, dropCaches: false)
    }

    func testReflowedHwpLinesSitWhereHancomSavedThem() async throws {
        try await Self.assertLines(hwpx: false, dropCaches: true)
    }

    func testCachedHwpxLinesSitWhereHancomSavedThem() async throws {
        try await Self.assertLines(hwpx: true, dropCaches: false)
    }

    func testReflowedHwpxLinesSitWhereHancomSavedThem() async throws {
        try await Self.assertLines(hwpx: true, dropCaches: true)
    }

    /// 그림 상단도 한글 자리다 — 두 포맷 × 두 경로.
    func testImagesSitWhereHancomDrawsThem() async throws {
        for hwpx in [false, true] {
            for dropCaches in [false, true] {
                let label = "\(hwpx ? "HWPX" : "HWP")\(dropCaches ? " 재조판" : " 캐시")"
                let pages = try await Self.pages(hwpx: hwpx, dropCaches: dropCaches)
                let tops = Self.imageTops(in: pages)
                expect(tops.count).to(equal(Self.hancomImageTops.count), description: label)
                for (actual, expected) in zip(tops, Self.hancomImageTops) {
                    expect(actual.page).to(equal(expected.page), description: label)
                    expect(actual.top).to(
                        beCloseTo(expected.top, within: Self.tolerance),
                        description: "\(label) \(expected)"
                    )
                }
            }
        }
    }

    /// 낡은 줄 캐시 — 개체 마커로 끝나는 문단의 문단 끝 글자(CR)가 캐시 줄보다 크면 그 캐시는
    /// 낡았다 (#217 PR 리뷰). 개체 마커의 글꼴은 낡음 판정에서 빠지므로(#217) 그런 문단의 40pt를
    /// 알려 주는 것은 CR의 기본 크기뿐이다 — 한글도 CR 크기를 마지막 줄 상자에 넣는다(#206).
    ///
    /// `E1`(10pt 글 + 40pt 마커의 8pt 그림 + 40pt CR)의 캐시 줄을 10pt로 낮추고 같은 쪽 뒤 문단의
    /// 캐시 위치를 그만큼(30pt) 당겨, E1의 CR이 10pt이던 때 저장된 캐시처럼 만든다. 그 캐시를 믿으면
    /// E1의 그려지는 줄 상자(40)가 뒤 `O1` 줄을 덮는다. 낡은 캐시로 판정하면 E1을 다시 조판한 높이로
    /// 놓고 뒤 문단을 30pt 밀어 한글이 저장한 자리(`O1` 641.7 · `O2` 701.2)로 온다. 두 포맷 모두.
    func testStaleCacheIsDetectedByTheParagraphEndSizeBehindAnObjectMarker() async throws {
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let pages = try await Self.pages(hwpx: hwpx) { paragraphs in
                try Self.shrinkingCache(of: "E1 ", in: paragraphs, to: 1000, pullingFollowers: true)
            }
            let lines = Self.drawnLines(in: pages).filter { $0.page == 0 }
            let expected = Self.hancomLines.filter { $0.page == 0 }
            expect(lines.map(\.baseline))
                .to(beCloseTo(expected.map(\.baseline), within: 0.011), description: label)
        }
    }

    /// 리뷰의 재현 — 그림만 있는 `O2`(40pt 마커의 8pt 그림 + 40pt CR)의 캐시 줄을 10pt로 낮추면
    /// 그 문단 블록은 캐시 높이(10 + 24)가 아니라 다시 조판한 높이(40 + 24)다. 두 포맷 모두.
    func testStaleCacheOfAnObjectOnlyParagraphTakesTheReflowedHeight() async throws {
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let pages = try await Self.pages(hwpx: hwpx) { paragraphs in
                try Self.shrinkingCache(of: nil, in: paragraphs, to: 1000, pullingFollowers: false)
            }
            let block = pages.first?.blocks.filter { $0.kind == .text }
                .max { $0.frame.minY < $1.frame.minY }
            expect(block.map { Double($0.frame.height) })
                .to(beCloseTo(64, within: 0.011), description: label)
        }
    }

    // MARK: 헬퍼

    /// 줄 하나 — 쪽(0-기준), 쪽 좌표 베이스라인, 첫 보이는 글자 (`hancomLines`의 규약).
    private struct Line {
        let page: Int
        let baseline: Double
        let prefix: String?

        init(_ page: Int, _ baseline: Double, _ prefix: String?) {
            self.page = page
            self.baseline = baseline
            self.prefix = prefix
        }
    }

    private static func fixtureURL(hwpx: Bool) -> URL {
        FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
            .appendingPathComponent(id)
            .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
    }

    /// 모든 문단(표 셀 안 포함)의 줄 캐시를 지운 사본.
    private static func droppingLineCaches(
        _ paragraphs: [CoreHwp.HwpParagraph]
    ) -> [CoreHwp.HwpParagraph] {
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

    /// 문서의 모든 쪽 — `dropCaches`면 줄 캐시 없이 조판한다.
    private static func pages(hwpx: Bool, dropCaches: Bool) async throws -> [HwpPage] {
        try await pages(hwpx: hwpx) { dropCaches ? droppingLineCaches($0) : $0 }
    }

    /// 문서의 모든 쪽 — 최상위 문단을 `edit`으로 바꾼 뒤 조판한다.
    private static func pages(
        hwpx: Bool, editing edit: ([CoreHwp.HwpParagraph]) throws -> [CoreHwp.HwpParagraph]
    ) async throws -> [HwpPage] {
        let file = try CoreHwp.HwpFile(fromPath: fixtureURL(hwpx: hwpx).path)
        var sections = file.displaySectionArray
        for index in sections.indices {
            sections[index].paragraph = try edit(sections[index].paragraph)
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file), fontResolver: .testDeterministic,
            imageStore: HwpImageStore(from: file)
        )
        var pages: [HwpPage] = []
        while let page = try await paginator.page(at: pages.count) {
            pages.append(page)
        }
        return pages
    }

    /// 그려지는 줄 — 쪽·첫 줄 자리 순. 빈칸뿐인 줄(표 `T1`의 빈 셀 문단)은 뺀다; 개체 마커만
    /// 있는 줄(`K5`·`O1`·`O2`·개체만 남은 가운데 줄)은 남긴다.
    private static func drawnLines(in pages: [HwpPage]) -> [Line] {
        var lines: [Line] = []
        for (pageIndex, page) in pages.enumerated() {
            for command in page.paintList.commands {
                guard case let .drawText(attributedString, origin, lineWidth) = command else {
                    continue
                }
                for line in HwpDrawnTextLayout.lines(
                    attributedString: attributedString, origin: origin, lineWidth: lineWidth
                ) {
                    let text = (attributedString.string as NSString)
                        .substring(with: line.stringRange)
                    guard text.contains(where: { !$0.isWhitespace }) else { continue }
                    lines.append(Line(
                        pageIndex, Double(line.baselineOrigin.y),
                        text.replacingOccurrences(of: "\u{FFFC}", with: "")
                    ))
                }
            }
        }
        return lines.sorted { ($0.page, $0.baseline) < ($1.page, $1.baseline) }
    }

    private static func assertLines(hwpx: Bool, dropCaches: Bool) async throws {
        let label = "\(hwpx ? "HWPX" : "HWP")\(dropCaches ? " 재조판" : " 캐시")"
        let pages = try await pages(hwpx: hwpx, dropCaches: dropCaches)
        expect(pages.count).to(equal(2), description: label)
        let lines = drawnLines(in: pages)
        expect(lines.count).to(equal(hancomLines.count), description: label)
        guard lines.count == hancomLines.count else {
            fail("\(label) 줄: \(lines.map { "\($0.page) \($0.baseline) \($0.prefix ?? "")" })")
            return
        }
        for (actual, expected) in zip(lines, hancomLines) {
            let description =
                "\(label) \(expected.page)쪽 \(expected.baseline) \(expected.prefix ?? "")"
            expect(actual.page).to(equal(expected.page), description: description)
            expect(actual.baseline)
                .to(beCloseTo(expected.baseline, within: 0.011), description: description)
            switch expected.prefix {
            case .none:
                break
            case let .some(prefix) where prefix.isEmpty:
                expect((actual.prefix ?? "").trimmingCharacters(in: .whitespaces))
                    .to(beEmpty(), description: description)
            case let .some(prefix):
                expect(actual.prefix ?? "").to(beginWith(prefix), description: description)
            }
        }
    }

    /// 그림 블록(최상위 그림과 자리 차지 표 셀 안 그림)의 상단 — 쪽·자리 순, 같은 줄(같은 상단)은
    /// 하나로 접는다. 결정론 글꼴에서 다음 줄로 넘어가는 `C5`의 그림(2쪽 443.2)은 뺀다.
    private static func imageTops(in pages: [HwpPage]) -> [(page: Int, top: Double)] {
        var tops: [(page: Int, top: Double)] = []
        for (pageIndex, page) in pages.enumerated() {
            var pageTops: [Double] = []
            for block in page.blocks where block.role == .body {
                switch block.payload {
                case .image:
                    pageTops.append(Double(block.frame.minY))
                case let .table(table):
                    for row in table.rows {
                        for cell in row.cells {
                            pageTops += cell.images.map { Double(block.frame.minY + $0.rect.minY) }
                        }
                    }
                default:
                    break
                }
            }
            let unique = Set(pageTops.map { ($0 * 100).rounded() / 100 }).sorted()
            tops += unique.filter { !(pageIndex == 1 && abs($0 - 443.2) < 0.05) }
                .map { (pageIndex, $0) }
        }
        return tops
    }

    /// 1쪽 최상위 문단 가운데 `prefix`로 시작하는 문단(nil이면 1쪽 마지막 문단 — 그림만 있는
    /// `O2`)의 캐시 줄 높이를 `height`(HWPUNIT)로 낮춘다 — 베이스라인도 0.85배로. `pullingFollowers`면
    /// 같은 쪽 뒤 문단의 캐시 위치를 줄어든 만큼 당겨, 그 크기로 저장된 캐시처럼 만든다.
    private static func shrinkingCache(
        of prefix: String?, in paragraphs: [CoreHwp.HwpParagraph],
        to height: Int32, pullingFollowers: Bool
    ) throws -> [CoreHwp.HwpParagraph] {
        // 2쪽은 쪽 나누기가 걸린 `N1`부터다.
        let pageBreak = try XCTUnwrap(paragraphs.firstIndex { paragraphText($0).hasPrefix("N1 ") })
        let target = try XCTUnwrap(prefix.map { prefix in
            paragraphs.firstIndex { paragraphText($0).hasPrefix(prefix) }
        } ?? pageBreak - 1)
        var edited = paragraphs
        let old = try XCTUnwrap(edited[target].paraLineSeg.paraLineSegInternalArray.first)
        edited[target].paraLineSeg = try lineSeg(edited[target], height: height)
        guard pullingFollowers else { return edited }
        for index in (target + 1) ..< pageBreak {
            edited[index].paraLineSeg = try lineSeg(
                edited[index], shift: height - old.lineHeight
            )
        }
        return edited
    }

    /// 문단 줄 캐시를 다시 만든다 — 줄마다 위치에 `shift`를 더하고, `height`가 있으면 줄 높이를
    /// 그 값으로·베이스라인을 그 0.85배로 바꾼다.
    private static func lineSeg(
        _ paragraph: CoreHwp.HwpParagraph, shift: Int32 = 0, height: Int32? = nil
    ) throws -> CoreHwp.HwpParaLineSeg {
        var payload = Data()
        for segment in paragraph.paraLineSeg.paraLineSegInternalArray {
            let lineHeight = height ?? segment.lineHeight
            for value in [
                Int32(bitPattern: segment.textStartingIndex), segment.lineLocation + shift,
                lineHeight, height ?? segment.textHeight,
                height.map { $0 * 85 / 100 } ?? segment.baselineDistance, segment.lineSpacing,
                segment.startingLocation, segment.width, Int32(bitPattern: segment.property),
            ] {
                withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
            }
        }
        return try CoreHwp.HwpParaLineSeg.load(payload)
    }

    /// 문단의 보이는 글자 (제어 문자 제외).
    private static func paragraphText(_ paragraph: CoreHwp.HwpParagraph) -> String {
        (paragraph.paraText?.charArray ?? []).compactMap { char -> String? in
            guard char.type == .char, char.value >= 32, let scalar = UnicodeScalar(char.value)
            else { return nil }
            return String(scalar)
        }.joined()
    }
}
