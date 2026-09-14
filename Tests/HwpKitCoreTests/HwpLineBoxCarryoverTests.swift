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
    }
#endif
