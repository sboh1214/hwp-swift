import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 끝 적합 판정(#222) 리뷰에서 나온 경계 — 다단의 빈 문단, 캐시 높이 문단의 판정 출처,
    /// 개체를 담은 각주의 스택, 본문 아래로 넘친 블록의 변경 막대. 배치 기하는
    /// `HwpPageEndLineBoxFitTests.layout`(여백 없는 쪽, 30자 단, 구역 첫 문단 16 + 채움 한 줄 16)이다.
    final class HwpPageEndFitReviewTests: XCTestCase {
        private typealias Fit = HwpPageEndLineBoxFitTests

        /// 다단 밴드에서 단 끝에 안 들어가는 빈 문단은 통째로 다음 단으로 간다 — 페이지네이터가 빈
        /// 문단 앵커의 줄 프레임을 비우므로 통째 이동이 줄 없는 나머지를 다룬다(종전에는 빈 줄 배열을
        /// 인덱싱해 멈췄다). 상자 10은 남은 9(160%)·9(고정 8 — 전진량은 들어간다)·10(100% — 상자
        /// 바닥이 단 바닥에 닿는다)에 들지 않는다.
        func testEmptyParagraphThatMissesTheColumnEndMovesWholeToTheNextColumn() async throws {
            var single = Fit.percentShape()
            single.lineSpacing2 = 100
            let cases: [String: (shape: CoreHwp.HwpParaShape, remaining: CGFloat)] = [
                "160%": (Fit.percentShape(), 9),
                "고정 8": (Fit.fixedShape(points: 8), 9),
                "100%": (single, 10),
            ]
            for (label, (shape, remaining)) in cases.sorted(by: { $0.key < $1.key }) {
                let layout = try await Fit.layout(
                    Fit.target(""), remaining: remaining, index: Fit.index(shape: shape), columns: 2
                )
                let block = try XCTUnwrap(layout.targets.first?.first, label)
                expect(block.frame.minX).to(beGreaterThan(200), description: label)
                expect(block.frame.minY).to(beCloseTo(0, within: 0.001), description: label)
                expect(layout.follower?.block.frame.minX)
                    .to(beCloseTo(block.frame.minX, within: 0.001), description: label)
                expect(layout.follower?.block.frame.minY)
                    .to(beCloseTo(block.frame.maxY, within: 0.001), description: label)
            }
        }

        /// 줄 캐시 높이를 쓰는 빈 문단도 다단에서 캐시의 줄 상자(`vertsize` 12)로 판정한다 — 1단과 같은
        /// 출처다(다단만 CT 앵커 상자 10으로 재면 남은 11에서 1단은 넘기고 다단은 남겼다).
        func testCachedEmptyParagraphIsJudgedByItsCachedBoxInColumnsToo() async throws {
            func cachedEmpty() throws -> CoreHwp.HwpParagraph {
                var paragraph = try HwpSynthetic.lineSegParagraph(
                    "", segments: [(location: 0, height: 1200)]
                )
                paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: 1, paraStyleId: 0
                )
                return paragraph
            }
            let index = try Fit.index(shape: Fit.percentShape())
            for columns in [1, 2] {
                let moved = try await Fit.layout(
                    cachedEmpty(), remaining: 11, index: index, columns: columns
                )
                let movedBlock = try XCTUnwrap(moved.targets.flatMap { $0 }.first)
                expect(movedBlock.frame.minY)
                    .to(beCloseTo(0, within: 0.001), description: "\(columns)단 남은 11")
                let kept = try await Fit.layout(
                    cachedEmpty(), remaining: 12.5, index: index, columns: columns
                )
                expect(kept.targets.first?.first?.frame.minY)
                    .to(beCloseTo(32, within: 0.001), description: "\(columns)단 남은 12.5")
            }
        }

        /// 캐시가 CT보다 줄이 적은(글꼴이 달라 CT가 더 잘게 나눈) 캐시 높이 문단은 캐시의 줄 상자만으로
        /// 문단 전체를 판정한다 — 앞 줄들의 CT 상자를 섞으면 캐시 높이(16)로 놓는 블록을 종전(캐시
        /// 전진량)보다도 엄격하게 넘겼다(남은 20에서 다섯 CT 줄의 상자 58로 재어 새 쪽으로 넘기고 쪽
        /// 머리에서 다시 나눴다).
        func testCachedParagraphWithMoreCTLinesIsJudgedByItsCache() async throws {
            var paragraph = try HwpSynthetic.lineSegParagraph(
                String(repeating: "가", count: 150), segments: [(location: 0, height: 1000)]
            )
            paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                paraShapeId: 1, paraStyleId: 0
            )
            let layout = try await Fit.layout(
                paragraph, remaining: 20, index: Fit.index(shape: Fit.percentShape())
            )
            expect(layout.targets.map(\.count)) == [1, 0]
            expect(layout.targets.first?.first?.frame.minY).to(beCloseTo(32, within: 0.001))
            expect(layout.targets.first?.first?.frame.height).to(beCloseTo(16, within: 0.001))
        }

        /// 개체를 담은 각주는 줄 캐시를 버리고 CT 높이로 쌓여도 마지막 줄 상자까지다 — 캐시 없는 같은
        /// 각주와 같은 스택이다(종전에는 표보다 낮은 낡은 캐시 한 줄이 붙었다는 이유만으로 CT 줄 간격
        /// 여분 6pt가 스택에 남았다).
        func testObjectCarryingFootnoteStacksToItsLastLineBoxWithOrWithoutAStaleCache() throws {
            let table = try InlineTableActualHeightSupport.staleTable(
                rows: 3, instanceId: 7, width: 10000
            )
            let bare = InlineTableActualHeightSupport.host(table: table, suffix: " 각주 뒤")
            var stale = bare
            stale.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "x", segments: [(location: 0, height: 1000)]
            ).paraLineSeg
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            func stacking(_ note: CoreHwp.HwpParagraph) -> CGFloat {
                layout.measureNote(
                    note, number: 1, width: 400, index: index, footnoteShape: nil, sizeResolver: nil
                ).stackingHeight(isNoteEnd: true)
            }
            expect(stacking(bare)).to(beCloseTo(30, within: 0.001))
            expect(stacking(stale)).to(beCloseTo(stacking(bare), within: 0.001))
        }

        /// 변경 추적 막대는 본문 하단에서 멈춘다 — 쪽 끝 적합이 줄 상자까지라 줄 간격 여분과 아래
        /// 간격(20pt)만큼 본문 아래로 나간 블록(16pt 줄, 블록 45.6)도 막대는 아래 여백으로 뻗지 않는다.
        func testTrackChangeBarStopsAtTheBodyBottom() async throws {
            var target = try Fit.target("X1", charShapeId: 1)
            var data = Data()
            for value in [UInt32(0), UInt32(2), UInt32(16) << 24] {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            target.paraRangeTagArray = [try CoreHwp.HwpParaRangeTag.load(data)]
            let layout = try await Fit.layout(
                target, remaining: 17.62,
                index: Fit.index(shape: Fit.percentShape(spacingBottom: 4000))
            )
            let page = try XCTUnwrap(layout.pages.first)
            let block = try XCTUnwrap(layout.targets.first?.first)
            let bodyBottom: CGFloat = 32 + 17.62
            expect(block.frame.maxY).to(beGreaterThan(bodyBottom))
            // 합성 문단은 paraId가 모두 0이라 쪽의 모든 텍스트 블록이 막대를 받는다 — 대상 블록 옆 막대.
            let bar = try XCTUnwrap(page.blocks.first {
                $0.kind == .shape && $0.frame.maxX <= block.frame.minX
                    && abs($0.frame.minY - block.frame.minY) < 0.001
            })
            expect(bar.frame.maxY).to(beCloseTo(bodyBottom, within: 0.01))
        }
    }
#endif
