@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 조판 성능 baseline — 절대 캐시 모드 (한/글 2007 계열, 1,030쪽급 실문서와
    /// 같은 경로)의 전량 페이지네이션 시간.
    ///
    /// 기본 (CI): N=1,000 스모크 + 폭주 방지 상한만. `HWP_PERF=1`: N=20,000 실측.
    ///
    /// baseline (2026-07-12 로컬, 개선 전): N=20,000 → 589쪽 13.08s
    /// (문단마다 CT 측정 강제 — 절대 캐시 모드 CT 생략이 주 개선 대상).
    final class PaginatorPerformanceTests: XCTestCase {
        func testPaginateLargeSyntheticAbsoluteCacheDocumentBaseline() async throws {
            let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
            let paragraphCount = full ? 20000 : 1000
            let linesPerPage = 34
            let bodyParagraphs = try (0 ..< paragraphCount).map { index in
                try HwpSynthetic.lineSegParagraph(
                    perfParagraphText(index: index),
                    segments: [(
                        location: Int32(2720 + (index % linesPerPage) * 2100),
                        height: 1500
                    )]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: bodyParagraphs
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let clock = ContinuousClock()
            let start = clock.now
            let totalPages = await paginator.totalPages()
            let elapsed = clock.now - start

            // wrap마다 페이지 확정 — 대략 문단 수 / 페이지당 줄 수
            expect(totalPages) >= paragraphCount / linesPerPage
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(
                "HWP_PERF paginate: N=\(paragraphCount) pages=\(totalPages) "
                    + "time=\(String(format: "%.3f", seconds))s"
            )
            // HWP_PERF 임계 = 개선 후 실측(~7.6s) + 여유. 스모크는 폭주 방지용.
            expect(seconds) < (full ? 15.0 : 60.0)
        }

        /// 문단마다 내용이 다른 본문 텍스트 (~80 UTF-16 단위)
        private func perfParagraphText(index: Int) -> String {
            var text = "제\(index)문단 "
            while text.utf16.count < 80 {
                text += "가나다라마바사아자차카타파하 조판 계측 본문 "
            }
            return String(decoding: Array(text.utf16.prefix(80)), as: UTF16.self)
        }
    }
#endif
