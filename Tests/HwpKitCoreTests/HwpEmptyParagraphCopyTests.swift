@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 빈 문단의 선택·복사 경계 — 실제 `HwpPaginator` 조판 (#145, PR #147 리뷰).
    ///
    /// 화면에는 빈 줄이 한 줄 높이로 남는데(#137 한 줄 하한) 조판 문자열이 비어
    /// `HwpBlockContentWalker`·`fragments(for:)`에서 빠지면 평문·속성 복사 모두
    /// `A\n\nB`가 아니라 `A\nB`를 낸다. 빈 문단의 세 가지 모델 형태 — HWP
    /// 바이너리(PARA_TEXT 없음)·빈 배열·HWPX(문단 끝 코드 13뿐) — 가 같아야 한다.
    /// 합성 문단은 paraId가 전부 0이라 위치 열쇠(`HwpBlockSource`)로만 문단이
    /// 갈린다 — 실물(noori)과 같은 조건이다.
    final class HwpEmptyParagraphCopyTests: XCTestCase {
        enum EmptyShape: CaseIterable {
            case noParaText, emptyCharArray, paragraphEndOnly
        }

        private func emptyParagraph(_ shape: EmptyShape) throws -> CoreHwp.HwpParagraph {
            switch shape {
            case .noParaText:
                var paragraph = try HwpSynthetic.textParagraph("")
                paragraph.paraText = nil
                return paragraph
            case .emptyCharArray:
                return try HwpSynthetic.textParagraph("")
            case .paragraphEndOnly:
                return try HwpSynthetic.textParagraph("\r")
            }
        }

        private func document(
            bodyParagraphs: [CoreHwp.HwpParagraph]
        ) async throws -> HwpDocument {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 60000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: bodyParagraphs
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

        /// 빈 문서 템플릿의 첫 문단(구역·단 마커 전용)을 뺀 본문 선택 —
        /// "A" 단위 시작부터 마지막 단위 끝까지.
        private func bodySelection(
            in geometry: HwpSelectionGeometry
        ) throws -> HwpTextSelection {
            let units = geometry.units(forPage: 0)
            let first = try XCTUnwrap(units.first { $0.attributedString.string == "A" })
            let last = try XCTUnwrap(units.last)
            return HwpTextSelection(
                anchor: HwpTextPosition(
                    pageIndex: 0, blockIndex: first.blockIndex,
                    unitIndex: first.unitIndex, characterOffset: 0
                ),
                focus: HwpTextPosition(
                    pageIndex: 0, blockIndex: last.blockIndex,
                    unitIndex: last.unitIndex,
                    characterOffset: last.attributedString.length
                )
            )
        }

        func testEmptyParagraphBetweenTextKeepsItsLineInPlainAndAttributedCopy() async throws {
            for shape in EmptyShape.allCases {
                let document = try await document(bodyParagraphs: [
                    try HwpSynthetic.textParagraph("A"),
                    try emptyParagraph(shape),
                    try HwpSynthetic.textParagraph("B"),
                ])
                let geometry = HwpSelectionGeometry(document: document)
                let selection = try bodySelection(in: geometry)

                let plain = geometry.plainText(for: selection)
                let attributed = geometry.attributedText(for: selection)
                expect(plain).to(
                    equal("A\n\nB"), description: "\(shape) 평문: \(plain.debugDescription)"
                )
                expect(attributed.string).to(equal(plain), description: "\(shape) 파리티")

                // 빈 문단 단위는 앵커 하나뿐이고, 그 종결 개행은 앵커의 글꼴·문단
                // 스타일을 입는다 (RTF에 빈 문단 서식이 남는 근거).
                let units = geometry.units(forPage: 0)
                let anchors = units.filter {
                    HwpTextRunBuilder.isEmptyParagraphAnchor($0.attributedString)
                }
                expect(anchors.count).to(equal(1), description: "\(shape) 앵커 단위")
                let afterEmpty = attributed.attributes(at: 2, effectiveRange: nil)
                expect(afterEmpty[kCTFontAttributeName as NSAttributedString.Key]).notTo(beNil())
                expect(afterEmpty[kCTParagraphStyleAttributeName as NSAttributedString.Key])
                    .notTo(beNil())

                // 빈 줄에 캐럿이 놓인다 (#145의 캐럿 축).
                let anchor = try XCTUnwrap(anchors.first)
                let caret = geometry.caretRect(
                    at: HwpTextPosition(
                        pageIndex: 0, blockIndex: anchor.blockIndex,
                        unitIndex: anchor.unitIndex, characterOffset: 0
                    ),
                    affinity: .downstream
                )
                expect(caret?.width) == 0
                expect(caret?.height ?? 0) > 0
            }
        }

        func testEmptyParagraphsAtDocumentEdgesKeepTheirLines() async throws {
            // 선두·말미 빈 문단: 전체 선택은 TextEdit처럼 "\nA\n" 꼴이다.
            let document = try await document(bodyParagraphs: [
                try emptyParagraph(.paragraphEndOnly),
                try HwpSynthetic.textParagraph("A"),
                try emptyParagraph(.noParaText),
            ])
            let geometry = HwpSelectionGeometry(document: document)
            let units = geometry.units(forPage: 0)
            let firstEmpty = try XCTUnwrap(units.first {
                HwpTextRunBuilder.isEmptyParagraphAnchor($0.attributedString)
            })
            let last = try XCTUnwrap(units.last)
            let selection = HwpTextSelection(
                anchor: HwpTextPosition(
                    pageIndex: 0, blockIndex: firstEmpty.blockIndex,
                    unitIndex: firstEmpty.unitIndex, characterOffset: 0
                ),
                focus: HwpTextPosition(
                    pageIndex: 0, blockIndex: last.blockIndex,
                    unitIndex: last.unitIndex,
                    characterOffset: last.attributedString.length
                )
            )

            expect(geometry.plainText(for: selection)) == "\nA\n"
        }
    }
#endif
