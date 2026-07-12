@testable import CoreHwp
import Foundation
import Nimble
import XCTest

#if canImport(Darwin)
    import Darwin
#endif

/// 파서 성능 baseline — 합성 대형 섹션의 파스 시간과 파스 후 상주 메모리.
///
/// 기본 (CI): N=1,000 스모크 + 폭주 방지용 넉넉한 상한만 확인한다.
/// `HWP_PERF=1`: N=20,000 (약 1.6M자, 1,030쪽급) 전체 파라미터로 실측한다.
/// 실측 수치는 콘솔 출력으로 기록한다 — 타이트 임계는 개선 커밋 완료 후 확정.
///
/// baseline (2026-07-12 로컬, 개선 전): N=20,000 파스 1.47s · 상주 +227.0MB
/// (HwpChar 문자당 ~80B + rawPayload 섹션 버퍼 상주가 지배).
final class ParserPerformanceTests: XCTestCase {
    func testParseLargeSyntheticSectionBaseline() throws {
        let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
        let paragraphCount = full ? 20000 : 1000
        let data = SyntheticLargeDocument.sectionData(
            paragraphCount: paragraphCount,
            charactersPerParagraph: 80
        )

        let residentBefore = Self.residentMemoryBytes()
        let clock = ContinuousClock()
        let start = clock.now
        let section = try HwpSection.load(data, SyntheticLargeDocument.version)
        let elapsed = clock.now - start
        let residentAfter = Self.residentMemoryBytes()

        expect(section.paragraph.count) == paragraphCount
        expect(section.paragraph.last?.paraText?.charArray.isEmpty) == false

        let seconds = Self.seconds(of: elapsed)
        let residentDelta = Self.megabytes(from: residentBefore, to: residentAfter)
        print(
            "HWP_PERF parse: N=\(paragraphCount) stream=\(data.count / 1024)KB "
                + "time=\(String(format: "%.3f", seconds))s"
                + (residentDelta.map { " resident+=\(String(format: "%.1f", $0))MB" } ?? "")
        )

        // 폭주 방지 상한 — 러너 편차를 흡수하는 넉넉한 값 (타이트 게이트 아님)
        expect(seconds) < (full ? 60.0 : 10.0)
        withExtendedLifetime(section) {}
    }

    // MARK: - 계측 헬퍼

    static func seconds(of duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    static func megabytes(from before: UInt64?, to after: UInt64?) -> Double? {
        guard let before, let after, after >= before else { return nil }
        return Double(after - before) / 1_048_576
    }

    /// 현재 프로세스 상주 메모리 (macOS mach API — Linux는 nil)
    static func residentMemoryBytes() -> UInt64? {
        #if canImport(Darwin)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(
                        mach_task_self_,
                        task_flavor_t(MACH_TASK_BASIC_INFO),
                        $0,
                        &count
                    )
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return info.resident_size
        #else
            return nil
        #endif
    }
}
