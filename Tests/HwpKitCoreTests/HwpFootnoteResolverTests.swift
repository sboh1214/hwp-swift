import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 각주 크기 해석기 (수집 시점 고정 · 단 폭 정규화)

    extension HwpFootnoteObjectLayoutTests {
        /// 배치는 **수집 시점에 잡은** 해석기를 쓴다 (R44 #1).
        /// `HwpPaginator.objectSizeResolver`는 현재 단·문단 폭을 읽는 계산
        /// 프로퍼티라, 배치가 페이지 확정 시점 값을 다시 읽으면 그 사이 단이 바뀐
        /// 문서에서 예약과 다른 크기로 재조판된다 — 예약 ≡ 배치의 시간 축이다.
        func testPlacementUsesResolverCapturedAtCollection() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.paperRelativeInlineObject(
                widthPercent: 1000, heightPercent: 2000
            ))]
            func resolver(paperHeight: CGFloat) -> HwpObjectSizeResolver {
                HwpObjectSizeResolver(
                    paperSize: CGSize(width: 595, height: paperHeight),
                    contentSize: geometry.contentFrame.size,
                    columnWidth: geometry.contentFrame.width
                )
            }
            func height(
                captured: HwpObjectSizeResolver, atPlacement: HwpObjectSizeResolver
            ) throws -> CGFloat {
                let blocks = layout.layout(
                    footnotes: [.init(paragraph: note, number: 1, sizeResolver: captured)],
                    onPage: geometry,
                    index: index,
                    sizeResolver: atPlacement
                )
                return try XCTUnwrap(blocks.first, "각주 블록이 없다").frame.height
            }

            let a4 = try height(captured: resolver(paperHeight: 842), atPlacement: resolver(paperHeight: 842))
            // 배치 때 2배 종이가 넘어와도 수집 시점(A4) 결과가 유지된다
            expect(try height(
                captured: resolver(paperHeight: 842), atPlacement: resolver(paperHeight: 1684)
            )).to(beCloseTo(a4, within: 0.5))
            // 수집 시점 값이 실제로 결과를 가른다 — 아니면 위 단언이 공허하다
            expect(try height(
                captured: resolver(paperHeight: 1684), atPlacement: resolver(paperHeight: 842)
            )) > a4 + 1
        }

        /// 이월 각주를 **재예약**할 때도 수집 시점 해석기를 쓴다 (R45 #1).
        /// 배치는 `Input.sizeResolver`를 쓰므로 (R44 #1) 재예약만 현재
        /// environment로 재면 예약 ≡ 배치가 다시 갈린다 — 수집→배치는 닫혔는데
        /// 수집→재예약이 열려 있었다.
        func testOverflowReReservationUsesCapturedResolver() {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.paperRelativeInlineObject(
                widthPercent: 1000, heightPercent: 2000
            ))]
            func resolver(paperHeight: CGFloat) -> HwpObjectSizeResolver {
                HwpObjectSizeResolver(
                    paperSize: CGSize(width: 595, height: paperHeight),
                    contentSize: geometry.contentFrame.size,
                    columnWidth: geometry.contentFrame.width
                )
            }
            var coordinator = HwpFootnoteCoordinator(
                index: index, fontResolver: .testDeterministic
            )
            func reserved(
                captured: HwpObjectSizeResolver, current: HwpObjectSizeResolver
            ) -> CGFloat {
                coordinator.reservedFootnoteHeight(
                    for: [.init(paragraph: note, number: 1, sizeResolver: captured)],
                    environment: .init(
                        contentWidth: geometry.contentFrame.width,
                        footnoteShape: nil,
                        sizeResolver: current
                    )
                )
            }

            let a4 = reserved(captured: resolver(paperHeight: 842), current: resolver(paperHeight: 842))
            // 재예약 시점에 단·구역이 바뀌어도 수집 시점(A4) 결과가 유지된다
            expect(reserved(
                captured: resolver(paperHeight: 842), current: resolver(paperHeight: 1684)
            )).to(beCloseTo(a4, within: 0.5))
            // 수집 시점 값이 실제로 결과를 가른다 — 아니면 위 단언이 공허하다
            expect(reserved(
                captured: resolver(paperHeight: 1684), current: resolver(paperHeight: 842)
            )) > a4 + 1
        }

        /// 각주 해석기는 **단 폭에 무관**하다 (R46 #2). 각주는 단으로 나뉘지
        /// 않으므로 (표 134 bits 8-9 미구현) 각주 안 '단' 기준 개체가 참조할 단은
        /// 각주 영역 자신이다. 이 정규화로 본문 문단이 단을 옮겨도 예약·배치가
        /// 흔들리지 않는다 — 드리프트를 값 운반이 아니라 구조로 없앤다.
        func testFootnoteObjectSizeIsIndependentOfCurrentColumnWidth() throws {
            var note = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            note.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                widthPercent: 5000, heightPercent: 1000
            ))]
            /// 블록 높이는 개체 **높이**만 따르는데 표 70에 '단' 기준 높이가 없어
            /// columnWidth에 무관하다 — 민감한 값은 개체 **폭**이라 그것을 잰다.
            func shapeWidth(columnWidth: CGFloat) throws -> CGFloat {
                let blocks = layout.layout(
                    footnotes: [.init(paragraph: note, number: 1)],
                    onPage: geometry,
                    index: index,
                    sizeResolver: HwpObjectSizeResolver(
                        paperSize: geometry.pageSize,
                        contentSize: geometry.contentFrame.size,
                        columnWidth: columnWidth
                    )
                )
                let block = try XCTUnwrap(blocks.first, "각주 블록이 없다")
                return try XCTUnwrap(block.shapes.first, "각주 도형이 없다").rect.width
            }

            // 현재 단이 좁든 넓든 각주 영역(451pt)의 50%로 해석된다
            let narrow = try shapeWidth(columnWidth: 120)
            expect(narrow).to(beCloseTo(try shapeWidth(columnWidth: 451), within: 0.5))
            expect(narrow).to(beCloseTo(geometry.contentFrame.width * 0.5, within: 1))
        }
    }
#endif
