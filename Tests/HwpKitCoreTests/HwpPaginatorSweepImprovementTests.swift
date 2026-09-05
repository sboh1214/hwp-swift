@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개선 스윕 (제목 줄 반복, 논리 쪽 번호, 깊이 초과 보고, 문단 스타일 부착) 테스트
    final class HwpPaginatorSweepImprovementTests: XCTestCase {
        private func paginate(_ sections: [CoreHwp.HwpSection]) -> HwpPaginator {
            HwpPaginator(
                sections: sections,
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 표 76 bit 2: 분할된 표의 이어지는 세그먼트마다 제목 행이 복제된다.
        func testRepeatedHeaderRowAppearsOnEverySegment() async throws {
            var cellParagraphs: [[[CoreHwp.HwpParagraph]]] = [
                [[try HwpSynthetic.textParagraph("제목 행")]],
            ]
            cellParagraphs.append(contentsOf: try (0 ..< 30).map {
                [[try HwpSynthetic.textParagraph("본문 행 \($0)")]]
            })
            let table = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [UInt32](repeating: 2000, count: cellParagraphs.count),
                property: 0b110, // 나눔 + 제목 줄 자동 반복
                headerRowCount: 1,
                cellParagraphs: cellParagraphs
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(table)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost]
            )
            let paginator = paginate([section])

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.kind == .table {
                    guard case let .table(frame) = block.payload,
                          let firstRow = frame.rows.first
                    else { continue }
                    let firstRowText = firstRow.cells
                        .flatMap(\.paragraphs)
                        .map(\.attributedString.string)
                        .joined()
                    expect(firstRowText).to(
                        contain("제목 행"),
                        description: "page \(pageIndex + 1) 세그먼트 첫 행이 제목 행이 아니다"
                    )
                    let contentMaxY = page.size.height - page.margins.bottom
                    expect(block.frame.maxY).to(beLessThanOrEqualTo(contentMaxY + 0.5))
                }
            }
        }

        /// 표 141 짝/홀 적용 범위는 구역 pageStartNumber를 반영한 논리 쪽 번호로 판정한다.
        func testHeaderParityUsesSectionPageStartNumber() async throws {
            let evenHeader = HwpSynthetic.listControl(
                ctrlId: .header,
                property: 1, // 짝수 쪽만
                paragraphs: [try HwpSynthetic.textParagraph("짝수쪽 머리말")]
            )
            var sectionDef = HwpSynthetic.sectionDef()
            sectionDef.pageStartNumber = 2 // 첫 물리 페이지의 논리 번호 = 2 (짝수)
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(sectionDef),
                    .column(CoreHwp.HwpColumn()),
                    .header(evenHeader),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("본문")]
            )
            let paginator = paginate([section])

            guard let page = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            let texts = page.blocks.compactMap(\.attributedString?.string)
            expect(texts.contains { $0.contains("짝수쪽 머리말") }).to(
                beTrue(),
                description: "논리 쪽 번호 2 (짝수)인 첫 페이지에 짝수 머리말이 나와야 한다"
            )
        }

        /// 깊이 3을 넘는 중첩 표는 조용히 사라지지 않고 unsupported로 보고된다.
        func testNestedTableBeyondDepthLimitReportsUnsupported() async throws {
            var innermost = HwpSynthetic.table(
                cellWidth: 4000,
                rowHeights: [1000],
                cellParagraphs: [[[try HwpSynthetic.textParagraph("가장 깊은 표")]]]
            )
            for depth in stride(from: 4, through: 1, by: -1) {
                var host = try HwpSynthetic.textParagraph("depth\(depth)")
                host.ctrlHeaderArray = [.table(innermost)]
                innermost = HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: [2000],
                    cellParagraphs: [[[host]]]
                )
            }
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(innermost)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost]
            )
            let paginator = paginate([section])

            _ = await paginator.totalPages()
            let hints = await paginator.unsupportedElements().map(\.hint)
            expect(hints.contains { $0.contains("중첩 표") }).to(
                beTrue(),
                description: "unsupported hints: \(hints)"
            )
        }

        /// 문단 머리 종류(표 44 bit 23-24) = 1 개요 문단은 생성 라벨이 numbering
        /// 정의에 있고 PARA_TEXT에 없어 렌더러가 못 만든다 — 번호가 조용히 사라지지
        /// 않도록 unsupported로 보고돼야 한다 (#1). 정의는 문단 모양이 아니라 구역
        /// 정의(기본 참조 1 → 사전 키 0)가 가리키므로(#152) 문단 모양의 참조는 0이다.
        func testOutlineNumberingHeadingReportedAsUnsupported() async throws {
            let headingParaShape = CoreHwp.HwpParaShape(
                property1: 1 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 0
            )
            let index = HwpIndex(
                charShapes: [:], paraShapes: [0: headingParaShape], borderFills: [:],
                tabDefs: [:], styles: [:], bullets: [:],
                numberings: [0: HwpSynthetic.numberingDefinition()], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("첫째 항목")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )

            _ = await paginator.totalPages()
            let hints = await paginator.unsupportedElements().map(\.hint)
            // 구역 첫 문단(빈 문서 템플릿)도 문단 모양 0을 쓰므로 개요 문단이 둘이다 —
            // 집계 단위가 문단이라 건수도 둘이다.
            expect(hints) == Array(repeating: "개요 번호 문단 머리 (미렌더)", count: 2)
        }

        /// 각주 예약으로 페이지가 사실상 찬 상태 + 이어지는 2단 정의 구역
        private func footnoteFilledSectionWithColumnDef() throws -> CoreHwp.HwpSection {
            let footnote = HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [try HwpSynthetic.textParagraph(
                    String(repeating: "각주 본문. ", count: 8)
                )]
            )
            var noteHost = try HwpSynthetic.textParagraph("각주 달린 문단")
            noteHost.ctrlHeaderArray = [.footnote(footnote)]

            var bodyParagraphs: [CoreHwp.HwpParagraph] = [noteHost]
            bodyParagraphs.append(contentsOf: try (0 ..< 12).map {
                try HwpSynthetic.textParagraph("채움 문단 \($0)")
            })
            var twoColumn = CoreHwp.HwpColumn()
            twoColumn.property = CoreHwp.HwpColumnProperty(
                rawValue: 0,
                type: .general,
                count: 2,
                direction: .left,
                isSameWidth: true
            )
            twoColumn.spacing = 2000
            var columnParagraph = try HwpSynthetic.textParagraph(
                String(repeating: "다단 본문 문장. ", count: 12)
            )
            columnParagraph.ctrlHeaderArray = [.column(twoColumn)]
            bodyParagraphs.append(columnParagraph)

            return HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: bodyParagraphs
            )
        }

        /// 각주 예약으로 페이지가 사실상 찬 상태의 단 정의는 퇴화 밴드가 아니라
        /// 새 페이지에서 열린다 (본문이 각주 영역/페이지 밖으로 나가지 않는다).
        func testColumnDefOnFootnoteFilledPageOpensBandOnNextPage() async throws {
            let paginator = paginate([try footnoteFilledSectionWithColumnDef()])

            let totalPages = await paginator.totalPages()
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                let contentMaxY = page.size.height - page.margins.bottom
                let footnoteFrames = page.blocks
                    .filter { $0.kind == .footnote }
                    .map(\.frame)
                for block in page.blocks where block.kind == .text {
                    expect(block.frame.minY).to(
                        beLessThanOrEqualTo(contentMaxY + 0.5),
                        description: "page \(pageIndex + 1) 본문이 페이지 밖에 배치됐다"
                    )
                    guard block.attributedString?.string.contains("다단 본문") == true
                    else { continue }
                    // 다단 본문이 각주 블록과 겹치지 않는다.
                    for footnoteFrame in footnoteFrames {
                        let overlaps = block.frame.maxY > footnoteFrame.minY + 0.5
                            && block.frame.minY < footnoteFrame.maxY - 0.5
                        expect(overlaps).to(
                            beFalse(),
                            description: "page \(pageIndex + 1) 다단 본문이 각주 영역과 겹친다"
                        )
                    }
                }
            }
        }

        /// HwpTextRunBuilder 출력에 문단 스타일이 실려 측정/렌더 조판이 일치한다.
        func testBuilderAttachesParagraphStyleAttribute() throws {
            let file = CoreHwp.HwpFile()
            let index = HwpIndex(from: file)
            let paragraph = try HwpSynthetic.textParagraph("스타일 검사")
            let attributed = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            guard attributed.length > 0 else {
                fail("빈 문자열")
                return
            }
            let style = attributed.attribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                at: 0,
                effectiveRange: nil
            )
            // 블랭크 문서 인덱스에 paraShape id 0이 있으면 스타일이 부착된다.
            if index.paraShape(id: 0) != nil {
                expect(style).toNot(beNil())
            }
        }
    }
#endif
