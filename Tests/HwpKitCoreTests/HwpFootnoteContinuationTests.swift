import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 합성 조립·페이지네이션 헬퍼 — 클래스 본문이 SwiftLint type_body_length
    /// 상한(400줄)에 닿아 갈라 뒀다.
    private enum FootnoteContinuationSupport {
        static let pitch: CGFloat = 11.72
        static let box: CGFloat = 9.0
        static let overhead: CGFloat = HwpRenderTuning.Footnote.dividerDefaultMarginTop
            + HwpRenderTuning.Footnote.dividerDefaultMarginBottom

        // MARK: - 합성 조립

        static func lineSegPayload(
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
        static func noteLines(
            _ locations: [Int32]
        ) -> [(location: Int32, height: Int32, spacing: Int32)] {
            locations.map { (location: $0, height: 900, spacing: 272) }
        }

        /// 자동 번호 마커로 시작하는 각주 첫 문단 + 줄 캐시. 줄바꿈 문자로 CT 줄 수를
        /// 캐시 줄 수와 같게 고정한다 (조각 문자열 대응이 비례 근사라 어긋나면 흔들린다).
        static func note(
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
        static func notePlainParagraph(
            _ text: String, locations: [Int32]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.textParagraph(text)
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                lineSegPayload(noteLines(locations))
            )
            return paragraph
        }

        /// 각주 참조 마커를 `noteCount`개 가진 한 줄 본문 문단 — 세로 위치 `location`.
        static func host(
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
        static func paginate(
            _ body: [CoreHwp.HwpParagraph],
            footnoteNumberingMode: UInt32 = 0
        ) -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(
                    footnoteNumberingMode: footnoteNumberingMode
                ))],
                bodyParagraphs: body
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 다음 쪽 본문 — 세로 위치가 되돌아가 한글의 쪽 절단점이 된다.
        static func nextPageBody(bottomAt location: Int32? = nil) throws -> [CoreHwp.HwpParagraph] {
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

        static func footnoteBlocks(on page: HwpPage?) -> [HwpFootnoteBlock] {
            (page?.blocks ?? []).compactMap { block in
                if case let .footnote(note) = block.payload {
                    return note
                }
                return nil
            }
        }

        static func text(_ block: HwpFootnoteBlock) -> String {
            block.paragraphs.map(\.attributedString.string).joined()
        }

        /// 앞·뒤 장식 문자만 지정한 각주 모양 — 구역마다 번호 라벨이 달라지는 문서를
        /// 재현한다. 구분선 값은 건드리지 않아 기본 여백이 그대로 쓰인다.
        static func footnoteShape(
            head: Character?, tail: Character?
        ) -> CoreHwp.HwpFootnoteShape {
            var shape = CoreHwp.HwpSectionDef().footNoteShape
            shape.decorationHeadRawValue = head?.utf16.first ?? 0
            shape.decorationTailRawValue = tail?.utf16.first ?? 0
            return shape
        }

        /// 지정 폭의 A4 쪽 기하 (단위 테스트용) — 구역이 바뀌며 폭이 달라지는 문서를
        /// 페이지네이터 없이 재현한다.
        static func geometry(contentWidth: CGFloat) -> HwpPageGeometry {
            let frame = CGRect(x: 72, y: 72, width: contentWidth, height: 698)
            return HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: frame,
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [frame]
            )
        }

        static func contentBottom(of page: HwpPage) -> CGFloat {
            page.size.height - page.margins.bottom
        }

        /// host 줄 상자 아래에서 본문 하단까지 `available`pt (구분선 여백 제외) 를 남기는
        /// host 세로 위치. 본문 상단 56.68pt·하단 799.36pt (sectionDef 기본 쪽).
        static func hostLocation(leaving available: CGFloat) -> Int32 {
            let contentHeight: CGFloat = 841.88 - 56.68 - 42.52
            let boxBottom = contentHeight - overhead - available
            return Int32((boxBottom * 100).rounded()) - 1000
        }
    }

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

        /// 폭이 다른 구역으로 이월돼도 **앞 쪽이 소비한 문자 경계**가 보존돼야 한다
        /// (#165 리뷰). 이어지는 조각은 새 쪽의 폭으로 문단을 다시 조판하므로 줄 나눔이
        /// 달라진다 — 캐시 줄 인덱스를 CT 줄 수에 비례 환산한 경계는 앞 쪽이 실제로 그린
        /// 마지막 글자와 다른 자리를 가리켜 글자가 통째로 사라지거나 겹친다.
        func testContinuationKeepsConsumedTextAcrossAWidthChange() throws {
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.noteParagraph(
                " " + words,
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 2344, 0, 1172, 2344]))
            )
            let input = HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let wide = Support.geometry(contentWidth: 451)
            let narrow = Support.geometry(contentWidth: 200)

            // 통째 배치(빈 쪽)의 문자열이 이 각주의 전체 텍스트다 — 폭과 무관하다.
            let whole = layout.place(
                footnotes: [input], onPage: wide, index: index, limitsAreaToHalfContent: false
            )
            let full = Support.text(try XCTUnwrap(whole.blocks.first))
            // 앞 세 줄(44.16pt)은 들어가고 전체(91.04pt)는 안 들어가는 자리에서 나눈다.
            let split = layout.place(
                footnotes: [input], onPage: wide, index: index,
                limitsAreaToHalfContent: false, bodyBottom: wide.contentFrame.maxY - 64.2
            )
            let head = Support.text(try XCTUnwrap(split.blocks.first))
            expect(split.overflow.count) == 1
            // 이월분은 **좁은** 쪽에서 다시 조판된다.
            let carried = layout.place(
                footnotes: split.overflow, onPage: narrow, index: index,
                limitsAreaToHalfContent: false
            )
            let tail = Support.text(try XCTUnwrap(carried.blocks.first))

            expect(full.hasPrefix(head)) == true
            expect(full.hasSuffix(tail)) == true
            expect(head.count + tail.count) == full.count
        }

        /// 개체를 담은 각주를 통째로 배치할 때 블록이 그 개체를 담아야 한다 (#165 리뷰).
        /// 쪽에 걸친 캐시(비단조)의 쪽 몫 합은 한글이 **두 쪽에 나눠** 그린 높이인데,
        /// 개체를 담은 각주는 나누지 않고 한 쪽에 통째로 그리므로 그 합으로는 CT 좌표로
        /// 수집한 개체를 담지 못해 다음 각주와 겹친다.
        func testWholeNoteWithAnObjectKeepsAHeightThatContainsIt() throws {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 18)]
                + " 첫째 줄\n둘째 줄\n셋째 줄\n넷째 줄 ".utf16
                .map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 11)]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")"),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 2000, height: 3000)),
            ]
            // 세로 위치가 되돌아가는 캐시 — 한글이 두 쪽에 나눠 그린 각주다.
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 0, 1172]))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let placement = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)],
                onPage: Support.geometry(contentWidth: 451),
                index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false
            )
            let block = try XCTUnwrap(placement.blocks.first)
            let objectBottom = block.shapes.map(\.rect.maxY).max() ?? 0
            expect(objectBottom) > 0
            expect(block.frame.height) >= objectBottom - 0.01
        }

        /// 쪽마다 번호를 새로 시작하면 (표 134 모드 2) 이월된 각주와 새 각주가 **같은 표시
        /// 번호**를 갖는다 (#165 리뷰). 번호로 그룹을 나누면 둘이 한 각주로 합쳐져 사이
        /// 여백이 사라지고, 앞 각주의 마지막 줄 간격까지 높이에 남는다.
        func testCarriedAndNewNoteSharingADisplayNumberStayDistinct() async throws {
            let split = try Support.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 0])
            let fresh = try Support.note(lines: ["새 각주"], locations: [0])
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[split]])
            let nextHost = try Support.host(at: 2720, notes: [[fresh]])
            let paginator = Support.paginate([host, nextHost], footnoteNumberingMode: 2)

            let second = try await paginator.page(at: 1)
            let blocks = Support.footnoteBlocks(on: second)
            expect(blocks.count) == 2
            expect(blocks.map(\.number)) == [1, 1]
            // 이어지는 조각은 그 각주의 끝이다 — 마지막 줄의 줄 간격을 세지 않는다.
            expect(blocks[0].frame.height).to(beCloseTo(Support.box, within: 0.01))
            // 서로 다른 각주 사이에는 여백이 들어간다.
            expect(blocks[1].frame.minY - blocks[0].frame.maxY).to(beCloseTo(
                HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes, within: 0.01
            ))
        }

        /// 구역이 바뀌어 **번호 장식**이 달라져도 소비한 문자 경계가 보존돼야 한다
        /// (#165 리뷰). 이어지는 조각은 그 쪽 구역의 각주 모양으로 문자열을 다시 만드는데,
        /// 라벨 길이가 달라지면 본문 글자 위치가 통째로 밀려 앞 쪽이 그린 마지막 글자와
        /// 다른 자리에서 이어진다 — 폭이 같아도 글자가 잘린다.
        func testContinuationKeepsConsumedTextAcrossAShapeChange() throws {
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.noteParagraph(
                " " + words,
                // 장식을 안 실은 자동 번호 — 라벨이 **구역 각주 모양**을 따른다.
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1)
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 2344, 0, 1172, 2344]))
            )
            let input = HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let page = Support.geometry(contentWidth: 451)
            let decorated = Support.footnoteShape(head: "(", tail: ")")
            let plain = Support.footnoteShape(head: nil, tail: nil)

            let whole = layout.place(
                footnotes: [input], onPage: page, index: index,
                footnoteShape: decorated, limitsAreaToHalfContent: false
            )
            let full = Support.text(try XCTUnwrap(whole.blocks.first))
            // 앞 세 줄(32.44pt)은 들어가고 전체(67.6pt)는 안 들어가는 자리에서 나눈다.
            let split = layout.place(
                footnotes: [input], onPage: page, index: index,
                footnoteShape: decorated, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 54.2
            )
            let head = Support.text(try XCTUnwrap(split.blocks.first))
            expect(split.overflow.count) == 1
            // 이월분은 **장식 없는** 구역에서 다시 조판된다.
            let carried = layout.place(
                footnotes: split.overflow, onPage: page, index: index,
                footnoteShape: plain, limitsAreaToHalfContent: false
            )
            let tail = Support.text(try XCTUnwrap(carried.blocks.first))

            expect(full.hasPrefix(head)) == true
            expect(full.hasSuffix(tail)) == true
            expect(head.count + tail.count) == full.count
        }

        /// 개체가 **뒤 문단**에 붙은 각주도 통째로 CT 높이를 쓴다 (#165 리뷰). 분할 금지는
        /// 각주 단위인데 높이 보존이 문단 단위면, 앞 문단이 캐시 합으로 줄어 그 문단의 마지막
        /// 글줄 위로 뒤 문단의 그림이 올라온다.
        func testObjectInALaterParagraphKeepsEveryParagraphOnCTHeight() throws {
            let text = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄"], locations: [0, 1172, 0, 1172]
            )
            var picture = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = "그림 ".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 11)]
            picture.paraText = paraText
            picture.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 2000, height: 3000)),
            ]
            picture.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0]))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let placement = layout.place(
                footnotes: [
                    HwpFootnoteLayout.Input(paragraph: text, number: 1),
                    HwpFootnoteLayout.Input(paragraph: picture, number: 1),
                ],
                onPage: Support.geometry(contentWidth: 451),
                index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false
            )
            expect(placement.blocks.count) == 2
            let first = try XCTUnwrap(placement.blocks.first)
            // 네 줄 × 16pt — 캐시 합 46.88pt로 줄면 넷째 줄이 그림 아래로 밀린다.
            expect(first.frame.height).to(beCloseTo(64, within: 1))
            expect(placement.blocks[1].frame.minY).to(beCloseTo(first.frame.maxY, within: 0.01))
        }

        /// 표시 번호가 같은 서로 다른 각주는 **식별자 없이는** 한 각주로 묶인다 (#165 리뷰) —
        /// 남은 자리에 들어가는 이월 조각까지 새 각주와 함께 다음 쪽으로 밀린다.
        func testNotesSharingADisplayNumberMergeWithoutAnIdentity() throws {
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let page = Support.geometry(contentWidth: 451)
            let split = try Support.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 0])
            // 캐시 없는 새 각주 — 나눌 지점이 없어 그룹이 통째로 밀린다.
            let fresh = HwpSynthetic.noteParagraph(
                " 새 각주",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let first = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: split, number: 1)],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 29.2
            )
            let carried = try XCTUnwrap(first.overflow.first)

            // 이월 조각 9.0pt는 남은 12pt에 들어가지만, 같은 번호라 새 각주와 한 그룹이 된다.
            let merged = layout.place(
                footnotes: [carried, HwpFootnoteLayout.Input(paragraph: fresh, number: 1)],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 26.2
            )
            expect(merged.blocks).to(beEmpty())
            expect(merged.overflow.count) == 2

            // 식별자를 주면 서로 다른 각주로 갈려 이월 조각이 남은 자리에 실린다.
            let distinct = layout.place(
                footnotes: [
                    carried,
                    HwpFootnoteLayout.Input(paragraph: fresh, number: 1, noteId: 2),
                ],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 26.2
            )
            expect(distinct.blocks.count) == 1
            expect(Support.text(try XCTUnwrap(distinct.blocks.first))).to(contain("둘째 줄"))
            expect(distinct.overflow.count) == 1
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
