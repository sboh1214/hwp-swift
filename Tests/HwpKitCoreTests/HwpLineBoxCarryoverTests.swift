import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 청크 이월이 **다음 자리에 빌려 주는** 값의 계약 (#178 리뷰).
    ///
    /// 미완 줄이 없는 이월은 그 청크 마지막 줄의 배치 ascent를 다음 청크 첫 줄에 빌려 준다 —
    /// 같은 문단이 이어지는 흔한 경우에 그 값이 그 자리의 값이고, 새 프레임의 첫 슬롯 특례를
    /// 타는 것보다 가깝다. 그러나 그 값이 **앞 줄에서 받은 몫**(CT가 다음 줄 슬롯에 얹는 글꼴
    /// leading)을 품고 있으면 다음 자리의 몫과 다를 수 있어, 그대로 쓰면 경계마다 되풀이된다.
    final class HwpLineBoxCarryoverTests: XCTestCase {
        /// **부풀려진 이월 ascent를 다음 자리에 되풀이 쓰면 안 된다** (#178 리뷰). CT는 글꼴
        /// leading을 그 줄이 아니라 **다음 줄** 슬롯에 얹으므로 (임계 실측: ascent·descent가
        /// 같고 leading만 다른 글꼴로 한 글자를 바꾸면 그 줄 슬롯은 24.0 그대로고 다음 줄이
        /// 26.0이 된다), 미완 줄 없는 이월이 그 부풀려진 ascent를 다음 자리에 빌려 주면
        /// 경계마다 되풀이된다 — 앞 커밋에서 Hiragino Sans 한 글자로 예산 14에서 **20.2998pt**,
        /// 예산 16에서 10.2998pt였다. 지금은 부풀린 몫이 다른 자리면 쓰지 않는다.
        ///
        /// 남는 잔차는 **버린 몫을 대신 세우지 못하는 것**이다 — 이월을 버리면 그 프레임의
        /// `floor`를 쓰는데 그 값은 앞 줄의 몫을 모른다. 그래서 줄마다 청크가 갈리는 아주 작은
        /// 예산(12·14)에서 4.4004pt가 남고, 예산 16 이상은 1.0pt 안이다 (전진량 축 #180·#192).
        func testInflatedCarryIsNotReusedAtTheNextSlot() throws {
            let name = try XCTUnwrap(
                LineBoxFixtures.nameOfFontWithLeading(), "leading이 있는 글꼴이 없는 기기"
            )
            for position in [12, 20, 24, 28, 36, 44] {
                let string = LineBoxFixtures.paragraphWithLeadingRun(at: position, fontName: name)
                let whole = LineBoxFixtures.baselines(
                    string, lineWidth: LineBoxFixtures.paragraphWidth
                )
                for budget in [12, 14, 16, 18, 20, 24, 28, 32, 40] {
                    let chunked = HwpDrawnTextLayout.lines(
                        attributedString: string, origin: CGPoint(x: 0, y: 100),
                        lineWidth: LineBoxFixtures.paragraphWidth, maxLineFrames: budget
                    ).map(\.baselineOrigin.y)
                    guard chunked.count == whole.count else { continue }
                    let drift = zip(chunked, whole).map { abs(Double($0 - $1)) }.max() ?? 0
                    let label = "위치 \(position)·예산 \(budget)"
                    // 한 경계 몫(4.4004)까지만 남는다 — 되풀이되면 20pt를 넘었다.
                    expect(drift).to(beLessThan(4.5), description: label)
                    if budget >= 16 {
                        expect(drift).to(beLessThan(1.0), description: label)
                    }
                }
            }
        }

        /// **글자 위치가 든 줄의 부풀려진 슬롯을 다음 자리에 이월하면 안 된다** (#197 리뷰).
        ///
        /// CT는 `kCTBaselineOffset`을 무시하지 않는다 — 2026-09-14 실측(macOS 27.0):
        /// 글리프를 실제로 옮기고(`CTRunGetPositions`의 y), 줄 지표를
        /// `ascent = max(글꼴 ascent + 오프셋)` · `descent = max(글꼴 descent − 오프셋)`으로
        /// 합성하며, 그 줄의 **슬롯 자체**가 그만큼 커진다(프레임 높이 임계 이분 탐색:
        /// 12.2996 → 14.2996). 그런데 `LineMetrics`는 글꼴 지표만 걷어, 오프셋이 든 줄과
        /// 없는 줄이 `boxHeight 10 · maxAscent 7.7002 · maxDescent 2.2998`로 **완전히 같게**
        /// 나왔다. 그래서 `matchesSlot`이 서로 다른 슬롯을 같다고 판정해, 부풀려진 배치
        /// ascent가 오프셋 없는 다음 줄에 그대로 쓰였다 — 예산 12에서 뒤 줄 간격이
        /// 12.000 → 14.300, 마지막 줄이 전체 조판보다 **16.099pt** 아래였다(그중 14.000pt가
        /// 이 몫이고 2.099pt는 위 테스트가 문서화한 `floor` 잔차다).
        ///
        /// 오프셋 위치를 옮기면 예산 13~37의 여러 칸에서도 정확히 오프셋 크기(2.000pt)만큼
        /// 어긋났다 — 예산 12 한 점의 문제가 아니라 **오프셋 줄이 청크 경계에 걸리는 모든
        /// 배치**의 문제다.
        func testBaselineOffsetSlotIsNotCarriedToAPlainLine() {
            for position in [4, 10, 22, 34, 46, 58] {
                for offset in [CGFloat(2), -2] {
                    let string = LineBoxFixtures.paragraphWithBaselineOffsetRun(
                        at: position, offset: offset
                    )
                    let whole = LineBoxFixtures.baselines(
                        string, lineWidth: LineBoxFixtures.paragraphWidth
                    )
                    for budget in [12, 13, 14, 16, 20, 24, 25, 32, 36, 37, 48] {
                        let chunked = HwpDrawnTextLayout.lines(
                            attributedString: string, origin: CGPoint(x: 0, y: 100),
                            lineWidth: LineBoxFixtures.paragraphWidth, maxLineFrames: budget
                        ).map(\.baselineOrigin.y)
                        guard chunked.count == whole.count else { continue }
                        let drift = zip(chunked, whole).map { abs(Double($0 - $1)) }.max() ?? 0
                        let label = "위치 \(position)·오프셋 \(offset)·예산 \(budget)"
                        // 수정 전에는 위치 4·10의 예산 12에서 16.099였고 나머지 위치는
                        // 여러 예산에서 정확히 오프셋 크기(2.000)만큼 어긋났다. 지금 남는
                        // 최대값은 2.099로, 같은 문단에서 오프셋만 0으로 바꾼 대조군의
                        // 예산 12 값과 **같다** — 이월을 버리고 `floor`를 쓸 때의 잔차라
                        // 오프셋과 무관한 축(#180·#192)의 몫이다.
                        expect(drift).to(beLessThan(2.2), description: label)
                    }
                }
            }
        }

        /// 오프셋이 든 줄과 없는 줄의 **슬롯 지표가 갈려야** 한다 — 위 테스트가 재는 결과의
        /// 원인을 지표 수준에서 바로 고정한다. 오프셋 몫은 `maxAscent`(양수)·`maxDescent`
        /// (음수)에 접혀 들어가고, 앵커용 `boxHeight`는 그대로다(상대크기 전 기본 크기라
        /// 오프셋과 무관하다).
        func testBaselineOffsetSplitsSlotMetrics() {
            let style = LineBoxFixtures.paragraphStyle(specs: [(.minimumLineHeight, 12)])
            var attributes = LineBoxFixtures.attributes(size: 10, style: style)
            let plain = HwpDrawnTextLayout.lineMetrics(
                of: CTLineCreateWithAttributedString(
                    NSAttributedString(string: "aaa", attributes: attributes)
                )
            )
            attributes[kCTBaselineOffsetAttributeName as NSAttributedString.Key] =
                NSNumber(value: 2.0)
            let raised = HwpDrawnTextLayout.lineMetrics(
                of: CTLineCreateWithAttributedString(
                    NSAttributedString(string: "aaa", attributes: attributes)
                )
            )
            expect(raised.matchesSlot(of: plain)).to(beFalse())
            expect(Double(raised.maxAscent - plain.maxAscent)).to(beCloseTo(2.0, within: 0.001))
            expect(Double(raised.maxDescent - plain.maxDescent))
                .to(beCloseTo(-2.0, within: 0.001))
            expect(Double(raised.boxHeight)).to(beCloseTo(Double(plain.boxHeight), within: 0.001))
        }
    }
#endif
