import Foundation
import Nimble
import XCTest

final class CoverageWorkflowTests: XCTestCase {
    func testCoverageWorkflowSelectsCoverageInstrumentedDebugBundle() throws {
        let workflow = try String(contentsOf: coverageWorkflowURL(), encoding: .utf8)

        // Release·Debug-iphonesimulator 산출물을 배제하고 SF 레코드가 가장 많은
        // macOS Debug 번들 하나를 골라 export한다 (#106). 병합 번들 이름 하드코딩은
        // 두 빌드 시스템 중 한쪽에서 반드시 깨지므로 금지한다.
        expect(workflow).to(contain("find .build -name '*.xctest' -type d"))
        expect(workflow).to(contain("grep -E '/(Debug|debug)/'"))
        expect(workflow).notTo(contain("*PackageTests.xctest"))
        expect(workflow).to(contain("No Debug XCTest bundle found"))
        expect(workflow).to(contain("No coverage-instrumented test bundle found"))
        expect(workflow).to(contain("coverage.lcov"))
    }

    func testCoverageWorkflowEnforcesPerPathLineCoverageThresholds() throws {
        let workflow = try String(contentsOf: coverageWorkflowURL(), encoding: .utf8)

        expect(workflow).to(contain("Enforce coverage thresholds"))
        expect(workflow).to(contain("coverage < threshold"))

        // 관측 전용 경로의 수치 기록(print)과 임계 미달의 실패 수집(append)·보고(raise)를
        // 각각 따로 고정한다 — 셋 중 하나만 무력화해도 게이트나 관측이 조용히 죽는다.
        expect(workflow).to(contain(#"print(f"{path} line coverage: "#))
        expect(workflow).to(contain(#"failures.append(f"{path} line coverage"#))
        expect(workflow).to(contain("is below"))
        expect(workflow).to(contain(#"raise SystemExit("\n".join(failures))"#))

        let targets = coverageTargets(in: workflow)
        expect(targets.map(\.path)) == [
            "Sources/CoreHwp/",
            "Sources/HwpKitCore/",
            "Sources/HwpKitNative/",
            "Sources/HwpKit/",
        ]

        guard let coreHwp = targets.first(where: { $0.path == "Sources/CoreHwp/" }),
              let coreHwpThreshold = coreHwp.threshold
        else {
            return fail(
                "Expected CI workflow to declare a numeric Sources/CoreHwp/ coverage threshold"
            )
        }

        expect(coreHwpThreshold).to(beGreaterThanOrEqualTo(95.0))

        guard let hwpKitCore = targets.first(where: { $0.path == "Sources/HwpKitCore/" }),
              let hwpKitCoreThreshold = hwpKitCore.threshold
        else {
            return fail(
                "Expected CI workflow to declare a numeric Sources/HwpKitCore/ coverage threshold"
            )
        }

        expect(hwpKitCoreThreshold).to(beGreaterThanOrEqualTo(91.0))
    }
}

private func coverageWorkflowURL() -> URL {
    testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".github")
        .appendingPathComponent("workflows")
        .appendingPathComponent("ci.yml")
}

/// 게이트 스텝의 `("<경로>", <임계|None>)` 쌍 목록을 선언 순서대로 파싱한다.
/// `None`(관측 전용)은 threshold nil로 나타낸다.
private func coverageTargets(in workflow: String) -> [(path: String, threshold: Double?)] {
    let pattern = #"\("(Sources/[A-Za-z]+/)",\s*(None|[0-9]+(?:\.[0-9]+)?)\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    let fullRange = NSRange(workflow.startIndex..., in: workflow)
    return regex.matches(in: workflow, range: fullRange).compactMap { match in
        guard let pathRange = Range(match.range(at: 1), in: workflow),
              let valueRange = Range(match.range(at: 2), in: workflow)
        else {
            return nil
        }
        return (
            path: String(workflow[pathRange]),
            threshold: Double(workflow[valueRange])
        )
    }
}
