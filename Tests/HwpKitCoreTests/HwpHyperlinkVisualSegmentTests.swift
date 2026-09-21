import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 스팬에 속한 run 범위를 잇닿은 구간으로 합치는 규칙 (`visualSegments`).
    final class HwpHyperlinkVisualSegmentTests: XCTestCase {
        private typealias Extent = HwpDrawnTextLayout.RunExtent

        /// 화면 순서 [A][B][A]: 스팬 A는 구간 둘, 스팬 B는 그 사이 하나.
        func testSplitsAroundAForeignRun() {
            let extents = [
                Extent(range: CFRange(location: 0, length: 4), minX: 0, maxX: 18.9),
                Extent(range: CFRange(location: 5, length: 2), minX: 18.9, maxX: 28.8),
                Extent(range: CFRange(location: 4, length: 1), minX: 28.8, maxX: 35.3),
            ]
            let first = HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 5)
            )
            let second = HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 5, length: 2)
            )

            expect(first) == [0 ... 18.9, 28.8 ... 35.3]
            expect(second) == [18.9 ... 28.8]
        }

        /// 잇닿은 run은 하나로 합치고 (경계 오차 0.001 안), 폭 0 run은 버리며, 스팬 경계에
        /// 걸친 run은 **첫 글자가 든 스팬** 것이다 — 자소 묶음(첫가끝 자모·ZWJ 열·lam-alef)을
        /// CT가 경계 너머까지 한 run으로 내기 때문에 포함으로 물으면 그 run이 양쪽에서 버려진다.
        func testJoinsAdjacentRunsDropsEmptyOnesAndAssignsStraddlersToTheirFirstCharacter() {
            let extents = [
                Extent(range: CFRange(location: 0, length: 2), minX: 0, maxX: 10),
                Extent(range: CFRange(location: 2, length: 1), minX: 10.0005, maxX: 10.0005),
                Extent(range: CFRange(location: 3, length: 2), minX: 10.0005, maxX: 20),
                Extent(range: CFRange(location: 5, length: 3), minX: 20, maxX: 30),
            ]
            // 스팬 [0, 6): 마지막 run [5, 8)은 경계에 걸치지만 첫 글자 5가 스팬 안이라 이 스팬 것.
            expect(HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 6)
            )) == [0 ... 30]
            // 스팬 [6, 2): 그 run의 첫 글자가 밖이라 아무것도 없다 — 구멍이 아니라 앞 스팬 몫.
            expect(HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 6, length: 2)
            )).to(beEmpty())
            // 폭 0 run만 든 스팬은 rect가 없다.
            expect(HwpDrawnTextLayout.visualSegments(
                of: [extents[1]], in: CFRange(location: 0, length: 6)
            )).to(beEmpty())
        }

        /// 진행 폭이 음수인 run(끝이 시작보다 왼쪽)은 정규화된 절대 구간으로 든다 — 역전된
        /// 범위로 `ClosedRange`를 만들면 트랩이다 (PR 리뷰).
        func testNegativeWidthExtentIsNormalized() {
            let extents = [
                Extent(range: CFRange(location: 0, length: 2), minX: 0, maxX: 10),
                Extent(range: CFRange(location: 2, length: 2), minX: 10, maxX: 9.8),
            ]
            expect(extents[1].minX) == 9.8
            expect(extents[1].maxX) == 10
            expect(HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 4)
            )) == [0 ... 10]
            expect(HwpDrawnTextLayout.visualSegments(
                of: [extents[1]], in: CFRange(location: 2, length: 2)
            )) == [9.8 ... 10]
        }

        /// 화면 순서가 흐트러진 입력도 x로 정렬해 합친다 — 결과는 순서와 무관하다.
        func testOrderIndependent() {
            let extents = [
                Extent(range: CFRange(location: 2, length: 2), minX: 20, maxX: 30),
                Extent(range: CFRange(location: 0, length: 2), minX: 10, maxX: 20),
            ]
            expect(HwpDrawnTextLayout.visualSegments(
                of: extents, in: CFRange(location: 0, length: 4)
            )) == [10 ... 30]
        }
    }
#endif
