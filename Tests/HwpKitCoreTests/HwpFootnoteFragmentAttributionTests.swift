import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 페이지에 걸친 문단의 각주는 **참조가 그려진 조각의 페이지**에 실린다 (#95).
    ///
    /// 수집이 문단 단위였을 때는 마지막 조각을 커밋할 때 한 번 돌아 각주 전부가
    /// 그 페이지로 몰렸고, 앞 조각 페이지에는 각주 자리가 예약된 채 비어 있었다
    /// (헌법주석 실측: 1,231개 중 535개가 앞 조각 소속이었다).
    final class HwpFootnoteFragmentAttributionTests: XCTestCase {
        /// 세 줄이 두 페이지로 갈리고 조각마다 각주 참조가 하나씩 놓인 문단.
        /// 줄바꿈 문자로 CT 줄 수를 3으로 고정했고 세그먼트가 2/1이라 run 0이
        /// 줄 0–1을, run 1이 줄 2를 가져간다.
        ///
        /// `lastSegmentTextStart`는 **캐시가 주장하는** 절단 위치다 — 그리는 조각
        /// 경계와 어긋나게 두면 원본 WCHAR 위치로 나누던 옛 규약이 뒤 조각의
        /// 각주를 앞 페이지로 보낸다.
        private func splitHostParagraph(
            lastSegmentTextStart: UInt32 = 12
        ) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: [
                    (characters: 5, marker: true),
                    (characters: 5, marker: false),
                    (characters: 5, marker: true),
                ],
                segments: [
                    // run 0 — 이 페이지 두 줄
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 6),
                    // location이 줄어드는 지점이 한글의 페이지 절단점 (run 1)
                    (location: 2720, height: 1500, textStart: lastSegmentTextStart),
                ]
            )
            host.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 앞 조각 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 뒤 조각 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            return host
        }

        private func paginate(
            _ host: CoreHwp.HwpParagraph,
            footnoteNumberingMode: UInt32 = 0,
            footnoteStartingNumber: UInt16 = 0
        ) throws -> HwpPaginator {
            // 절대 캐시 모드 감지 (detectAbsoluteCacheMode): 첫 loc > 0인 캐시 문단이
            // **다수**여야 한다 — 빈 문서 템플릿의 첫 문단이 loc 0이라 host 하나로는
            // 과반이 되지 않는다.
            let tail = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "뒤 문단 \(index)",
                    segments: [(location: Int32(4820 + index * 2100), height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(
                    footnoteNumberingMode: footnoteNumberingMode,
                    footnoteStartingNumber: footnoteStartingNumber
                ))],
                bodyParagraphs: [host] + tail
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        private func noteTexts(on page: HwpPage?) -> [String] {
            (page?.blocks ?? [])
                .filter { $0.kind == .footnote }
                .compactMap { $0.attributedString?.string }
        }

        /// 그 페이지 본문에 **그려진** 텍스트 — 참조 마커가 어느 쪽에 보이는지 본다.
        private func bodyText(on page: HwpPage?) -> String {
            (page?.blocks ?? [])
                .filter { $0.kind != .footnote }
                .compactMap { $0.attributedString?.string }
                .joined()
        }

        func testEachFragmentCarriesItsOwnFootnotes() async throws {
            let paginator = try paginate(splitHostParagraph())

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)

            expect(self.noteTexts(on: first).count) == 1
            expect(self.noteTexts(on: first).first).to(contain("앞 조각"))
            expect(self.noteTexts(on: second).count) == 1
            expect(self.noteTexts(on: second).first).to(contain("뒤 조각"))
        }

        /// 조각을 나눠 수집해도 번호는 문서 순서 그대로다 — run을 순서대로 돌고
        /// run 안에서도 컨트롤 서수 순이라 카운터 증가 순서가 보존된다.
        func testFragmentSplitPreservesNoteNumbering() async throws {
            let paginator = try paginate(splitHostParagraph())
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)

            expect(self.noteTexts(on: first).first?.hasPrefix("1)")) == true
            expect(self.noteTexts(on: second).first?.hasPrefix("2)")) == true
        }

        /// 이중 수집 방지: 조각 단위로 담았으면 문단 단위 수집을 건너뛴다.
        /// (건너뛰지 않으면 각주가 두 번 세어져 번호와 개수가 어긋난다.)
        func testFootnotesAreNotCollectedTwice() async throws {
            let paginator = try paginate(splitHostParagraph())
            var total = 0
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                total += noteTexts(on: page).count
                pageIndex += 1
            }
            expect(total) == 2
        }

        /// **참조가 보이는 쪽에 그 각주가 있다** — 이 스위트가 지키는 성질.
        /// 번호는 본문 마커와 각주 머리 양쪽에 같은 문자열로 나타나므로 쪽마다
        /// 두 집합이 같아야 한다. 한쪽만 맞으면 참조 없는 각주 (또는 각주 없는
        /// 참조) 가 생긴다.
        func testReferenceAndItsNoteLandOnTheSamePage() async throws {
            let paginator = try paginate(splitHostParagraph())
            for pageIndex in 0 ..< 2 {
                let page = try await paginator.page(at: pageIndex)
                let body = bodyText(on: page)
                let notes = noteTexts(on: page)
                for number in ["1)", "2)"] {
                    expect(body.contains(number)) == notes.contains { $0.hasPrefix(number) }
                }
            }
        }

        /// 캐시가 주장하는 절단 위치 (textStartingIndex) 가 그려진 조각과 어긋나도
        /// 각주는 참조가 **그려진** 페이지를 따른다 — 폰트 대체·stale 캐시로 CT 줄
        /// 배분이 캐시와 갈리는 문단이 그렇다. 원본 WCHAR 위치로 나누면 뒤 조각의
        /// 각주가 앞 페이지로 가, 그 쪽에 참조 없는 각주가 뜬다.
        func testAttributionFollowsDrawnSliceNotCacheTextIndex() async throws {
            // 마지막 세그먼트가 두 마커보다 뒤라고 주장한다 (그리기는 그대로 2:1 분할)
            let paginator = try paginate(splitHostParagraph(lastSegmentTextStart: 30))
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)

            expect(self.noteTexts(on: first).count) == 1
            expect(self.noteTexts(on: first).first).to(contain("앞 조각"))
            expect(self.noteTexts(on: second).count) == 1
            expect(self.noteTexts(on: second).first).to(contain("뒤 조각"))
        }

        /// "쪽마다 새로 시작" (표 134 numberingMode 2): run 사이 cacheCurrentPage가
        /// 카운터를 리셋하는데 마커 번호는 조판 전에 문단 단위로 한 번 구워진다 —
        /// 배치 직전 다시 계산하지 않으면 뒤 조각 참조가 2), 각주는 1)이 된다.
        func testMarkerMatchesCollectedNumberWhenNumberingRestartsPerPage() async throws {
            let paginator = try paginate(splitHostParagraph(), footnoteNumberingMode: 2)
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)

            expect(self.noteTexts(on: first).first?.hasPrefix("1)")) == true
            expect(self.bodyText(on: first)).to(contain("1)"))
            // 쪽이 바뀌며 번호가 1)로 돌아왔으니 참조도 1)이어야 한다
            expect(self.noteTexts(on: second).first?.hasPrefix("1)")) == true
            expect(self.bodyText(on: second)).to(contain("1)"))
            expect(self.bodyText(on: second)).toNot(contain("2)"))
        }

        /// 번호 **폭이 바뀌는** 재기록 — 시작 번호 9면 뒤 조각 마커가 "10)"으로
        /// 구워졌다가 리셋 뒤 "9)"가 된다. 조판·슬라이스는 옛 번호로 이미 끝난
        /// 뒤라 조각 **안**의 줄바꿈이 달라질 수 있지만 (문서화된 근사 — 번호는
        /// 실릴 쪽이 정해져야 알 수 있고 그 쪽은 배치가 끝나야 안다), 참조와
        /// 각주 번호가 어긋나서는 안 된다.
        func testRenumberingKeepsMarkerAndNoteInSyncWhenWidthChanges() async throws {
            let paginator = try paginate(
                splitHostParagraph(),
                footnoteNumberingMode: 2,
                footnoteStartingNumber: 9
            )
            let first = try await paginator.page(at: 0)
            let second = try await paginator.page(at: 1)

            expect(self.noteTexts(on: first).first?.hasPrefix("9)")) == true
            expect(self.bodyText(on: first)).to(contain("9)"))
            expect(self.noteTexts(on: second).first?.hasPrefix("9)")) == true
            expect(self.bodyText(on: second)).to(contain("9)"))
            expect(self.bodyText(on: second)).toNot(contain("10)"))
        }

        // MARK: - 조각별 컨트롤 서수 분할

        /// 그 조각에 그려진 마커만 담은 텍스트 — 배치가 낸 슬라이스의 최소 형상.
        private func slice(drawing ordinals: [Int]) -> NSAttributedString {
            let output = NSMutableAttributedString(string: "본문")
            for ordinal in ordinals {
                output.append(NSAttributedString(
                    string: "\u{FFFC}",
                    attributes: [HwpAttributedStringKey.controlIndex: NSNumber(value: ordinal)]
                ))
            }
            return output
        }

        func testRangesFollowTheOrdinalsDrawnInEachSlice() throws {
            let ranges = try XCTUnwrap(HwpAbsoluteCachePlacer.controlOrdinalRanges(
                slices: [slice(drawing: [0]), slice(drawing: [1])], controlCount: 2
            ))
            expect(ranges) == [0 ..< 1, 1 ..< 2]
            // 빈틈 없는 분할 — 어떤 컨트롤도 누락되지 않는다
            expect(ranges.map(\.count).reduce(0, +)) == 2
        }

        /// 마지막 조각이 나머지를 전부 가져간다 — 어디에도 안 그려진 컨트롤
        /// (마커 없는 컨트롤·CT가 잘라낸 라인) 도 유실되지 않는다.
        func testLastSliceTakesControlsThatWereNeverDrawn() throws {
            let ranges = try XCTUnwrap(HwpAbsoluteCachePlacer.controlOrdinalRanges(
                slices: [slice(drawing: [0, 1]), slice(drawing: [])], controlCount: 3
            ))
            expect(ranges) == [0 ..< 2, 2 ..< 3]
        }

        /// 서수가 컨트롤 배열 밖이면 (파스 폴백 등 서수 ↔ 컨트롤 불일치) 나누지
        /// 않는다 — 유실하느니 마지막 조각에 몰아 두는 쪽이 낫다.
        func testOrdinalBeyondControlCountFallsBackToWholeParagraph() {
            expect(HwpAbsoluteCachePlacer.controlOrdinalRanges(
                slices: [self.slice(drawing: [0]), self.slice(drawing: [5])], controlCount: 2
            )).to(beNil())
        }

        /// 번호 문자열 중간에서 줄이 갈리면 두 조각이 마커의 일부씩 갖는다 —
        /// 그 서수를 재기록에서 빼지 않으면 부분이 완전한 번호로 바뀌어 다음 쪽에
        /// 남은 나머지와 합쳐 깨진다 (번호가 그대로여도, #95 리뷰).
        func testOrdinalsDrawnInTwoSlicesAreReportedAsSplit() {
            expect(HwpAbsoluteCachePlacer.ordinalsSpanningSlices([
                self.slice(drawing: [0, 1]), self.slice(drawing: [1, 2]),
            ])) == [1]
            expect(HwpAbsoluteCachePlacer.ordinalsSpanningSlices([
                self.slice(drawing: [0]), self.slice(drawing: [1]),
            ])).to(beEmpty())
        }

        /// 단일 조각 (페이지에 안 걸친 문단) 은 나눌 것이 없다.
        func testSingleSliceHasNoOrdinalRanges() {
            expect(HwpAbsoluteCachePlacer.controlOrdinalRanges(
                slices: [self.slice(drawing: [0])], controlCount: 1
            )).to(beNil())
        }
    }
#endif
