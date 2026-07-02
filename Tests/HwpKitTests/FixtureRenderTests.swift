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
            fail("Fixture render failures (\(failures.count)):\n" + failures.joined(separator: "\n"))
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
                    failures.append("[\(fixture.id)] paint list missing '\(phrase)' — got: '\(preview)'")
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("Paint list render failures (\(failures.count)):\n" + failures.joined(separator: "\n"))
        }
    }

    func testFixtureCountAndCategories() throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        expect(fixtures.count) >= 33
        let withText = fixtures.filter { !$0.expectedVisibleText.isEmpty }
        let empty = fixtures.filter { $0.expectedVisibleText.isEmpty }
        expect(withText.count) >= 20
        expect(empty.count) >= 13
        expect(withText.count + empty.count) == fixtures.count
    }

    func testPageBlocksDoNotOverlap() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        var failures: [String] = []
        let tolerance: CGFloat = 0.5

        for fixture in fixtures where !fixture.expectedVisibleText.isEmpty {
            do {
                let document = try await HwpDocumentLoader().load(from: fixture.documentURL)
                for (pageIndex, page) in document.pages.enumerated() {
                    let blocks = page.blocks
                    for lhs in 0 ..< blocks.count {
                        for rhs in (lhs + 1) ..< blocks.count {
                            let frameA = blocks[lhs].frame
                            let frameB = blocks[rhs].frame
                            guard frameA.width > 0, frameA.height > 0,
                                  frameB.width > 0, frameB.height > 0
                            else { continue }
                            let overlapX = min(frameA.maxX, frameB.maxX) - max(frameA.minX, frameB.minX)
                            let overlapY = min(frameA.maxY, frameB.maxY) - max(frameA.minY, frameB.minY)
                            if overlapX > tolerance, overlapY > tolerance {
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
