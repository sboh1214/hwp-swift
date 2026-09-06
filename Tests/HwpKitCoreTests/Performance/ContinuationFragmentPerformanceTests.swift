@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 이어지는 조각의 문단 스타일 보정(`HwpParagraphLayout.continuationFragment`)은
    /// 조각 길이에 비례해야 한다 (#154 리뷰). 원문에서 앞뒤 문단 구분자를 찾는 구현
    /// (`NSString.getParagraphStart`)은 줄바꿈 없는 긴 문단에서 조각마다 원문 전체를
    /// 훑어 분할 비용이 이차로 늘었다 — 리뷰 실측: 3,000자 조각으로 100만 자 0.82초,
    /// 500만 자 20초.
    ///
    /// 기본 (CI): 300만 자 스모크 + 폭주 방지 상한. `HWP_PERF=1`: 500만 자 실측.
    final class ContinuationFragmentPerformanceTests: XCTestCase {
        func testContinuationFragmentCostIsLinearInFragmentLength() {
            let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
            let characterCount = full ? 5_000_000 : 3_000_000
            let fragmentLength = 3000
            // 내어쓰기 문단(첫 줄 0·둘째 줄부터 20pt) — 보정이 실제로 일어나는 형태.
            let paraShape = CoreHwp.HwpParaShape(
                property1: 0, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 0
            )
            let body = NSMutableAttributedString(string: String(repeating: "가", count: characterCount))
            body.addAttribute(
                HwpAttributedStringKey.numberingHeadIndent, value: NSNumber(value: 20),
                range: NSRange(location: 0, length: 1)
            )
            body.addAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: HwpParagraphLayout.paragraphStyle(for: paraShape, attributedString: body),
                range: NSRange(location: 0, length: body.length)
            )

            let clock = ContinuousClock()
            let start = clock.now
            var corrected = 0
            var fragments = 0
            var location = 0
            while location < body.length {
                let range = NSRange(location: location, length: min(fragmentLength, body.length - location))
                let fragment = HwpParagraphLayout.continuationFragment(of: body, range: range)
                fragments += 1
                // 실제로 보정된 조각만 센다 — 첫 줄 들여쓰기가 둘째 줄 값(20pt)으로 바뀐 것.
                if Self.firstLineHeadIndent(of: fragment) == 20 {
                    corrected += 1
                }
                location += fragmentLength
            }
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(
                "HWP_PERF continuation fragment: chars=\(characterCount) "
                    + "time=\(String(format: "%.3f", seconds))s"
            )
            // 마지막 짧은 조각까지 센다 (올림 나눗셈) — 첫 조각만 보정 대상이 아니다.
            let expectedFragments = (characterCount + fragmentLength - 1) / fragmentLength
            expect(fragments) == expectedFragments
            expect(corrected) == expectedFragments - 1
            // 실측(2026-09-06 로컬): 300만 자 약 0.1s. 원문 전수 탐색 구현은 같은 입력에서
            // 약 7초(이차 증가)다.
            expect(seconds) < (full ? 5.0 : 3.0)
        }

        private static func firstLineHeadIndent(of fragment: NSAttributedString) -> CGFloat {
            guard let value = fragment.attribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key, at: 0, effectiveRange: nil
            ) else { return -1 }
            let reference = value as CFTypeRef
            guard CFGetTypeID(reference) == CTParagraphStyleGetTypeID() else { return -1 }
            var indent: CGFloat = -1
            CTParagraphStyleGetValueForSpecifier(
                unsafeBitCast(reference, to: CTParagraphStyle.self),
                .firstLineHeadIndent, MemoryLayout<CGFloat>.size, &indent
            )
            return indent
        }
    }
#endif
