import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 측정 줄 조각 표식의 **높이 출처 게이트** (#166 리뷰): 세 분할 경로도 저장본 줄 캐시가
    /// 유효하면 문단 높이가 캐시 값이라, 잔여를 흡수하는 마지막 줄을 담은 조각의 높이는 측정
    /// 줄 전진량이 아니다 — 그 조각은 표식 없이 종전 접힘을 유지한다(캐시 줄 수가 오라클이라
    /// 대체 폰트로 CT 줄이 하나 많을 때 접힘이 캐시 상자에 맞는 쪽이다). 앞 조각은 측정
    /// 전진량이라 표식을 단다. 입력은 한글 캐시 세 줄(48pt)·CT 네 줄(30자·30자·30자·1자)이다.
    ///
    /// 뒤쪽은 비등폭 단 판정(PR 리뷰): 좁은 단으로 옮겨진 조각은 폭 허용 오차 없이 실제 줄바꿈으로
    /// 판정하므로 0.4pt만 좁은 단(HWPUNIT 단위 저작에서 가능)에서도 잰 폭에 꼭 맞던 한 줄
    /// 조각은 접힘을 유지하고, 두 줄 조각은 그려지는 줄이 측정 줄 수를 넘지 않으면 표식을 단다.
    final class HwpMeasuredLineFragmentCacheTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport

        /// 캐시 줄 셋(줄 상자 1000 + 간격 600 = 16pt 피치, 48pt)에 CT가 네 줄을 내는 문단 —
        /// 마지막 글자는 `끝`이라 마지막 줄을 담은 조각을 글자로 가려낼 수 있다.
        private static func cachedParagraph() throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph(
                String(repeating: "가", count: 90) + "끝",
                segments: [
                    (location: 0, height: 1000), (location: 1600, height: 1000),
                    (location: 3200, height: 1000),
                ]
            )
        }

        private static func built(_ paragraph: CoreHwp.HwpParagraph) -> NSAttributedString {
            HwpTextRunBuilder(index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
        }

        /// 마지막 줄(`끝`)을 담은 조각은 캐시 잔여 높이(16 + 1pt)라 표식이 없고 종전대로 한 줄로
        /// 접혀 상자에 들어간다; 앞 조각(두 줄)은 측정 전진량이라 표식이 있다.
        private static func expectCacheGate(
            fragments: [(text: NSAttributedString, rect: CGRect)],
            file: FileString = #filePath, line: UInt = #line
        ) {
            expect(file: file, line: line, fragments.count).to(beGreaterThanOrEqualTo(2))
            for fragment in fragments {
                let holdsLastLine = fragment.text.string.contains("끝")
                expect(file: file, line: line, Support.isMarked(fragment.text))
                    .to(equal(!holdsLastLine), description: "표식 = 마지막 줄 미포함")
                guard holdsLastLine else { continue }
                // 상자는 줄 하나 + 캐시 잔여(흐름·균형 1pt, 표 0pt)라 두 줄을 그리면 넘친다.
                expect(file: file, line: line, fragment.rect.height).to(beGreaterThanOrEqualTo(15.5))
                expect(file: file, line: line, fragment.rect.height).to(beLessThan(31.5))
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: fragment.text, origin: fragment.rect.origin,
                    lineWidth: fragment.rect.width
                )
                expect(file: file, line: line, drawn.count).to(equal(1), description: "종전 접힘 유지")
            }
        }

        /// 쪽 경계 흐름 분할: 본문 40pt라 캐시 높이 48pt 문단이 쪽보다 커 줄 단위로 나뉜다 —
        /// 앞 조각 60자 두 줄(표식), 뒤 조각 30자 + `끝`(무표식·17pt·한 줄).
        func testFlowSplitKeepsTheCachedRemainderFragmentUnmarked() async throws {
            let paragraph = try Self.cachedParagraph()
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: Self.built(paragraph)),
                    contentHeight: 40
                ))],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            let fragments = pages.compactMap { page -> (text: NSAttributedString, rect: CGRect)? in
                guard let block = InlineControlFragmentSupport.hostFragment(on: page),
                      let text = block.attributedString else { return nil }
                return (text, block.frame)
            }
            expect(fragments.map(\.text.length)) == [60, 31]
            Self.expectCacheGate(fragments: fragments)
        }

        /// 표 행 분할: 셀 문단은 캐시 높이(`preferCachedHeight`)로 재어 rect 높이가 48pt이고
        /// 행은 마지막 줄 간격을 뺀 42pt(#160)다 — 본문 40pt라 빈 쪽에도 안 들어가 줄 둘
        /// (표식)과 나머지 둘(무표식)로 나뉜다.
        func testTableRowSplitKeepsTheCachedRemainderFragmentUnmarked() async throws {
            let cell = try Self.cachedParagraph()
            var host = try HwpSynthetic.textParagraph("")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [1000], cellParagraphs: [[[cell]]]
            ))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: Self.built(cell)),
                    contentHeight: 40
                ))],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            let fragments = pages.flatMap { Support.cellFragments(on: $0) }
            expect(fragments.map(\.text.length)) == [60, 31]
            Self.expectCacheGate(fragments: fragments)
        }

        /// 다단 균형 재배치: 첫 단에 다 들어간 캐시 높이 블록을 줄 단위로 나눌 때 마지막 줄
        /// 단위는 잔여(1pt)라 그 줄을 담은 뒤 단 조각은 무표식이고, 앞 단 조각은 표식이다.
        func testColumnBalanceKeepsTheCachedRemainderFragmentUnmarked() async throws {
            let paragraph = try Self.cachedParagraph()
            let columnWidth = Support.columnWidth(charactersPerLine: 30, in: Self.built(paragraph))
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(Support.sectionDef(columnWidth: columnWidth * 2 + 10, contentHeight: 80)),
                    .column(HwpSynthetic.column(count: 2, spacing: 1000)),
                ],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
                .compactMap { block -> (text: NSAttributedString, rect: CGRect)? in
                    block.attributedString.map { ($0, block.frame) }
                }
            // 뒤 단 조각이 두 줄(30자 + `끝`)이어야 접힘 축이 실제로 걸린다.
            expect(fragments.last?.text.length) == 31
            Self.expectCacheGate(fragments: fragments)
        }

        /// 비등폭 2단 구역(간격 10pt) — 넓은 단은 31자 폭에 0.2pt 여유, 좁은 단은 31자 폭에서
        /// 0.2pt 부족이라 두 단의 폭 차는 0.4pt다(PR 리뷰의 268.355 / 267.955pt 재현). 62자 문단은
        /// 넓은 단 폭으로 31자 + 31자 두 줄로 재어지고, 그 31자 줄은 좁은 단에는 들어가지 않는다.
        private static func unevenColumnPaginator(
            paragraph: CoreHwp.HwpParagraph, contentHeight: CGFloat
        ) -> (paginator: HwpPaginator, narrow: CGFloat) {
            let glyph = Support.characterAdvance(in: Self.built(paragraph))
            let wide = 31 * glyph + 0.2
            let narrow = 31 * glyph - 0.2
            // 단 폭·간격은 HWPUNIT(pt × 100)으로 적어 본문 폭에 1:1로 배분되게 한다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(Support.sectionDef(
                        columnWidth: wide + narrow + 10, contentHeight: contentHeight
                    )),
                    .column(HwpSynthetic.column(
                        count: 2,
                        widths: [UInt16((wide * 100).rounded()), UInt16((narrow * 100).rounded())],
                        gaps: [1000, 0]
                    )),
                ],
                bodyParagraphs: [paragraph]
            )
            return (HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            ), narrow)
        }

        private static func fragments(on page: HwpPage) -> [AnyHwpBlock] {
            page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
        }

        /// 좁은 뒤 단에 놓인 한 줄 조각(31자)의 계약: 표식이 없고 렌더러는 종전대로 한 줄로
        /// 접는다 — 같은 조각에 표식을 달면 두 줄이 되어 한 줄 상자를 넘친다.
        private static func expectNarrowSingleLineFold(
            on page: HwpPage, narrow: CGFloat, file: FileString = #filePath, line: UInt = #line
        ) {
            let fragments = Self.fragments(on: page)
            expect(file: file, line: line, fragments.map { $0.attributedString?.length }) == [31, 31]
            guard fragments.count == 2, let tail = fragments[1].attributedString else { return }
            expect(file: file, line: line, fragments[1].frame.width).to(beCloseTo(narrow, within: 0.01))
            // 상자는 줄 하나(+ 마지막 줄 ascent 초과분 2pt, #164)라 두 줄을 그리면 넘친다.
            expect(file: file, line: line, fragments[1].frame.height).to(beGreaterThanOrEqualTo(15.5))
            expect(file: file, line: line, fragments[1].frame.height).to(beLessThan(31.5))
            expect(file: file, line: line, Support.isMarked(tail)).to(beFalse())
            expect(file: file, line: line, HwpDrawnTextLayout.lines(
                attributedString: tail, origin: .zero, lineWidth: fragments[1].frame.width
            ).count) == 1
            let marked = NSMutableAttributedString(attributedString: tail)
            marked.addAttribute(
                HwpAttributedStringKey.measuredLineFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: marked.length)
            )
            expect(file: file, line: line, HwpDrawnTextLayout.lines(
                attributedString: marked, origin: .zero, lineWidth: fragments[1].frame.width
            ).count) == 2
        }

        /// 흐름 분할(`appendLineSliceBlock`)로 0.4pt 좁은 단에 이월된 **한 줄** 조각(캐시 없음): 본문
        /// 40pt라 넓은 단에 구역 첫 문단과 첫 줄이 들어가고 둘째 줄이 좁은 단으로 간다 — 잰 폭에
        /// 꼭 맞던 31자는 그 단에서 다시 나뉘므로 표식 없이 종전 접힘을 둔다 (PR 리뷰).
        func testSingleLineFragmentCarriedToASlightlyNarrowerColumnKeepsTheFold() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 62))
            let (paginator, narrow) = Self.unevenColumnPaginator(paragraph: paragraph, contentHeight: 40)
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            Self.expectNarrowSingleLineFold(on: page, narrow: narrow)
        }

        /// 다단 균형 재배치(`balancedBlocks`)로 0.4pt 좁은 단에 옮겨진 **한 줄** 조각도 같다: 본문
        /// 60pt라 문단이 넓은 단에 다 들어간 뒤 밴드를 닫으며 둘째 줄이 좁은 단으로 옮겨진다.
        func testSingleLineUnitRebalancedIntoASlightlyNarrowerColumnKeepsTheFold() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 62))
            let (paginator, narrow) = Self.unevenColumnPaginator(paragraph: paragraph, contentHeight: 60)
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            Self.expectNarrowSingleLineFold(on: page, narrow: narrow)
        }

        /// 0.4pt 좁은 단에 이월된 **두 줄** 조각(31자 + 1자)은 그 단에서 접지 않고 그려도 30자 + 2자
        /// 두 줄이라 표식을 단다 — 접히면 두 줄 상자에 한 줄만 그려져 아래가 빈다(#166의 증상).
        /// 판정은 폭 비교가 아니라 실제 줄바꿈이다.
        func testTwoLineFragmentCarriedToASlightlyNarrowerColumnStaysMarked() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 63))
            let (paginator, narrow) = Self.unevenColumnPaginator(paragraph: paragraph, contentHeight: 40)
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Self.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [31, 32]
            guard fragments.count == 2, let tail = fragments[1].attributedString else { return }
            expect(fragments[1].frame.width).to(beCloseTo(narrow, within: 0.01))
            expect(fragments[1].frame.height).to(beCloseTo(32, within: 0.5))
            expect(Support.isMarked(tail)).to(beTrue())
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: tail, origin: fragments[1].frame.origin,
                lineWidth: fragments[1].frame.width
            )
            expect(drawn.map(\.stringRange.length)) == [30, 2]
            expect((drawn.last?.baselineOrigin.y ?? 0) + (drawn.last?.descent ?? 0))
                .to(beLessThanOrEqualTo(fragments[1].frame.maxY + 0.5))
            // 표식이 없었다면 접혀 한 줄이 되고 상자 아래 한 줄이 빈다.
            expect(HwpDrawnTextLayout.lines(
                attributedString: HwpParagraphLayout.strippingMeasuredLineMarker(tail),
                origin: .zero, lineWidth: fragments[1].frame.width
            ).count) == 1
        }
    }
#endif
