@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 번호 형식 분해의 폭주 방지 — 형식이 표 38 WORD 길이(65,535 단위)만큼 길어도
    /// 출력 천장까지만 훑어야 한다. 스칼라 뷰를 배열로 펼치면 천장이 있어도 호출마다
    /// 형식 전체를 복사·디코드해 N=2,000에서 이미 수 초, 20,000이면 수십 초다.
    ///
    /// 기본 (CI): N=2,000 스모크 + 폭주 방지 상한만. `HWP_PERF=1`: N=20,000 실측.
    final class NumberingPerformanceTests: XCTestCase {
        func testBoundedFormatParsingIsIndependentOfFormatLength() {
            let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
            let calls = full ? 20000 : 2000
            let format = String(repeating: "^1", count: 32767) + "."
            expect(format.utf16.count) == 65535

            let clock = ContinuousClock()
            let start = clock.now
            var tokens = 0
            for _ in 0 ..< calls {
                tokens += HwpNumberingFormatPattern.parse(
                    format, unitCeiling: HwpParagraphNumber.textUnitCeiling
                ).tokens.count
            }
            let elapsed = clock.now - start

            expect(tokens) == calls * HwpParagraphNumber.textUnitCeiling
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(
                "HWP_PERF numbering parse: N=\(calls) time=\(String(format: "%.3f", seconds))s"
            )
            // 실측(2026-09-06 로컬): N=20,000 약 0.4s. 스모크는 폭주 방지용 — 배열로
            // 펼치는 구현은 N=2,000에서도 수 초다.
            expect(seconds) < (full ? 5.0 : 3.0)
        }
    }
#endif
