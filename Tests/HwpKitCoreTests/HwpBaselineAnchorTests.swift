import CoreGraphics
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

        /// **줄마다 자기 상자 앵커를 쓴다** — 청크 첫 줄의 앵커를 나머지 줄에 쓰면
        /// 키 큰 개체가 첫 줄이 아닌 줄에서 그 줄 글자·장식선이 개체 높이의 0.85배만큼
        /// 어긋난다 (헌법주석 구역 24에 그 배치가 있다). 상자 상단은 CT 줄 origin으로
        /// 독립 재구성해 구현 내부를 믿지 않는다.
        func testEachLineUsesItsOwnBoxAnchor() {
            let string = Self.attributedString(Input(
                size: 10, baseSize: 10, text: "ab\n", delegateHeight: 60, delegateAtEnd: true
            ))
            let lines = HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: 200
            )
            expect(lines.count).to(equal(2))
            guard lines.count == 2 else { return }
            let origins = Self.frameLineOrigins(string, lineWidth: 200)
            expect(origins.count).to(equal(2))
            guard origins.count == 2 else { return }
            // 첫 줄 상자 상단 = 블록 상단, 나머지는 CT origin 델타로 타일된다.
            let boxTops = origins.map { 100 + origins[0].y - $0.y }
            expect(lines[0].baselineOrigin.y - boxTops[0]).to(equal(8.5))
            expect(lines[1].baselineOrigin.y - boxTops[1]).to(equal(51.0))
        }

        /// `HwpLineBreaker.nextFrameChunk`와 같은 꼴로 프레임을 만들어 CT 줄 origin을
        /// 돌려준다 — 테스트가 구현의 청크 기하를 재사용하지 않고 직접 재구성한다.
        private static func frameLineOrigins(
            _ string: NSAttributedString, lineWidth: CGFloat
        ) -> [CGPoint] {
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: string.length), nil,
                CGSize(width: lineWidth, height: .greatestFiniteMagnitude), nil
            )
            let height = max(ceil(suggested.height), 1)
            let path = CGPath(
                rect: CGRect(x: 0, y: 0, width: lineWidth, height: height), transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: string.length), path, nil
            )
            let count = (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
            var origins = [CGPoint](repeating: .zero, count: count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            return origins
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
