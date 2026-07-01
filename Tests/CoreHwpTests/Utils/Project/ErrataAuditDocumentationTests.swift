import Foundation
import Nimble
import XCTest

final class ErrataAuditDocumentationTests: XCTestCase {
    func testErrataAuditDocumentsSourceRevisionsAndFixturePolicy() throws {
        let audit = try errataAuditDocument()

        expect(audit).to(contain("한글문서파일형식_5.0_revision1.3.pdf"))
        expect(audit).to(contain(
            "https://github.com/edwardkim/rhwp/blob/devel/mydocs/tech/hwp_spec_errata.md"
        ))
        expect(audit).to(contain("1d8c25778edd44896208525a672570123a6892f7"))
        expect(audit).to(contain("10f5c51e65e0e8e9260cf1498972db14ea04c29e"))
        expect(audit).to(contain("rhwp sample은 보조 검증 단서로만 사용한다"))
        expect(audit).to(contain("직접 생성하거나 재저장한 `.hwp`"))
    }

    func testErrataAuditKeepsEveryKnownRhwpItemClassified() throws {
        let rows = try errataAuditRows()
        let itemIdentifiers = Set(rows.map(\.itemIdentifier))

        expect(itemIdentifiers) == expectedErrataItemIdentifiers
        for row in rows {
            expect(allowedErrataStatuses).to(contain(row.status))
        }
    }

    func testFixtureGatedErrataItemsHaveHancomFixtureRequests() throws {
        let needsFixtureItems = Set(
            try errataAuditRows()
                .filter { $0.status == "needs Hancom fixture" }
                .map(\.itemIdentifier)
        )
        let requestRows = try hancomFixtureRequestRows()
        let requestedItems = Set(requestRows.flatMap(\.errataItemIdentifiers))
        let requestedFixtureIds = Set(requestRows.map(\.fixtureId))

        expect(needsFixtureItems) == expectedFixtureGatedItemIdentifiers
        for item in needsFixtureItems {
            expect(requestedItems).to(contain(item))
        }
        expect(requestedFixtureIds) == expectedHancomFixtureRequestIds
    }
}

private let expectedErrataItemIdentifiers: Set<String> = [
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "10",
    "11",
    "12",
    "13",
    "14",
    "15",
    "16",
    "17",
    "18",
    "19",
    "20",
    "21",
    "22",
    "23",
    "24",
    "25",
    "26",
    "26b",
    "27",
    "28",
    "29",
    "30",
    "31a",
    "EQEDIT",
    "31b",
    "32",
]

private let expectedFixtureGatedItemIdentifiers: Set<String> = [
    "1",
    "2",
    "8",
    "10",
    "17",
    "19",
    "20",
    "21",
    "29",
    "32",
]

private let expectedHancomFixtureRequestIds: Set<String> = [
    "border-fill-variants",
    "fill-alpha",
    "table-repeat-header",
    "shape-shadow-fill",
    "clickhere-field",
    "section-def-first-page-hides",
    "paragraph-border-connect",
]

private let allowedErrataStatuses: Set<String> = [
    "implemented",
    "already correct",
    "not reader scope",
    "needs Hancom fixture",
    "blocked by dependency",
]

private struct ErrataAuditTableRow {
    let columns: [String]

    var itemIdentifier: String {
        let token = columns[0].split(separator: " ", maxSplits: 1).first
        guard let token else {
            return columns[0]
        }

        let punctuation = CharacterSet(charactersIn: ".")
        return String(token).trimmingCharacters(in: punctuation)
    }

    var status: String {
        columns[3]
    }
}

private struct HancomFixtureRequestTableRow {
    let columns: [String]

    var fixtureId: String {
        columns[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    }

    var errataItemIdentifiers: [String] {
        columns[1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private func errataAuditDocument() throws -> String {
    try String(
        contentsOf: projectRootURL()
            .appendingPathComponent("Documentation")
            .appendingPathComponent("ErrataAudit.md"),
        encoding: .utf8
    )
}

private func errataAuditRows() throws -> [ErrataAuditTableRow] {
    markdownTableRows(
        afterHeader: "| 항목 번호/제목",
        in: try errataAuditDocument()
    ).map(ErrataAuditTableRow.init)
}

private func hancomFixtureRequestRows() throws -> [HancomFixtureRequestTableRow] {
    markdownTableRows(
        afterHeader: "| 제안 fixture id",
        in: try errataAuditDocument()
    ).map(HancomFixtureRequestTableRow.init)
}

private func markdownTableRows(afterHeader header: String, in document: String) -> [[String]] {
    var isInTargetTable = false
    var rows: [[String]] = []

    for lineSubstring in document.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(lineSubstring)
        if line.hasPrefix(header) {
            isInTargetTable = true
            continue
        }

        guard isInTargetTable else {
            continue
        }
        guard line.hasPrefix("|") else {
            break
        }
        guard !line.hasPrefix("|---") else {
            continue
        }

        let columns = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        rows.append(columns)
    }

    return rows
}

private func projectRootURL() -> URL {
    testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
