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

        func testPercentLineSpacingForcesLineHeightFromFontSize() {
            // 표 46 종류 0 (글자에 따라 %): 비율 160 → 줄 높이 ≈ 글자 크기 × 1.6 (±10%)
            let text = String(repeating: "percent line spacing ", count: 12)
            let frame = layout().layout(
                attributedString: attributedString(text),
                paraShape: paraShape(), // property3 = 0 (비율), lineSpacing2 = 160
                columnWidth: 120
            )

            expect(frame.lines.count) >= 3
            let perLine = frame.totalHeight / CGFloat(frame.lines.count)
            let expected = 12.0 * 1.6
            expect(perLine).to(beCloseTo(expected, within: expected * 0.1))
        }

        func testFixedLineSpacingUsesHwpUnitValue() {
            // 표 46 종류 1 (고정값): 3600 HWPUNIT = 36pt
            var shape = paraShape()
            shape.property3 = 1
            shape.lineSpacing2 = 3600
            let text = String(repeating: "fixed line spacing ", count: 12)
            let frame = layout().layout(
                attributedString: attributedString(text),
                paraShape: shape,
                columnWidth: 120
            )

            expect(frame.lines.count) >= 3
            let perLine = frame.totalHeight / CGFloat(frame.lines.count)
            expect(perLine).to(beCloseTo(36, within: 1))
        }

        func testMarginOnlyLineSpacingAddsSpacingBetweenLines() {
            // 표 44 종류 2 (여백만 지정, 5.0.2.5 미만 저장본): 500 HWPUNIT = 5pt 추가
            var plain = paraShape(property1: 2, lineSpacing: 0)
            plain.property3 = nil
            plain.lineSpacing2 = nil
            var spaced = paraShape(property1: 2, lineSpacing: 500)
            spaced.property3 = nil
            spaced.lineSpacing2 = nil
            let text = String(repeating: "margin only spacing ", count: 12)

            let plainFrame = layout().layout(
                attributedString: attributedString(text),
                paraShape: plain,
                columnWidth: 120
            )
            let spacedFrame = layout().layout(
                attributedString: attributedString(text),
                paraShape: spaced,
                columnWidth: 120
            )

            expect(plainFrame.lines.count) == spacedFrame.lines.count
            expect(plainFrame.lines.count) >= 3
            let expectedGain = 5.0 * CGFloat(spacedFrame.lines.count - 1)
            expect(spacedFrame.totalHeight - plainFrame.totalHeight)
                .to(beCloseTo(expectedGain, within: 1))
        }

        func testLegacyProperty1PercentKindAppliesWithoutProperty3() {
            // 한글 2007 이하 (5.0.2.5 미만): property3 없이 property1 bits 0-1 = 0
            // (비율)과 lineSpacing 값으로 해석한다 (헌법주석 저장본 실측 경로).
            var shape = paraShape(property1: 0, lineSpacing: 160)
            shape.property3 = nil
            shape.lineSpacing2 = nil
            let text = String(repeating: "legacy percent spacing ", count: 12)
            let frame = layout().layout(
                attributedString: attributedString(text),
                paraShape: shape,
                columnWidth: 120
            )

            expect(frame.lines.count) >= 3
            let perLine = frame.totalHeight / CGFloat(frame.lines.count)
            let expected = 12.0 * 1.6
            expect(perLine).to(beCloseTo(expected, within: expected * 0.1))
        }

        func testCenterAlignmentOffsetsLineFromLeftEdge() {
            // 정렬 방식은 property1 bits 2-4: 3(가운데) << 2
            let frame = layout().layout(
                attributedString: attributedString("hi"),
                paraShape: paraShape(property1: 3 << 2),
                columnWidth: 300
            )

            expect(frame.lines.count) == 1
            expect(frame.lines[0].origin.x) > 0
        }
    }

    private extension HwpParagraphLayoutTests {
        func layout() -> HwpParagraphLayout {
            HwpParagraphLayout()
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

        func paraShape(
            property1: UInt32 = 0,
            lineSpacing: Int32 = 160
        ) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                property1: property1,
                marginLeft: 0,
                lineSpacing: lineSpacing,
                tabDefId: 0,
                lineSpacing2: 160
            )
        }
    }
#endif
