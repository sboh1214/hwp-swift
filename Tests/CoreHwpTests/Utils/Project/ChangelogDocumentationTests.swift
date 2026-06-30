import Foundation
import Nimble
import XCTest

final class ChangelogDocumentationTests: XCTestCase {
    func testChangelogDocumentsBreakingReaderApiChanges() throws {
        let changelog = try String(contentsOf: changelogURL(), encoding: .utf8)

        expect(changelog).to(contain("### Breaking Changes"))
        expect(changelog).to(contain("Sources/CoreHwp/Enums/HwpBorderType.swift"))
        expect(changelog).to(contain("`HwpBorderType.rawValue`"))
        expect(changelog).to(contain("`none = 0`"))
        expect(changelog).to(contain("`0`, `1`, `2`에서 `1`, `2`, `3`"))
        expect(changelog).to(contain(
            "Sources/CoreHwp/Models/Section/CtrlHeader/Field/HwpFieldControl.swift"
        ))
        expect(changelog).to(contain("`HwpFieldControl` `Codable` 형상"))
        expect(changelog).to(contain("`properties`"))
        expect(changelog).to(contain("`propertyInfo`"))
        expect(changelog).to(contain("`extraProperties`"))
        expect(changelog).to(contain("`command`, `fieldId`, `memoIndex`"))
        expect(changelog).to(contain("public reader model의 `Codable` snapshot 형상"))
        expect(changelog).to(contain("`HwpBorderFill.borderLineArray`"))
        expect(changelog).to(contain("`HwpSectionDef.property`/`propertyInfo`"))
        expect(changelog).to(contain("`HwpEquationEdit.rawTrailing`"))
    }
}

private func changelogURL() -> URL {
    testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("CHANGELOG.md")
}
