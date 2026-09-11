import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 이어짐 (#165) PR 리뷰가 잡은 **쪽 수 × 줄 수** 비용의 재현 — 이월 입력이 원본
    /// 조판(`SourceLayout`)을 나르고, 남은 줄의 분할 지점·높이를 복사 없이 읽는다. 수치는
    /// 단언하지 않는다 (CI 러너마다 다르다); 대신 같은 값을 주는 **동치**와, 나른 원본을
    /// 실제로 쓰는지 (다른 폭이면 다시 조판하는지) 를 잠근다. 조립 헬퍼는
    /// `FootnoteContinuationSupport`.
    final class HwpFootnoteContinuationSourceLayoutTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        /// 쪽 리셋·간격이 섞인 줄 캐시들 — 누적표와 분할 탐색의 동치 검사 표본.
        private static let samples: [[Int32]] = [
            [0],
            [0, 1172, 2344],
            [0, 1172, 2344, 0, 1172],
            [0, 0, 1172],
            [0, 1172, 0, 0, 1172, 2344, 3516, 0],
            (0 ..< 40).map { Int32($0 % 7) * 1172 },
        ]

        /// 줄 높이가 섞인 캐시 — 고정 피치보다 큰 줄이 앞에 있어 그 전진량 끝이 마지막 줄
        /// 아래까지 내려오는 표본 (`(location, height, spacing)`).
        private static let mixedSamples: [[(location: Int32, height: Int32, spacing: Int32)]] = [
            [(0, 3000, 272), (1172, 900, 272)],
            [(0, 900, 272), (1172, 3000, 272), (2344, 900, 272), (0, 900, 272), (1172, 900, 272)],
            [(0, 900, 272), (1172, 900, 0), (2344, 5000, 272), (3516, 900, 272), (0, 4000, 272), (1172, 900, 272)],
        ]

        private static func paragraph(
            _ lines: [(location: Int32, height: Int32, spacing: Int32)]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = HwpSynthetic.noteParagraph(
                " " + lines.indices.map { "줄 \($0)" }.joined(separator: "\n"),
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(Support.lineSegPayload(lines))
            return paragraph
        }

        /// `remainingHeights[i]`는 `height(of:in: i ..< count)`와 같다 — 이월 입력이 쪽마다
        /// 남은 줄을 다 더하지 않고 이 표 하나로 남은 높이를 읽는다.
        func testRemainingHeightsMatchTheRangeHeightFromEveryLine() throws {
            let paragraphs = try Self.samples.map {
                try Support.note(lines: $0.map { "줄 \($0)" }, locations: $0)
            } + Self.mixedSamples.map(Self.paragraph)
            for paragraph in paragraphs {
                let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: paragraph))
                let layout = HwpFootnoteLayout.SourceLayout(
                    width: 300, attributed: NSAttributedString(string: ""), lines: [],
                    cacheLines: lines
                )
                for start in 0 ... lines.count {
                    expect(layout.remainingHeight(from: start))
                        .to(beCloseTo(
                            HwpFootnoteCacheLines.height(of: lines, in: start ..< lines.count),
                            within: 0.0001
                        ))
                }
            }
        }

        /// 쪽 몫의 높이는 마지막 줄이 아니라 전진량 끝의 **최댓값**까지다 (#165 리뷰) — 정본
        /// `cachedLineExtent`와 같은 정의. 고정 피치보다 큰 앞 줄(3000)이 마지막 줄(1172+900+272
        /// = 2344) 아래 3272까지 내려오면 높이는 32.72pt다; 마지막 줄만 보면 23.44pt라 25pt
        /// 자리에 들여 본문 위에 놓는다.
        func testRunHeightReachesTheTallestEarlierLine() async throws {
            let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: Self.paragraph(Self.mixedSamples[0])))
            expect(HwpFootnoteCacheLines.height(of: lines, in: 0 ..< 2)).to(beCloseTo(32.72, within: 0.001))
            expect(HwpFootnoteCacheLines.remainingHeights(of: lines)) == [3272, 2344 - 1172]

            let note = try Self.paragraph(Self.mixedSamples[0])
            let host = try Support.host(at: Support.hostLocation(leaving: 25), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            // 25pt 자리엔 32.72pt 각주가 못 들어간다 — 분할 지점도 없어 통째로 다음 쪽이다.
            expect(Support.footnoteBlocks(on: firstPage)).to(beEmpty())
            expect(Support.footnoteBlocks(on: secondPage).count) == 1
            expect(try XCTUnwrap(Support.footnoteBlocks(on: secondPage).first).frame.height)
                .to(beCloseTo(32.72 - 2.72, within: 0.01))
        }

        /// `firstPageBreak(in:after:)`는 남은 줄을 떠서 모은 분할 지점의 첫 항목과 같다.
        func testFirstPageBreakMatchesTheFirstBreakOfTheRemainingLines() throws {
            for sample in Self.samples {
                let paragraph = try Support.note(
                    lines: sample.map { "줄 \($0)" }, locations: sample
                )
                let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: paragraph))
                for start in 0 ..< lines.count {
                    let remaining = Array(lines.dropFirst(start))
                    let expected = HwpFootnoteCacheLines.pageBreaks(in: remaining).first.map { $0 + start }
                    expect(HwpFootnoteCacheLines.firstPageBreak(in: lines, after: start) ?? -1)
                        == (expected ?? -1)
                }
            }
        }

        /// 이월 입력은 원본 조판을 나르고, 다음 쪽은 폭이 같으면 그것을 **그대로** 쓴다 —
        /// 나른 원본의 문자열이 조각에 나타나는 것으로 확인한다. 폭이 다르면 (구역 변경)
        /// 문단을 다시 조판하므로 나른 원본은 쓰이지 않는다.
        func testContinuationReusesTheCarriedLayoutOnlyAtTheSameWidth() throws {
            let paragraph = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let geometry = Support.geometry(contentWidth: 451)
            let split = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)],
                onPage: geometry, index: index,
                // 앞 세 줄(32.44pt)은 들어가고 전체(55.88pt)는 안 들어가는 자리에서 나눈다.
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 50
            )
            let carried = try XCTUnwrap(split.overflow.first)
            let source = try XCTUnwrap(carried.sourceLayout)
            expect(source.width) == 451
            expect(source.cacheLines.count) == 5
            expect(source.lines.count) == 5

            // 나른 원본의 글자를 같은 길이의 표식으로 바꿔 심은 뒤 같은 폭으로 재면 그 원본에서
            // 잘라 낸 조각이 나온다 (줄 프레임의 문자 범위는 그대로라 길이를 지켜야 한다).
            let marked = NSMutableAttributedString(attributedString: source.attributed)
            marked.replaceCharacters(
                in: NSRange(location: 0, length: marked.length),
                with: String(repeating: "E", count: marked.length)
            )
            let planted = HwpFootnoteLayout.SourceLayout(
                width: source.width, attributed: marked, lines: source.lines,
                cacheLines: source.cacheLines
            )
            let reused = layout.measureNote(
                paragraph, number: 1, width: 451, index: index, footnoteShape: nil,
                sizeResolver: nil, placedLineCount: carried.placedLineCount,
                placedLength: carried.placedLength, sourceLayout: planted
            )
            expect(reused.attributed.string).to(contain("EEEE"))
            expect(reused.attributed.string).toNot(contain("다섯째"))
            // 폭이 다르면 문단을 다시 조판한다 — 심은 원본은 버려진다.
            let relaid = layout.measureNote(
                paragraph, number: 1, width: 200, index: index, footnoteShape: nil,
                sizeResolver: nil, placedLineCount: carried.placedLineCount,
                placedLength: carried.placedLength, sourceLayout: planted
            )
            expect(relaid.attributed.string).to(contain("다섯째"))
            expect(relaid.attributed.string).toNot(contain("EEEE"))
            expect(try XCTUnwrap(relaid.sourceLayout).width) == 200
        }

        /// 이어지는 조각의 측정은 조판 문자열을 **읽을 때** 잘라 낸다 — 높이만 쓰는 스택 계획은
        /// 원본에서 아무것도 자르지 않아야 한다. 잘라 내기가 지연인지는 원본을 나중에 바꿔도
        /// 결과가 그때의 원본을 따르는 것으로 확인할 수 없으므로 (불변 값), 높이가 원본 문자열
        /// 없이도 나오는지로 잠근다.
        func testContinuationHeightNeedsNoFragmentText() throws {
            let paragraph = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let lines = try XCTUnwrap(HwpFootnoteCacheLines.lines(of: paragraph))
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            // 원본 조판을 빈 값으로 심어도 높이는 캐시 누적표에서 나온다.
            let empty = HwpFootnoteLayout.SourceLayout(
                width: 451, attributed: NSAttributedString(string: ""), lines: [],
                cacheLines: lines
            )
            let measured = layout.measureNote(
                paragraph, number: 1, width: 451, index: index, footnoteShape: nil,
                sizeResolver: nil, placedLineCount: 3, placedLength: 0, sourceLayout: empty
            )
            expect(measured.textRectHeight).to(beCloseTo(
                HwpFootnoteCacheLines.height(of: lines, in: 3 ..< 5), within: 0.0001
            ))
            expect(measured.stackingHeight(isNoteEnd: true)).to(beCloseTo(
                HwpFootnoteCacheLines.height(of: lines, in: 3 ..< 5)
                    - HwpFootnoteCacheLines.trailingSpacing(of: lines, in: 3 ..< 5),
                within: 0.0001
            ))
            expect(measured.attributed.length) == 0
        }

        /// 페이지네이터의 대기 각주는 수집 시점에 각주 모양을 각인한다 (#165 리뷰) — 예약이 그
        /// 모양으로 재고 배치가 각인된 모양을 쓰므로, 배치가 쪽마다 대기 각주 전부에 각인할
        /// 일이 없다. 기본 모양(nil)도 확정 상태다.
        func testCollectedFootnotesCarryTheCollectionShape() throws {
            let note = try Support.note(lines: ["줄"], locations: [0])
            let host = try Support.host(at: 0, notes: [[note]])
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            let shape = Support.footnoteShape(head: "《", tail: "》")
            coordinator.collectFootnotes(
                from: host,
                environment: .init(contentWidth: 400, footnoteShape: shape),
                childParagraphs: { _ in [] }
            )
            let stamped = try XCTUnwrap(coordinator.pendingFootnotes.first?.measuredShape)
            expect(stamped.footnoteShape?.decorationHeadRawValue) == shape.decorationHeadRawValue

            var plain = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            plain.collectFootnotes(
                from: host,
                environment: .init(contentWidth: 400, footnoteShape: nil),
                childParagraphs: { _ in [] }
            )
            let confirmed = try XCTUnwrap(plain.pendingFootnotes.first?.measuredShape)
            expect(confirmed.footnoteShape).to(beNil())
        }

        /// 문단 N개짜리 각주가 문단마다 쪽을 넘길 때 스택 계획은 이 쪽에 실을 문단과 그 다음
        /// 문단만 잰다 (#165 리뷰) — 통째 판정을 위해 남은 문단을 전부 재면 쪽 수 × N의 CT
        /// 조판이고, 분할 지점 탐색은 줄 캐시·개체 판정만 필요해 측정을 거치지 않는다.
        func testStackPlanMeasuresOnlyTheParagraphsItPlaces() throws {
            // 문단 20개, 각 55줄(≈645pt) — 모두 위치 0에서 시작해 문단마다 쪽이 갈린다.
            let lines = 55
            var paragraphs = [try Support.note(
                lines: (1 ... lines).map { "문단 1 줄 \($0)" },
                locations: (0 ..< lines).map { Int32($0) * 1172 }
            )]
            for number in 2 ... 20 {
                paragraphs.append(try Support.notePlainParagraph(
                    (1 ... lines).map { "문단 \(number) 줄 \($0)" }.joined(separator: "\n"),
                    locations: (0 ..< lines).map { Int32($0) * 1172 }
                ))
            }
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let inputs = HwpFootnoteLayout.PendingNotes(paragraphs.map {
                HwpFootnoteLayout.Input(paragraph: $0, number: 1, sizeResolver: nil, numbering: nil, noteId: 1)
            }[...])
            var measuredOffsets: [Int] = []
            let notes = HwpFootnoteLayout.MeasuredNotes(inputs: inputs, footnoteShape: nil) { input, carries in
                measuredOffsets.append(input.paragraph.paraText?.charArray.count ?? -1)
                return layout.measureNote(
                    input.paragraph, number: input.number, width: 451, index: index,
                    footnoteShape: nil, sizeResolver: nil, noteCarriesObjects: carries
                )
            }
            let plan = HwpFootnoteLayout.stackPlan(
                notes: notes, available: 682, fullPage: 682, betweenNotes: 2.83, emptyPage: false
            )
            // 첫 문단만 실리고 (둘째 문단은 0에서 다시 시작) 나머지는 이월된다.
            expect(plan.entries.count) == 1
            expect(plan.overflow.count) == 19
            // 잰 문단은 통째 판정이 빈 쪽 자리를 넘긴 둘째 문단까지 — 20개가 아니다.
            expect(measuredOffsets.count) <= 2
        }

        /// 쪽 끝에서 나뉜 문단의 이월 입력은 남은 목록의 **첫 항목을 대신**하고 꼬리는 같은
        /// 저장소다 (#165 리뷰) — 뒤에 남은 각주를 쪽마다 복사하지 않는다.
        func testSplitOverflowReplacesTheHeadWithoutCopyingTheTail() throws {
            let splittable = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let others = try (2 ... 4).map { number in
                try Support.note(lines: ["각주 \(number)"], locations: [0])
            }
            let inputs = HwpFootnoteLayout.PendingNotes(([splittable] + others).enumerated().map {
                HwpFootnoteLayout.Input(paragraph: $1, number: $0 + 1)
            }[...])
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = Support.geometry(contentWidth: 451)
            let placement = layout.placePending(
                footnotes: inputs, onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 50
            )
            expect(placement.blocks.count) == 1
            expect(placement.overflow.count) == 4
            let head = try XCTUnwrap(placement.overflow.head)
            expect(head.placedLineCount) == 3
            expect(placement.overflow.first?.placedLineCount) == 3
            // 꼬리는 원래 저장소의 같은 자리다 — 새 배열이 아니다.
            expect(placement.overflow.storage.startIndex) == inputs.storage.startIndex
            expect(placement.overflow.storage.count) == 4
            expect(placement.overflow.map(\.number)) == [1, 2, 3, 4]
            // 다음 쪽에서 이어지는 조각이 첫 항목으로 실린다.
            let next = layout.placePending(
                footnotes: placement.overflow, onPage: geometry,
                index: HwpIndex(from: CoreHwp.HwpFile()), limitsAreaToHalfContent: false
            )
            expect(Support.text(try XCTUnwrap(next.blocks.first))).to(contain("넷째 줄"))
            expect(next.blocks.count) == 4
        }

        /// 공개 `place`로 쪽을 넘기는 호출자: 잰 뒤 **통째로** 넘어간 각주도 처음 잰 쪽의 모양을
        /// 나른다 (#165 리뷰) — 이월 목록이 처음 본 모양을 각인(`PendingNotes.stamp`)해 다음 쪽의
        /// 다른 모양을 새로 채택하지 않는다. 나뉜 조각(`appendHead`)만 각인하던 비대칭을 없앴다.
        func testWholeOverflowKeepsTheShapeItWasFirstMeasuredWith() throws {
            // 자동 번호 컨트롤에 장식이 없어야 구역 각주 모양의 장식이 라벨에 쓰인다.
            var note = HwpSynthetic.noteParagraph(
                " " + (1 ... 8).map { "줄 \($0)" }.joined(separator: "\n"),
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1)
            )
            note.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines((0 ..< 8).map { Int32($0) * 1172 }))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let geometry = Support.geometry(contentWidth: 451)
            let first = Support.footnoteShape(head: "《", tail: "》")
            let second = Support.footnoteShape(head: "[", tail: "]")
            // 첫 쪽: 5pt 자리 — 분할 지점이 없어 통째로 넘어간다 (잰 뒤에).
            let overflowed = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: note, number: 1)],
                onPage: geometry, index: index, footnoteShape: first,
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 5
            )
            expect(overflowed.blocks).to(beEmpty())
            expect(overflowed.overflow.first?.measuredShape?.footnoteShape?.decorationHeadRawValue)
                == first.decorationHeadRawValue
            // 둘째 쪽: 다른 모양을 주어도 라벨은 처음 잰 모양이다.
            let placed = layout.place(
                footnotes: overflowed.overflow, onPage: geometry, index: index, footnoteShape: second,
                limitsAreaToHalfContent: false
            )
            let text = Support.text(try XCTUnwrap(placed.blocks.first))
            expect(text).to(contain("《1》"))
            expect(text).toNot(contain("[1]"))
        }

        /// 수집 시점의 사실(`Input.noteFacts`)이 있으면 각주의 끝과 개체 유무를 훑지 않고 준다
        /// (#165 리뷰) — 없는 공개 API 입력은 식별자·술어를 훑어 같은 답을 낸다.
        func testNoteFactsAnswerGroupEndAndObjectsWithoutScanning() throws {
            let paragraphs = try (1 ... 4).map { number in
                try Support.notePlainParagraph("문단 \(number)", locations: [0])
            }
            var withObject = paragraphs[2]
            withObject.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 1000, height: 1000, textWrap: .inFrontOfText
            ))]
            let group = [paragraphs[0], paragraphs[1], withObject, paragraphs[3]]
            func notes(withFacts: Bool) -> HwpFootnoteLayout.MeasuredNotes {
                let inputs = group.enumerated().map { offset, paragraph in
                    HwpFootnoteLayout.Input(
                        paragraph: paragraph, number: 1, sizeResolver: nil, numbering: nil,
                        noteId: offset < 3 ? 7 : 8,
                        noteFacts: withFacts ? .init(
                            paragraphsAfter: offset < 3 ? 2 - offset : 0,
                            carriesObjects: offset < 3
                        ) : nil
                    )
                }
                return HwpFootnoteLayout.MeasuredNotes(
                    inputs: .init(inputs[...]), footnoteShape: nil
                ) { _, _ in fatalError("잰 적 없어야 한다") }
            }
            for withFacts in [true, false] {
                let measured = notes(withFacts: withFacts)
                expect(measured.groupEnd(from: 0)) == 3
                expect(measured.groupEnd(from: 1)) == 3
                expect(measured.groupEnd(from: 3)) == 4
                expect(measured.carriesObjects(at: 0)) == true
                expect(measured.carriesObjects(at: 1)) == true
                expect(measured.carriesObjects(at: 3)) == false
            }
        }

        /// CT 줄이 캐시 줄보다 적으면 짧은 쪽 몫의 양 끝이 같은 CT 줄로 환산돼 빈 조각이 된다
        /// (#165 리뷰) — 그런 경계는 줄 안 글자 위치로 보간해 쪽 몫마다 글이 있고, 전체 글은
        /// 쪽 몫 순서대로 한 번씩 나온다 (한글이 세 쪽에 이어 놓은 구조 그대로).
        func testHeadFragmentsNeverComeOutEmpty() throws {
            // 캐시 5줄(쪽 몫 [0,2)·[2,4)·[4,5))인데 글은 CT 한 줄이다.
            var note = HwpSynthetic.noteParagraph(
                " 짧은 글이 여기에 있다",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            note.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 0, 1172, 0]))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let geometry = Support.geometry(contentWidth: 451)
            // 두 줄 몫(20.72pt)은 들어가고 전체(55.88pt)는 안 들어가는 자리 — 첫 몫에서 나뉜다.
            var pending: [HwpFootnoteLayout.Input] = [.init(paragraph: note, number: 1)]
            var texts: [String] = []
            var pagesUsed = 0
            while !pending.isEmpty, pagesUsed < 6 {
                let placement = layout.place(
                    footnotes: pending, onPage: geometry, index: index,
                    limitsAreaToHalfContent: false,
                    bodyBottom: geometry.contentFrame.maxY - Support.overhead - 23
                )
                texts += placement.blocks.map(Support.text)
                pending = placement.overflow
                pagesUsed += 1
            }
            expect(pending).to(beEmpty())
            expect(texts.count) == 3
            expect(texts.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) == true
            expect(texts.joined()) == "1) 짧은 글이 여기에 있다"
        }

        /// 글을 다 그린 조각은 캐시 줄이 남았어도 이어짐 표식을 달지 않는다 (#165 리뷰).
        func testHeadThatConsumesAllTextIsNotMarkedContinued() {
            let attributed = NSAttributedString(string: "a")
            let line = HwpLineFrame(
                origin: .zero, width: 10, baseline: 8, attributedRange: NSRange(location: 0, length: 1),
                inlineAnchors: []
            )
            // 캐시 3줄(쪽 몫 [0,2)·[2,3))인데 글은 한 글자 — 앞 몫이 글을 다 가져간다.
            let head = HwpFootnoteLayout.fragment(
                of: attributed, lines: [line], cacheLineCount: 3, cacheRange: 0 ..< 2
            )
            expect(head.sourceRange) == NSRange(location: 0, length: 1)
            expect(head.attributed.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: 0, effectiveRange: nil
            )).to(beNil())
        }

        /// 보간한 경계는 대리 쌍·결합 문자열 가운데에 떨어지지 않는다 (#165 리뷰) — 이모지 넷을
        /// 캐시 3줄로 나눌 때 각 조각이 온전한 글자로만 이루어지고 이어 붙이면 원문이다.
        func testInterpolatedSplitsSnapToComposedCharacters() {
            let text = "😀😀😀😀"
            let attributed = NSAttributedString(string: text)
            let line = HwpLineFrame(
                origin: .zero, width: 40, baseline: 8,
                attributedRange: NSRange(location: 0, length: attributed.length), inlineAnchors: []
            )
            var placed = 0
            var pieces: [String] = []
            for range in [0 ..< 1, 1 ..< 2, 2 ..< 3] {
                let fragment = HwpFootnoteLayout.fragment(
                    of: attributed, lines: [line], cacheLineCount: 3, cacheRange: range,
                    startingAt: placed
                )
                pieces.append(fragment.attributed.string)
                placed = NSMaxRange(fragment.sourceRange)
            }
            expect(pieces.joined()) == text
            expect(pieces.allSatisfy { !$0.isEmpty && !$0.contains("\u{FFFD}") }) == true
            expect(pieces.map { $0.utf16.count % 2 }) == [0, 0, 0]
        }
    }
#endif
