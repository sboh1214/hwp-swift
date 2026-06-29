@testable import CoreHwp
import Nimble
import OLEKit
import XCTest

final class StreamReaderTests: XCTestCase {
    func testStreamNameCasesDocumentReaderTopLevelEntrySurface() {
        expect(HwpStreamName.allCases) == [
            .fileHeader,
            .docInfo,
            .bodyText,
            .summary,
            .previewText,
            .previewImage,
            .binData,
        ]
        expect(HwpStreamName.requiredTopLevelEntries) == [
            .fileHeader,
            .docInfo,
            .bodyText,
        ]
        expect(HwpStreamName.optionalTopLevelEntries) == [
            .summary,
            .previewText,
            .previewImage,
            .binData,
        ]
        expect(HwpStreamName.requiredTopLevelEntries.intersection(
            HwpStreamName.optionalTopLevelEntries
        )).to(beEmpty())
        expect(HwpStreamName.requiredTopLevelEntries.union(
            HwpStreamName.optionalTopLevelEntries
        )) == Set(HwpStreamName.allCases)
        for streamName in HwpStreamName.allCases {
            expect(streamName.isRequiredTopLevelEntry) ==
                HwpStreamName.requiredTopLevelEntries.contains(streamName)
        }
    }

    func testBodyTextStorageNamesKeepOnlyNumericSectionsInSectionOrder() {
        let names = [
            "Section10",
            "Section2",
            "Section-1",
            "SectionA",
            "Section999999999999999999999999",
            "Section",
            "Preview",
            "Section0",
            "Section1",
        ]

        expect(StreamReader.sortedStorageChildNames(names, for: .bodyText)) == [
            "Section0",
            "Section1",
            "Section2",
            "Section10",
        ]
    }

    func testRequiredBodyTextStorageNamesRejectMissingNumericSections() {
        let names = [String]()

        expect {
            _ = try StreamReader.requiredSortedStorageChildNames(names, for: .bodyText)
        }.to(throwError { error in
            guard case let HwpError.streamDoesNotExist(name) = error else {
                return fail("Expected streamDoesNotExist, got \(error)")
            }
            expect(name) == .bodyText
        })
    }

    func testRequiredBodyTextStorageNamesRejectUnexpectedNonSectionNames() {
        expectUnexpectedBodyTextDirectoryEntry("Preview") {
            _ = try StreamReader.requiredSortedStorageChildNames(["Preview"], for: .bodyText)
        }
        expectUnexpectedBodyTextDirectoryEntry("Preview") {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0", "Preview"],
                for: .bodyText,
                expectedCount: 1
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectMalformedSectionLikeNames() {
        let names = [
            "Section",
            "SectionA",
            "Section-1",
            "Section１",
            "Section١",
        ]

        for name in names {
            expectInvalidBodyTextSections {
                _ = try StreamReader.requiredSortedStorageChildNames([name], for: .bodyText)
            }
        }
    }

    func testRequiredStorageNamesRejectDuplicateDirectoryEntryNames() {
        expectDuplicateStorageDirectoryEntryNames(
            streamName: .bodyText,
            duplicateName: "Section1"
        ) {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0", "Section1", "Section1"],
                for: .bodyText
            )
        }
        expectDuplicateStorageDirectoryEntryNames(
            streamName: .binData,
            duplicateName: "BIN0001.png"
        ) {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["BIN0001.png", "BIN0001.png"],
                for: .binData
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectNonCanonicalNumericSections() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0", "Section01"],
                for: .bodyText,
                expectedCount: 2
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectZeroPaddedSectionZero() {
        for name in ["Section00", "Section000"] {
            expectInvalidBodyTextSections {
                _ = try StreamReader.requiredSortedStorageChildNames(
                    [name],
                    for: .bodyText,
                    expectedCount: 1
                )
            }
        }
    }

    func testRequiredBodyTextStorageNamesRejectOverflowNumericSections() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0", "Section999999999999999999999999"],
                for: .bodyText,
                expectedCount: 2
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectMissingSectionZero() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(["Section1"], for: .bodyText)
        }
    }

    func testRequiredBodyTextStorageNamesRejectSectionGaps() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0", "Section2"],
                for: .bodyText
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectSectionCountMismatch() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0"],
                for: .bodyText,
                expectedCount: 2
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectZeroExpectedSectionCount() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                [String](),
                for: .bodyText,
                expectedCount: 0
            )
        }
    }

    func testRequiredBodyTextStorageNamesRejectNegativeExpectedSectionCount() {
        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                ["Section0"],
                for: .bodyText,
                expectedCount: -1
            )
        }
    }

    func testRequiredNonBodyTextStorageNamesMayBeEmpty() throws {
        let names = try StreamReader.requiredSortedStorageChildNames([String](), for: .binData)

        expect(names).to(beEmpty())
    }

    func testNonBodyTextStorageNamesUseNameOrderWithoutSectionFiltering() {
        let names = [
            "BIN0002.png",
            "Section0",
            "BIN0010.png",
            "BIN10.png",
            "BIN2.png",
            "BIN0001.png",
        ]

        expect(StreamReader.sortedStorageChildNames(names, for: .binData)) == [
            "BIN0001.png",
            "BIN0002.png",
            "BIN0010.png",
            "BIN10.png",
            "BIN2.png",
            "Section0",
        ]
    }

    func testStorageNameSortingIgnoresNonStreamChildren() {
        let children: [(name: String, type: StorageType)] = [
            ("BIN0002.png", .stream),
            ("ObjectPool", .storage),
            ("BIN0001.png", .stream),
            ("PropertySet", .property),
            ("Section0", .storage),
        ]

        expect(StreamReader.sortedStorageChildNames(children, for: .binData)) == [
            "BIN0001.png",
            "BIN0002.png",
        ]
    }

    func testBodyTextStorageNameSortingKeepsOnlyStreamSections() {
        let children: [(name: String, type: StorageType)] = [
            ("Section1", .storage),
            ("Section0", .stream),
            ("Section2", .stream),
            ("Preview", .stream),
        ]

        expect(StreamReader.sortedStorageChildNames(children, for: .bodyText)) == [
            "Section0",
            "Section2",
        ]
    }

    func testRequiredBodyTextStorageNameValidationRejectsMalformedNonStreamSectionLikeChildren() {
        let children: [(name: String, type: StorageType)] = [
            ("SectionA", .storage),
            ("Section-1", .property),
            ("Section0", .stream),
        ]

        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                children,
                for: .bodyText,
                expectedCount: 1
            )
        }
    }

    func testRequiredBodyTextStorageNameValidationRejectsMalformedStreamSectionLikeChildren() {
        let children: [(name: String, type: StorageType)] = [
            ("SectionA", .stream),
            ("Section0", .stream),
        ]

        expectInvalidBodyTextSections {
            _ = try StreamReader.requiredSortedStorageChildNames(
                children,
                for: .bodyText,
                expectedCount: 1
            )
        }
    }

    func testRequiredBodyTextStorageNameValidationRejectsCanonicalNonStreamSections() {
        let children: [(name: String, type: StorageType)] = [
            ("Section0", .storage),
        ]

        expectInvalidBodyTextSectionType("Section0") {
            _ = try StreamReader.requiredSortedStorageChildNames(
                children,
                for: .bodyText,
                expectedCount: 1
            )
        }
    }
}

private func expectInvalidBodyTextSections(_ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("BodyText section"))
    })
}

private func expectUnexpectedBodyTextDirectoryEntry(
    _ entryName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("BodyText directory entry \(entryName) is unexpected"))
    })
}

private func expectDuplicateStorageDirectoryEntryNames(
    streamName: HwpStreamName,
    duplicateName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Duplicate \(streamName.rawValue) directory entry names"))
        expect(reason).to(contain(duplicateName))
    })
}

private func expectInvalidBodyTextSectionType(
    _ sectionName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Directory entry 'BodyText/\(sectionName)'"))
        expect(reason).to(contain("expected stream"))
    })
}
