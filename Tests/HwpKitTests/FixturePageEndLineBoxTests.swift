import CoreGraphics
@testable import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 쪽 끝 적합 판정이 줄 **상자** 하단까지인지 (#222) — `page-end-line-box` HWP·HWPX 쌍.
///
/// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-24)이 같은 편집 세션에서 저장한 줄 캐시
/// (`PARA_LINE_SEG` — 본문 상단 99.2 + `vertpos` + `baseline`)다 (`Fixtures/page-end-line-box/
/// README.md`의 표). 본문 97.62pt의 작은 쪽마다 채움 줄로 남은 자리를 만들고 한 사례씩 싣는다 —
/// 한글은 마지막으로 남기는 줄의 상자 하단이 본문 하단보다 위면 그 줄을 남기고(줄 간격 여분·문단
/// 아래 간격은 넘쳐도 된다) 같으면 넘기며, 고정 줄 간격이 상자보다 작은 줄도 상자로 판정한다.
///
/// 캐시가 있는 저장본은 한글의 쪽 나눔을 그대로 따르므로 이 규칙과 무관하게 맞는다 — 이 스위트의
/// 축은 **캐시를 지우고 다시 조판한** 경로다. 종전(전진량 판정)에는 그 경로가 28문단에서 한글과
/// 갈렸다(16pt 한 줄·17.61pt 줄·아래 간격 20pt 줄·세 줄 문단·문단 보호·외톨이줄 보호·빈 문단·
/// 각주 위 20pt 줄을 다음 쪽으로 넘기고, 상자보다 작은 고정 8pt 줄은 남겼다). 여러 줄 문단은
/// 한 줄 끝(LF)으로 줄 수를 고정했으므로 줄바꿈이 글꼴과 무관하다 — 폰트는
/// `HwpFontResolver.testDeterministic`이다.
final class FixturePageEndLineBoxTests: XCTestCase {
    private static let id = "page-end-line-box"

    /// 한글이 저장한 쪽 수 (PDF 내보내기도 29쪽).
    private static let hancomPageCount = 29

    /// 채움 줄을 뺀 줄의 한글 자리 — 쪽(0-기준), 쪽 좌표 베이스라인, 첫 글자. 빈 문단은 빈 문자열.
    /// 각주 줄(`1)`)은 각주 영역의 상자 바닥이 본문 하단(196.82)에 닿는 자리다 — 한글 PDF로는
    /// 195.4(장치 양자화).
    private static let hancomLines: [Line] = [
        Line(0, 107.7, "#222"), Line(0, 192.8, "XAT"), Line(1, 107.7, "XAA"),
        Line(3, 114.5, "XBT"), Line(3, 136.5, "XBA"),
        Line(5, 114.18, "XCT"), Line(5, 135.88, "XCA"),
        Line(6, 194.17, "XDT"), Line(7, 107.7, "XDA"),
        Line(8, 187.7, "FAP"), Line(9, 107.7, "FAT"), Line(9, 115.7, "FAA"),
        Line(10, 187.7, "FBP"), Line(10, 195.31, "FBT"), Line(11, 107.7, "FBA"),
        Line(12, 187.7, "GAT"), Line(13, 107.7, "GAA"),
        Line(14, 155.7, "LAP"), Line(14, 160.7, "LAT 첫"), Line(14, 176.7, "LAT 2째"),
        Line(14, 192.7, "LAT 3째"), Line(15, 107.7, "LAA"),
        Line(16, 155.7, "LBP"), Line(16, 160.7, "LBT 첫"), Line(16, 176.7, "LBT 2째"),
        Line(16, 192.7, "LBT 3째"), Line(17, 107.7, "LBA"),
        Line(18, 155.7, "LCP"), Line(19, 107.7, "LCT 첫"), Line(19, 123.7, "LCT 2째"),
        Line(19, 139.7, "LCT 3째"), Line(19, 155.7, "LCA"),
        Line(20, 160.8, "WAT 첫"), Line(20, 186.4, "WAT 2째"), Line(21, 112.8, "WAT 3째"),
        Line(21, 138.4, "WAT 4째"), Line(21, 164.0, "WAT 5째"), Line(21, 184.5, "WAA"),
        Line(22, 192.8, "ZAT 첫"), Line(23, 112.8, "ZAT 2째"), Line(23, 138.4, "ZAT 3째"),
        Line(23, 158.9, "ZAA"),
        Line(24, 187.7, "EAP"), Line(24, 193.32, ""), Line(25, 107.7, "EAA"),
        Line(26, 164.2, "NAT"), Line(26, 195.32, "1)"), Line(27, 107.7, "NAA"),
        Line(28, 107.7, "ZZ"),
    ]

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

    /// 넘친 여분은 이월하지 않는다 — 줄을 남긴 쪽의 뒤 문단(XAA·XDA·FBA·GAA·LAA·LBA·EAA·NAA)은
    /// 다음 쪽 본문 상단에서 시작하고, 남긴 줄의 블록은 줄 간격 여분(과 아래 간격)만큼 본문
    /// 하단(196.82) 아래로 나간다 — 16pt 한 줄·17.61pt 줄·아래 간격 20pt 줄·세 줄 문단 둘·16pt 세 줄
    /// 문단의 첫 조각.
    func testKeptLinesHangTheirSpacingBelowTheBodyWithoutCarryingIt() async throws {
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let pages = try await Self.pages(hwpx: hwpx, dropCaches: true)
            let hanging = ["XAT", "XDT", "GAT", "LAT", "LBT", "ZAT"].compactMap { prefix in
                Self.textBlock(beginningWith: prefix, in: pages)
            }
            expect(hanging.count).to(equal(6), description: label)
            for (page, block) in hanging {
                expect(Double(block.frame.maxY)).to(
                    beGreaterThan(196.82), description: "\(label) \(page)쪽 여분"
                )
            }
            for prefix in ["XAA", "XDA", "FBA", "GAA", "LAA", "LBA", "EAA", "NAA"] {
                let block = Self.textBlock(beginningWith: prefix, in: pages)
                expect(block.map { Double($0.block.frame.minY) })
                    .to(beCloseTo(99.2, within: 0.011), description: "\(label) \(prefix)")
            }
        }
    }

    // MARK: 헬퍼

    /// 줄 하나 — 쪽(0-기준), 쪽 좌표 베이스라인, 첫 글자.
    private struct Line {
        let page: Int
        let baseline: Double
        let prefix: String

        init(_ page: Int, _ baseline: Double, _ prefix: String) {
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

    /// 문서의 모든 쪽 — `dropCaches`면 모든 최상위 문단의 줄 캐시를 지우고 조판한다(표는 없다).
    private static func pages(hwpx: Bool, dropCaches: Bool) async throws -> [HwpPage] {
        let file = try CoreHwp.HwpFile(fromPath: fixtureURL(hwpx: hwpx).path)
        var sections = file.displaySectionArray
        if dropCaches {
            for index in sections.indices {
                sections[index].paragraph = sections[index].paragraph.map { paragraph in
                    var copy = paragraph
                    copy.paraLineSeg.paraLineSegInternalArray = []
                    return copy
                }
            }
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file), fontResolver: .testDeterministic
        )
        var pages: [HwpPage] = []
        while let page = try await paginator.page(at: pages.count) {
            pages.append(page)
        }
        return pages
    }

    /// 그려지는 줄 가운데 채움 줄을 뺀 것 — 쪽·자리 순.
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
                    guard !text.contains("채움") else { continue }
                    // 구역 첫 문단의 컨트롤 마커(U+FFFC)는 글자가 아니다.
                    lines.append(Line(
                        pageIndex, Double(line.baselineOrigin.y),
                        text.replacingOccurrences(of: "\u{FFFC}", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
        }
        return lines.sorted { ($0.page, $0.baseline) < ($1.page, $1.baseline) }
    }

    /// 문자열이 `prefix`로 시작하는 본문 텍스트 블록과 그 쪽.
    private static func textBlock(
        beginningWith prefix: String, in pages: [HwpPage]
    ) -> (page: Int, block: AnyHwpBlock)? {
        for (pageIndex, page) in pages.enumerated() {
            if let block = page.blocks.first(where: {
                $0.kind == .text && $0.attributedString?.string.hasPrefix(prefix) == true
            }) {
                return (pageIndex, block)
            }
        }
        return nil
    }

    private static func assertLines(hwpx: Bool, dropCaches: Bool) async throws {
        let label = "\(hwpx ? "HWPX" : "HWP")\(dropCaches ? " 재조판" : " 캐시")"
        let pages = try await pages(hwpx: hwpx, dropCaches: dropCaches)
        expect(pages.count).to(equal(hancomPageCount), description: label)
        let lines = drawnLines(in: pages)
        expect(lines.count).to(equal(hancomLines.count), description: label)
        guard lines.count == hancomLines.count else {
            fail("\(label) 줄: \(lines.map { "\($0.page) \($0.baseline) \($0.prefix)" })")
            return
        }
        for (actual, expected) in zip(lines, hancomLines) {
            let description = "\(label) \(expected.page)쪽 \(expected.baseline) \(expected.prefix)"
            expect(actual.page).to(equal(expected.page), description: description)
            expect(actual.baseline)
                .to(beCloseTo(expected.baseline, within: 0.011), description: description)
            if expected.prefix.isEmpty {
                expect(actual.prefix).to(beEmpty(), description: description)
            } else {
                expect(actual.prefix).to(beginWith(expected.prefix), description: description)
            }
        }
    }
}
