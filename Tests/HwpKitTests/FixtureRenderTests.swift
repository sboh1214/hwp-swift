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
        // 파싱 가능한 45개 픽스처 전부에 pageCount 명세가 있다
        expect(withPageCount.count) >= 45

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
        expect(fixtures.count) >= 49
        let withText = fixtures.filter { !$0.expectedVisibleText.isEmpty }
        let empty = fixtures.filter(\.expectedVisibleText.isEmpty)
        expect(withText.count) >= 36
        expect(empty.count) >= 13
        expect(withText.count + empty.count) == fixtures.count
    }

    /// 고정 줄 간격이 글자 상자보다 작은 줄은 한글에서도 다음 줄에 겹쳐 그려진다 — 텍스트 블록
    /// 프레임은 줄 상자 높이라 상자와 고정 간격의 차만큼 겹치는 것이 저장본 그대로의 자리다.
    /// `page-end-line-box`(#222)는 쪽 끝 적합 판정을 가르려고 상자 10pt 줄에 고정 8·7.61·5·5.62pt
    /// 간격을 건다. 자리는 한글이 저장한 줄 캐시라 글꼴과 무관하므로 쪽과 겹침량(10 − 간격)을
    /// 정확히 핀한다 — 다른 자리의 겹침도, 핀한 겹침의 소실도 그대로 실패한다.
    private static let fixedSpacingOverlaps: [String: [Int: CGFloat]] = [
        "page-end-line-box": [9: 2.0, 10: 2.39, 14: 5.0, 16: 5.0, 24: 4.38],
    ]

    func testPageBlocksDoNotOverlap() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        var failures: [String] = []
        var pinnedPages: [String: Set<Int>] = [:]
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
                                if let pinned = Self.fixedSpacingOverlaps[fixture.id]?[pageIndex],
                                   abs(overlapY - pinned) < 0.01
                                {
                                    pinnedPages[fixture.id, default: []].insert(pageIndex)
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

        for (id, pinned) in Self.fixedSpacingOverlaps {
            expect(pinnedPages[id] ?? []).to(
                equal(Set(pinned.keys)),
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
