import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 절대 캐시 모드의 각주 이어짐 (#165) — 한글.app 12.30 실측 규칙
    /// (`HwpFootnoteContinuation.swift` 머리 주석) 을 합성 문서로 잠근다.
    ///
    /// 각주 문단의 줄 캐시는 각주 시작 기준 세로 위치라 쪽이 갈리면 0으로 되돌아온다.
    /// 줄 높이 900 + 줄 간격 272 (헌법주석 각주 줄 캐시 그대로) 라 피치는 11.72pt,
    /// 마지막 줄 상자는 9pt다. 본문 host는 한 줄 (h 1000 + sp 600) 이고 그 아래 자리
    /// = 본문 하단 − (host 줄 상자 아래) − 구분선 여백 (8.5 + 5.7, 기본값) 이다.
    final class HwpFootnoteContinuationTests: XCTestCase {
        private static let pitch: CGFloat = 11.72
        private static let box: CGFloat = 9.0
        private static let overhead: CGFloat = HwpRenderTuning.Footnote.dividerDefaultMarginTop
            + HwpRenderTuning.Footnote.dividerDefaultMarginBottom

        // MARK: - 합성 조립

        private static func lineSegPayload(
            _ lines: [(location: Int32, height: Int32, spacing: Int32)],
            property: UInt32 = 0x60000
        ) -> Data {
            var payload = Data()
            for line in lines {
                withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.location.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(765).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.spacing.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(42520).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: property.littleEndian) { payload.append(contentsOf: $0) }
            }
            return payload
        }

        /// 각주 줄 캐시 — 세로 위치 목록 (HWPUNIT, 각주 시작 기준). 줄 높이 900·간격 272.
        private static func noteLines(
            _ locations: [Int32]
        ) -> [(location: Int32, height: Int32, spacing: Int32)] {
            locations.map { (location: $0, height: 900, spacing: 272) }
        }

        /// 자동 번호 마커로 시작하는 각주 첫 문단 + 줄 캐시. 줄바꿈 문자로 CT 줄 수를
        /// 캐시 줄 수와 같게 고정한다 (조각 문자열 대응이 비례 근사라 어긋나면 흔들린다).
        private static func note(
            lines texts: [String], locations: [Int32]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = HwpSynthetic.noteParagraph(
                " " + texts.joined(separator: "\n"),
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                lineSegPayload(noteLines(locations))
            )
            return paragraph
        }

        /// 각주의 뒤 문단 (마커 없음) + 줄 캐시.
        private static func notePlainParagraph(
            _ text: String, locations: [Int32]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.textParagraph(text)
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                lineSegPayload(noteLines(locations))
            )
            return paragraph
        }

        /// 각주 참조 마커를 `noteCount`개 가진 한 줄 본문 문단 — 세로 위치 `location`.
        private static func host(
            at location: Int32, notes: [[CoreHwp.HwpParagraph]]
        ) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [(characters: 5, markers: Array(repeating: 17, count: notes.count))],
                segments: [(location: location, height: 1000, textStart: 0)]
            )
            host.ctrlHeaderArray = notes.map {
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: $0))
            }
            return host
        }

        /// 절대 캐시 모드 문서 — 첫 loc > 0인 캐시 문단이 다수여야 한다 (감지 규칙).
        private static func paginate(
            _ body: [CoreHwp.HwpParagraph]
        ) -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: body
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 다음 쪽 본문 — 세로 위치가 되돌아가 한글의 쪽 절단점이 된다.
        private static func nextPageBody(bottomAt location: Int32? = nil) throws -> [CoreHwp.HwpParagraph] {
            var body = [try HwpSynthetic.lineSegParagraph(
                "다음 쪽 문단", segments: [(location: 2720, height: 1500)]
            )]
            if let location {
                body.append(try HwpSynthetic.lineSegParagraph(
                    "다음 쪽 아래 문단", segments: [(location: location, height: 1000)]
                ))
            }
            return body
        }

        private static func footnoteBlocks(on page: HwpPage?) -> [HwpFootnoteBlock] {
            (page?.blocks ?? []).compactMap { block in
                if case let .footnote(note) = block.payload {
                    return note
                }
                return nil
            }
        }

        private static func text(_ block: HwpFootnoteBlock) -> String {
            block.paragraphs.map(\.attributedString.string).joined()
        }

        private static func contentBottom(of page: HwpPage) -> CGFloat {
            page.size.height - page.margins.bottom
        }

        /// host 줄 상자 아래에서 본문 하단까지 `available`pt (구분선 여백 제외) 를 남기는
        /// host 세로 위치. 본문 상단 56.68pt·하단 799.36pt (sectionDef 기본 쪽).
        private static func hostLocation(leaving available: CGFloat) -> Int32 {
            let contentHeight: CGFloat = 841.88 - 56.68 - 42.52
            let boxBottom = contentHeight - overhead - available
            return Int32((boxBottom * 100).rounded()) - 1000
        }

        // MARK: - 분할·이월

        /// 통째로 안 들어가는 각주는 줄 캐시의 분할 지점 (세로 위치 리셋) 에서 나뉜다 —
        /// 앞 몫은 참조 쪽 바닥에, 나머지는 다음 쪽 첫 각주로 (구분선 다시, 번호 없이).
        func testNoteSplitsAtTheCachedPageBreak() async throws {
            let note = try Self.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            // 3줄 (32.44) 은 들어가고 4줄 (44.16) 은 안 들어가는 자리
            let host = try Self.host(at: Self.hostLocation(leaving: 40), notes: [[note]])
            let paginator = Self.paginate([host] + (try Self.nextPageBody()))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            let head = try XCTUnwrap(Self.footnoteBlocks(on: first).first)
            let tail = try XCTUnwrap(Self.footnoteBlocks(on: second).first)

            expect(Self.footnoteBlocks(on: first).count) == 1
            expect(Self.text(head).hasPrefix("1)")) == true
            expect(Self.text(head)).to(contain("셋째 줄"))
            expect(Self.text(head)).toNot(contain("넷째 줄"))
            expect(head.frame.height).to(beCloseTo(2 * Self.pitch + Self.box, within: 0.01))
            // 바닥 정렬 — 마지막 줄 상자 아래가 본문 하단
            expect(head.frame.maxY).to(beCloseTo(Self.contentBottom(of: try XCTUnwrap(first)), within: 0.01))
            // 구분선은 위 여백 끝 가운데, 첫 각주는 선 가운데 + 아래 여백
            expect(head.separatorLine.midY).to(beCloseTo(
                head.frame.minY - HwpRenderTuning.Footnote.dividerDefaultMarginBottom, within: 0.01
            ))

            expect(Self.footnoteBlocks(on: second).count) == 1
            expect(tail.number) == head.number
            expect(Self.text(tail).hasPrefix("1)")) == false
            expect(Self.text(tail)).to(contain("넷째 줄"))
            expect(Self.text(tail)).to(contain("다섯째 줄"))
            expect(Self.text(tail)).toNot(contain("셋째 줄"))
            expect(tail.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
            expect(tail.separatorLine.width) > 0
            expect(tail.frame.maxY).to(beCloseTo(Self.contentBottom(of: try XCTUnwrap(second)), within: 0.01))
        }

        /// 분할 지점이 없는 각주는 첫 줄이 들어가도 통째로 다음 쪽으로 옮긴다 (한글은 나눌
        /// 때 캐시에 리셋을 남기므로, 리셋 없는 각주를 나누면 한글에 없는 분할이다).
        func testNoteWithoutCachedBreakMovesWhole() async throws {
            let note = try Self.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 1172])
            // 한 줄 (9) 은 들어가지만 두 줄 (20.72) 은 안 들어가는 자리
            let host = try Self.host(at: Self.hostLocation(leaving: 15), notes: [[note]])
            let paginator = Self.paginate([host] + (try Self.nextPageBody()))

            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            expect(Self.footnoteBlocks(on: first)).to(beEmpty())
            let moved = try XCTUnwrap(Self.footnoteBlocks(on: second).first)
            expect(Self.text(moved).hasPrefix("1)")) == true
            expect(moved.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
        }

        /// 들어맞음은 마지막 줄 **상자**까지다 — 줄 간격까지 세면 한 줄 각주가 9pt
        /// 자리에 못 들어간다 (한글 실측: 여유 0.01pt에도 싣는다).
        func testFitCountsLastLineBoxWithoutItsSpacing() async throws {
            let note = try Self.note(lines: ["한 줄 각주"], locations: [0])
            let fitting = try Self.host(at: Self.hostLocation(leaving: 9.3), notes: [[note]])
            let fittingPage = try await Self.paginate([fitting] + (try Self.nextPageBody())).page(at: 0)
            let placed = try XCTUnwrap(Self.footnoteBlocks(on: fittingPage).first)
            expect(placed.frame.height).to(beCloseTo(Self.box, within: 0.01))
            expect(placed.frame.maxY).to(beCloseTo(Self.contentBottom(of: try XCTUnwrap(fittingPage)), within: 0.01))

            let cramped = try Self.host(at: Self.hostLocation(leaving: 8.5), notes: [[note]])
            let crampedPaginator = Self.paginate([cramped] + (try Self.nextPageBody()))
            let crampedFirst = try await crampedPaginator.page(at: 0)
            let crampedSecond = try await crampedPaginator.page(at: 1)
            expect(Self.footnoteBlocks(on: crampedFirst)).to(beEmpty())
            expect(Self.footnoteBlocks(on: crampedSecond).count) == 1
        }

        /// 각주 사이 피치 = 앞 각주 마지막 줄 상자 + 사이 여백 (줄 간격은 여백이 대체한다).
        func testBetweenNotesGapReplacesTrailingLineSpacing() async throws {
            let first = try Self.note(lines: ["첫 각주"], locations: [0])
            let second = try Self.note(lines: ["둘째 각주"], locations: [0])
            let host = try Self.host(at: 30000, notes: [[first], [second]])
            let page = try await Self.paginate([host] + (try Self.nextPageBody())).page(at: 0)
            let blocks = Self.footnoteBlocks(on: page)

            expect(blocks.count) == 2
            expect(blocks[0].frame.height).to(beCloseTo(Self.box, within: 0.01))
            expect(blocks[1].frame.minY).to(beCloseTo(
                blocks[0].frame.maxY + HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes,
                within: 0.01
            ))
            expect(blocks[1].frame.maxY).to(beCloseTo(Self.contentBottom(of: try XCTUnwrap(page)), within: 0.01))
        }

        /// 여러 문단짜리 각주의 뒤 문단이 0에서 다시 시작하면 (앞 문단 아래보다 낮은 위치)
        /// 그 문단부터 통째로 다음 쪽이다 — 앞 문단이 이 쪽의 마지막 줄이 된다.
        func testLaterParagraphRestartingAtZeroMovesToTheNextPage() async throws {
            let first = try Self.note(lines: ["첫째 문단 첫 줄", "첫째 문단 둘째 줄"], locations: [0, 1172])
            let second = try Self.notePlainParagraph("둘째 문단", locations: [0])
            // 첫째 문단 (20.72) 은 들어가고 각주 전체 (32.44) 는 안 들어가는 자리
            let host = try Self.host(at: Self.hostLocation(leaving: 25), notes: [[first, second]])
            let paginator = Self.paginate([host] + (try Self.nextPageBody()))

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let head = Self.footnoteBlocks(on: firstPage)
            let tail = Self.footnoteBlocks(on: secondPage)
            expect(head.count) == 1
            expect(Self.text(try XCTUnwrap(head.first))).to(contain("첫째 문단 둘째 줄"))
            expect(head.first?.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
            expect(tail.count) == 1
            expect(Self.text(try XCTUnwrap(tail.first))) == "둘째 문단"
            expect(tail.first?.number) == head.first?.number
            expect(tail.first?.frame.height).to(beCloseTo(Self.box, within: 0.01))
        }

        /// 세 쪽에 걸친 각주 — 이어지는 조각도 다시 나뉜다 (캐시 리셋이 둘).
        func testContinuationSplitsAgainAcrossThreePages() async throws {
            let note = try Self.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 0, 1172, 0]
            )
            let location = Self.hostLocation(leaving: 25)
            let host = try Self.host(at: location, notes: [[note]])
            let paginator = Self.paginate([host] + (try Self.nextPageBody(bottomAt: location)))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 3
            let pages = try await (0 ..< 3).asyncMap { try await paginator.page(at: $0) }
            let blocks = pages.map { Self.footnoteBlocks(on: $0) }
            expect(blocks.map(\.count)) == [1, 1, 1]
            expect(Self.text(try XCTUnwrap(blocks[0].first))).to(contain("둘째 줄"))
            expect(Self.text(try XCTUnwrap(blocks[1].first))).to(contain("셋째 줄"))
            expect(Self.text(try XCTUnwrap(blocks[1].first))).toNot(contain("다섯째 줄"))
            expect(Self.text(try XCTUnwrap(blocks[2].first))).to(contain("다섯째 줄"))
            expect(blocks[0].first?.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
            expect(blocks[1].first?.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
            expect(blocks[2].first?.frame.height).to(beCloseTo(Self.box, within: 0.01))
        }

        /// 진행 보장 — 빈 쪽에도 안 들어가는 각주 (분할 지점 없음) 는 참조 쪽에 그대로
        /// 싣는다. 넘기면 영영 못 싣고 이월 드레인이 쪽 상한까지 돈다.
        func testOversizeNoteWithoutBreakIsPlacedAnyway() async throws {
            let lines = (1 ... 80).map { "줄 \($0)" }
            let note = try Self.note(lines: lines, locations: (0 ..< 80).map { Int32($0 * 1172) })
            let host = try Self.host(at: Self.hostLocation(leaving: 40), notes: [[note]])
            let paginator = Self.paginate([host] + (try Self.nextPageBody()))

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)
            let placed = try XCTUnwrap(Self.footnoteBlocks(on: first).first)
            let contentTop = try XCTUnwrap(first).margins.top
            expect(placed.frame.minY) >= contentTop - 0.01
            expect(Self.footnoteBlocks(on: second)).to(beEmpty())
        }

        /// 예약 ≡ 배치 — 이어지는 조각의 재예약 (`reservedFootnoteHeight`) 은 배치가 낼
        /// 블록 높이와 구분선 여백의 합이다 (예약이 크면 한글에 없는 쪽 절단이 생긴다).
        func testContinuationReservationMatchesPlacement() throws {
            let note = try Self.note(
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
                paragraph: note, number: 1, sizeResolver: nil, numbering: nil, placedLineCount: 3
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
            expect(block.frame.height).to(beCloseTo(Self.pitch + Self.box, within: 0.01))
            expect(reserved).to(beCloseTo(Self.overhead + block.frame.height, within: 0.01))
            expect(Self.text(block).hasPrefix("1)")) == false
            expect(Self.text(block)).to(contain("넷째 줄"))
        }

        // MARK: - 줄 캐시 해석

        func testCacheLinesMergeContinuationSegmentsAndFindPageBreaks() throws {
            var paragraph = try HwpSynthetic.textParagraph("각주")
            // 둘째 세그먼트는 같은 위치에 bit 17이 꺼진 이어지는 세그먼트 — 같은 줄
            var payload = Self.lineSegPayload(Self.noteLines([0]))
            payload += Self.lineSegPayload(Self.noteLines([0]), property: 0x40000)
            payload += Self.lineSegPayload(Self.noteLines([1172, 0, 1172]))
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
                Self.lineSegPayload(Self.noteLines([0, 0, 1172]))
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
