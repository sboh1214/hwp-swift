import Foundation
import Nimble
import XCTest

final class CoverageWorkflowTests: XCTestCase {
    func testCoverageWorkflowEnforcesCoreHwpLineCoverageThreshold() throws {
        let workflow = try String(contentsOf: coverageWorkflowURL(), encoding: .utf8)

        expect(workflow).to(contain("Enforce CoreHwp coverage"))
        expect(workflow).to(contain("coverage.lcov"))
        expect(workflow).to(contain("Sources/CoreHwp/"))
        expect(workflow).to(contain("CoreHwp line coverage"))
        expect(workflow).to(contain("coverage < threshold"))
        expect(workflow).to(contain("find .build -name '*.xctest' -type d"))
        expect(workflow).notTo(contain("*PackageTests.xctest"))
        expect(workflow).to(contain("No XCTest bundle found"))
        expect(workflow).to(contain("No executable test binary found"))

        guard let threshold = coverageThreshold(in: workflow) else {
            return fail("Expected CI workflow to declare a numeric CoreHwp coverage threshold")
        }

        expect(threshold >= 95.0) == true
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

private func coverageThreshold(in workflow: String) -> Double? {
    guard let range = workflow.range(
        of: #"threshold\s*=\s*[0-9]+(\.[0-9]+)?"#,
        options: .regularExpression
    ) else {
        return nil
    }

    let assignment = workflow[range]
    guard let value = assignment.split(separator: "=").last else {
        return nil
    }
    return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
}
