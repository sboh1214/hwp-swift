@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreGraphics)
    import CoreGraphics

    final class HwpObjectSizeResolverTests: XCTestCase {
        private func resolver(paragraphWidth: CGFloat? = nil) -> HwpObjectSizeResolver {
            HwpObjectSizeResolver(
                paperSize: CGSize(width: 595, height: 842),
                contentSize: CGSize(width: 500, height: 700),
                columnWidth: 400,
                paragraphWidth: paragraphWidth
            )
        }

        func testParagraphBasisResolvesAgainstParagraphWidth() {
            // 5000 = 50% — 문단 폭 100pt 기준 50pt (단 폭 400pt가 아님, #2)
            expect(self.resolver(paragraphWidth: 100).width(5000, basis: .paragraph)) == 50
        }

        func testColumnBasisStaysOnColumnWidth() {
            expect(self.resolver(paragraphWidth: 100).width(5000, basis: .column)) == 200
        }

        func testParagraphWidthDefaultsToColumnWidth() {
            expect(self.resolver().width(5000, basis: .paragraph)) == 200
        }

        func testWithParagraphWidthKeepsOtherBases() {
            let narrowed = resolver().withParagraphWidth(80)
            expect(narrowed.width(10000, basis: .paragraph)) == 80
            expect(narrowed.width(10000, basis: .column)) == 400
            expect(narrowed.width(10000, basis: .paper)) == 595
            expect(narrowed.width(10000, basis: .absolute)) == 100
        }
    }
#endif
