import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 링크 클릭 영역의 세로 범위가 한글 편집 화면의 **줄 클릭 띠**인지 (#233) — `hyperlink-click-band`
/// 쌍(한글 12.30.0이 2026-09-26에 저장, 2쪽).
///
/// 오라클은 한글 편집 화면의 클릭이다 (155%, 링크를 한 줄씩 번갈아 왼쪽·오른쪽 칸에 둬 칸마다
/// 위→아래로 눌러 열린 URL을 읽었다 — 픽스처 README의 표). 규칙은 줄 상자 상단(`vertpos`)부터 줄
/// 간격 몫까지(`vertpos + vertsize + spacing` = 다음 줄 상자 상단), 문단 위·아래 간격은 어느 줄의
/// 것도 아니고, 표 셀·각주의 마지막 줄은 줄 상자(`vertpos + vertsize`)에서 끝난다. 아래 기대값의
/// 수는 이 문서 자신의 줄 캐시(`PARA_LINE_SEG` = `hp:lineseg`)다 — 10pt 줄 1000/850/600, 40pt 문단
/// 끝 글자·책갈피·글자 줄 4000/3400/2400, 40pt 그림 줄 4000/3400/600, 고정 8pt 1000/850/−200,
/// 100% 1000/850/0 (`vertsize`/`baseline`/`spacing`, HWPUNIT). 그려지는 베이스라인이 그 캐시와 같다는
/// 것은 `FixtureBaselineAnchorTests`가 따로 잠그므로 여기서는 베이스라인 기준 거리로 견준다.
///
/// 폰트는 `testDeterministic`이다 — 한글 문서의 줄 상자는 글꼴 지표의 함수가 아니다(가로 자리는
/// 결정론 글꼴의 것이라 링크 rect의 가운데로 누른다).
///
/// HWPX 쌍은 아직 링크가 없다 — HWPX 매퍼가 `hp:fieldBegin type="HYPERLINK"`를 typed 하이퍼링크로
/// 승격하지 않고 강등 컨트롤로 보존한다(`HwpxFixtureRenderTests.knownHwpxHintGaps`). 그 격차를
/// `testHwpxPairHasNoLinksUntilFieldPromotion`이 따로 핀하고, 승격되면 아래 두 가드를 HWPX에도 건다.
final class FixtureHyperlinkClickBandTests: XCTestCase {
    private static let id = "hyperlink-click-band"

    private static func pages(hwpx: Bool) async throws -> [HwpPage] {
        let url = hwpx
            ? FixtureRoot.url(from: #file, subdirectory: "HwpxFixtures")
            .appendingPathComponent(id).appendingPathComponent("document.hwpx")
            : FixtureRoot.url(from: #file).appendingPathComponent(id)
            .appendingPathComponent("document.hwp")
        return try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url).pages
    }

    /// 링크 URL의 표본 이름 — `https://hwp-swift.test/<이름>`의 마지막 경로.
    private static func sample(_ url: String) -> String {
        url.components(separatedBy: "/").last?.components(separatedBy: ";").first ?? url
    }

    /// 방출된 링크 하나 — 쪽, rect(`.hyperlink` 명령), 그 링크가 놓인 줄의 그려진 베이스라인.
    private struct DrawnLink {
        let page: Int
        let rect: CGRect
        let baseline: CGFloat
    }

    private static func links(_ pages: [HwpPage]) -> [String: [DrawnLink]] {
        var links: [String: [DrawnLink]] = [:]
        for (index, page) in pages.enumerated() {
            var baselines: [String: CGFloat] = [:]
            for command in page.paintList.commands {
                guard case let .drawText(string, origin, width) = command else { continue }
                for line in HwpDrawnTextLayout.lines(
                    attributedString: string, origin: origin, lineWidth: width
                ) {
                    string.enumerateAttribute(
                        HwpAttributedStringKey.hyperlink, in: line.stringRange
                    ) { value, _, _ in
                        guard let url = value as? String else { return }
                        baselines[sample(url)] = line.baselineOrigin.y
                    }
                }
            }
            for command in page.paintList.commands {
                guard case let .hyperlink(rect, url) = command,
                      let baseline = baselines[sample(url)]
                else { continue }
                links[sample(url), default: []].append(
                    DrawnLink(page: index, rect: rect, baseline: baseline)
                )
            }
        }
        return links
    }

    /// 표본 → (쪽, 띠 상단·하단의 베이스라인 기준 거리, 아래가 +). 한글 편집 화면 실측과 같다
    /// (README) — 단 **쪽·문서의 마지막 본문 줄**(`l21`·`r22`)은 한글이 줄 상자(+1.5)에서 끊는데
    /// 우리는 줄 간격 몫까지 둔다: 문단 블록은 자기가 단의 끝인지 모르고, 그 몫은 블록 프레임 안의
    /// 빈 자리라 다른 링크·글자를 가리지 않는다 (`HwpDrawnTextLayout.ClickBand`).
    private static let expected: [String: (page: Int, top: CGFloat, bottom: CGFloat)] = [
        "r00-control": (0, -8.5, 7.5), "l01-control": (0, -8.5, 7.5), "r02": (0, -8.5, 7.5),
        "l03-cr40": (0, -34, 30), "r04": (0, -8.5, 7.5),
        "l05-bookmark40": (0, -34, 30), "r06": (0, -8.5, 7.5),
        "l07-pic40": (0, -34, 12), "r08": (0, -8.5, 7.5),
        "l09-text40": (0, -34, 30), "r10": (0, -8.5, 7.5),
        "l11-spacing-below24": (0, -8.5, 7.5), "r12": (0, -8.5, 7.5), "l13": (0, -8.5, 7.5),
        "r14-spacing-above24": (0, -8.5, 7.5),
        "l15-line1": (0, -8.5, 7.5), "r16-line2": (0, -8.5, 7.5),
        "l17-fixed8-line1": (0, -8.5, -0.5), "r18-fixed8-line2": (0, -8.5, -0.5),
        "l19-percent100": (0, -8.5, 1.5), "r20-percent100": (0, -8.5, 1.5),
        "l21-page-last": (0, -8.5, 7.5),
        "c1-left": (1, -8.5, 7.5), "c2-right": (1, -8.5, 7.5), "c3-cell-last": (1, -8.5, 1.5),
        "r22-document-last": (1, -8.5, 7.5),
        "f1-left": (1, -8.5, 7.5), "f2-note-last": (1, -8.5, 1.5), "g1-note-last": (1, -8.5, 1.5),
    ]

    /// 표본마다 링크 rect가 하나이고 그 세로 범위가 한글의 줄 클릭 띠다.
    func testLinkBandsMatchTheHangulClickBands() async throws {
        for hwpx in [false] {
            let label = hwpx ? "HWPX" : "HWP"
            let pages = try await Self.pages(hwpx: hwpx)
            expect(pages.count).to(equal(2), description: label)
            let links = Self.links(pages)
            expect(Set(links.keys)).to(equal(Set(Self.expected.keys)), description: label)
            for (sample, band) in Self.expected {
                let name = "\(label) \(sample)"
                let drawn = links[sample] ?? []
                expect(drawn.count).to(equal(1), description: name)
                guard let link = drawn.first else { continue }
                expect(link.page).to(equal(band.page), description: name)
                expect(Double(link.rect.minY - link.baseline))
                    .to(beCloseTo(Double(band.top), within: 0.001), description: name)
                expect(Double(link.rect.maxY - link.baseline))
                    .to(beCloseTo(Double(band.bottom), within: 0.001), description: name)
            }
        }
    }

    /// 히트로도 같다 — 밑줄(줄 상자 바닥 +0.2)과 글자·밑줄 사이를 누르면 그 링크가 열리고, 목록
    /// 끝(셀·각주의 마지막 줄)의 밑줄과 문단 사이 간격에서는 안 열린다 (한글 실측과 같다).
    func testHitTesterFollowsTheHangulClickBands() async throws {
        for hwpx in [false] {
            let label = hwpx ? "HWPX" : "HWP"
            let pages = try await Self.pages(hwpx: hwpx)
            let links = Self.links(pages)
            let tester = HwpHitTester()
            func hit(_ sample: String, below baselineOffset: CGFloat) -> String? {
                guard let link = links[sample]?.first else { return "missing" }
                let point = CGPoint(x: link.rect.midX, y: link.baseline + baselineOffset)
                guard case let .hyperlink(url, _) = tester.hit(page: pages[link.page], point: point)
                else { return nil }
                return Self.sample(url)
            }
            // 줄 상자가 링크 글자보다 높은 줄 — 밑줄(40pt 상자 바닥 +6.0 아래)과 그 위 빈칸.
            for sample in ["l03-cr40", "l05-bookmark40", "l07-pic40", "l09-text40"] {
                expect(hit(sample, below: 6.2)).to(equal(sample), description: "\(label) \(sample)")
                expect(hit(sample, below: 4)).to(equal(sample), description: "\(label) \(sample)")
            }
            // 목록 끝이 아닌 줄의 밑줄은 열리고, 셀·각주의 마지막 줄 밑줄은 안 열린다.
            for sample in ["c1-left", "c2-right", "f1-left", "l01-control"] {
                expect(hit(sample, below: 1.7)).to(equal(sample), description: "\(label) \(sample)")
            }
            for sample in ["c3-cell-last", "f2-note-last", "g1-note-last"] {
                expect(hit(sample, below: 1.7)).to(beNil(), description: "\(label) \(sample)")
            }
            // 문단 아래·위 간격 24pt 띠는 어느 링크도 아니다.
            expect(hit("l11-spacing-below24", below: 7.4)) == "l11-spacing-below24"
            expect(hit("l11-spacing-below24", below: 8)).to(beNil(), description: label)
            expect(hit("r14-spacing-above24", below: -8.4)) == "r14-spacing-above24"
            expect(hit("r14-spacing-above24", below: -9)).to(beNil(), description: label)
            // 100%·고정 8pt는 줄 전진량에서 끊긴다 — 앞 줄 밑줄은 다음 줄(평문 칸)이다.
            expect(hit("l19-percent100", below: 1.7)).to(beNil(), description: label)
            expect(hit("l17-fixed8-line1", below: -0.6)) == "l17-fixed8-line1"
            expect(hit("l17-fixed8-line1", below: -0.4)).to(beNil(), description: label)
        }
    }

    /// HWPX 쌍은 링크 필드가 강등 컨트롤이라 링크 영역이 하나도 없다 — 쪽수·글자는 HWP 쌍과 같다.
    /// HWPX 하이퍼링크 승격이 들어오면 이 가드가 빨개진다: 지우고 위 두 가드의 포맷 목록에
    /// HWPX(`true`)를 더할 것.
    func testHwpxPairHasNoLinksUntilFieldPromotion() async throws {
        let hwp = try await Self.pages(hwpx: false)
        let hwpx = try await Self.pages(hwpx: true)
        func linkCount(_ pages: [HwpPage]) -> Int {
            pages.flatMap(\.paintList.commands).filter { command in
                if case .hyperlink = command {
                    return true
                }
                return false
            }.count
        }
        expect(hwpx.count) == hwp.count
        expect(linkCount(hwp)) == 29
        expect(linkCount(hwpx)) == 0
    }
}
