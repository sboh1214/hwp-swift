import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 한글 줄 모델의 **베이스라인 앵커** 계약 (#178).
    ///
    /// 한글은 줄 상자 상단에서 `HwpRenderTuning.Text.baselineAnchorRatio`(0.85)만큼
    /// 내린 자리에 베이스라인을 둔다. 상자 높이는 그 줄 글자들의 **상대크기 적용 전
    /// 기본 크기**이고, 줄 간격 종류·값과 글꼴 지표는 앵커에 관여하지 않는다.
    ///
    /// 오라클: 한글 12.30.0 (2026-09-12) 가 저장한 줄 캐시(`PARA_LINE_SEG`)의
    /// `baseline` ÷ `vertsize`가 글자 크기 5·7·10·12·15·20·30·40pt × 줄 간격 종류
    /// 네 가지(비율 100~300%·고정 5~30pt·여백만 0~10pt·최소 5~30pt) × 글꼴 세 가지
    /// (함초롬바탕·함초롬돋움·Apple SD 산돌고딕 Neo) × 상대크기 50·170%의 34개 표본
    /// **전부에서 정확히 0.85**였고, 같은 문서를 한글이 내보낸 PDF의 텍스트 베이스라인이
    /// `vertpos + baseline`과 0.10pt(한글 PDF의 0.12pt 장치 양자화) 안에서 같았다.
    ///
    /// 종전 구현은 앵커를 **폰트 ascent**에서 역산해 (`ascent − 0.85 × 크기`를 CT가 준
    /// 줄 ascent에서 뺐다) 강제 줄 높이가 걸린 줄에서 베이스라인이 1~2pt 내려갔다.
    final class HwpBaselineAnchorTests: XCTestCase {
        private static let text = "가나다 Wg"

        /// 앵커 비율만으로 baseline이 정해지는지 — 줄 상자 상단(= origin.y) 아래
        /// `0.85 × 기본 크기`.
        private func baseline(
            size: CGFloat,
            baseSize: CGFloat? = nil,
            fontName: String = "Helvetica",
            forcedLineHeight: CGFloat? = nil,
            text: String = HwpBaselineAnchorTests.text,
            delegateHeight: CGFloat? = nil
        ) -> [CGFloat] {
            let string = Self.attributedString(Input(
                size: size, baseSize: baseSize, fontName: fontName,
                forcedLineHeight: forcedLineHeight, text: text, delegateHeight: delegateHeight
            ))
            return HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: 400
            ).map(\.baselineOrigin.y)
        }

        /// 한 줄 조판 입력 — 조판 문자열 빌더의 인자 묶음.
        private struct Input {
            var size: CGFloat
            var baseSize: CGFloat?
            var fontName = "Helvetica"
            var forcedLineHeight: CGFloat?
            var text = HwpBaselineAnchorTests.text
            var delegateHeight: CGFloat?
            /// 개체 마커를 문자열 **끝**에 붙인다 (기본은 앞)
            var delegateAtEnd = false
        }

        private static func attributedString(_ input: Input) -> NSAttributedString {
            let font = CTFontCreateWithName(input.fontName as CFString, input.size, nil)
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
            ]
            if let baseSize = input.baseSize {
                attributes[HwpAttributedStringKey.baseFontSize] = NSNumber(
                    value: Double(baseSize)
                )
            }
            if let forcedLineHeight = input.forcedLineHeight {
                attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] =
                    paragraphStyle(forcedLineHeight: forcedLineHeight)
            }
            let string = NSMutableAttributedString(string: input.text, attributes: attributes)
            if let delegateHeight = input.delegateHeight,
               let delegate = HwpInlineObjectReservation.runDelegate(
                   width: 20, height: delegateHeight
               )
            {
                var marker = attributes
                marker[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
                // 측정 경로(`inlineAnchors`)가 개체 앵커를 내려면 컨트롤 서수가 있어야 한다.
                marker[HwpAttributedStringKey.controlIndex] = NSNumber(value: 0)
                let markerString = NSAttributedString(string: "\u{FFFC}", attributes: marker)
                if input.delegateAtEnd {
                    string.append(markerString)
                } else {
                    string.insert(markerString, at: 0)
                }
            }
            return string
        }

        /// 비율 줄 간격 문단의 min = max 강제 줄 높이 (`HwpParagraphMetrics`와 같은 꼴)
        private static func paragraphStyle(forcedLineHeight: CGFloat) -> CTParagraphStyle {
            var minimum = forcedLineHeight
            var maximum = forcedLineHeight
            return withUnsafeMutablePointer(to: &minimum) { minimumPointer in
                withUnsafeMutablePointer(to: &maximum) { maximumPointer in
                    let settings = [
                        CTParagraphStyleSetting(
                            spec: .minimumLineHeight,
                            valueSize: MemoryLayout<CGFloat>.size, value: minimumPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .maximumLineHeight,
                            valueSize: MemoryLayout<CGFloat>.size, value: maximumPointer
                        ),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }

        // MARK: 앵커 규칙

        /// 강제 줄 높이를 어떻게 주어도 baseline은 상자 상단 아래 0.85em 하나다 —
        /// 종전 구현은 CT가 강제 높이 안에서 ascent를 다시 나눈 몫이 그대로 새어
        /// 100% 줄에서 −1.7pt, 300% 줄에서 +8.3pt로 벌어졌다.
        func testBaselineIgnoresTheForcedLineHeight() {
            for ratio in [100, 120, 130, 160, 200, 300] {
                let forced = 10 * CGFloat(ratio) / 100
                expect(self.baseline(size: 10, baseSize: 10, forcedLineHeight: forced))
                    .to(equal([108.5]), description: "줄 간격 \(ratio)%")
            }
        }

        /// 글꼴 지표에 무관 — ascent가 0.85em보다 큰 글꼴(Times)과 작은 글꼴(Menlo)이
        /// 같은 baseline을 낸다. 종전 구현은 `ascent − 0.85 × 크기`를 보정량으로 써
        /// 글꼴마다 다른 자리에 그렸다.
        func testBaselineDoesNotDependOnFontMetrics() {
            let anchors = ["Helvetica", "Times New Roman", "Menlo", "Apple SD Gothic Neo"]
                .map { self.baseline(size: 10, baseSize: 10, fontName: $0, forcedLineHeight: 16) }
            expect(anchors).to(equal(Array(repeating: [108.5], count: 4)))
        }

        /// 상대크기를 적용한 줄도 줄 상자는 **기본 크기**다 (한글 실측: 상대크기
        /// 170% 줄의 `vertsize`가 1000, `baseline`이 850으로 일반 줄과 같다).
        func testBaselineUsesTheBaseSizeNotTheRelativeSize() {
            expect(self.baseline(size: 17, baseSize: 10, forcedLineHeight: 16))
                .to(equal([108.5]))
            expect(self.baseline(size: 5, baseSize: 10, forcedLineHeight: 16))
                .to(equal([108.5]))
        }

        /// 기본 크기 표식이 없는 합성 문자열은 글자 크기로 떨어진다.
        func testBaselineFallsBackToTheFontSizeWithoutTheBaseSizeMarker() {
            expect(self.baseline(size: 20, baseSize: nil, forcedLineHeight: 32))
                .to(equal([117.0]))
        }

        /// 여러 크기 전수 — 앵커는 크기에 비례한다.
        func testBaselineScalesWithTheDeclaredSize() {
            for size in [CGFloat(5), 7, 10, 12, 15, 20, 30, 40] {
                expect(self.baseline(size: size, baseSize: size, forcedLineHeight: size * 1.6))
                    .to(equal([100 + size * 0.85]), description: "\(size)pt")
            }
        }

        /// 둘째 줄부터는 첫 줄 baseline에서 문단 전진량(강제 줄 높이)만큼 내려간다 —
        /// 앵커를 첫 줄에서 맞추면 나머지 줄이 따라온다.
        func testFollowingLinesSitOneAdvanceBelowTheFirst() {
            let baselines = baseline(
                size: 10, baseSize: 10, forcedLineHeight: 16,
                text: String(repeating: "가", count: 200)
            )
            expect(baselines.count).to(beGreaterThan(2))
            expect(baselines.first).to(equal(108.5))
            let deltas = Set(zip(baselines.dropFirst(), baselines).map { $0 - $1 })
            expect(deltas).to(equal([16]))
        }

        /// 키 큰 글자처럼 취급 개체가 줄에 있으면 줄 상자는 개체 높이다 (한글 실측:
        /// noori 1쪽 개체 문단의 `vertsize` 6134 · `baseline` 5214 = 0.85배).
        func testTallInlineObjectSetsTheLineBox() {
            expect(self.baseline(size: 10, baseSize: 10, delegateHeight: 60))
                .to(equal([151.0]))
            // 강제 줄 높이가 개체보다 크면 CT가 ascent를 그만큼 부풀리는데, 앵커는
            // 개체 높이의 0.85배 그대로다 (종전 산식은 부풀린 ascent를 기준점으로 썼다).
            expect(self.baseline(size: 10, baseSize: 10, forcedLineHeight: 96, delegateHeight: 60))
                .to(equal([151.0]))
        }

        /// 개체가 글자보다 작으면 상자는 글자 크기다.
        func testShortInlineObjectLeavesTheTextLineBox() {
            expect(self.baseline(size: 20, baseSize: 20, delegateHeight: 6))
                .to(equal([117.0]))
        }

        /// 폭 0 개체 마커만 있는 줄 — 상자는 **그 마커의 글자 크기**다. 자리 차지 개체
        /// 앵커·필드 표식·메모 앵커가 그 꼴이고 (`HwpTextRunBuilder.appendMarker`가 폭 0
        /// delegate를 단다), delegate 분기가 마커의 `baseFontSize`를 버리면 상자가 0이 되어
        /// baseline이 줄 상자 상단으로 올라간다 (noori 1쪽 자리 차지 그림 문단이 그 입력이다).
        func testMarkerOnlyLineUsesTheMarkerCharacterSize() {
            expect(self.baseline(size: 10, baseSize: 10, text: "", delegateHeight: 0))
                .to(equal([108.5]))
        }

        /// 첫 줄이 아닌 줄에 키 큰 글자처럼 취급 개체가 있어도 그 줄 글자가 **개체의
        /// 세로 구간 안에** 남는다 (헌법주석 구역 24에 그 배치가 있다).
        ///
        /// 줄 상자 상단은 CT가 그 줄에 준 슬롯에서 오고 (`placementAscent`), CT 줄 origin
        /// **델타**는 다음 줄의 커진 ascent를 이미 품고 있어 그것을 상자 간격으로 쓰면
        /// 글자가 개체보다 한참 아래로 내려간다 — 이 입력에서 42.5pt(= 0.85 × (60 − 10))
        /// 아래이고 개체 바닥보다도 43.3pt 낮았다.
        func testTallInlineObjectOnALaterLineKeepsTheTextInsideItsBox() {
            let objectHeight: CGFloat = 60
            let string = Self.attributedString(Input(
                size: 10, baseSize: 10, text: "ab\n",
                delegateHeight: objectHeight, delegateAtEnd: true
            ))
            let blockTop: CGFloat = 100
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: blockTop), lineWidth: 200
            )
            expect(lines.count).to(equal(2))
            guard lines.count == 2 else { return }
            // 첫 줄은 블록 상단 + 자기 앵커.
            expect(lines[0].baselineOrigin.y).to(equal(blockTop + 8.5))
            // 개체가 놓이는 자리는 측정 경로가 정한다 (`HwpObjectAnchorGeometry`와 같은 식).
            let frame = HwpParagraphLayout().layout(
                attributedString: string, paraShape: CoreHwp.HwpParaShape(), columnWidth: 200
            )
            expect(frame.lines.count).to(equal(2))
            expect(frame.lines.last?.inlineAnchors.count).to(equal(1))
            guard frame.lines.count == 2,
                  let anchor = frame.lines[1].inlineAnchors.first
            else { return }
            let objectBottom = blockTop + frame.lines[0].baseline + frame.lines[1].origin.y
            let objectTop = objectBottom - anchor.ascent
            let baseline = lines[1].baselineOrigin.y
            expect(baseline).to(beGreaterThan(objectTop), description: "개체 상단 아래")
            expect(baseline).to(beLessThanOrEqualTo(objectBottom), description: "개체 바닥 위")
            // 남은 격차: 개체 바닥 − baseline은 0.15 × 개체 높이여야 하는데 측정 경로가
            // 아직 CT 보고 ascent를 기준점으로 쓴다 (#195). 그 축은 여기서 잠그지 않는다.
        }

        /// 청크 경계에 **기본 글자 크기 변화**가 걸려도 이월이 앵커를 새지 않는다 (#178).
        ///
        /// 버린 마지막 줄은 미완이라 다음 청크에서 온전히 재조판된 줄과 앵커가 다르다
        /// (여기서는 10pt → 20pt로 0.85 × (20 − 10) = 8.5pt). baseline을 이월하면 그 앵커가
        /// 다음 청크에서 소거되지 않아 뒤 줄 전체가 8.5pt 밀린다 — 그래서 **상자 상단**을
        /// 이월한다. 남는 편차는 청크마다 프레임을 다시 잡는 데서 오는 근사 몫이고
        /// (이 입력에서 9.0pt — 종전 폰트 ascent 산식과 **같은 값**이다) 크기 변화와 무관하게
        /// 있던 축이다. 그래서 허용 오차는 그 근사를 담되 앵커 누출(+8.5pt → 17.5pt)은
        /// 못 담는 10.0pt다 — 이 가드가 잡는 것은 누출 하나다.
        func testChunkCarryoverDoesNotLeakTheIncompleteLineAnchor() {
            let string = NSMutableAttributedString(
                attributedString: Self.attributedString(
                    Input(size: 10, baseSize: 10, text: String(repeating: "a", count: 60))
                )
            )
            string.append(Self.attributedString(
                Input(size: 20, baseSize: 20, text: String(repeating: "B", count: 40))
            ))
            let origin = CGPoint(x: 0, y: 100)
            let uncapped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: origin, lineWidth: 120
            )
            let capped = HwpDrawnTextLayout.lines(
                attributedString: string, origin: origin, lineWidth: 120, maxLineFrames: 30
            )
            expect(capped.count).to(equal(uncapped.count))
            for (index, pair) in zip(capped, uncapped).enumerated() {
                expect(pair.0.baselineOrigin.y).to(
                    beCloseTo(pair.1.baselineOrigin.y, within: 10.0), description: "줄 \(index)"
                )
            }
        }

        /// `baselineAnchor`는 비율 상수를 그대로 쓴다 — 값 핀은
        /// `HwpRenderTuningTests`가, 여기서는 결합만 잠근다.
        func testAnchorIsTheTunedRatioOfTheLineBox() {
            let string = Self.attributedString(
                Input(size: 10, baseSize: 10, forcedLineHeight: 16)
            )
            let line = CTLineCreateWithAttributedString(string)
            expect(HwpDrawnTextLayout.baselineAnchor(of: line))
                .to(equal(10 * HwpRenderTuning.Text.baselineAnchorRatio))
        }
    }
#endif
