@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 적대적 리뷰에서 확인된 결함들의 회귀 테스트
    final class HwpPaginatorReviewRegressionTests: XCTestCase {
        private func paginate(
            _ section: CoreHwp.HwpSection
        ) -> HwpPaginator {
            HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 페이지보다 큰 row를 분할할 때 경계에 걸친 문단 텍스트가
        /// 라인 단위로 다음 페이지 조각에 실제로 이월되어야 한다.
        func testSlicedRowCarriesParagraphTextToNextPage() async throws {
            let longText = (0 ..< 240).map { "셀문단\($0)" }.joined(separator: " ")
            let table = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [1000], // 콘텐츠가 높이를 지배 (긴 문단 → 페이지 초과)
                property: 2,
                cellParagraphs: [[[try HwpSynthetic.textParagraph(longText)]]]
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(table)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 20000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost]
            )
            let paginator = paginate(section)

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            var pagesWithCellText = 0
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                let contentMaxY = page.size.height - page.margins.bottom
                for block in page.blocks where block.kind == .table {
                    guard case let .table(frame) = block.payload else { continue }
                    var hasText = false
                    for row in frame.rows {
                        for cell in row.cells {
                            for paragraph in cell.paragraphs {
                                if !paragraph.attributedString.string.isEmpty {
                                    hasText = true
                                }
                                // 조각 안 문단은 조각 (블록) 높이를 넘지 않는다.
                                expect(block.frame.minY + paragraph.rect.maxY).to(
                                    beLessThanOrEqualTo(contentMaxY + 1),
                                    description: "page \(pageIndex + 1) 셀 문단이 조각 밖으로 넘친다"
                                )
                                // 이월 문단이 조각 상단 위로 삐져나오지 않는다
                                // (절단선 라인 정렬 회귀 가드).
                                expect(paragraph.rect.minY).to(
                                    beGreaterThanOrEqualTo(-0.5),
                                    description: "page \(pageIndex + 1) 이월 문단이 조각 위로 나간다"
                                )
                            }
                        }
                    }
                    if hasText {
                        pagesWithCellText += 1
                    }
                }
            }
            // 텍스트가 첫 조각에만 남지 않고 이월 조각에도 존재한다.
            expect(pagesWithCellText) >= 2
        }

        /// 문단의 표가 페이지를 넘긴 뒤 처리되는 같은 문단의 treatAsChar 개체는
        /// 이전 페이지 좌표 (stale 앵커)가 아니라 새 페이지 안에 배치되어야 한다.
        func testInlineObjectAfterPageSplitStaysWithinItsPage() async throws {
            let bigTable = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [30000], // 페이지 (콘텐츠 ~200pt)보다 큰 표 → 분할
                property: 2,
                cellParagraphs: [[[try HwpSynthetic.textParagraph("표 내용")]]]
            )
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "본문 ", suffix: "")
            // FFFC(코드 11) 하나 + 컨트롤 2개: 표가 0번, 개체가 1번이 되도록
            // 표 마커와 개체 마커를 모두 둔다.
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = "본문 ".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [
                    CoreHwp.HwpChar(type: .extended, value: 11),
                    CoreHwp.HwpChar(type: .extended, value: 11),
                ]
            host.paraText = paraText
            host.ctrlHeaderArray = [
                .table(bigTable),
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 5000,
                    height: 2000,
                    instanceId: 99
                )),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            let paginator = paginate(section)

            let totalPages = await paginator.totalPages()
            var found = false
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.source?.controlInstanceId == 99 {
                    found = true
                    let contentMinY = page.margins.top
                    let contentMaxY = page.size.height - page.margins.bottom
                    expect(block.frame.minY).to(
                        beGreaterThanOrEqualTo(contentMinY - 0.5),
                        description: "개체가 자기 페이지 위 여백을 침범한다 (stale 앵커)"
                    )
                    expect(block.frame.minY).to(
                        beLessThanOrEqualTo(contentMaxY + 0.5),
                        description: "개체가 자기 페이지 아래로 벗어난다"
                    )
                }
            }
            expect(found).to(beTrue(), description: "인라인 개체 블록이 없다")
        }

        /// 이전 콘텐츠가 페이지를 채운 뒤 나오는 단 정의는 1pt 잔여 밴드가 아니라
        /// 새 페이지에서 열려야 한다 (텍스트가 종이 밖에 배치되면 안 된다).
        func testColumnDefAfterFullPageOpensBandOnNextPage() async throws {
            // 쪽 경계 나눔 없음 표가 콘텐츠 높이를 초과 → bandUsedBottom > contentMaxY
            let tallTable = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [25000],
                property: 0,
                cellParagraphs: [[[try HwpSynthetic.textParagraph("통째 표")]]]
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(tallTable)]

            var twoColumn = CoreHwp.HwpColumn()
            twoColumn.property = CoreHwp.HwpColumnProperty(
                rawValue: 0,
                type: .general,
                count: 2,
                direction: .left,
                isSameWidth: true
            )
            twoColumn.spacing = 2000
            var columnParagraph = try HwpSynthetic.textParagraph("다단 첫 줄")
            columnParagraph.ctrlHeaderArray = [.column(twoColumn)]

            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost, columnParagraph]
            )
            let paginator = paginate(section)

            let totalPages = await paginator.totalPages()
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.kind == .text {
                    guard block.attributedString?.string.contains("다단 첫 줄") == true
                    else { continue }
                    // 종이 밖/하단 여백이 아니라 콘텐츠 영역 안이어야 한다.
                    expect(block.frame.minY).to(
                        beLessThanOrEqualTo(page.size.height - page.margins.bottom + 0.5),
                        description: "다단 텍스트가 페이지 밖에 배치됐다"
                    )
                    expect(block.frame.minY).to(
                        beGreaterThanOrEqualTo(page.margins.top - 0.5)
                    )
                }
            }
        }

        /// 구역 경계에서도 마지막 다단 밴드가 균형 재배치되어야 한다.
        func testSectionBoundaryRebalancesTrailingColumnBand() async throws {
            var twoColumn = CoreHwp.HwpColumn()
            twoColumn.property = CoreHwp.HwpColumnProperty(
                rawValue: 0,
                type: .general,
                count: 2,
                direction: .left,
                isSameWidth: true
            )
            twoColumn.spacing = 2000
            var longParagraph = try HwpSynthetic.textParagraph(
                String(repeating: "구역 끝 배분 본문. ", count: 20)
            )
            longParagraph.ctrlHeaderArray = [.column(twoColumn)]
            let firstSection = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [longParagraph]
            )
            let secondSection = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("2구역 본문")]
            )
            let paginator = HwpPaginator(
                sections: [firstSection, secondSection],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            guard let firstPage = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            let balanced = firstPage.blocks.filter {
                $0.kind == .text && $0.attributedString?.string.contains("배분 본문") == true
            }
            expect(balanced.count) >= 2
            expect(Set(balanced.map(\.frame.minX)).count) >= 2
        }

        /// 글상자를 level단 중첩한 gso 개체 (각 단계의 문단이 다음 단계를 품는다)
        private func nestedTextbox(level: Int) throws -> CoreHwp.HwpGenShapeObject {
            var object = try HwpSynthetic.inlineTextboxObject(
                width: 2000, height: 2000, text: "L\(level)"
            )
            guard level > 0 else { return object }
            var inner = try HwpSynthetic.textParagraph("L\(level)")
            inner.ctrlHeaderArray = [.genShapeObject(try nestedTextbox(level: level - 1))]
            var component = object.shapeComponentArray[0]
            component.textBoxListArray[0].paragraphArray = [inner]
            object.shapeComponentArray[0] = component
            return object
        }

        private func unsupportedHints(nesting level: Int) async throws -> [String] {
            var host = try HwpSynthetic.textParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(try nestedTextbox(level: level))]
            let paginator = paginate(HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host]
            ))
            _ = await paginator.totalPages()
            return await paginator.unsupportedElements().map(\.hint)
        }

        /// 렌더는 컨테이너 중첩 depth 3에서 자식 컨트롤 방출을 멈춘다 — 그보다 깊은
        /// 글상자 안 개체는 조용히 사라지므로 진단으로 보고돼야 한다 (R72 #4).
        func testContainerNestingBeyondRenderLimitIsReported() async throws {
            let hints = try await unsupportedHints(nesting: 4)

            expect(hints.contains { $0.contains("중첩 컨테이너") }) == true
        }

        /// 한도 안의 중첩은 정상 렌더되므로 보고하지 않는다 (과잉 보고 가드).
        func testContainerNestingWithinRenderLimitIsNotReported() async throws {
            let hints = try await unsupportedHints(nesting: 1)

            expect(hints.contains { $0.contains("중첩 컨테이너") }) == false
        }
    }
#endif
