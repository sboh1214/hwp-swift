@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpParagraphLayoutTests: XCTestCase {
        func testEmptyAttributedStringReturnsEmptyFrame() {
            let frame = layout().layout(
                attributedString: attributedString(""),
                paraShape: paraShape(),
                columnWidth: 300
            )

            expect(frame.totalHeight) == 0
            expect(frame.lines) == []
        }

        func testSingleLineHasReasonableHeight() {
            let frame = layout().layout(
                attributedString: attributedString("hello"),
                paraShape: paraShape(),
                columnWidth: 300
            )

            expect(frame.lines.count) == 1
            expect(frame.totalHeight).to(beGreaterThanOrEqualTo(10))
            expect(frame.totalHeight).to(beLessThanOrEqualTo(20))
            expect(frame.lines.first?.attributedRange) == NSRange(location: 0, length: 5)
        }

        func testLongTextWrapsInNarrowColumn() {
            let text = String(repeating: "hello world ", count: 18)
            let frame = layout().layout(
                attributedString: attributedString(text),
                paraShape: paraShape(),
                columnWidth: 100
            )

            expect(frame.lines.count) >= 2
        }

        func testCenterAlignmentOffsetsLineFromLeftEdge() {
            let frame = layout().layout(
                attributedString: attributedString("hi"),
                paraShape: paraShape(property1: 2),
                columnWidth: 300
            )

            expect(frame.lines.count) == 1
            expect(frame.lines[0].origin.x) > 0
        }
    }

    private extension HwpParagraphLayoutTests {
        func layout() -> HwpParagraphLayout {
            HwpParagraphLayout(fontResolver: .testDeterministic)
        }

        func attributedString(_ string: String) -> NSAttributedString {
            NSAttributedString(
                string: string,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName("Menlo" as CFString, 12, nil),
                ]
            )
        }

        func paraShape(property1: UInt32 = 0) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(property1: property1, marginLeft: 0, tabDefId: 0, lineSpacing2: 160)
        }
    }
#endif
