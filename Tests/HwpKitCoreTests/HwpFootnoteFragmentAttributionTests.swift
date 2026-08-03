import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 페이지에 걸친 문단의 각주는 **참조가 놓인 조각의 페이지**에 실린다 (#95).
    ///
    /// 수집이 문단 단위였을 때는 마지막 조각을 커밋할 때 한 번 돌아 각주 전부가
    /// 그 페이지로 몰렸고, 앞 조각 페이지에는 각주 자리가 예약된 채 비어 있었다
    /// (헌법주석 실측: 1,231개 중 535개가 앞 조각 소속이었다).
    final class HwpFootnoteFragmentAttributionTests: XCTestCase {
        /// 각주 참조 마커 두 개가 run 경계 양쪽에 놓인 문단.
        /// 마커 서수 0의 WCHAR 위치 = 10, 서수 1 = 10 + 8 + 20 = 38.
        /// run 경계 (`textStart`)를 20에 두면 0 → 앞 페이지, 1 → 뒤 페이지다.
        private func splitHostParagraph() throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                markerAfter: [10, 20],
                trailingCharacters: 10,
                segments: [
                    // run 0 — 이 페이지 두 줄
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 10),
                    // location이 줄어드는 지점이 한글의 페이지 절단점 (run 1)
                    (location: 2720, height: 1500, textStart: 20),
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

        private func paginate(_ host: CoreHwp.HwpParagraph) throws -> HwpPaginator {
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
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
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

        // MARK: - 서수 → WCHAR 위치 · run 분할

        func testExtendedControlPositionsMatchRunBuilderStride() throws {
            // 평문 1 / inline·extended 8 — HwpTextRunBuilder.wcharLength와 같은 산식
            let host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                markerAfter: [10, 20],
                trailingCharacters: 10,
                segments: [(location: 2720, height: 1500, textStart: 0)]
            )
            expect(HwpAbsoluteCachePlacer.extendedControlPositions(in: host)) == [10, 38]
        }

        func testControlOrdinalRangesPartitionEveryControl() throws {
            let host = try splitHostParagraph()
            let runs = try XCTUnwrap(HwpAbsoluteCachePlacer.cacheRuns(for: host))
            expect(runs.count) == 2
            let ranges = try XCTUnwrap(
                HwpAbsoluteCachePlacer.controlOrdinalRanges(runs: runs, paragraph: host)
            )
            expect(ranges) == [0 ..< 1, 1 ..< 2]
            // 빈틈 없는 분할 — 어떤 컨트롤도 누락되지 않는다
            expect(ranges.map(\.count).reduce(0, +)) == host.ctrlHeaderArray?.count
        }

        /// 마지막 run이 경계 뒤의 나머지를 전부 가져간다 — 경계보다 뒤에 있는
        /// 컨트롤이 하나도 없어도 범위가 비지 결코 유실되지 않는다.
        func testLastRunTakesTrailingControls() throws {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                markerAfter: [10, 20],
                trailingCharacters: 10,
                segments: [
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 10),
                    // location 리셋 = 페이지 절단점. 경계가 두 마커보다 뒤라
                    // 둘 다 첫 조각 소속이다.
                    (location: 2720, height: 1500, textStart: 60),
                ]
            )
            host.ctrlHeaderArray = try splitHostParagraph().ctrlHeaderArray
            let runs = try XCTUnwrap(HwpAbsoluteCachePlacer.cacheRuns(for: host))
            let ranges = try XCTUnwrap(
                HwpAbsoluteCachePlacer.controlOrdinalRanges(runs: runs, paragraph: host)
            )
            expect(ranges) == [0 ..< 2, 2 ..< 2]
        }

        /// 서수와 컨트롤 배열이 어긋난 문단은 나누지 않는다 (nil → 기존 동작 폴백).
        /// 조각 경계를 못 믿을 때 각주를 유실하느니 마지막 조각에 몰아 두는 쪽이 낫다.
        func testMismatchedControlCountFallsBackToWholeParagraph() throws {
            var host = try splitHostParagraph()
            // 마커는 2개인데 컨트롤은 3개 — 서수 ↔ 위치 대응이 깨진다
            host.ctrlHeaderArray = (host.ctrlHeaderArray ?? []) + [
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [])),
            ]
            let runs = try XCTUnwrap(HwpAbsoluteCachePlacer.cacheRuns(for: host))
            expect(
                HwpAbsoluteCachePlacer.controlOrdinalRanges(runs: runs, paragraph: host)
            ).to(beNil())
        }

        /// 단일 run (페이지에 안 걸친 문단)은 나눌 것이 없다.
        func testSingleRunHasNoOrdinalRanges() throws {
            let host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                markerAfter: [10],
                trailingCharacters: 5,
                segments: [(location: 2720, height: 1500, textStart: 0)]
            )
            let runs = try XCTUnwrap(HwpAbsoluteCachePlacer.cacheRuns(for: host))
            expect(
                HwpAbsoluteCachePlacer.controlOrdinalRanges(runs: runs, paragraph: host)
            ).to(beNil())
        }
    }
#endif
