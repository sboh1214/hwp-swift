import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 흐름 분할 조각의 각주 귀속·예약 (#207, `HwpFlowFragmentFootnotes`) — 절대 캐시 run의
    /// 조각별 귀속(#95, `HwpFootnoteFragmentAttributionTests`)의 흐름판.
    ///
    /// 한글 12.30 실측(2026-09-21, `probes/207` MA·MC·MD): 각주는 참조 줄의 쪽에 실리고, 줄을
    /// 남길지 판정할 때 그 줄의 각주 몫이 든다 — 각주 없이는 세 줄이 들어갈 자리에 첫 줄 + 각주만
    /// 남고, 각주가 마지막 줄 참조면 앞 줄들은 남고 각주는 참조 줄과 함께 다음 쪽이다.
    ///
    /// 기하: 여백 없는 쪽, 줄바꿈 문자로 줄 수를 고정한 세 줄 문단(줄 16pt). 구역 첫 문단(16pt)과
    /// 채움 문단(여덟 줄 128pt)이 첫 쪽 머리를 차지하고 본문 높이는 그 뒤 남은 자리 `remaining`으로
    /// 정한다 — 쪽이 충분히 커야 흐름 모드의 각주 영역 절반 상한이 각주를 자르지 않는다. 각주 영역
    /// 높이는 글꼴·구분선 여백의 함수라 상수로 박지 않고 남은 자리를 훑으며(sweep) 불변식으로
    /// 잠근다.
    final class HwpFlowFragmentFootnoteTests: XCTestCase {
        private static let linePitch: CGFloat = 16
        /// 구역 첫 문단 + 채움 여덟 줄.
        private static let usedBeforeHost: CGFloat = 16 + 128

        /// 줄 셋(줄바꿈 문자로 고정) 가운데 `markerLine`째 줄 끝에 각주 참조가 있는 문단.
        private static func host(markerLine: Int) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: (0 ..< 3).map { (characters: 5, marker: $0 == markerLine) },
                segments: []
            )
            host.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 각주 본문",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            return host
        }

        private struct Placement {
            let pages: [HwpPage]
            /// 쪽마다 본문 문단(서수 1)의 조각.
            let fragments: [AnyHwpBlock?]
            /// 쪽마다 각주 블록.
            let notes: [[AnyHwpBlock]]

            func lineCount(onPage page: Int) -> Int {
                guard let fragment = fragments[page] else { return 0 }
                return Int((fragment.frame.height / linePitch).rounded())
            }
        }

        /// 첫 쪽에 `remaining`pt를 남기는 본문 높이.
        private static func contentHeight(remaining: CGFloat) -> CGFloat {
            usedBeforeHost + remaining
        }

        private static func place(
            _ host: CoreHwp.HwpParagraph,
            remaining: CGFloat,
            footnoteNumberingMode: UInt32 = 0
        ) async throws -> Placement {
            var sectionDef = MeasuredLineFragmentSupport.sectionDef(
                columnWidth: 300, contentHeight: contentHeight(remaining: remaining)
            )
            sectionDef.footNoteShape.property = footnoteNumberingMode << 10
            let filler = try HwpSynthetic.textParagraph(
                (1 ... 8).map { "채움 \($0)" }.joined(separator: "\n")
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(sectionDef)],
                bodyParagraphs: [filler, host, try HwpSynthetic.textParagraph("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            return Placement(
                pages: pages,
                fragments: pages.map { page in
                    page.blocks.first {
                        $0.kind == .text && $0.source?.sectionIndex == 0
                            && $0.source?.paragraphIndex == 2
                    }
                },
                notes: pages.map { page in page.blocks.filter { $0.kind == .footnote } }
            )
        }

        /// 첫 줄 참조: 본문 높이를 훑으며 (a) 각주는 늘 첫 조각의 쪽에, (b) 조각과 각주가 겹치지
        /// 않고 각주가 쪽 안에, (c) 각주는 문서 전체에 하나(문단 단위 수집과 이중이 아님), (d) 첫
        /// 쪽 줄 수는 본문 높이에 단조. 각주 없이 세 줄이 들어갈 자리에서 각주 몫 때문에 줄이
        /// 줄어드는 높이가 반드시 있다 (한글 실측 MA).
        func testFootnoteReferencedOnTheFirstLineStaysWithItsLine() async throws {
            var previousLines = 0
            var sawPartialSplitWithNote = false
            for remaining in stride(from: 20, through: 120, by: 4) {
                let placement = try await Self.place(
                    Self.host(markerLine: 0), remaining: CGFloat(remaining)
                )
                let label = "남은 \(remaining)"
                let notes = placement.notes.flatMap { $0 }
                expect(notes.count).to(equal(1), description: "\(label): 각주 하나")
                let firstFragmentPage = try XCTUnwrap(placement.fragments.firstIndex { $0 != nil })
                let notePage = try XCTUnwrap(placement.notes.firstIndex { !$0.isEmpty })
                expect(notePage).to(equal(firstFragmentPage), description: "\(label): 각주는 첫 조각 쪽")
                let fragment = try XCTUnwrap(placement.fragments[firstFragmentPage])
                let note = try XCTUnwrap(placement.notes[notePage].first)
                expect(fragment.frame.maxY)
                    .to(beLessThanOrEqualTo(note.frame.minY + 0.01), description: label)
                expect(note.frame.maxY).to(
                    beLessThanOrEqualTo(Self.contentHeight(remaining: CGFloat(remaining)) + 0.01),
                    description: label
                )
                let lines = placement.lineCount(onPage: 0)
                expect(lines).to(beGreaterThanOrEqualTo(previousLines), description: "\(label): 단조")
                previousLines = lines
                // 각주 없이면 세 줄(48)이 들어가는 자리인데 첫 조각이 줄어들고 각주가 그 쪽에 있다.
                if remaining >= 48, lines > 0, lines < 3, notePage == 0 {
                    sawPartialSplitWithNote = true
                }
            }
            expect(sawPartialSplitWithNote).to(beTrue())
        }

        /// 마지막 줄 참조: 앞 줄들만 남는 높이에서 각주는 참조 줄과 함께 다음 쪽에 실리고, 첫 쪽은
        /// 각주 몫을 예약하지 않아 첫 줄 참조일 때보다 줄이 적지 않다 (한글 실측 MD).
        func testFootnoteReferencedOnTheLastLineMovesWithThatLine() async throws {
            for remaining in stride(from: 20, through: 120, by: 4) {
                let last = try await Self.place(Self.host(markerLine: 2), remaining: CGFloat(remaining))
                let first = try await Self.place(Self.host(markerLine: 0), remaining: CGFloat(remaining))
                let label = "남은 \(remaining)"
                expect(last.notes.flatMap { $0 }.count).to(equal(1), description: label)
                let lastLinePage = try XCTUnwrap(last.fragments.lastIndex { $0 != nil })
                let notePage = try XCTUnwrap(last.notes.firstIndex { !$0.isEmpty })
                expect(notePage).to(equal(lastLinePage), description: "\(label): 각주는 마지막 줄 쪽")
                expect(last.lineCount(onPage: 0))
                    .to(beGreaterThanOrEqualTo(first.lineCount(onPage: 0)), description: label)
            }
        }

        /// 첫 줄은 들어가지만 그 각주까지는 안 들어가면 문단을 통째로 다음 쪽으로 보낸다 (한글은
        /// 줄을 남기고 각주만 이월하지만 — 실측 MB — 그 규칙은 모델링하지 않았다). 각주는 문단과
        /// 같은 쪽이다.
        func testParagraphMovesWholeWhenTheFirstLineFitsButItsFootnoteDoesNot() async throws {
            // 남은 20pt: 첫 줄 16은 들어가지만 각주 영역(구분선 + 한 줄, 20pt 초과)까지는 아니다.
            let placement = try await Self.place(Self.host(markerLine: 0), remaining: 20)
            expect(placement.fragments[0]).to(beNil())
            expect(placement.notes[0]).to(beEmpty())
            let fragment = try XCTUnwrap(placement.fragments[1])
            expect(fragment.frame.minY).to(beCloseTo(0, within: 0.01))
            expect(placement.notes[1].count) == 1
        }

        /// 쪽마다 각주 번호를 새로 시작하는 구역(표 134 numberingMode 2)에서는 조각별 귀속을 못
        /// 하므로(뒤 조각 참조 번호를 못 고친다) 부분 적합 문단을 나누지 않고 통째로 옮긴다.
        func testPerPageNumberingKeepsTheWholeParagraphTogether() async throws {
            // 남은 60pt: 보통이면 두 줄 + 각주가 들어간다.
            let continuous = try await Self.place(Self.host(markerLine: 0), remaining: 60)
            expect(continuous.fragments[0]).toNot(beNil())
            let perPage = try await Self.place(
                Self.host(markerLine: 0), remaining: 60, footnoteNumberingMode: 2
            )
            expect(perPage.fragments[0]).to(beNil())
            expect(perPage.fragments[1]).toNot(beNil())
            expect(perPage.notes[1].count) == 1
        }

        /// 다단 밴드에서는 조각별 귀속을 쓰지 않는다 — 각주 영역이 쪽 폭 하단이라 뒤 단 조각이 걷은
        /// 각주가 이미 끝까지 찬 앞 단의 아랫줄을 덮는다 (PR 리뷰). 문단 전체 예약이 모든 단에
        /// 미리 빠져 앞 단 조각 아래에 각주 자리가 남는다.
        func testMultiColumnBandKeepsTheWholeParagraphReservation() async throws {
            // 참조가 셋째 줄(둘째 단 몫)에 있는 세 줄 문단, 2단 본문 48pt: 첫 단은 구역 첫 문단 뒤
            // 두 줄(16~48)로 가득 차고 셋째 줄은 둘째 단이다 — 조각별 예약이면 둘째 단에서 셋째 줄
            // + 각주(16 + 24)가 들어간다고 보고 각주를 쪽 하단(약 24~48)에 놓아 첫 단 둘째 줄을 덮는다.
            let host = try Self.host(markerLine: 2)
            var sectionDef = MeasuredLineFragmentSupport.sectionDef(
                columnWidth: 300 * 2 + 10, contentHeight: 48
            )
            sectionDef.footNoteShape.property = 0
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(sectionDef), .column(HwpSynthetic.column(count: 2, spacing: 1000)),
                ],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            let fragments = pages.flatMap { page in
                page.blocks.filter { $0.kind == .text && $0.source?.paragraphIndex == 1 }
            }
            let notes = pages.flatMap { page in page.blocks.filter { $0.kind == .footnote } }
            expect(notes.count) == 1
            guard let note = notes.first else { return }
            for fragment in fragments where fragment.frame.minX < note.frame.maxX
                && fragment.frame.maxX > note.frame.minX
            {
                expect(fragment.frame.maxY).to(beLessThanOrEqualTo(note.frame.minY + 0.01))
            }
        }

        // MARK: 귀속 문맥 단위

        /// 마커 속성 run이 있는 조판 문자열과 줄 프레임을 직접 지어 서수 범위 산식을 잠근다.
        private static func context(
            controlCount: Int,
            markers: [(ordinal: Int, location: Int, length: Int)],
            length: Int
        ) -> HwpFlowFragmentFootnotes? {
            let text = NSMutableAttributedString(string: String(repeating: "가", count: length))
            for marker in markers {
                text.addAttribute(
                    HwpAttributedStringKey.controlIndex, value: NSNumber(value: marker.ordinal),
                    range: NSRange(location: marker.location, length: marker.length)
                )
            }
            return HwpFlowFragmentFootnotes(
                paragraph: CoreHwp.HwpParagraph(), attributedString: text, controlCount: controlCount
            )
        }

        private static func remainder(lineRanges: [NSRange]) -> HwpFragmentRemainder {
            let lines = lineRanges.enumerated().map { index, range in
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: CGFloat(index) * 16), width: 100, baseline: 8.5,
                    attributedRange: range
                )
            }
            return HwpFragmentRemainder(
                lines: lines, textHeight: CGFloat(lineRanges.count) * 16,
                measuredWidth: 100, heightIsMeasured: true
            )
        }

        func testOrdinalsFollowTheDrawnMarkersAndTheCursor() throws {
            // 줄 0에 서수 0, 줄 1엔 없음, 줄 2에 서수 1·2 (컨트롤 넷 — 마지막 하나는 마커 없음).
            let context = try XCTUnwrap(Self.context(
                controlCount: 4,
                markers: [(0, 2, 1), (1, 21, 1), (2, 23, 1)],
                length: 30
            ))
            let remainder = Self.remainder(lineRanges: [
                NSRange(location: 0, length: 10), NSRange(location: 10, length: 10),
                NSRange(location: 20, length: 10),
            ])
            expect(context.ordinals(through: 0, of: remainder)) == 0 ..< 1
            expect(context.ordinals(through: 1, of: remainder)) == 0 ..< 1
            // 마지막 줄까지면 남은 서수 전부 (마커 없는 컨트롤 3 포함).
            expect(context.ordinals(through: 2, of: remainder)) == 0 ..< 4
            context.markCollected(0 ..< 1)
            expect(context.collectedEnd) == 1
            expect(context.ordinals(through: 1, of: remainder)) == 1 ..< 1
            expect(context.ordinals(through: 2, of: remainder)) == 1 ..< 4
            context.markCollected(1 ..< 4)
            expect(context.ordinals(through: 2, of: remainder)) == 4 ..< 4
        }

        /// 줄에 걸쳐 그려진 마커는 앞 줄에 귀속된다 (절대 경로의 "그려진 마지막 서수"와 같다).
        func testMarkerSpanningTwoLinesBelongsToTheEarlierLine() throws {
            let context = try XCTUnwrap(Self.context(
                controlCount: 1, markers: [(0, 8, 4)], length: 30
            ))
            let remainder = Self.remainder(lineRanges: [
                NSRange(location: 0, length: 10), NSRange(location: 10, length: 10),
                NSRange(location: 20, length: 10),
            ])
            expect(context.ordinals(through: 0, of: remainder)) == 0 ..< 1
        }

        /// 마커 서수가 컨트롤 수를 넘으면(파스 폴백 등 어긋난 문단) 문맥을 만들지 않는다.
        func testMismatchedMarkersProduceNoContext() {
            expect(Self.context(controlCount: 1, markers: [(1, 0, 1)], length: 5)).to(beNil())
            expect(Self.context(controlCount: 0, markers: [], length: 5)).toNot(beNil())
        }

        /// 예약 메모는 같은 범위·같은 커서에서만 재사용되고, 조각을 걷거나 쪽을 넘기면 비워진다.
        func testReservationMemoIsInvalidatedWhenTheCursorOrPageMoves() throws {
            let context = try XCTUnwrap(Self.context(
                controlCount: 2, markers: [(0, 1, 1), (1, 11, 1)], length: 20
            ))
            var computed = 0
            let compute: () -> CGFloat = {
                computed += 1
                return 7
            }
            expect(context.reservation(for: 0 ..< 1, isLast: false, compute: compute)) == 7
            expect(context.reservation(for: 0 ..< 1, isLast: false, compute: compute)) == 7
            expect(computed) == 1
            _ = context.reservation(for: 0 ..< 1, isLast: true, compute: compute)
            expect(computed) == 2
            context.invalidateReservations()
            _ = context.reservation(for: 0 ..< 1, isLast: false, compute: compute)
            expect(computed) == 3
            context.markCollected(0 ..< 1)
            _ = context.reservation(for: 1 ..< 2, isLast: true, compute: compute)
            expect(computed) == 4
        }
    }
#endif
