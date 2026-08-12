import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 검색(#75)이 쓰는 지오메트리 확장 — 배치 하이라이트·단위 캐시 축출·페이지 수.
final class HwpSelectionGeometrySearchTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func textBlock(_ text: String, frame: CGRect) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            role: .body
        )
    }

    private func makeDocument(pages: [[AnyHwpBlock]]) -> HwpDocument {
        HwpDocument(
            pages: pages.enumerated().map { index, blocks in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: blocks,
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pages.count),
            unsupportedElements: []
        )
    }

    private func selection(
        page: Int, block: Int, unit: Int, from: Int, upTo: Int
    ) -> HwpTextSelection {
        HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: page, blockIndex: block, unitIndex: unit, characterOffset: from
            ),
            focus: HwpTextPosition(
                pageIndex: page, blockIndex: block, unitIndex: unit, characterOffset: upTo
            )
        )
    }

    /// 정렬해 비교한다 — 배치는 (단위 → 선택) 순, 단일은 (선택 → 단위) 순이라
    /// 순서가 다를 수 있고, 계약은 **집합** 동일성이다.
    private func sorted(_ rects: [CGRect]) -> [CGRect] {
        rects.sorted {
            ($0.origin.y, $0.origin.x, $0.width) < ($1.origin.y, $1.origin.x, $1.width)
        }
    }

    // MARK: - 배치 ≡ 단일 합집합

    func testBatchMatchesUnionOfSingleQueriesWithinOneUnit() {
        let document = makeDocument(pages: [[
            textBlock("alpha beta gamma", frame: CGRect(x: 10, y: 20, width: 400, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        let selections = [
            selection(page: 0, block: 0, unit: 0, from: 0, upTo: 5),
            selection(page: 0, block: 0, unit: 0, from: 6, upTo: 10),
        ]

        let batch = geometry.highlightRects(pageIndex: 0, selections: selections)
        let union = selections.flatMap {
            geometry.highlightRects(pageIndex: 0, selection: $0)
        }

        let sortedBatch = sorted(batch)
        let sortedUnion = sorted(union)
        expect(batch).toNot(beEmpty())
        expect(sortedBatch) == sortedUnion
    }

    /// 단위를 **통째로 덮는** 선택과 단위 **안에 갇힌** 선택은 본체가 서로 다른
    /// 분기를 탄다(`upper` 삼항) — 둘 다 배치와 일치해야 한다.
    func testBatchMatchesUnionAcrossUnitsAndPages() {
        let document = makeDocument(pages: [
            [
                textBlock("first unit", frame: CGRect(x: 10, y: 20, width: 400, height: 20)),
                textBlock("second unit", frame: CGRect(x: 10, y: 60, width: 400, height: 20)),
            ],
            [
                textBlock("third unit", frame: CGRect(x: 10, y: 20, width: 400, height: 20)),
            ],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        let spanning = HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 3
            ),
            focus: HwpTextPosition(
                pageIndex: 1, blockIndex: 0, unitIndex: 0, characterOffset: 5
            )
        )
        let inner = selection(page: 0, block: 1, unit: 0, from: 2, upTo: 4)

        for page in 0 ... 1 {
            let batch = geometry.highlightRects(pageIndex: page, selections: [spanning, inner])
            let union = [spanning, inner].flatMap {
                geometry.highlightRects(pageIndex: page, selection: $0)
            }
            let sortedBatch = sorted(batch)
            let sortedUnion = sorted(union)
            expect(sortedBatch) == sortedUnion
        }
    }

    func testBatchIgnoresCollapsedAndOffPageSelections() {
        let document = makeDocument(pages: [
            [textBlock("page zero", frame: CGRect(x: 10, y: 20, width: 400, height: 20))],
            [textBlock("page one", frame: CGRect(x: 10, y: 20, width: 400, height: 20))],
        ])
        let geometry = HwpSelectionGeometry(document: document)
        let collapsed = selection(page: 0, block: 0, unit: 0, from: 2, upTo: 2)
        let otherPage = selection(page: 1, block: 0, unit: 0, from: 0, upTo: 4)

        expect(geometry.highlightRects(pageIndex: 0, selections: [collapsed])).to(beEmpty())
        expect(geometry.highlightRects(pageIndex: 0, selections: [otherPage])).to(beEmpty())
        expect(geometry.highlightRects(pageIndex: 0, selections: [])).to(beEmpty())
    }

    /// 스윕이 정렬을 전제하므로, 뒤섞어 넣어도 결과가 같아야 한다.
    func testBatchIsOrderInsensitive() {
        let document = makeDocument(pages: [[
            textBlock("aaa", frame: CGRect(x: 10, y: 20, width: 200, height: 20)),
            textBlock("bbb", frame: CGRect(x: 10, y: 60, width: 200, height: 20)),
            textBlock("ccc", frame: CGRect(x: 10, y: 100, width: 200, height: 20)),
        ]])
        let geometry = HwpSelectionGeometry(document: document)
        let forward = [
            selection(page: 0, block: 0, unit: 0, from: 0, upTo: 3),
            selection(page: 0, block: 1, unit: 0, from: 0, upTo: 3),
            selection(page: 0, block: 2, unit: 0, from: 0, upTo: 3),
        ]

        let ascending = geometry.highlightRects(pageIndex: 0, selections: forward)
        let shuffled = geometry.highlightRects(pageIndex: 0, selections: forward.reversed())

        let sortedAscending = sorted(ascending)
        let sortedShuffled = sorted(shuffled)
        expect(ascending.count) == 3
        expect(sortedAscending) == sortedShuffled
    }

    // MARK: - 캐시 축출

    func testEvictUnitsDropsOutOfRangePagesAndKeepsResultsIdentical() {
        let document = makeDocument(pages: (0 ..< 5).map { index in
            [textBlock("page \(index)", frame: CGRect(x: 10, y: 20, width: 200, height: 20))]
        })
        let geometry = HwpSelectionGeometry(document: document)
        for page in 0 ..< 5 {
            _ = geometry.units(forPage: page)
        }
        expect(geometry.unitCache.count) == 5
        let before = geometry.highlightRects(
            pageIndex: 4, selections: [selection(page: 4, block: 0, unit: 0, from: 0, upTo: 6)]
        )

        geometry.evictUnits(keeping: 3 ..< 5)

        expect(Set(geometry.unitCache.keys)) == Set([3, 4])
        // 재질의는 캐시를 다시 채우고 같은 결과를 낸다 — 문서가 불변이라
        // 단위 전개는 결정론적이다.
        geometry.evictUnits(keeping: 0 ..< 0)
        expect(geometry.unitCache).to(beEmpty())
        let after = geometry.highlightRects(
            pageIndex: 4, selections: [selection(page: 4, block: 0, unit: 0, from: 0, upTo: 6)]
        )
        expect(after) == before
    }

    func testPageCountReportsDocumentPages() {
        let empty = HwpSelectionGeometry(document: makeDocument(pages: []))
        expect(empty.pageCount) == 0
        let three = makeDocument(pages: (0 ..< 3).map { _ in
            [textBlock("x", frame: CGRect(x: 0, y: 0, width: 100, height: 20))]
        })
        expect(HwpSelectionGeometry(document: three).pageCount) == 3
    }
}
