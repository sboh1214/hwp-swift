@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// recover 모드(#65)가 남긴 placeholder 구역·문단의 하류(조판) 안전성과
    /// `unsupportedElements` 진단 노출을 고정한다.
    final class HwpPaginatorRecoveryPlaceholderTests: XCTestCase {
        func testPlaceholderSectionPaginatesAndReportsUnsupportedElement() async throws {
            let placeholder = CoreHwp.HwpSection.parseFailurePlaceholder(
                error: .invalidRecordTree(reason: "record level 2 has no parent")
            )
            let paginator = HwpPaginator(
                sections: [CoreHwp.HwpFile().sectionArray[0], placeholder],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            var pageIndex = 0
            while try await paginator.page(at: pageIndex) != nil {
                pageIndex += 1
            }
            let unsupported = await paginator.unsupportedElements()

            expect(pageIndex) >= 1
            let sectionHints = unsupported.filter { $0.hint.contains("손상 구역 복구") }
            expect(sectionHints.count) == 1
            expect(sectionHints.first?.kind) == .placeholder
            expect(sectionHints.first?.hint).to(contain("record level 2 has no parent"))
        }

        func testPlaceholderParagraphPaginatesAndReportsUnsupportedElement() async throws {
            var section = CoreHwp.HwpFile().sectionArray[0]
            section.paragraph.append(CoreHwp.HwpParagraph.parseFailurePlaceholder(
                record: HwpRecord(tagId: 66, level: 0, payload: Data([0xAA])),
                error: .invalidRecordTree(reason: "paragraph char shape count mismatch")
            ))
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            var pageIndex = 0
            while try await paginator.page(at: pageIndex) != nil {
                pageIndex += 1
            }
            let unsupported = await paginator.unsupportedElements()

            expect(pageIndex) >= 1
            let paragraphHints = unsupported.filter { $0.hint.contains("손상 문단 복구") }
            expect(paragraphHints.count) == 1
            expect(paragraphHints.first?.kind) == .placeholder
            expect(paragraphHints.first?.hint).to(
                contain("paragraph char shape count mismatch")
            )
        }

        func testPlaceholderOnlySectionWithoutSectionDefUsesDefaultGeometry() async throws {
            // 구역의 유일한 문단이 placeholder면 sectionDef/column 컨트롤이
            // 없다 — 조판은 기본 지오메트리 폴백(`?? HwpSectionDef()`)으로
            // 페이지를 만들어야 한다 (#65 하류 안전).
            var section = CoreHwp.HwpFile().sectionArray[0]
            section.paragraph = [CoreHwp.HwpParagraph.parseFailurePlaceholder(
                record: HwpRecord(tagId: 66, level: 0, payload: Data()),
                error: .recordDoesNotExist(tag: 68)
            )]
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)
            let unsupported = await paginator.unsupportedElements()

            expect(page).notTo(beNil())
            expect(unsupported.filter { $0.hint.contains("손상 문단 복구") }.count) == 1
        }

        func testHealthySectionsReportNoRecoveryPlaceholders() async throws {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            var pageIndex = 0
            while try await paginator.page(at: pageIndex) != nil {
                pageIndex += 1
            }
            let unsupported = await paginator.unsupportedElements()

            expect(unsupported.filter { $0.hint.contains("복구") }).to(beEmpty())
        }
    }
#endif
