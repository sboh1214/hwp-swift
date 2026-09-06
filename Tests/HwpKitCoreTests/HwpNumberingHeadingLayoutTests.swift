@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 라벨의 **기하** (#154) — 번호 너비·정렬·본문과의 거리·자동
    /// 내어쓰기·여러 줄 문단의 양쪽 정렬·이어지는 조각의 문단 스타일을 합성 입력으로
    /// 잠근다. 문단·정의·조판 헬퍼는 `HwpNumberingHeadingRenderTests`의 것을 쓴다.
    final class HwpNumberingHeadingLayoutTests: XCTestCase {
        private typealias Support = HwpNumberingHeadingRenderTests

        // MARK: - 자동 내어쓰기

        /// 자동 내어쓰기: 라벨 폭 + 거리가 표식으로 실리고 문단 스타일의 둘째 줄
        /// 들여쓰기(`headIndent`)가 첫 줄 본문 시작과 같아진다.
        func testAutoIndentAlignsFollowingLinesWithTheBody() throws {
            let attributed = try Support.build()
            let labelWidth = HwpTextRunBuilder.typographicWidth(
                of: attributed.attributedSubstring(from: NSRange(location: 0, length: 2))
            )
            let head = attributed.attribute(
                HwpAttributedStringKey.numberingHeadIndent, at: 0, effectiveRange: nil
            ) as? NSNumber

            expect(head.map { CGFloat($0.doubleValue) })
                .to(beCloseTo(labelWidth + 6, within: 0.01))
            expect(Support.styleValue(.firstLineHeadIndent, in: attributed)) == 0
            expect(Support.styleValue(.headIndent, in: attributed))
                .to(beCloseTo(labelWidth + 6, within: 0.01))
        }

        /// `ParagraphMetrics`는 첫 줄 여백 표식을 첫 줄 시작에, 내어쓰기 표식을 그 위에
        /// 더한다.
        func testParagraphMetricsAddHangingIndentToFirstLineStart() {
            let paraShape = CoreHwp.HwpParaShape(
                property1: 1 << 23, marginLeft: 2000, tabDefId: 0, numberingOrBulletId: 0
            )
            let plain = NSAttributedString(string: "가")
            let labelled = NSAttributedString(string: "1. 가", attributes: [
                HwpAttributedStringKey.numberingFirstLineInset: NSNumber(value: 4),
                HwpAttributedStringKey.numberingHeadIndent: NSNumber(value: 20),
            ])

            let before = HwpParagraphLayout.ParagraphMetrics(
                paraShape: paraShape, attributedString: plain
            )
            expect(before.firstLineHeadIndent) == 10
            expect(before.headIndent) == 10
            let after = HwpParagraphLayout.ParagraphMetrics(
                paraShape: paraShape, attributedString: labelled
            )
            expect(after.firstLineHeadIndent) == 14
            expect(after.headIndent) == 34
        }

        // MARK: - 기하 순수 함수

        /// 정보가 없으면 한글 기본값(왼쪽·자릿수 맞춤·비율 50%).
        func testMetricsDefaultToLeftInstanceWidthAndHalfEm() {
            let metrics = HwpTextRunBuilder.NumberingHeadingMetrics(
                info: nil, labelWidth: 8, fontSize: 10
            )
            expect(metrics.leadingPad) == 0
            expect(metrics.trailingPad) == 0
            expect(metrics.gap) == 5
            expect(metrics.headIndent) == 13
        }

        /// 자릿수 맞춤 해제 + 너비 조정 5pt: 번호 너비 = 1.5em(15pt) + 5pt = 20pt라
        /// 라벨(8pt)보다 넓은 영역 안에서 정렬한다.
        func testMetricsAlignLabelInsideFixedWidth() {
            func info(_ alignment: CoreHwp.HwpParaHeadAlignment) -> CoreHwp.HwpParaHeadInfo {
                CoreHwp.HwpParaHeadInfo(
                    alignment: alignment, useInstWidth: false, autoIndent: true,
                    textOffsetType: .percent, numberFormat: 0, widthAdjust: 500, textOffset: 100
                )
            }
            typealias Metrics = HwpTextRunBuilder.NumberingHeadingMetrics
            let left = Metrics(info: info(.left), labelWidth: 8, fontSize: 10)
            expect([left.leadingPad, left.trailingPad, left.gap, left.headIndent])
                == [0, 12, 10, 30]
            // 앞 여백은 첫 줄 들여쓰기로 나가므로 내어쓰기 전진량에서 빠진다.
            let center = Metrics(info: info(.center), labelWidth: 8, fontSize: 10)
            expect([center.leadingPad, center.trailingPad, center.gap, center.headIndent])
                == [6, 6, 10, 24]
            let right = Metrics(info: info(.right), labelWidth: 8, fontSize: 10)
            expect([right.leadingPad, right.trailingPad, right.gap, right.headIndent])
                == [12, 0, 10, 18]
            // 라벨이 영역보다 넓으면 라벨 폭이 영역이다.
            let wide = Metrics(info: info(.right), labelWidth: 25, fontSize: 10)
            expect([wide.leadingPad, wide.trailingPad, wide.headIndent]) == [0, 0, 35]
        }

        /// 자릿수 맞춤 + 음수 너비 조정은 거리를 깎고, HWPUNIT 거리는 글자 크기와
        /// 무관하다.
        func testMetricsApplyNegativeAdjustAndHwpUnitOffset() {
            let negative = CoreHwp.HwpParaHeadInfo(
                alignment: .left, useInstWidth: true, autoIndent: true,
                textOffsetType: .percent, numberFormat: 0, widthAdjust: -300, textOffset: 50
            )
            let shrunk = HwpTextRunBuilder.NumberingHeadingMetrics(
                info: negative, labelWidth: 8, fontSize: 10
            )
            expect([shrunk.leadingPad, shrunk.trailingPad, shrunk.gap, shrunk.headIndent])
                == [0, -3, 5, 10]
            expect(shrunk.gapSpaceWidth) == 2

            // 보정값이 거리보다 크게 음수면 빈칸 폭은 0으로 접히고 내어쓰기 전진량도
            // 같은 값(라벨 폭)이다 — 첫 줄 본문과 둘째 줄이 같은 x에 놓인다.
            let collapsed = CoreHwp.HwpParaHeadInfo(
                alignment: .left, useInstWidth: true, autoIndent: true,
                textOffsetType: .percent, numberFormat: 0, widthAdjust: -1000, textOffset: 50
            )
            let clamped = HwpTextRunBuilder.NumberingHeadingMetrics(
                info: collapsed, labelWidth: 8, fontSize: 10
            )
            expect([clamped.trailingPad, clamped.gapSpaceWidth, clamped.headIndent]) == [-10, 0, 8]

            let absolute = CoreHwp.HwpParaHeadInfo(
                alignment: .left, useInstWidth: true, autoIndent: true,
                textOffsetType: .hwpUnit, numberFormat: 0, textOffset: 1000
            )
            let fixed = HwpTextRunBuilder.NumberingHeadingMetrics(
                info: absolute, labelWidth: 8, fontSize: 24
            )
            expect(fixed.gap) == 10
            expect(fixed.headIndent) == 18
        }

        /// 여러 줄 문단: 라벨은 첫 줄에 한 번이고, 둘째 줄부터는 자동 내어쓰기로 첫 줄
        /// 본문 시작 x(라벨 폭 + 거리)에서 시작한다 — 렌더 줄(`HwpDrawnTextLayout.lines`)
        /// 의 시작 x로 직접 잰다.
        func testMultiLineParagraphHangsFollowingLinesAtTheBodyStart() throws {
            let attributed = try Support.build(String(repeating: "가나다 ", count: 60), runs: [(0, 0)])
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: 160
            )
            let hanging = try XCTUnwrap(attributed.attribute(
                HwpAttributedStringKey.numberingHeadIndent, at: 0, effectiveRange: nil
            ) as? NSNumber)

            expect(lines.count) > 2
            expect(lines[0].stringRange.location) == 0
            expect(lines[0].baselineOrigin.x) == 0
            for line in lines.dropFirst() {
                expect(line.baselineOrigin.x)
                    .to(beCloseTo(CGFloat(hanging.doubleValue), within: 0.01))
            }
            // 양쪽 정렬(표 44 정렬 0)의 첫 줄에서도 라벨 거리 빈칸은 벌어지지 않아
            // 본문 첫 글자가 둘째 줄 시작과 같은 x에 놓인다. 캐럿 오프셋
            // (`CTLineGetOffsetForStringIndex`)은 kern을 반씩 나눠 놓으므로 글리프
            // 위치로 잰다.
            let bodyStart = try XCTUnwrap(Support.glyphX(ofStringIndex: 3, in: lines[0].line))
            expect(lines[0].baselineOrigin.x + bodyStart)
                .to(beCloseTo(CGFloat(hanging.doubleValue), within: 0.01))
            // 라벨 표식은 첫 줄 안에만 있다.
            var labelRange = NSRange(location: NSNotFound, length: 0)
            _ = attributed.attribute(
                HwpAttributedStringKey.numberingLabel, at: 0,
                longestEffectiveRange: &labelRange,
                in: NSRange(location: 0, length: attributed.length)
            )
            expect(NSMaxRange(labelRange)) <= NSMaxRange(lines[0].stringRange)
        }

        /// 빈칸 없는 본문(한글 문서의 흔한 형태)의 양쪽 정렬: 첫 줄은 라벨 거리 빈칸을
        /// 그대로 두고 본문 글자 사이만 벌려 줄 폭을 채우고, 둘째 줄부터는 CT 정렬로
        /// 채운다 — 어느 줄도 자연 폭으로 줄어들지 않는다.
        func testSpacelessBodyStaysJustifiedWithTheLabelGapFixed() throws {
            let attributed = try Support.build(String(repeating: "가나다라", count: 40), runs: [(0, 0)])
            let width: CGFloat = 153
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: width
            )
            let hanging = try XCTUnwrap(attributed.attribute(
                HwpAttributedStringKey.numberingHeadIndent, at: 0, effectiveRange: nil
            ) as? NSNumber)
            expect(lines.count) > 2
            let bodyStart = try XCTUnwrap(Support.glyphX(ofStringIndex: 3, in: lines[0].line))
            expect(bodyStart).to(beCloseTo(CGFloat(hanging.doubleValue), within: 0.01))
            for line in lines.dropLast() {
                let inkWidth = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
                    - CGFloat(CTLineGetTrailingWhitespaceWidth(line.line))
                expect(line.baselineOrigin.x + inkWidth).to(beCloseTo(width, within: 0.05))
            }
        }

        /// 이어지는 조각의 문단 스타일: 첫 줄 들여쓰기가 둘째 줄 들여쓰기로 바뀌고 나머지
        /// 설정은 그대로다. 두 값이 같은 문단은 원본을 돌려준다.
        func testContinuationFragmentAlignsItsFirstLineWithTheHangingIndent() throws {
            let attributed = try Support.build(String(repeating: "가나다 ", count: 30), runs: [(0, 0)])
            let fragment = attributed.attributedSubstring(from: NSRange(location: 12, length: 20))
            let continued = HwpParagraphLayout.continuationFragment(fragment)

            expect(Support.styleValue(.firstLineHeadIndent, in: fragment)) == 0
            expect(Support.styleValue(.firstLineHeadIndent, in: continued))
                == Support.styleValue(.headIndent, in: fragment)
            expect(Support.styleValue(.headIndent, in: continued))
                == Support.styleValue(.headIndent, in: fragment)
            expect(Support.styleValue(.maximumLineHeight, in: continued))
                == Support.styleValue(.maximumLineHeight, in: fragment)
            expect(continued.string) == fragment.string

            let plain = try Support.build("가나", runs: [(0, 0)], number: nil)
            expect(HwpParagraphLayout.continuationFragment(plain)) === plain
        }
    }
#endif
