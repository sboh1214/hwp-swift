import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽·단 분할 조각의 이어짐 표식(`continuedParagraphFragment`) — 표 행 분할·각주 이어짐만
    /// 달던 표식을 쪽 흐름 분할(`HwpPaginator.appendLineSliceBlock`)·다단 균형 재배치
    /// (`HwpColumnBandController.rebalancedFragment`)·절대 캐시 run 분할
    /// (`HwpAbsoluteCachePlacer.runAttributedSlice`)도 단다 (PR 리뷰: 없으면 앞 조각 끝 줄이
    /// 문단 마지막 줄로 오인돼 MS 워드 호환 문단 끝 상자가 앞 조각에 들고 양쪽 정렬이 풀린다).
    /// 문서는 `HwpMeasuredLineFragmentTests`의 분할 재현 문서다.
    final class HwpContinuedFragmentMarkerTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport

        private static func isContinued(_ block: AnyHwpBlock?) -> Bool? {
            guard let text = block?.attributedString, text.length > 0 else { return nil }
            return text.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: text.length - 1,
                effectiveRange: nil
            ) != nil
        }

        /// 쪽에 걸쳐 나뉜 문단: 앞 조각(줄 셋)은 표식이 있고 뒤 조각(줄 둘)은 없다 — 표식은
        /// 조각 전체에 붙어 첫 글자에도 있다.
        func testFlowPageSplitMarksOnlyTheLeadingFragment() async throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let host = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: host)
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: built),
                    contentHeight: 56
                ))],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 3
            guard pages.count == 3 else { return }
            let head = try XCTUnwrap(InlineControlFragmentSupport.hostFragment(on: pages[1]))
            let tail = try XCTUnwrap(InlineControlFragmentSupport.hostFragment(on: pages[2]))
            expect(head.attributedString?.length) == 90
            expect(Self.isContinued(head)) == true
            expect(head.attributedString?.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: 0, effectiveRange: nil
            )).toNot(beNil())
            expect(Self.isContinued(tail)) == false
            // 뒤 문단은 표식이 없다.
            let followerBlock = try XCTUnwrap(pages[2].blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(Self.isContinued(followerBlock)) == false
        }

        /// 다단 균형 재배치로 두 단에 나뉜 문단: 첫 단 조각은 표식이 있고 뒤 단 조각은 없다.
        func testColumnBalanceMarksOnlyTheLeadingFragment() async throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let host = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: host)
            let columnWidth = Support.columnWidth(charactersPerLine: 30, in: built)
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(Support.sectionDef(
                        columnWidth: columnWidth * 2 + 10, contentHeight: 120
                    )),
                    .column(HwpSynthetic.column(count: 2, spacing: 1000)),
                ],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(fragments.map { $0.attributedString?.length }) == [90, 31]
            guard fragments.count == 2 else { return }
            expect(Self.isContinued(fragments[0])) == true
            expect(Self.isContinued(fragments[1])) == false
        }

        /// 절대 캐시 run 분할: 마지막 run 앞의 조각은 표식이 있고 마지막 run 조각은 없다.
        func testAbsoluteCacheRunSlicesMarkAllButTheLastRun() {
            let text = NSAttributedString(string: "AAAA BBBB CCCC")
            let lines = [0, 5, 10].map { start in
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: CGFloat(start)), width: 100, baseline: 10,
                    attributedRange: NSRange(location: start, length: start == 10 ? 4 : 5)
                )
            }
            var cursor = 0
            var marks: [Bool?] = []
            var texts: [String] = []
            for runIndex in 0 ..< 3 {
                let slice = HwpAbsoluteCachePlacer.runAttributedSlice(
                    runIndex: runIndex,
                    runShare: HwpAbsoluteCachePlacer.RunShare(segments: 1, total: 3, runCount: 3),
                    attributedString: text, lines: lines, lineCursor: &cursor
                )
                texts.append(slice.text.string)
                marks.append(slice.text.length > 0
                    ? slice.text.attribute(
                        HwpAttributedStringKey.continuedParagraphFragment,
                        at: slice.text.length - 1, effectiveRange: nil
                    ) != nil
                    : nil)
            }
            expect(texts) == ["AAAA ", "BBBB ", "CCCC"]
            expect(marks) == [true, true, false]
            // 단일 run은 자르지도 표식을 달지도 않는다.
            var single = 0
            let whole = HwpAbsoluteCachePlacer.runAttributedSlice(
                runIndex: 0,
                runShare: HwpAbsoluteCachePlacer.RunShare(segments: 3, total: 3, runCount: 1),
                attributedString: text, lines: lines, lineCursor: &single
            )
            expect(whole.text.string) == text.string
            expect(whole.text.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: whole.text.length - 1,
                effectiveRange: nil
            )).to(beNil())
        }
    }
#endif
