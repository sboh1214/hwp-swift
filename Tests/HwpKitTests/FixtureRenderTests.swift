@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

final class FixtureRenderTests: XCTestCase {
    func testAllFixturesRenderExpectedText() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        expect(fixtures.count) > 0

        var failures: [String] = []

        for fixture in fixtures where !fixture.expectedVisibleText.isEmpty {
            do {
                let document = try await HwpDocumentLoader().load(from: fixture.documentURL)
                let rendered = FixtureText.extract(from: document)

                for phrase in fixture.expectedVisibleText where !rendered.contains(phrase) {
                    let preview = String(rendered.prefix(200))
                        .replacingOccurrences(of: "\n", with: "\\n")
                    failures.append("[\(fixture.id)] missing '\(phrase)' — got: '\(preview)'")
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("Fixture render failures (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    func testPaintListContainsExpectedText() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        var failures: [String] = []

        for fixture in fixtures where !fixture.expectedVisibleText.isEmpty {
            do {
                let document = try await HwpDocumentLoader().load(from: fixture.documentURL)
                let paintText = FixtureText.extractFromPaintList(document)

                for phrase in fixture.expectedVisibleText where !paintText.contains(phrase) {
                    let preview = String(paintText.prefix(200))
                        .replacingOccurrences(of: "\n", with: "\\n")
                    failures.append(
                        "[\(fixture.id)] paint list missing '\(phrase)' — got: '\(preview)'"
                    )
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("Paint list render failures (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// manifest expectations.pageCount (렌더 실측 잠금 — 출처는 manifest의
    /// pageCountSource)와 실제 렌더 페이지 수가 정확히 일치해야 한다.
    ///
    /// 페이지 수는 줄바꿈 누적 = 폰트 메트릭의 함수라 예전에는 환경 의존
    /// 테스트였다. `.testDeterministic`으로 resolver를 핀 고정해 그 축을 닫고
    /// CI 상시 가드로 올린다 (#69). 기대값은 그대로 쓴다 — 결정론 resolver로
    /// 뜬 페이지 수가 4개 다중 페이지 픽스처의 한글.app 실측(noori 3·
    /// footnote-endnote 2·multi-section 2·legacy 1,030)과 그대로 일치한다.
    func testPageCountsMatchManifest() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let withPageCount = fixtures.filter { $0.expectedPageCount != nil }
        // 파싱 가능한 46개 픽스처 전부에 pageCount 명세가 있다
        expect(withPageCount.count) >= 46

        var failures: [String] = []
        for fixture in withPageCount {
            guard let expected = fixture.expectedPageCount else { continue }
            do {
                let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                    .load(from: fixture.documentURL)
                if document.pages.count != expected {
                    failures.append(
                        "[\(fixture.id)] pages \(document.pages.count) != expected \(expected)"
                    )
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("Page count failures (\(failures.count)):\n" + failures.joined(separator: "\n"))
        }
    }

    func testFixtureCountAndCategories() throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        expect(fixtures.count) >= 50
        let withText = fixtures.filter { !$0.expectedVisibleText.isEmpty }
        let empty = fixtures.filter(\.expectedVisibleText.isEmpty)
        expect(withText.count) >= 37
        expect(empty.count) >= 13
        expect(withText.count + empty.count) == fixtures.count
    }

    /// 고정 줄 간격이 글자 상자보다 작은 줄은 한글에서도 다음 줄에 겹쳐 그려진다 — 텍스트 블록
    /// 프레임은 줄 상자 높이라 상자와 고정 간격의 차만큼 겹치는 것이 저장본 그대로의 자리다.
    /// `page-end-line-box`(#222)는 쪽 끝 적합 판정을 가르려고 상자 10pt 줄에 고정 8·7.61·5·5.62pt
    /// 간격을 건다. 자리는 한글이 저장한 줄 캐시라 글꼴과 무관하므로 겹치는 **블록 쌍**(두 블록의
    /// 상단과 문자열 머리)과 겹침량(10 − 간격)을 정확히 핀한다 — 같은 쪽의 다른 쌍이 같은 깊이로
    /// 겹쳐도, 핀한 겹침이 사라져도 그대로 실패한다 (#222 PR 리뷰).
    private struct PinnedOverlap {
        let page: Int
        /// 위·아래 블록의 상단과 문자열 머리 (아래 블록 `" "`은 빈 문단 앵커다).
        let upper: (minY: CGFloat, prefix: String)
        let lower: (minY: CGFloat, prefix: String)
        let depth: CGFloat

        func matches(page: Int, upper: AnyHwpBlock, lower: AnyHwpBlock, depth: CGFloat) -> Bool {
            page == self.page && abs(depth - self.depth) < 0.01
                && abs(upper.frame.minY - self.upper.minY) < 0.01
                && abs(lower.frame.minY - self.lower.minY) < 0.01
                && upper.attributedString?.string.hasPrefix(self.upper.prefix) == true
                && lower.attributedString?.string.hasPrefix(self.lower.prefix) == true
        }
    }

    private static let fixedSpacingOverlaps: [String: [PinnedOverlap]] = [
        "page-end-line-box": [
            PinnedOverlap(page: 9, upper: (99.2, "FAT"), lower: (107.2, "FAA"), depth: 2.0),
            PinnedOverlap(page: 10, upper: (179.2, "FBP"), lower: (186.81, "FBT"), depth: 2.39),
            PinnedOverlap(page: 14, upper: (147.2, "LAP"), lower: (152.2, "LAT"), depth: 5.0),
            PinnedOverlap(page: 16, upper: (147.2, "LBP"), lower: (152.2, "LBT"), depth: 5.0),
            PinnedOverlap(page: 24, upper: (179.2, "EAP"), lower: (184.82, " "), depth: 4.38),
        ],
    ]

    /// 겹친 텍스트 블록 쌍이 핀한 겹침이면 그 핀의 순번 (위·아래는 블록 상단으로 가른다).
    private static func pinnedOverlapIndex(
        fixture: String, page: Int, _ lhs: AnyHwpBlock, _ rhs: AnyHwpBlock, depth: CGFloat
    ) -> Int? {
        let (upper, lower) = lhs.frame.minY <= rhs.frame.minY ? (lhs, rhs) : (rhs, lhs)
        return fixedSpacingOverlaps[fixture]?.firstIndex {
            $0.matches(page: page, upper: upper, lower: lower, depth: depth)
        }
    }

    func testPageBlocksDoNotOverlap() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        var failures: [String] = []
        var matchedPins: [String: [Int]] = [:]
        let tolerance: CGFloat = 0.5

        for fixture in fixtures where !fixture.expectedVisibleText.isEmpty {
            do {
                let document = try await HwpDocumentLoader().load(from: fixture.documentURL)
                for (pageIndex, page) in document.pages.enumerated() {
                    // 글 앞/뒤 앵커 개체는 본문과 겹칠 수 있으므로 텍스트 블록 쌍만 검사한다.
                    let blocks = page.blocks.filter { $0.kind == .text }
                    for lhs in 0 ..< blocks.count {
                        for rhs in (lhs + 1) ..< blocks.count {
                            let frameA = blocks[lhs].frame
                            let frameB = blocks[rhs].frame
                            guard frameA.width > 0, frameA.height > 0,
                                  frameB.width > 0, frameB.height > 0
                            else { continue }
                            let overlapX = min(frameA.maxX, frameB.maxX) -
                                max(frameA.minX, frameB.minX)
                            let overlapY = min(frameA.maxY, frameB.maxY) -
                                max(frameA.minY, frameB.minY)
                            if overlapX > tolerance, overlapY > tolerance {
                                if let pin = Self.pinnedOverlapIndex(
                                    fixture: fixture.id, page: pageIndex,
                                    blocks[lhs], blocks[rhs], depth: overlapY
                                ) {
                                    matchedPins[fixture.id, default: []].append(pin)
                                    continue
                                }
                                failures.append(
                                    "[\(fixture.id)] page \(pageIndex) " +
                                        "block \(lhs) \(frameA) overlaps block \(rhs) \(frameB)"
                                )
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }

        // 핀마다 정확히 한 쌍 — 소실도, 같은 핀에 걸리는 두 번째 쌍도 실패다.
        for (id, pins) in Self.fixedSpacingOverlaps {
            expect((matchedPins[id] ?? []).sorted()).to(
                equal(Array(pins.indices)),
                description: "[\(id)] 고정 줄 간격 겹침 핀"
            )
        }
        if !failures.isEmpty {
            fail("Block overlap failures (\(failures.count)):\n" + failures.joined(separator: "\n"))
        }
    }

    func testFixturesWithEmptyExpectationsLoadOrFailGracefully() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        var crashes: [String] = []

        for fixture in fixtures where fixture.expectedVisibleText.isEmpty {
            do {
                _ = try await HwpDocumentLoader().load(from: fixture.documentURL)
            } catch is HwpDocumentLoadError {
                continue
            } catch {
                crashes.append("[\(fixture.id)] unexpected error type: \(error)")
            }
        }

        if !crashes.isEmpty {
            fail("Fixture load unexpected crashes:\n" + crashes.joined(separator: "\n"))
        }
    }
}
