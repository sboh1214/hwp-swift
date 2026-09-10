import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    // 합성 조립·페이지네이션 헬퍼 — 클래스 본문이 SwiftLint type_body_length
    // 상한(400줄)에 닿아 갈라 뒀다.

    /// 절대 캐시 모드의 각주 이어짐 (#165) — 한글.app 12.30 실측 규칙
    /// (`HwpFootnoteContinuation.swift` 머리 주석) 을 합성 문서로 잠근다.
    ///
    /// 각주 문단의 줄 캐시는 각주 시작 기준 세로 위치라 쪽이 갈리면 0으로 되돌아온다.
    /// 줄 높이 900 + 줄 간격 272 (헌법주석 각주 줄 캐시 그대로) 라 피치는 11.72pt,
    /// 마지막 줄 상자는 9pt다. 본문 host는 한 줄 (h 1000 + sp 600) 이고 그 아래 자리
    /// = 본문 하단 − (host 줄 상자 아래) − 구분선 여백 (8.5 + 5.7, 기본값) 이다.
    final class HwpFootnoteContinuationTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        // MARK: - 분할·이월

        /// 통째로 안 들어가는 각주는 줄 캐시의 분할 지점 (세로 위치 리셋) 에서 나뉜다 —
        /// 앞 몫은 참조 쪽 바닥에, 나머지는 다음 쪽 첫 각주로 (구분선 다시, 번호 없이).
        func testNoteSplitsAtTheCachedPageBreak() async throws {
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            // 3줄 (32.44) 은 들어가고 4줄 (44.16) 은 안 들어가는 자리
            let host = try Support.host(at: Support.hostLocation(leaving: 40), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            let head = try XCTUnwrap(Support.footnoteBlocks(on: first).first)
            let tail = try XCTUnwrap(Support.footnoteBlocks(on: second).first)

            expect(Support.footnoteBlocks(on: first).count) == 1
            expect(Support.text(head).hasPrefix("1)")) == true
            expect(Support.text(head)).to(contain("셋째 줄"))
            expect(Support.text(head)).toNot(contain("넷째 줄"))
            expect(head.frame.height).to(beCloseTo(2 * Support.pitch + Support.box, within: 0.01))
            // 바닥 정렬 — 마지막 줄 상자 아래가 본문 하단
            expect(head.frame.maxY).to(beCloseTo(Support.contentBottom(of: try XCTUnwrap(first)), within: 0.01))
            // 구분선은 위 여백 끝 가운데, 첫 각주는 선 가운데 + 아래 여백
            expect(head.separatorLine.midY).to(beCloseTo(
                head.frame.minY - HwpRenderTuning.Footnote.dividerDefaultMarginBottom, within: 0.01
            ))

            expect(Support.footnoteBlocks(on: second).count) == 1
            expect(tail.number) == head.number
            expect(Support.text(tail).hasPrefix("1)")) == false
            expect(Support.text(tail)).to(contain("넷째 줄"))
            expect(Support.text(tail)).to(contain("다섯째 줄"))
            expect(Support.text(tail)).toNot(contain("셋째 줄"))
            expect(tail.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
            expect(tail.separatorLine.width) > 0
            expect(tail.frame.maxY).to(beCloseTo(Support.contentBottom(of: try XCTUnwrap(second)), within: 0.01))
        }

        /// 분할 지점이 없는 각주는 첫 줄이 들어가도 통째로 다음 쪽으로 옮긴다 (한글은 나눌
        /// 때 캐시에 리셋을 남기므로, 리셋 없는 각주를 나누면 한글에 없는 분할이다).
        func testNoteWithoutCachedBreakMovesWhole() async throws {
            let note = try Support.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 1172])
            // 한 줄 (9) 은 들어가지만 두 줄 (20.72) 은 안 들어가는 자리
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))

            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            expect(Support.footnoteBlocks(on: first)).to(beEmpty())
            let moved = try XCTUnwrap(Support.footnoteBlocks(on: second).first)
            expect(Support.text(moved).hasPrefix("1)")) == true
            expect(moved.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
        }

        /// 들어맞음은 마지막 줄 **상자**까지다 — 줄 간격까지 세면 한 줄 각주가 9pt
        /// 자리에 못 들어간다 (한글 실측: 여유 0.01pt에도 싣는다).
        func testFitCountsLastLineBoxWithoutItsSpacing() async throws {
            let note = try Support.note(lines: ["한 줄 각주"], locations: [0])
            let fitting = try Support.host(at: Support.hostLocation(leaving: 9.3), notes: [[note]])
            let fittingPage = try await Support.paginate([fitting] + (try Support.nextPageBody())).page(at: 0)
            let placed = try XCTUnwrap(Support.footnoteBlocks(on: fittingPage).first)
            expect(placed.frame.height).to(beCloseTo(Support.box, within: 0.01))
            expect(placed.frame.maxY).to(beCloseTo(Support.contentBottom(of: try XCTUnwrap(fittingPage)), within: 0.01))

            let cramped = try Support.host(at: Support.hostLocation(leaving: 8.5), notes: [[note]])
            let crampedPaginator = Support.paginate([cramped] + (try Support.nextPageBody()))
            let crampedFirst = try await crampedPaginator.page(at: 0)
            let crampedSecond = try await crampedPaginator.page(at: 1)
            expect(Support.footnoteBlocks(on: crampedFirst)).to(beEmpty())
            expect(Support.footnoteBlocks(on: crampedSecond).count) == 1
        }

        /// 각주 사이 피치 = 앞 각주 마지막 줄 상자 + 사이 여백 (줄 간격은 여백이 대체한다).
        func testBetweenNotesGapReplacesTrailingLineSpacing() async throws {
            let first = try Support.note(lines: ["첫 각주"], locations: [0])
            let second = try Support.note(lines: ["둘째 각주"], locations: [0])
            let host = try Support.host(at: 30000, notes: [[first], [second]])
            let page = try await Support.paginate([host] + (try Support.nextPageBody())).page(at: 0)
            let blocks = Support.footnoteBlocks(on: page)

            expect(blocks.count) == 2
            expect(blocks[0].frame.height).to(beCloseTo(Support.box, within: 0.01))
            expect(blocks[1].frame.minY).to(beCloseTo(
                blocks[0].frame.maxY + HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes,
                within: 0.01
            ))
            expect(blocks[1].frame.maxY).to(beCloseTo(Support.contentBottom(of: try XCTUnwrap(page)), within: 0.01))
        }

        /// 여러 문단짜리 각주의 뒤 문단이 0에서 다시 시작하면 (앞 문단 아래보다 낮은 위치)
        /// 그 문단부터 통째로 다음 쪽이다 — 앞 문단이 이 쪽의 마지막 줄이 된다.
        func testLaterParagraphRestartingAtZeroMovesToTheNextPage() async throws {
            let first = try Support.note(lines: ["첫째 문단 첫 줄", "첫째 문단 둘째 줄"], locations: [0, 1172])
            let second = try Support.notePlainParagraph("둘째 문단", locations: [0])
            // 첫째 문단 (20.72) 은 들어가고 각주 전체 (32.44) 는 안 들어가는 자리
            let host = try Support.host(at: Support.hostLocation(leaving: 25), notes: [[first, second]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let head = Support.footnoteBlocks(on: firstPage)
            let tail = Support.footnoteBlocks(on: secondPage)
            expect(head.count) == 1
            expect(Support.text(try XCTUnwrap(head.first))).to(contain("첫째 문단 둘째 줄"))
            expect(head.first?.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
            expect(tail.count) == 1
            expect(Support.text(try XCTUnwrap(tail.first))) == "둘째 문단"
            expect(tail.first?.number) == head.first?.number
            expect(tail.first?.frame.height).to(beCloseTo(Support.box, within: 0.01))
        }

        /// 세 쪽에 걸친 각주 — 이어지는 조각도 다시 나뉜다 (캐시 리셋이 둘).
        func testContinuationSplitsAgainAcrossThreePages() async throws {
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 0, 1172, 0]
            )
            let location = Support.hostLocation(leaving: 25)
            let host = try Support.host(at: location, notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody(bottomAt: location)))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 3
            let pages = try await (0 ..< 3).asyncMap { try await paginator.page(at: $0) }
            let blocks = pages.map { Support.footnoteBlocks(on: $0) }
            expect(blocks.map(\.count)) == [1, 1, 1]
            expect(Support.text(try XCTUnwrap(blocks[0].first))).to(contain("둘째 줄"))
            expect(Support.text(try XCTUnwrap(blocks[1].first))).to(contain("셋째 줄"))
            expect(Support.text(try XCTUnwrap(blocks[1].first))).toNot(contain("다섯째 줄"))
            expect(Support.text(try XCTUnwrap(blocks[2].first))).to(contain("다섯째 줄"))
            expect(blocks[0].first?.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
            expect(blocks[1].first?.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
            expect(blocks[2].first?.frame.height).to(beCloseTo(Support.box, within: 0.01))
        }

        /// 이어지는 조각을 **다시** 나눌 때도 경계는 문단 전체 기준이다 (#165 리뷰).
        /// 캐시 4줄·CT 5줄처럼 줄 수가 갈리면 (폰트 대체) 조각 문자열은 비례로 잘리는데,
        /// 남은 줄 기준으로 환산한 앞 조각 경계와 다음 쪽이 문단 전체 기준으로 다시 계산한
        /// 경계가 반올림에서 어긋나 가운데 줄이 통째로 사라진다 (반대 비율이면 중복된다).
        func testResplitKeepsEveryLineWhenCacheAndCTLineCountsDiffer() async throws {
            let texts = ["가나다라", "마바사아", "자차카타", "파하거너", "더러머버"]
            let note = try Support.note(lines: texts, locations: [0, 0, 0, 1172])
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            let paginator = Support.paginate(
                [host] + (try Support.nextPageBody(bottomAt: Support.hostLocation(leaving: 12)))
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 3
            let pages = try await (0 ..< 3).asyncMap { try await paginator.page(at: $0) }
            let drawn = pages.map { page in
                Support.footnoteBlocks(on: page).map { Support.text($0) }.joined()
            }
            let missing = texts.filter { line in !drawn.contains { $0.contains(line) } }
            let duplicated = texts.filter { line in
                drawn.filter { $0.contains(line) }.count > 1
            }
            expect(missing) == []
            expect(duplicated) == []
            // 경계는 문단 전체 기준 비례 환산이다 — 캐시 [1,2)는 CT [1,3) (round(2/4×5)=3).
            expect(drawn[1]).to(contain("마바사아"))
            expect(drawn[1]).to(contain("자차카타"))
            expect(drawn[2]).to(contain("파하거너"))
        }

        /// 개체를 담은 각주는 나누지 않는다 (#165 리뷰). 개체 좌표는 문단 **전체** 조판
        /// 기준이라 조각으로 나누면 뒤 줄의 그림이 앞 조각에 남아 블록 밖에 그려지고 뒤
        /// 조각은 빈다. 한글이 그런 각주를 어떻게 나누는지는 실측이 없으므로 통째로 옮긴다.
        func testNoteCarryingAnObjectMovesWholeInsteadOfSplitting() async throws {
            var note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄"],
                locations: [0, 1172, 0, 1172]
            )
            note.ctrlHeaderArray = (note.ctrlHeaderArray ?? []) + [
                .genShapeObject(HwpSynthetic.floatingShapeObject(width: 20000, height: 1000)),
            ]
            // 앞 두 줄(20.72pt)은 들어가고 각주 전체(44.16pt)는 안 들어가는 자리 —
            // 개체가 없으면 캐시 분할 지점(줄 2)에서 나뉜다.
            let host = try Support.host(at: Support.hostLocation(leaving: 25), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))

            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            expect(Support.footnoteBlocks(on: first)).to(beEmpty())
            let moved = try XCTUnwrap(Support.footnoteBlocks(on: second).first)
            expect(Support.text(moved)).to(contain("첫째 줄"))
            expect(Support.text(moved)).to(contain("넷째 줄"))
            // 개체는 옮겨진 각주 하나에만 있고 그 블록 안에 있다.
            expect(moved.shapes.count) == 1
            expect(moved.shapes.first?.rect.maxY) <= moved.frame.height + 0.01
        }

        /// 진행 보장 — 빈 쪽에도 안 들어가는 각주 (분할 지점 없음) 는 참조 쪽에 그대로
        /// 싣는다. 넘기면 영영 못 싣고 이월 드레인이 쪽 상한까지 돈다.
        func testOversizeNoteWithoutBreakIsPlacedAnyway() async throws {
            let lines = (1 ... 80).map { "줄 \($0)" }
            let note = try Support.note(lines: lines, locations: (0 ..< 80).map { Int32($0 * 1172) })
            let host = try Support.host(at: Support.hostLocation(leaving: 40), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            let placed = try XCTUnwrap(Support.footnoteBlocks(on: first).first)
            let contentTop = try XCTUnwrap(first).margins.top
            expect(placed.frame.minY) >= contentTop - 0.01
            expect(Support.footnoteBlocks(on: second)).to(beEmpty())
        }

        /// 예약 ≡ 배치 — 이어지는 조각의 재예약 (`reservedFootnoteHeight`) 은 배치가 낼
        /// 블록 높이와 구분선 여백의 합이다 (예약이 크면 한글에 없는 쪽 절단이 생긴다).
        func testContinuationReservationMatchesPlacement() throws {
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let geometry = HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
            )
            let continuation = HwpFootnoteLayout.Input(
                paragraph: note, number: 1, sizeResolver: nil, numbering: nil,
                placedLineCount: 3, noteId: 1
            )
            var coordinator = HwpFootnoteCoordinator(index: index, fontResolver: .testDeterministic)
            let reserved = coordinator.reservedFootnoteHeight(
                for: [continuation],
                environment: .init(contentWidth: geometry.contentFrame.width, footnoteShape: nil)
            )
            let placement = HwpFootnoteLayout(fontResolver: .testDeterministic).place(
                footnotes: [continuation], onPage: geometry, index: index,
                limitsAreaToHalfContent: false
            )
            let block = try XCTUnwrap(placement.blocks.first)
            expect(block.frame.height).to(beCloseTo(Support.pitch + Support.box, within: 0.01))
            expect(reserved).to(beCloseTo(Support.overhead + block.frame.height, within: 0.01))
            expect(Support.text(block).hasPrefix("1)")) == false
            expect(Support.text(block)).to(contain("넷째 줄"))
        }

        // MARK: - 줄 캐시 해석

        func testCacheLinesMergeContinuationSegmentsAndFindPageBreaks() throws {
            var paragraph = try HwpSynthetic.textParagraph("각주")
            // 둘째 세그먼트는 같은 위치에 bit 17이 꺼진 이어지는 세그먼트 — 같은 줄
            var payload = Support.lineSegPayload(Support.noteLines([0]))
            payload += Support.lineSegPayload(Support.noteLines([0]), property: 0x40000)
            payload += Support.lineSegPayload(Support.noteLines([1172, 0, 1172]))
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)

            let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: paragraph))
            expect(lines.map(\.location)) == [0, 1172, 0, 1172]
            expect(HwpFootnoteCacheLines.pageBreaks(in: lines)) == [2]
            // 쪽 몫의 합: 쪽마다 첫 줄 위 ~ 마지막 줄 전진량 끝 (2344 + 2344 HWPUNIT)
            expect(HwpFootnoteCacheLines.height(of: lines, in: 0 ..< 4)).to(beCloseTo(46.88, within: 0.001))
            expect(HwpFootnoteCacheLines.height(of: lines, in: 2 ..< 4)).to(beCloseTo(23.44, within: 0.001))
            expect(HwpFootnoteCacheLines.trailingSpacing(of: lines, in: 0 ..< 4)).to(beCloseTo(2.72, within: 0.001))
        }

        /// `0, 0` — bit 17이 켜진 채 같은 위치면 새 줄이자 분할 지점이다 (첫 줄만 앞 쪽).
        func testEqualLocationWithLineStartFlagIsAPageBreak() throws {
            var paragraph = try HwpSynthetic.textParagraph("각주")
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 0, 1172]))
            )
            let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: paragraph))
            expect(lines.count) == 3
            expect(HwpFootnoteCacheLines.pageBreaks(in: lines)) == [1]
        }
    }

    private extension Range<Int> {
        func asyncMap<T>(_ transform: (Int) async throws -> T) async rethrows -> [T] {
            var results: [T] = []
            for index in self {
                await results.append(try transform(index))
            }
            return results
        }
    }
#endif
