@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 책갈피 수집·쪽 귀속·재조판 멱등 (#77).
    ///
    /// 수준 판정과 제목 정규화는 `HwpOutlineCollectorTests`가 본다 (한 클래스에
    /// 다 넣으면 swiftlint `type_body_length` error를 넘는다).
    final class HwpOutlineNavigationTests: XCTestCase {
        // MARK: - 책갈피

        func testBookmarkIsCollectedWithItsName() async throws {
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("첫 앵커")]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            expect(outline.count) == 1
            expect(outline.first?.kind) == .bookmark
            expect(outline.first?.title) == "첫 앵커"
            expect(outline.first?.level).to(beNil())
            expect(outline.first?.pageNumber) == 1
            expect(outline.first?.pageIndex) == 0
        }

        func testUnnamedBookmarkIsSkipped() async throws {
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [
                HwpSynthetic.bookmarkControl(""),
                HwpSynthetic.bookmarkControl(nil),
            ]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// 머리말/꼬리말 책갈피는 뺀다 (검색의 `role == .body` 스코프와 같은 규약).
        /// 쪽마다 다시 그려지는 크롬의 앵커는 "그 쪽으로 간다"의 목적지가 아니다.
        func testPageChromeBookmarksAreExcluded() async throws {
            var chromeParagraph = try HwpSynthetic.styledParagraph("머리말 텍스트")
            chromeParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("머리말 앵커")]
            var footerParagraph = try HwpSynthetic.styledParagraph("꼬리말 텍스트")
            footerParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("꼬리말 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [
                .header(HwpSynthetic.listControl(
                    ctrlId: .header, paragraphs: [chromeParagraph]
                )),
                .footer(HwpSynthetic.listControl(
                    ctrlId: .footer, paragraphs: [footerParagraph]
                )),
                HwpSynthetic.bookmarkControl("본문 앵커"),
            ]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["본문 앵커"]
        }

        /// 표 셀·각주는 본문이라 포함한다. 모델을 걷는 것이라 여러 쪽에 걸친
        /// 표에서도 셀은 한 번만 순회된다 — 같은 책갈피가 두 번 실리지 않는다.
        func testBookmarksInsideBodyContainersAreCollectedOnce() async throws {
            var cellParagraph = try HwpSynthetic.styledParagraph("셀 텍스트")
            cellParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("셀 앵커")]
            var noteParagraph = try HwpSynthetic.styledParagraph("각주 텍스트")
            noteParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("각주 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [
                .table(HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: [2000],
                    cellParagraphs: [[[cellParagraph]]]
                )),
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote, paragraphs: [noteParagraph]
                )),
            ]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["셀 앵커", "각주 앵커"]
        }

        /// 개요는 **최상위 본문 문단만** 대상이다 — 표 셀 안 개요 문단은 문서
        /// 목차의 항목이 아니다 (`noori`의 개요 문단 4개가 전부 이 모양이라
        /// 그 픽스처는 개요 예시로 부적절하다). 책갈피는 반대로 셀 안까지 모은다.
        func testHeadingsInsideContainersAreNotCollected() async throws {
            var cellParagraph = try HwpSynthetic.styledParagraph("셀 안 제목", paraShapeId: 1)
            cellParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("셀 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [
                .table(HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: [2000],
                    cellParagraphs: [[[cellParagraph]]]
                )),
            ]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            expect(outline.map(\.title)) == ["셀 앵커"]
            expect(outline.headings).to(beEmpty())
        }

        // MARK: - 쪽 귀속

        /// 개요는 문단이 **시작한** 쪽이고 책갈피는 앵커가 **놓인** 쪽이다.
        /// 쪽 경계를 걸친 제목이 뒷쪽으로 밀리지 않게 하려면 개요는 배치 **전**
        /// 값을 써야 한다 — 이 문단은 1쪽에서 시작해 2쪽으로 넘어간다.
        func testHeadingOnPageBoundaryReportsTheStartingPage() async throws {
            var heading = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: [
                    (characters: 5, marker: false),
                    (characters: 5, marker: false),
                    (characters: 5, marker: false),
                ],
                segments: [
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 6),
                    // location이 줄어드는 지점이 한글의 페이지 절단점
                    (location: 2720, height: 1500, textStart: 12),
                ]
            )
            heading.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            heading.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("뒤 조각 앵커")]
            // 절대 캐시 모드 감지는 첫 loc > 0인 캐시 문단이 **다수**여야 한다.
            let tail = try (0 ..< 2).map { offset in
                try HwpSynthetic.lineSegParagraph(
                    "뒤 문단 \(offset)",
                    segments: [(location: Int32(4820 + offset * 2100), height: 1500)]
                )
            }
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [heading] + tail,
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let outline = await paginator.outline()

            let heading1 = try XCTUnwrap(outline.first { $0.kind == .heading })
            let anchor = try XCTUnwrap(outline.first { $0.kind == .bookmark })
            // 개요는 문단이 시작한 1쪽, 책갈피는 배치가 끝난 2쪽.
            expect(heading1.pageNumber) == 1
            expect(anchor.pageNumber) == 2
        }

        func testItemsOnLaterPagesCarryTheirOwnPageNumber() async throws {
            let first = try HwpSynthetic.styledParagraph("1쪽 제목", paraShapeId: 1)
            // 쪽 나누기 컨트롤 없이 작은 종이 + 채움 문단으로 쪽을 가른다.
            let filler = try (0 ..< 12).map { offset in
                try HwpSynthetic.lineSegParagraph(
                    "채움 \(offset)", segments: [(location: 0, height: 4000)]
                )
            }
            let second = try HwpSynthetic.styledParagraph("뒤쪽 제목", paraShapeId: 1)
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [first] + filler + [second],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                pageHeight: 20000
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2
            let outline = await paginator.outline()

            expect(outline.map(\.title)) == ["1쪽 제목", "뒤쪽 제목"]
            expect(outline.first?.pageNumber) == 1
            expect(try XCTUnwrap(outline.last?.pageNumber)) >= 2
        }

        // MARK: - 멱등

        /// 재조판 중복 수집을 막는 것은 "페이지네이션이 일회성"이라는 기존
        /// 불변식이다 — 같은 paginator를 몇 번 더 몰아도 목록이 늘지 않는다.
        /// (`collectedUnsupported`가 리셋 없이 성립하는 것과 같은 근거.)
        func testRepeatedPaginationDoesNotDuplicateItems() async throws {
            var host = try HwpSynthetic.styledParagraph("제목", paraShapeId: 1)
            host.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("앵커")]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let first = await paginator.outline()
            _ = await paginator.totalPages()
            _ = try await paginator.page(at: 0)
            _ = try await paginator.page(at: 1)
            let second = await paginator.outline()

            expect(first.map(\.title)) == ["제목", "앵커"]
            expect(second) == first
        }

        /// 프로그레시브 스냅샷은 확정된 접두를 그대로 싣는다 — 조판 도중에 물어도
        /// 의미가 있고, append-only라 `ordinal`이 스냅샷 사이에서 움직이지 않는다.
        func testOutlineIsAvailableAsAPrefixWhilePaginating() async throws {
            let bodyParagraphs = try (0 ..< 12).flatMap { offset in
                [
                    try HwpSynthetic.styledParagraph("제목 \(offset)", paraShapeId: 1),
                    try HwpSynthetic.lineSegParagraph(
                        "본문 \(offset)", segments: [(location: 0, height: 4000)]
                    ),
                ]
            }
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: bodyParagraphs,
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                pageHeight: 20000
            )

            _ = try await paginator.page(at: 0)
            let partial = await paginator.outline()
            _ = await paginator.totalPages()
            let complete = await paginator.outline()

            expect(partial).toNot(beEmpty())
            expect(partial.count) < complete.count
            expect(Array(complete.prefix(partial.count))) == partial
            expect(complete.map(\.ordinal)) == Array(0 ..< complete.count)
        }

        // MARK: - 컬렉션 편의 API

        func testCollectionHelpersSplitKinds() {
            let items = [
                HwpOutlineItem(kind: .heading, title: "가", level: 1, pageNumber: 1, ordinal: 0),
                HwpOutlineItem(kind: .bookmark, title: "나", level: nil, pageNumber: 2, ordinal: 1),
                HwpOutlineItem(kind: .heading, title: "다", level: 2, pageNumber: 2, ordinal: 2),
            ]

            expect(items.headings.map(\.title)) == ["가", "다"]
            expect(items.bookmarks.map(\.title)) == ["나"]
            // 0-기반 인덱스는 1-기반 쪽 번호에서 파생된다 (네이티브 뷰 좌표계).
            expect(items.headings.map(\.pageIndex)) == [0, 1]
        }
    }
#endif
