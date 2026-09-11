import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 폭이 다른 단으로 옮겨진 조각의 **높이·줄 수 재측정** (#166 PR 리뷰): 측정 줄 조각 표식은
    /// 접힘만 막아, 좁은 단에서 잰 두 줄 조각을 넓은 단에 놓으면 CT가 한 줄로 합쳐 두 줄 상자
    /// 아래가 비었다. 측정 높이 문단의 나머지는 흐름 분할(`HwpFragmentRemainder`)·균형 재배치
    /// (`rebalancedFragment`)가 목적 단 폭으로 다시 재어 상자 높이가 그려지는 줄과 같다.
    /// 저장본 줄 캐시 높이를 따르는 문단은 다시 재지 않는다.
    final class HwpMeasuredLineFragmentRemeasureTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport

        private typealias Columns = MeasuredLineRemeasureSupport

        /// 흐름 분할, 좁은 단(30자) → 넓은 단(61자): 121자 문단은 좁은 단에서 다섯 줄로 재어지고
        /// 본문 56pt라 두 줄이 들어간다. 나머지 61자(좁은 단의 줄 셋 30·30·1자)는 넓은 단 폭으로
        /// 다시 재어 한 줄이 되고(상자 16pt + 문단 마지막 줄의 ascent 초과분 2pt = 18pt) 뒤 문단이
        /// 바로 아래 온다 — 종전에는 잰 줄 셋을 48pt 상자에 놓고 넓은 단에서 한 줄로 합쳐져
        /// (표식은 접힘만 막는다) 아래 32pt가 비었다.
        func testFlowSplitRemeasuresTheRemainderInAWiderColumn() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [30, 61], contentHeight: 56, bodyParagraphs: [paragraph, follower]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [60, 61]
            guard fragments.count == 2, let tail = fragments[1].attributedString else { return }
            expect(fragments[1].frame.width).to(beCloseTo(widths[1], within: 0.01))
            // 한 줄 16pt + 문단 마지막 줄의 ascent 초과분 2pt(#164 — CT가 프레임 마지막 줄의
            // ascent를 키우고, 다시 잰 첫 줄의 초과분은 앞 조각·나머지의 마지막 줄 가운데 작은
            // ascent 기준이라 여기 실린다)다.
            expect(fragments[1].frame.height).to(beCloseTo(18, within: 0.5))
            expect(Columns.drawnLineLengths(of: fragments[1])) == [61]
            expect(Support.isMarked(tail)).to(beFalse())
            let followerBlock = try XCTUnwrap(page.blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minY).to(beCloseTo(fragments[1].frame.maxY, within: 0.01))
        }

        /// 흐름 분할, 넓은 단(61자) → 좁은 단(30자): 122자 문단은 넓은 단에서 두 줄로 재어지고
        /// 첫 줄만 들어간다. 나머지 61자는 좁은 단 폭으로 다시 재어 세 줄(48pt)이 되므로 둘째
        /// 단엔 두 줄(60자, 32pt)만 들어가고 마지막 글자는 다음 쪽으로 간다 — 종전에는 한 줄로
        /// 잰 61자를 16pt 상자에 놓아 세 줄이 상자를 32pt 넘쳤다.
        func testFlowSplitRemeasuresTheRemainderInANarrowerColumn() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 122))
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [61, 30], contentHeight: 40, bodyParagraphs: [paragraph]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            let first = Columns.fragments(on: pages[0])
            expect(first.map { $0.attributedString?.length }) == [61, 60]
            guard first.count == 2 else { return }
            expect(first[1].frame.width).to(beCloseTo(widths[1], within: 0.01))
            // 마지막 줄의 ascent 초과분 2pt(#164)는 다음 조각 몫이라 30 + 18 = 48pt다.
            expect(first[1].frame.height).to(beGreaterThanOrEqualTo(29.5))
            expect(first[1].frame.height).to(beLessThanOrEqualTo(32.5))
            expect(Columns.drawnLineLengths(of: first[1])) == [30, 30]
            expect(Support.isMarked(try XCTUnwrap(first[1].attributedString))).to(beTrue())
            let last = try XCTUnwrap(Columns.fragments(on: pages[1]).first)
            expect(last.attributedString?.length) == 1
            expect(first[1].frame.height + last.frame.height).to(beCloseTo(48, within: 0.5))
            expect(Columns.drawnLineLengths(of: last)) == [1]
        }

        /// 다단 균형 재배치, 좁은 단 → 넓은 단: 121자 문단(좁은 단에서 다섯 줄)과 뒤 문단이 첫
        /// 단에 다 들어간 뒤 밴드를 닫으며 줄 단위로 나뉜다. 넓은 단으로 옮겨진 줄 넷·다섯
        /// (31자)은 그 단 폭으로 다시 재어 한 줄(16pt)이고 뒤 문단이 바로 아래 온다 — 종전에는
        /// 두 줄 높이(32pt) 상자에 한 줄이 그려져 뒤 문단 위 16pt가 비었다.
        func testColumnBalanceRemeasuresTheFragmentInAWiderColumn() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [30, 61], contentHeight: 120,
                bodyParagraphs: [paragraph, follower]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [90, 31]
            guard fragments.count == 2 else { return }
            expect(fragments[1].frame.width).to(beCloseTo(widths[1], within: 0.01))
            expect(fragments[1].frame.height).to(beCloseTo(16, within: 0.5))
            expect(Columns.drawnLineLengths(of: fragments[1])) == [31]
            let followerBlock = try XCTUnwrap(page.blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minX).to(beCloseTo(fragments[1].frame.minX, within: 0.01))
            expect(followerBlock.frame.minY).to(beCloseTo(fragments[1].frame.maxY, within: 0.01))
        }

        /// 저장본 줄 캐시 높이를 따르는 문단은 다시 재지 않는다: 캐시 세 줄(48pt)·CT 네 줄 문단의
        /// 나머지(줄 둘·셋·넷, 61자)가 넓은 단으로 가면 잰 전진량 16 + 16 + 캐시 잔여 1pt = 33pt
        /// 상자 그대로다 — 다시 쟀다면 한 줄 상자(약 18pt)가 된다. 캐시 잔여를 담아 표식도 없다.
        func testCachedHeightRemainderIsNotRemeasured() async throws {
            let paragraph = try HwpSynthetic.lineSegParagraph(
                String(repeating: "가", count: 91),
                segments: [
                    (location: 0, height: 1000), (location: 1600, height: 1000),
                    (location: 3200, height: 1000),
                ]
            )
            let (paginator, _) = try Columns.columns(
                charactersPerLine: [30, 61], contentHeight: 40, bodyParagraphs: [paragraph]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [30, 61]
            guard fragments.count == 2, let tail = fragments[1].attributedString else { return }
            expect(fragments[1].frame.height).to(beCloseTo(33, within: 0.5))
            expect(Support.isMarked(tail)).to(beFalse())
        }
    }

    /// 비등폭 단 재측정 테스트의 공용 입력·조회.
    enum MeasuredLineRemeasureSupport {
        /// 줄당 글자 수가 다른 단(간격 10pt) 구역. 단 폭·간격은 HWPUNIT(pt × 100)으로 적어
        /// 본문 폭에 1:1로 배분되게 한다.
        static func columns(
            charactersPerLine: [Int], contentHeight: CGFloat,
            bodyParagraphs: [CoreHwp.HwpParagraph],
            index: HwpIndex = HwpIndex(from: CoreHwp.HwpFile())
        ) throws -> (paginator: HwpPaginator, widths: [CGFloat]) {
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            ).build(paragraph: try HwpSynthetic.textParagraph("가"))
            let widths = charactersPerLine.map {
                MeasuredLineFragmentSupport.columnWidth(charactersPerLine: $0, in: built)
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(MeasuredLineFragmentSupport.sectionDef(
                        columnWidth: widths.reduce(0, +) + 10 * CGFloat(widths.count - 1),
                        contentHeight: contentHeight
                    )),
                    .column(HwpSynthetic.column(
                        count: widths.count,
                        widths: widths.map { UInt16(($0 * 100).rounded()) },
                        gaps: Array(repeating: UInt16(1000), count: widths.count - 1) + [0]
                    )),
                ],
                bodyParagraphs: bodyParagraphs
            )
            return (
                HwpPaginator(sections: [section], index: index, fontResolver: .testDeterministic),
                widths
            )
        }

        static func fragments(on page: HwpPage) -> [AnyHwpBlock] {
            page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가") == true }
                .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        }

        static func drawnLineLengths(of block: AnyHwpBlock) -> [Int] {
            drawnLines(of: block).map(\.stringRange.length)
        }

        static func drawnLines(of block: AnyHwpBlock) -> [HwpDrawnLine] {
            guard let text = block.attributedString else { return [] }
            return HwpDrawnTextLayout.lines(
                attributedString: text, origin: block.frame.origin, lineWidth: block.frame.width
            )
        }
    }
#endif
