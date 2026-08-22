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
                attributedString: styled("", paraShape: paraShape()),
                paraShape: paraShape(),
                columnWidth: 300
            )

            expect(frame.totalHeight) == 0
            expect(frame.lines) == []
        }

        func testSingleLineHasReasonableHeight() {
            let frame = layout().layout(
                attributedString: styled("hello", paraShape: paraShape()),
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
                attributedString: styled(text, paraShape: paraShape()),
                paraShape: paraShape(),
                columnWidth: 100
            )

            expect(frame.lines.count) >= 2
        }

        /// 줄 프레임 누적은 maxLineFrames에서 정확히 절단된다 — 거대 문단이
        /// 페이지 상한에 닿기 전에 메모리/CPU를 고갈시키지 않는 자원 상한 (R36 #2).
        func testLineFrameAccumulationHonorsCap() {
            let text = String(repeating: "hello world ", count: 60)
            let frame = layout().layout(
                attributedString: styled(text, paraShape: paraShape()),
                paraShape: paraShape(),
                columnWidth: 60,
                maxLineFrames: 4
            )

            expect(frame.lines.count) == 4
            // 높이는 보존된 4줄만 반영한다 (줄당 10-20pt + 문단 간격 여유) —
            // 버려진 줄이 높이에 남으면 이 상한을 크게 넘는다 (R37 #1).
            expect(frame.totalHeight).to(beLessThanOrEqualTo(100))
        }

        /// 렌더/선택 경로(HwpDrawnTextLayout.lines)도 같은 줄 상한을 따른다 —
        /// 좁은 거대 문단이 전체 CTLine을 즉시 만들어 자원을 고갈시키지 않는다.
        /// 상한을 주면 uncapped보다 줄 수가 준다 (R47 #1).
        func testDrawnLinesHonorMaxLineFrameCap() {
            let string = attributedString(String(repeating: "x ", count: 40))
            let full = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20
            )
            let capped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20, maxLineFrames: 4
            )

            expect(full.count).to(beGreaterThan(4))
            expect(capped.count).to(beLessThanOrEqualTo(4))
        }

        /// 폭이 넓어 줄 수는 cap 미만이지만 문자 수가 cap을 넘는 문단: 줄 예산이
        /// 남는 한 이어 프레이밍해 tail까지 전체를 덮는다 — 문자 기준으로 잘랐다면
        /// 마지막 줄이 문자열 끝에 못 닿는다 (R48).
        func testDrawnLinesFrameEntireWideParagraphBeyondCharCap() {
            let string = attributedString(String(repeating: "a", count: 30))
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 100_000, maxLineFrames: 25
            )

            let covered = drawn.map { $0.stringRange.location + $0.stringRange.length }.max() ?? 0
            expect(covered) == string.length
        }

        /// 문자 수는 cap을 넘지만 줄 수는 cap 미만인 문단: capped 결과가 uncapped와
        /// 같은 줄 경계를 내야 한다 — 청크 경계가 논리 줄을 쪼개면 capped 줄 수·
        /// 범위가 어긋난다 (R49).
        func testCappedFramingPreservesLineBoundaries() {
            let string = attributedString("a b c d e f g h i j")
            let uncapped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20
            )
            let capped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20, maxLineFrames: 15
            )

            expect(capped.count).to(beGreaterThan(1))
            expect(capped.map(\.stringRange.location)) == uncapped.map(\.stringRange.location)
            expect(capped.map(\.stringRange.length)) == uncapped.map(\.stringRange.length)
        }

        /// 측정(layout)과 렌더(lines)가 nextFrameChunk를 공유해 같은 청크 경계를
        /// 쓰므로 줄 range가 일치해야 한다 — R49가 렌더만 미완 줄 drop으로 바꿔
        /// 어긋났던 것을 교정 (R50 #4).
        func testCappedMeasurementMatchesRenderRanges() {
            // 프로덕션과 같은 모양: 부착본 **하나**를 두 경로가 나눠 쓴다.
            let string = styled("a b c d e f g h", paraShape: paraShape())
            let measured = layout().layout(
                attributedString: string, paraShape: paraShape(), columnWidth: 20, maxLineFrames: 6
            )
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20, maxLineFrames: 6
            )

            expect(measured.lines.map(\.attributedRange)) == drawn.map(\.stringRange)
        }

        /// 예산보다 긴 한 시각 줄은 쪼개지 않고 한 줄로 유지한다 — 한 시각 줄은 줄
        /// 예산 하나만 소비한다 (R50 #2).
        func testWideSingleLineNotSplitAcrossChunks() {
            let string = attributedString(String(repeating: "a", count: 8))
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 100_000, maxLineFrames: 3
            )

            expect(drawn.count) == 1
            expect(drawn.first?.stringRange) == NSRange(location: 0, length: 8)
        }

        /// 청크 경계 이월 후에도 각 줄 baseline이 uncapped와 같아야 한다 — 재개 줄이
        /// 아래로 밀리는 세로 간격·선택 어긋남이 없다 (R50 #3).
        func testCappedBaselineMatchesUncapped() {
            let string = attributedString("a b c d e f g")
            let uncapped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20
            )
            let capped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 20, maxLineFrames: 10
            )

            expect(capped.count) == uncapped.count
            for (cappedLine, uncappedLine) in zip(capped, uncapped) {
                expect(cappedLine.baselineOrigin.y).to(beCloseTo(uncappedLine.baselineOrigin.y, within: 0.5))
            }
        }

        /// slight-overflow probe는 shaping 전에 길이로 거른다 — 같은 폭 비율에서
        /// 짧은 문단은 slight-overflow(non-nil)지만 maximumLineFrames를 넘으면 nil이라
        /// 큰 개행 없는 문단의 전체 shaping을 피한다 (R50 #1).
        func testSlightOverflowProbeBoundsInputLength() {
            let shortString = attributedString(String(repeating: "a", count: 30))
            let shortNatural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(shortString), nil, nil, nil
            ))
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: shortString, lineWidth: shortNatural * 0.98
            )).toNot(beNil())

            let longString = attributedString(
                String(repeating: "a", count: HwpParagraphLayout.maximumLineFrames + 1)
            )
            let longNatural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(longString), nil, nil, nil
            ))
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: longString, lineWidth: longNatural * 0.98
            )).to(beNil())
        }

        /// 오른쪽 여백(tailIndent) 있는 문단에서 rescue가 실제 줄 폭을 잘못 잡아도
        /// 커밋 줄 수는 남은 예산을 넘지 않는다 — maxLineFrames:1은 1줄 (R51 #1).
        func testMaxLineFramesBudgetNotExceededWithTailIndent() {
            let string = styledString(String(repeating: "a", count: 200), tailIndent: -75)
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 100, maxLineFrames: 1
            )

            expect(drawn.count).to(beLessThanOrEqualTo(1))
        }

        /// 한 줄 rescue 뒤 이어지는 청크의 baseline이 줄 간격(lineSpacingAdjustment)을
        /// 포함해 uncapped와 같아야 한다 — 재개 줄이 위로 밀리지 않는다 (R51 #2).
        func testRescueContinuationBaselineIncludesLineSpacing() {
            let string = styledString("aaaaaaaa\nbbbb", lineSpacing: 10)
            let uncapped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 100_000
            )
            let capped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: .zero, lineWidth: 100_000, maxLineFrames: 3
            )

            expect(capped.count) == uncapped.count
            for (cappedLine, uncappedLine) in zip(capped, uncapped) {
                expect(cappedLine.baselineOrigin.y).to(beCloseTo(uncappedLine.baselineOrigin.y, within: 0.5))
            }
        }

        func testPercentLineSpacingForcesLineHeightFromFontSize() {
            // 표 46 종류 0 (글자에 따라 %): 비율 160 → 줄 높이 ≈ 글자 크기 × 1.6 (±10%)
            let text = String(repeating: "percent line spacing ", count: 12)
            let frame = layout().layout(
                attributedString: styled(text, paraShape: paraShape()),
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
                attributedString: styled(text, paraShape: shape),
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
                attributedString: styled(text, paraShape: plain),
                paraShape: plain,
                columnWidth: 120
            )
            let spacedFrame = layout().layout(
                attributedString: styled(text, paraShape: spaced),
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
                attributedString: styled(text, paraShape: shape),
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
                attributedString: styled("hi", paraShape: paraShape(property1: 3 << 2)),
                paraShape: paraShape(property1: 3 << 2),
                columnWidth: 300
            )

            expect(frame.lines.count) == 1
            expect(frame.lines[0].origin.x) > 0
        }

        func testTabParagraphMeasurementMatchesDrawnLayout() {
            // 측정 (layout)과 렌더 (HwpDrawnTextLayout)가 같은 문서 정의 탭으로
            // 조판해야 탭 포함 문단의 줄바꿈 위치가 일치한다 — B-1a 정합 가드.
            // 탭이 조판에 닿는 경로는 **부착본 하나뿐**이다 (#80 조각 3): 측정도
            // 그 부착본을 그대로 framesetting하므로 두 경로가 구조적으로 같은 탭을
            // 본다.
            let tabs = [CTTextTabCreate(.left, 250, nil)]
            let text = "이름\t값이 아주 길어서 줄바꿈 위치가 탭 스톱 위치에 좌우되는 "
                + "문단입니다 하나 둘 셋 넷 다섯 여섯 일곱 여덟"
            let shape = paraShape()
            let width: CGFloat = 300

            let attached = styled(text, paraShape: shape, tabStops: tabs)
            let measured = layout().layout(
                attributedString: attached,
                paraShape: shape,
                columnWidth: width
            )
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: attached, origin: .zero, lineWidth: width
            )

            expect(measured.lines.count) > 1
            expect(measured.lines.map(\.attributedRange)) == drawn.map(\.stringRange)

            // 탭이 빠진 부착본으로 측정하면 줄바꿈이 어긋난다 — 이 테스트가
            // 불일치를 실제로 감지함을 증명
            let withoutTabs = layout().layout(
                attributedString: styled(text, paraShape: shape),
                paraShape: shape,
                columnWidth: width
            )
            expect(withoutTabs.lines.map(\.attributedRange))
                != drawn.map(\.stringRange)
        }
    }

    private extension HwpParagraphLayoutTests {
        func layout() -> HwpParagraphLayout {
            HwpParagraphLayout()
        }

        /// 측정 입력 계약을 지킨 문자열 — `layout`은 문단 스타일이 **부착된**
        /// 입력을 그대로 framesetting한다 (#80 조각 3). 프로덕션에서는
        /// `HwpTextRunBuilder.attachParagraphStyle`이 이 일을 하므로, 문자열을 직접
        /// 만드는 테스트는 여기서 같은 부착을 해야 paraShape 기반 단언이 의미를
        /// 갖는다 (안 하면 CT 기본값으로 조판된다).
        func styled(
            _ string: String,
            paraShape shape: CoreHwp.HwpParaShape,
            tabStops: [CTTextTab] = []
        ) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: attributedString(string))
            guard output.length > 0 else { return output }
            output.addAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: HwpParagraphLayout.paragraphStyle(
                    for: shape, attributedString: output, tabStops: tabStops
                ),
                range: NSRange(location: 0, length: output.length)
            )
            return output
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

        func styledString(
            _ string: String, tailIndent: CGFloat = 0, lineSpacing: CGFloat = 0
        ) -> NSAttributedString {
            var tail = tailIndent
            var spacing = lineSpacing
            let style: CTParagraphStyle = withUnsafeMutablePointer(to: &tail) { tailPtr in
                withUnsafeMutablePointer(to: &spacing) { spacingPtr in
                    CTParagraphStyleCreate([
                        CTParagraphStyleSetting(
                            spec: .tailIndent,
                            valueSize: MemoryLayout<CGFloat>.size, value: tailPtr
                        ),
                        CTParagraphStyleSetting(
                            spec: .lineSpacingAdjustment,
                            valueSize: MemoryLayout<CGFloat>.size, value: spacingPtr
                        ),
                    ], 2)
                }
            }
            return NSAttributedString(string: string, attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Menlo" as CFString, 12, nil),
                kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ])
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
