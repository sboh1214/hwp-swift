import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 끝 적합 판정(#222) PR 리뷰의 경계 — 각주가 있는 쪽의 변경 막대와 균형 배분된 다단 밴드의
    /// 단 구분선. 줄 상자까지만 판정해 블록이 줄 간격 여분·문단 아래 간격만큼 본문 아래로 나갈 수
    /// 있게 되면서, 그 몫을 본문 하단(각주 영역 상단)·줄 상자 바닥에서 끊어야 하는 자리들이다.
    final class HwpPageEndFitBandReviewTests: XCTestCase {
        private typealias Fit = HwpPageEndLineBoxFitTests
        private typealias Columns = MeasuredLineRemeasureSupport

        /// 각주가 있는 쪽의 변경 막대는 각주 영역 상단에서 멈춘다 — 본문 하단이 그 자리다. 남은
        /// 40pt에 10pt·160% 한 줄(상자 10, 아래 간격 20 → 블록 36)과 그 한 줄 각주가 함께 들어가지만
        /// 블록은 각주 영역 위로 20pt 넘게 내려간다. 쪽 하단에서만 끊으면 막대가 구분선을 넘어 각주
        /// 옆까지 그려졌다. 줄 상자(10)는 자르지 않는다.
        func testTrackChangeBarStopsAtTheFootnoteAreaTop() async throws {
            var target = try Self.footnotedTarget()
            target.paraRangeTagArray = [try Self.trackChangeTag()]
            let layout = try await Fit.layout(
                target, remaining: 40,
                index: Fit.index(shape: Fit.percentShape(spacingBottom: 4000))
            )
            let page = try XCTUnwrap(layout.pages.first)
            let block = try XCTUnwrap(layout.targets.first?.first)
            let note = try XCTUnwrap(page.blocks.first { $0.kind == .footnote })
            guard case let .footnote(payload) = note.payload else {
                fail("각주 블록의 payload가 각주가 아니다")
                return
            }
            // 대상 줄과 그 각주가 한 쪽에 있고, 블록(전진량 + 아래 간격)은 구분선 아래까지 내려간다.
            expect(block.frame.minY + 10).to(beLessThan(payload.separatorLine.minY))
            expect(block.frame.maxY).to(beGreaterThan(payload.separatorLine.maxY))
            // 합성 문단은 paraId가 모두 0이라 쪽의 모든 텍스트 블록이 막대를 받는다 — 대상 블록 옆 막대.
            let bar = try XCTUnwrap(page.blocks.first {
                $0.kind == .shape && $0.frame.maxX <= block.frame.minX
                    && abs($0.frame.minY - block.frame.minY) < 0.001
            })
            expect(bar.frame.maxY).to(beLessThan(payload.separatorLine.minY))
            expect(bar.frame.maxY).to(beGreaterThanOrEqualTo(block.frame.minY + 10))
            // 각주 영역 상단 = 구분선 가운데 − 구분선 위 여백(합성 구역은 구분선 정보가 없어 기본값)
            // — 막대는 거기서 끝난다.
            expect(bar.frame.maxY).to(beCloseTo(
                payload.separatorLine.midY - HwpRenderTuning.Footnote.dividerDefaultMarginTop,
                within: 0.01
            ))
        }

        /// 구분선 획이 위 여백보다 굵으면 본문 하단은 그 획의 상단이다 — 예약이 획의 넘친 몫
        /// (`separatorOverhang`)을 세므로 본문 줄은 거기까지만 들어가고, 막대도 거기서 멈춘다 (#222 PR
        /// 리뷰). 위 여백 0·굵기 14.17pt 구분선이면 획 반 두께(7.09)만큼 영역 상단 위에서 끊는다 —
        /// 영역 상단에서 끊으면 막대가 구분선 획 안으로 그만큼 들어갔다.
        func testTrackChangeBarStopsAtAThickSeparatorTop() async throws {
            var target = try Self.footnotedTarget()
            target.paraRangeTagArray = [try Self.trackChangeTag()]
            let layout = try await Fit.layout(
                target, remaining: 40,
                index: Fit.index(shape: Fit.percentShape(spacingBottom: 4000)),
                footnoteShape: HwpFootnoteContinuationBodyBottomTests.thickDividerShape()
            )
            let page = try XCTUnwrap(layout.pages.first)
            let block = try XCTUnwrap(layout.targets.first?.first)
            let note = try XCTUnwrap(page.blocks.first { $0.kind == .footnote })
            guard case let .footnote(payload) = note.payload else {
                fail("각주 블록의 payload가 각주가 아니다")
                return
            }
            expect(payload.separatorLine.height).to(beCloseTo(14.17, within: 0.01))
            // 대상 줄과 그 각주가 한 쪽에 있고 블록은 구분선 획 아래까지 내려간다.
            expect(block.frame.minY + 10).to(beLessThan(payload.separatorLine.minY))
            expect(block.frame.maxY).to(beGreaterThan(payload.separatorLine.maxY))
            let bar = try XCTUnwrap(page.blocks.first {
                $0.kind == .shape && $0.frame.maxX <= block.frame.minX
                    && abs($0.frame.minY - block.frame.minY) < 0.001
            })
            expect(bar.frame.maxY).to(beCloseTo(payload.separatorLine.minY, within: 0.01))
        }

        /// 각주 배치가 내는 칠하는 상단은 두 배치 모두 예약 경계와 같다 — 구분선 획이 위 여백보다
        /// 굵으면 그 획의 상단(`separatorLine.minY`), 아니면 영역 상단(구분선 가운데 − 위 여백)이다.
        func testPaintedTopIsTheSeparatorTopWhenTheStrokeOverhangs() throws {
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = FootnoteContinuationSupport.geometry(contentWidth: 451)
            let note = try FootnoteContinuationSupport.note(lines: ["줄 1"], locations: [0])
            let thick = try HwpFootnoteContinuationBodyBottomTests.thickDividerShape()
            for halfCap in [true, false] {
                for shape in [thick, nil] {
                    let placement = layout.placePending(
                        footnotes: HwpFootnoteLayout.PendingNotes([
                            HwpFootnoteLayout.Input(paragraph: note, number: 1),
                        ]),
                        onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()),
                        footnoteShape: shape, limitsAreaToHalfContent: halfCap,
                        bodyBottom: geometry.contentFrame.minY + 100
                    )
                    let label = "절반 상한 \(halfCap), 굵은 구분선 \(shape != nil)"
                    let separator = try XCTUnwrap(placement.blocks.first?.separatorLine, label)
                    let expected = shape == nil
                        ? separator.midY - HwpRenderTuning.Footnote.dividerDefaultMarginTop
                        : separator.minY
                    expect(placement.paintedTop)
                        .to(beCloseTo(expected, within: 0.001), description: label)
                }
            }
        }

        /// 한 줄 각주를 첫 줄에 단 대상 문단(문단 모양 1).
        private static func footnotedTarget() throws -> CoreHwp.HwpParagraph {
            var target = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: [(characters: 3, marker: true)], segments: []
            )
            target.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            target.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 각주",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            return target
        }

        /// 막대는 그려진 줄 상자를 자르지 않는다 — 쪽마다 각주 번호를 새로 매기는 구역에서 문단 높이가
        /// 단에 들어가는(20pt·160% 세 줄, 96 ≤ 본문 100) 문단은 셋째 줄에 단 두 줄 각주를 품고도 기준과
        /// 같이 통째로 놓여 셋째 줄 상자(64~84)가 각주 영역 아래로 내려간다(남은 격차 — 한글은 줄을
        /// 남기고 각주를 다음 쪽에 잇는다). 그 줄도 변경된 글줄이라 막대가 상자 바닥 84까지 선다.
        func testTrackChangeBarKeepsLineBoxesBelowTheFootnoteAreaTop() async throws {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: (0 ..< 3).map { (characters: 3, marker: $0 == 2) }, segments: []
            )
            host.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            var runs = CoreHwp.HwpParaCharShape()
            runs.startingIndex = [0]
            runs.shapeId = [5] // 20pt
            host.paraCharShape = runs
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 첫 줄\n둘째 줄",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            host.paraRangeTagArray = [try Self.trackChangeTag()]
            let layout = try await Fit.layout(
                host, remaining: 52, index: Fit.index(shape: Fit.percentShape()), fillerLines: 2,
                footnoteNumberingMode: 2
            )
            // 뒤 문단은 셋째 쪽이다 — 각주 영역 위(59.83)에 남은 자리가 없다.
            expect(layout.targets.map(\.count)) == [0, 1, 0]
            guard layout.targets.count == 3 else { return }
            let page = layout.pages[1]
            let block = try XCTUnwrap(layout.targets[1].first)
            expect(block.frame.height).to(beCloseTo(96, within: 0.001))
            let note = try XCTUnwrap(page.blocks.first { $0.kind == .footnote })
            guard case let .footnote(payload) = note.payload else {
                fail("각주 블록의 payload가 각주가 아니다")
                return
            }
            expect(block.frame.minY + 84).to(beGreaterThan(payload.separatorLine.maxY))
            let bar = try XCTUnwrap(page.blocks.first {
                $0.kind == .shape && $0.frame.maxX <= block.frame.minX
                    && abs($0.frame.minY - block.frame.minY) < 0.001
            })
            expect(bar.frame.maxY).to(beCloseTo(block.frame.minY + 84, within: 0.01))
        }

        /// 변경 추적(표 32 종류 16) 영역 태그 — 문단 전체.
        private static func trackChangeTag() throws -> CoreHwp.HwpParaRangeTag {
            var data = Data()
            for value in [UInt32(0), UInt32(2), UInt32(16) << 24] {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            return try CoreHwp.HwpParaRangeTag.load(data)
        }

        /// 균형 배분된 2단 밴드의 구분선도 마지막 줄 상자 바닥에서 끝난다 — 재배치가 새로 만든
        /// 조각이 원래 블록의 상자 아래 몫(줄 간격 여분 + 문단 아래 간격)을 물려받는다. 한글 12.30
        /// 실측(so222r): 10pt·160% 여섯 줄 밴드(3 + 3)의 둘째 단 마지막 문단에 아래 간격 20pt가
        /// 있어도 구분선은 밴드 상단 + 42(상자 바닥)에서 끝난다. 물려받지 않으면 측정 규칙(줄 간격만
        /// 뺀다)으로 재어 62까지 그렸다.
        func testRebalancedBandDividerEndsAtTheLastLineBox() async throws {
            var first = try HwpSynthetic.textParagraph("RB01")
            first.ctrlHeaderArray = [.column(HwpColumnDividerTests.column(divider: 1))]
            let fillers = try (2 ... 5).map { try HwpSynthetic.textParagraph("RB0\($0)") }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [first] + fillers + [try Fit.target("RBT 끝")]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: try Fit.index(shape: Fit.percentShape(spacingBottom: 4000)),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let band = page.blocks.filter {
                $0.kind == .text && $0.attributedString?.string.contains("RB") == true
            }
            expect(band.count) == 6
            let last = try XCTUnwrap(
                band.first { $0.attributedString?.string.contains("RBT") == true }
            )
            let divider = try XCTUnwrap(HwpColumnDividerTests.dividers(in: page).first)
            // 3 + 3으로 배분됐고 마지막 문단은 둘째 단 셋째 줄이다.
            expect(last.frame.minX).to(beGreaterThan(divider.frame.maxX))
            expect(last.frame.minY - divider.frame.minY).to(beCloseTo(32, within: 0.01))
            expect(last.frame.height).to(beCloseTo(36, within: 0.01))
            expect(divider.frame.maxY - divider.frame.minY).to(beCloseTo(42, within: 0.01))
        }

        /// 폭이 다른 단으로 옮겨 다시 잰 재배치 조각은 다시 잰 줄로 상자 아래 몫을 잰다 — 30자 단에
        /// 다섯 줄(30·30·30·25·5 — 넷째 줄엔 20pt 글자가 다섯까지 든다)인 문단(아래 간격 20)은
        /// 마지막 줄에도 20pt 글자(115번째)가 있어 원래 블록의 상자 아래 몫이 32(전진량 32 − 상자
        /// 20 + 20)다. 단 정의를 실은 구역 첫 문단(템플릿 줄)까지 여섯 단위라 3 + 3으로 나뉘고, 뒤
        /// 세 줄(60자)이 16자 단에서 다섯 줄(16·16·16·20pt 줄 32·10pt 줄 16 + 아래 간격 20 = 116)이
        /// 되면 마지막 줄은 10pt라 몫은 26이고 구분선은 상자 바닥 90에서 끝난다 — 원래 블록의 몫을
        /// 물려받으면 84, 측정 규칙(줄 간격만 뺀다)은 110이다.
        func testRemeasuredRebalancedFragmentMeasuresItsOwnLineBox() async throws {
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            ).build(paragraph: try HwpSynthetic.textParagraph("가"))
            let widths = [30, 16].map {
                MeasuredLineFragmentSupport.columnWidth(charactersPerLine: $0, in: built)
            }
            var column = HwpSynthetic.column(
                count: 2, widths: widths.map { UInt16(($0 * 100).rounded()) }, gaps: [1000, 0]
            )
            column.dividerType = 1
            column.dividerThickness = 1
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(MeasuredLineFragmentSupport.sectionDef(
                        columnWidth: widths.reduce(0, +) + 10, contentHeight: 300
                    )),
                    .column(column),
                ],
                bodyParagraphs: [try Self.mixedSizeTarget()]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: try Fit.index(shape: Fit.percentShape(spacingBottom: 4000)),
                fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            let page = try XCTUnwrap(pages.first)
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [60, 60]
            guard fragments.count == 2 else { return }
            expect(Columns.drawnLineLengths(of: fragments[1])) == [16, 16, 16, 10, 2]
            expect(fragments[1].frame.height).to(beCloseTo(116, within: 0.01))
            let divider = try XCTUnwrap(HwpColumnDividerTests.dividers(in: page).first)
            expect(divider.frame.maxY)
                .to(beCloseTo(fragments[1].frame.minY + 48 + 32 + 10, within: 0.01))
        }

        /// 가 120자(10pt) 가운데 110~115번째 여섯 자만 20pt인 문단(문단 모양 1 — 아래 간격 20).
        private static func mixedSizeTarget() throws -> CoreHwp.HwpParagraph {
            var paragraph = try Fit.target(String(repeating: "가", count: 120))
            var runs = CoreHwp.HwpParaCharShape()
            runs.startingIndex = [0, 110, 116]
            runs.shapeId = [0, 5, 0]
            paragraph.paraCharShape = runs
            return paragraph
        }
    }
#endif
