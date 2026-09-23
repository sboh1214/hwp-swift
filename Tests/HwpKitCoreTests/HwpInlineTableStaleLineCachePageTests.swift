import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 낡은 캐시 보정으로 밀린 문단의 쪽 넘김 (#214 PR 리뷰) — 절대 캐시의 쪽 절단점은 보정 **전**
    /// 자리로 정해졌으므로 절단점만 따르면, 표가 크게 커진 문서에서 밀린 뒤 문단이 종이 밖으로 나가
    /// 사라진다. 한글은 넘는 문단을 다음 쪽 머리에 놓는다 — 한글 12.30.0(6446) 실측(2026-09-23): 앞 표가
    /// 51.28 → 563.28pt로 커진 문서의 뒤 표 문단은 2쪽 머리(줄 위치 0)에, 제 표가 627.28pt로 커져 남은
    /// 자리에 안 들어가는 문단은 2쪽 머리에 통째로 놓이고 그 뒤 문단은 3쪽 머리다.
    ///
    /// 문서: 구역 첫 문단(16pt) 뒤 호스트(캐시 위치 16pt, 28.2pt 줄 + 6pt 간격)와 캐시 문단 둘(호스트
    /// 캐시 바로 아래부터 16pt 간격). 본문은 56.68~799.36pt라 표 `rows` × 10pt가 들어갈 자리가 정해진다.
    final class HwpInlineTableStaleLineCachePageTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport
        private typealias Stale = InlineTableStaleLineCacheSupport

        private static let contentTop: CGFloat = 56.68

        private static func pages(tableRows rows: Int) async throws -> [HwpPage] {
            let host = try Stale.cachedHost(
                instanceId: 24, rows: rows, location: 1600, height: 2820
            )
            return try await InlineControlFragmentSupport.pages(
                of: Stale.absolutePaginator(host: host, tailLocation: 5020)
            )
        }

        /// 72행(720pt) 표 — 호스트는 1쪽에 들어가지만(72.68 + 720 = 792.68) 밀린 뒤 문단 첫 줄은 본문
        /// 아래(798.68 + 10)를 넘는다. 뒤 문단 둘은 2쪽 머리부터 캐시 간격(16pt) 그대로 놓인다. 쪽을
        /// 넘기지 않으면 종이 밖(798.68·814.68)에 그려진다.
        func testParagraphsPushedPastThePageBottomMoveToTheNextPageTop() async throws {
            let pages = try await Self.pages(tableRows: 72)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            let host = try XCTUnwrap(Support.textBlock(on: pages[0], containing: " 뒤"))
            expect(host.frame.minY).to(beCloseTo(Self.contentTop + 16, within: 0.01))
            expect(Support.table(on: pages[0], instanceId: 24)).toNot(beNil())
            expect(Support.textBlock(on: pages[0], containing: "뒤 문단")).to(beNil())
            let first = try XCTUnwrap(Support.textBlock(on: pages[1], containing: "뒤 문단 0"))
            let second = try XCTUnwrap(Support.textBlock(on: pages[1], containing: "뒤 문단 1"))
            expect(first.frame.minY).to(beCloseTo(Self.contentTop, within: 0.01))
            expect(second.frame.minY - first.frame.minY).to(beCloseTo(16, within: 0.01))
        }

        /// 73행(730pt) 표 — 커진 호스트 자신이 남은 자리(72.68 + 730 > 799.36)에 안 들어가 2쪽 머리에
        /// 통째로 놓이고(56.68 + 730 = 786.68), 그 뒤 문단은 다시 밀려(792.68 + 10) 3쪽 머리다.
        func testGrownParagraphThatNoLongerFitsStartsTheNextPage() async throws {
            let pages = try await Self.pages(tableRows: 73)
            expect(pages.count) == 3
            guard pages.count == 3 else { return }
            expect(Support.textBlock(on: pages[0], containing: " 뒤")).to(beNil())
            let host = try XCTUnwrap(Support.textBlock(on: pages[1], containing: " 뒤"))
            let table = try XCTUnwrap(Support.table(on: pages[1], instanceId: 24))
            expect(host.frame.minY).to(beCloseTo(Self.contentTop, within: 0.01))
            expect(host.frame.height).to(beCloseTo(736, within: 0.01))
            expect(table.frame.minY).to(beCloseTo(Self.contentTop, within: 0.01))
            let first = try XCTUnwrap(Support.textBlock(on: pages[2], containing: "뒤 문단 0"))
            let second = try XCTUnwrap(Support.textBlock(on: pages[2], containing: "뒤 문단 1"))
            expect(first.frame.minY).to(beCloseTo(Self.contentTop, within: 0.01))
            expect(second.frame.minY - first.frame.minY).to(beCloseTo(16, within: 0.01))
        }
    }
#endif
