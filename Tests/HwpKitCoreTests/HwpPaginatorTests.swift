@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    final class HwpPaginatorTests: XCTestCase {
        func testEmptySectionsReturnsSingleEmptyPage() async throws {
            let paginator = HwpPaginator(
                sections: [],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            expect(page).notTo(beNil())
            expect(page?.blocks) == []
            expect(page?.pageNumber) == 1
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 1
        }

        func testBlankFileReturnsOnePage() async throws {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)
            let totalPages = await paginator.totalPages()
            let secondPage = try await paginator.page(at: 1)

            expect(page).notTo(beNil())
            expect(totalPages) == 1
            expect(secondPage).to(beNil())
        }

        func testMissingLineSegmentFallback() async throws {
            let file = CoreHwp.HwpFile()
            var section = file.sectionArray[0]
            section.paragraph[0].paraLineSeg.paraLineSegInternalArray = []
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            expect(page).notTo(beNil())
            expect(page?.pageNumber) == 1
        }

        func testLazyDoesNotComputeAllPagesUpFront() async throws {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let initialCacheCount = await paginator.cachedPages.count
            expect(initialCacheCount) == 0

            _ = try await paginator.page(at: 0)

            let cachedPages = await paginator.cachedPages
            expect(cachedPages.count) == 1
            expect(cachedPages[0]).notTo(beNil())
        }
    }
#endif
