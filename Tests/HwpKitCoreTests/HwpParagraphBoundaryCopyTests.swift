@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 선택이 지난 문단 경계의 종결 개행 — 실제 `HwpPaginator` 조판 (PR 리뷰 P2).
    ///
    /// 문단 끝 코드 13이 조판 문자열에 없으므로(#137) 문단 부호는 조각 사이
    /// 개행으로만 복사에 남는다. 종전 `fragments(for:)`는 끝점이 단위 시작이면
    /// 그 단위를 빼서, A 시작→B 시작이 `A`, 문단 부호만 고르면 빈 문자열이 됐다.
    /// 한글.app 12.30 실측(2026-09-05, `outline-numbering` 문서): A 시작→B 시작은
    /// `A\r\n`, 문단 부호만은 `\r\n`, A 끝→B 중간은 `\r\n` + B의 글자다.
    final class HwpParagraphBoundaryCopyTests: XCTestCase {
        private func document() async throws -> HwpDocument {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 60000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [
                    try HwpSynthetic.textParagraph("AAA"),
                    try HwpSynthetic.textParagraph("BBB"),
                    try HwpSynthetic.textParagraph("CCC"),
                ]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var pages: [HwpPage] = []
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                pages.append(page)
                pageIndex += 1
            }
            return HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: pages.count),
                unsupportedElements: []
            )
        }

        private func unit(_ text: String, in geometry: HwpSelectionGeometry) throws -> HwpTextUnit {
            try XCTUnwrap(geometry.units(forPage: 0).first { $0.attributedString.string == text })
        }

        private func position(_ unit: HwpTextUnit, _ offset: Int) -> HwpTextPosition {
            HwpTextPosition(
                pageIndex: 0, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex, characterOffset: offset
            )
        }

        /// 평문·속성 복사가 같은 문자열을 내는 것까지 함께 본다 (`.string` 파리티).
        private func copies(
            _ geometry: HwpSelectionGeometry, _ start: HwpTextPosition, _ end: HwpTextPosition
        ) -> (plain: String, attributed: String) {
            let selection = HwpTextSelection(anchor: start, focus: end)
            return (
                geometry.plainText(for: selection),
                geometry.attributedText(for: selection).string
            )
        }

        func testSelectionEndingAtNextParagraphStartKeepsTheTerminator() async throws {
            let geometry = await HwpSelectionGeometry(document: try document())
            let first = try unit("AAA", in: geometry)
            let second = try unit("BBB", in: geometry)

            let startToStart = copies(geometry, position(first, 0), position(second, 0))
            expect(startToStart.plain) == "AAA\n"
            expect(startToStart.attributed) == "AAA\n"
            // A의 글자만 고르면(문단 부호 앞에서 끝) 개행이 없다.
            let startToEnd = copies(geometry, position(first, 0), position(first, 3))
            expect(startToEnd.plain) == "AAA"
            expect(startToEnd.attributed) == "AAA"
        }

        func testParagraphMarkAloneCopiesANewline() async throws {
            let geometry = await HwpSelectionGeometry(document: try document())
            let first = try unit("AAA", in: geometry)
            let second = try unit("BBB", in: geometry)

            let boundary = copies(geometry, position(first, 3), position(second, 0))
            expect(boundary.plain) == "\n"
            expect(boundary.attributed) == "\n"
            // A 끝에서 B 안으로 — 문단 부호가 앞선다.
            let endToMid = copies(geometry, position(first, 3), position(second, 2))
            expect(endToMid.plain) == "\nBB"
            expect(endToMid.attributed) == "\nBB"
            // 글자 사이 선택은 종전과 같다.
            let midToMid = copies(geometry, position(first, 1), position(second, 1))
            expect(midToMid.plain) == "AA\nB"
        }

        /// 문단 부호만 고른 복사의 개행도 **그 문단**(A)의 글꼴을 입는다 — 빈 조각은
        /// 자기 단위의 조판 문자열을 꼬리로 넘긴다 (#124 폴백의 일반화).
        func testNewlineOfParagraphMarkOnlySelectionInheritsThatParagraphFont() async throws {
            let geometry = await HwpSelectionGeometry(document: try document())
            let first = try unit("AAA", in: geometry)
            let second = try unit("BBB", in: geometry)
            let selection = HwpTextSelection(anchor: position(first, 3), focus: position(second, 0))

            let attributed = geometry.attributedText(for: selection)
            expect(attributed.string) == "\n"
            let fontKey = kCTFontAttributeName as NSAttributedString.Key
            guard let newlineFont = attributed.attribute(fontKey, at: 0, effectiveRange: nil),
                  let paragraphFont = first.attributedString.attribute(
                      fontKey, at: first.attributedString.length - 1, effectiveRange: nil
                  )
            else {
                return fail("개행과 A 문단의 글꼴 속성이 있어야 한다")
            }
            expect(CFEqual(newlineFont as AnyObject, paragraphFont as AnyObject)) == true
        }
    }
#endif
