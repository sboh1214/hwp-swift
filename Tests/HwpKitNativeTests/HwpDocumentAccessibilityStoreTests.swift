import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 페이지별 합성 AX 요소 보관함 (#79) — anchor 대조·가상화 동기 청소·낭독
/// 순서 평탄화. `#if` 밖 공통 코드라 macOS swift test 가 커버한다.
@MainActor
final class HwpDocumentAccessibilityStoreTests: XCTestCase {
    private final class Element {}

    func testAnchoredLookupMissesWhenPageFrameMoved() {
        let store = HwpDocumentAccessibilityStore<Element>()
        let frame = CGRect(x: 0, y: 0, width: 595, height: 842)
        store.setElements([Element()], forPage: 0, anchoredTo: frame)

        expect(store.elements(forPage: 0, anchoredTo: frame)?.count) == 1
        // 프로그레시브 로딩이 콘텐츠 폭을 키우면 가운데 정렬 x 가 밀린다 —
        // 옛 frame 으로 만든 요소는 재생성 신호 (nil) 를 받아야 한다.
        let moved = frame.offsetBy(dx: 40, dy: 0)
        expect(store.elements(forPage: 0, anchoredTo: moved)).to(beNil())
        expect(store.elements(forPage: 0)?.count) == 1
    }

    func testPruneKeepsOnlyMaterializedPages() {
        let store = HwpDocumentAccessibilityStore<Element>()
        for pageIndex in 0 ..< 5 {
            store.setElements([Element()], forPage: pageIndex, anchoredTo: .zero)
        }

        store.prune(keeping: [2, 3])

        expect(store.pageIndices.sorted()) == [2, 3]
    }

    func testFlattenedListFollowsPageOrder() {
        let store = HwpDocumentAccessibilityStore<Element>()
        let second = Element()
        let first = Element()
        store.setElements([second], forPage: 7, anchoredTo: .zero)
        store.setElements([first], forPage: 3, anchoredTo: .zero)

        let flattened = store.flattenedInPageOrder

        expect(flattened.count) == 2
        expect(flattened[0]) === first
        expect(flattened[1]) === second
    }

    func testRemoveAllDropsEverything() {
        let store = HwpDocumentAccessibilityStore<Element>()
        store.setElements([Element()], forPage: 0, anchoredTo: .zero)

        store.removeAll()

        expect(store.pageIndices).to(beEmpty())
        expect(store.flattenedInPageOrder).to(beEmpty())
    }

    // MARK: - HwpDocumentAccessibility.units (뷰 공통 진입점)

    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: Self.font]
        )
    }

    private func document(outline: [HwpOutlineItem] = []) -> HwpDocument {
        let page = HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: [AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                kind: .text,
                attributedString: attributed("제1장 총칙")
            )],
            pageNumber: 1,
            memoPanel: HwpMemoPanel(
                width: 200,
                paintList: HwpPaintList(commands: [
                    .drawText(
                        attributedString: attributed("메모"),
                        origin: CGPoint(x: 10, y: 20),
                        lineWidth: 180
                    ),
                ])
            )
        )
        return HwpDocument(
            pages: [page],
            metadata: HwpDocumentMetadata(pageCount: 1, outline: outline),
            unsupportedElements: []
        )
    }

    func testUnitsAreEmptyWithoutDocument() {
        let models = HwpDocumentAccessibility.units(document: nil, pageIndex: 0, bodyUnits: nil)

        expect(models.page).to(beEmpty())
        expect(models.memo).to(beEmpty())
    }

    func testUnitsSynthesizePageAndMemoPanel() {
        let models = HwpDocumentAccessibility.units(
            document: document(), pageIndex: 0, bodyUnits: nil
        )

        expect(models.page.map(\.label)) == ["제1장 총칙"]
        expect(models.memo.map(\.label)) == ["메모"]
    }

    /// 개요 제목은 **그 쪽** 항목만 헤딩 재료로 쓴다 — 다른 쪽의 같은 제목이
    /// 새면 접두가 겹치는 문단이 전부 헤딩이 된다.
    func testHeadingTitlesAreFilteredByPage() {
        let samePage = HwpOutlineItem(
            kind: .heading, title: "제1장 총칙", level: 1, pageNumber: 1, ordinal: 0
        )
        let otherPage = HwpOutlineItem(
            kind: .heading, title: "제1장 총칙", level: 1, pageNumber: 2, ordinal: 1
        )

        let marked = HwpDocumentAccessibility.units(
            document: document(outline: [samePage]), pageIndex: 0, bodyUnits: nil
        )
        let unmarked = HwpDocumentAccessibility.units(
            document: document(outline: [otherPage]), pageIndex: 0, bodyUnits: nil
        )

        expect(marked.page.map(\.isHeading)) == [true]
        expect(unmarked.page.map(\.isHeading)) == [false]
    }

    /// 책갈피는 제목 문단이 아니다 — 헤딩 재료에서 빠진다.
    func testBookmarksDoNotMarkHeadings() {
        let bookmark = HwpOutlineItem(
            kind: .bookmark, title: "제1장 총칙", level: nil, pageNumber: 1, ordinal: 0
        )

        let models = HwpDocumentAccessibility.units(
            document: document(outline: [bookmark]), pageIndex: 0, bodyUnits: nil
        )

        expect(models.page.map(\.isHeading)) == [false]
    }
}
