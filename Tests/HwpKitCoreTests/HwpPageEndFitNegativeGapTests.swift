import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 고정 줄 간격이 줄 상자보다 작은 줄 — 상자가 블록(전진량) 아래로 나가 "줄 상자 아래 몫"이 음수인
    /// 자리 (#222 PR 리뷰). 한글 12.30 실측(`probes/222` so222n): 단 구분선은 그 상자 바닥에서 끝나고
    /// (12pt·고정 8pt 줄로 끝나는 균형 배분 밴드 → 44), 고정 8pt 두 줄 각주의 스택은 마지막 줄 상자
    /// 바닥이 본문 하단에 닿는다. 0에서 자르면 셋 다 전진량 끝에서 멈췄다.
    final class HwpPageEndFitNegativeGapTests: XCTestCase {
        private typealias Fit = HwpPageEndLineBoxFitTests

        /// 둘째 단 마지막 문단이 16pt·고정 8pt면 그 줄 상자 바닥(32 + 16 = 48)이 첫 단 상자 바닥(42)
        /// 보다 낮고 전진량 끝(32 + 8 = 40)은 높다 — 구분선은 48에서 끝난다(한글 so222n DG와 같은
        /// 형태: 12pt·고정 8pt → 44). 음수 몫을 0으로 자르면 첫 단이 정한 42에서 끝났다.
        func testDividerReachesALineBoxHangingBelowItsAdvance() async throws {
            var first = try HwpSynthetic.textParagraph("RB01")
            first.ctrlHeaderArray = [.column(HwpColumnDividerTests.column(divider: 1))]
            let fillers = try (2 ... 5).map { try HwpSynthetic.textParagraph("RB0\($0)") }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [first] + fillers + [try Fit.target("RBT 끝", charShapeId: 1)]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: try Fit.index(shape: Fit.fixedShape(points: 8)),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let last = try XCTUnwrap(page.blocks.first {
                $0.kind == .text && $0.attributedString?.string.contains("RBT") == true
            })
            let divider = try XCTUnwrap(HwpColumnDividerTests.dividers(in: page).first)
            expect(last.frame.minX).to(beGreaterThan(divider.frame.maxX))
            expect(last.frame.minY - divider.frame.minY).to(beCloseTo(32, within: 0.01))
            expect(last.frame.height).to(beCloseTo(8, within: 0.01))
            expect(divider.frame.maxY - divider.frame.minY).to(beCloseTo(48, within: 0.01))
        }

        /// 다른 단의 표가 본문 줄 블록 아래(140)와 그 줄 상자 아래(144) 사이(142)에서 끝나도 구분선은
        /// 줄 상자 바닥까지다 (#222 PR 리뷰) — 밴드 바닥이 블록 아래로만 재면 본문이 바닥에 닿지 않은
        /// 것으로 보여 표 바닥 142에서 끊겨, 그려진 줄 상자 안에서 멈췄다. 상자도 표 바닥에 못 닿으면
        /// (141) 종전대로 표 바닥이다.
        func testDividerReachesAHangingLineBoxBelowANonTextBandBottom() throws {
            var band = HwpColumnBandController()
            band.currentColumnDef = HwpColumnDividerTests.column(divider: 1)
            band.columnFrames = [
                CGRect(x: 50, y: 100, width: 200, height: 500),
                CGRect(x: 300, y: 100, width: 150, height: 500),
            ]
            band.bandUsedBottom = 142
            let text = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 200, height: 40), kind: .text,
                attributedString: NSAttributedString(string: "가")
            )
            let table = AnyHwpBlock(
                frame: CGRect(x: 300, y: 100, width: 150, height: 42), kind: .table
            )
            let hanging = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [text, table], trailingSpacing: { _, _ in -4 }
            ).first)
            expect(hanging.frame.maxY).to(beCloseTo(144, within: 0.001))
            let short = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [text, table], trailingSpacing: { _, _ in -1 }
            ).first)
            expect(short.frame.maxY).to(beCloseTo(142, within: 0.001))
        }

        /// 변경 막대도 블록 아래로 나간 줄 상자까지 긋는다 — 16pt·고정 8pt 한 줄 문단의 블록은 8이고
        /// 상자는 16이다. 블록에서 끊으면 그려진 글줄의 아래 절반 옆에 막대가 없었다.
        func testTrackChangeBarReachesALineBoxHangingBelowItsBlock() async throws {
            var target = try Fit.target("X1", charShapeId: 1)
            var data = Data()
            for value in [UInt32(0), UInt32(2), UInt32(16) << 24] {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            target.paraRangeTagArray = [try CoreHwp.HwpParaRangeTag.load(data)]
            let layout = try await Fit.layout(
                target, remaining: 100, index: Fit.index(shape: Fit.fixedShape(points: 8))
            )
            let page = try XCTUnwrap(layout.pages.first)
            let block = try XCTUnwrap(layout.targets.first?.first)
            expect(block.frame.height).to(beCloseTo(8, within: 0.01))
            let bar = try XCTUnwrap(page.blocks.first {
                $0.kind == .shape && $0.frame.maxX <= block.frame.minX
                    && abs($0.frame.minY - block.frame.minY) < 0.001
            })
            expect(bar.frame.height).to(beCloseTo(16, within: 0.01))
        }

        /// 한글이 단별 run으로 저장한 고정 줄 간격 문단(10pt·고정 8pt → 캐시 줄 간격 −200)은 run 블록
        /// 높이가 이미 상자 바닥까지다(`lineBottom`이 음수 간격을 0으로 잡아 8 + 10 = 18) — 구분선은
        /// 블록 아래에서 끝난다. 음수 간격에 표식을 달지 않으면 블록 문자열을 다시 재는 측정 규칙이
        /// 문단 모양의 줄 간격으로 재어 상자 바닥과 어긋난다 — 이 합성 문단(기본 160%)은 6pt 위,
        /// 실제 고정 8pt 문단은 음수(−2)라 2pt 아래다.
        func testCachedColumnRunWithNegativeSpacingEndsTheDividerAtItsBlock() async throws {
            let text = String(repeating: "가나다라 ", count: 8) // 40자
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1000, width: 13416),
                .init(textIndex: 10, location: 800, height: 1000, width: 13416),
                .init(textIndex: 20, location: 0, height: 1000, width: 13416),
                .init(textIndex: 30, location: 800, height: 1000, width: 13416),
            ])
            var payload = Data()
            for (index, textIndex) in [UInt32(0), 10, 20, 30].enumerated() {
                let line: [Int32] = [
                    Int32(textIndex), index % 2 == 0 ? 0 : 800, 1000, 1000, 850, -200,
                    0, 13416, 393_216,
                ]
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            paragraph.ctrlHeaderArray = [.column(HwpColumnDividerTests.column(divider: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가나") == true }
            expect(columns.count) == 2
            for column in columns {
                expect(column.frame.height).to(beCloseTo(18, within: 0.01))
            }
            let lowest = try XCTUnwrap(columns.map(\.frame.maxY).max())
            let divider = try XCTUnwrap(HwpColumnDividerTests.dividers(in: page).first)
            expect(divider.frame.maxY).to(beCloseTo(lowest, within: 0.01))
        }

        /// 기록이 없는 블록의 구분선 규칙(`measuredTrailingSpacing` — 마지막 줄 전진량 − 상자)도 음수를
        /// 낸다 — 16pt·고정 8pt 줄은 −8이라 구분선이 블록 아래 8pt의 상자 바닥까지 내려간다.
        func testMeasuredTrailingSpacingIsNegativeForAHangingLineBox() throws {
            let index = try Fit.index(shape: Fit.fixedShape(points: 8))
            let attributed = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: try Fit.target("X1", charShapeId: 1))
            expect(HwpColumnBandController.measuredTrailingSpacing(of: attributed, lineWidth: 400))
                .to(beCloseTo(-8, within: 0.01))
        }

        /// 줄 캐시 없는 각주의 스택은 마지막 줄 상자 바닥까지 자란다 — 10pt·고정 8pt 두 줄 각주는 전진량
        /// 끝이 16이고 둘째 줄 상자 바닥이 8 + 10 = 18이다(한글 so222n NF: 그 상자 바닥이 본문 하단에
        /// 닿는다). 0으로 자르면 스택이 16이라 둘째 줄 상자가 영역(본문 하단) 아래로 2pt 나갔다.
        func testFootnoteStackGrowsToALineBoxHangingBelowItsAdvance() async throws {
            var host = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: [(characters: 3, marker: true)], segments: []
            )
            var note = HwpSynthetic.noteParagraph(
                " 첫 줄\n둘째 줄",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            note.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [note]
            ))]
            let layout = try await Fit.layout(
                host, remaining: 60, index: Fit.index(shape: Fit.fixedShape(points: 8))
            )
            let page = try XCTUnwrap(layout.pages.first)
            let block = try XCTUnwrap(page.blocks.first { $0.kind == .footnote })
            guard case let .footnote(payload) = block.payload else {
                fail("각주 블록의 payload가 각주가 아니다")
                return
            }
            // 스택 = 구분선 가운데 + 아래 여백부터 둘째 줄 상자 바닥까지.
            expect(block.frame.height).to(beCloseTo(18, within: 0.01))
            expect(block.frame.minY).to(beCloseTo(
                payload.separatorLine.midY + HwpRenderTuning.Footnote.dividerDefaultMarginBottom,
                within: 0.01
            ))
            // 흐름 모드 각주 영역의 바닥(쪽 본문 하단)에 둘째 줄 상자 바닥이 닿는다.
            let target = try XCTUnwrap(layout.targets.first?.first)
            let bodyBottom = target.frame.minY + 60
            expect(block.frame.maxY).to(beCloseTo(bodyBottom, within: 0.01))
        }
    }
#endif
