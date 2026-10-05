import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 흐름을 차지하는 표(자리 차지·어울림)의 가로 자리 (#254) — 한글 12.30은 그런 표를 가로
    /// 기준(종이·쪽·단·문단)·정렬·오프셋으로 놓고, 정렬은 바깥 상자(표 + 좌우 바깥 여백)로 하며
    /// 표가 기준보다 넓으면 정렬대로 넘긴다. 종전에는 정렬·오프셋·여백과 무관하게 단 왼쪽에 놓았다.
    /// 한글 실측 표는 `HwpPaginator.flowTableOriginX` doc-comment.
    final class HwpFlowTableHorizontalPlacementTests: XCTestCase {
        private typealias Support = FloatingTablePrecedesTextSupport

        /// 행 `rows`개(15pt)·폭 `width`(HWPUNIT)인 자리 차지 표를 품은 `앵커` 문단
        static func host(
            width: UInt32,
            rows: Int = 1,
            relativeTo: CoreHwp.HwpCommonCtrlHorizontalRelativeTo = .paragraph,
            alignment: CoreHwp.HwpCommonCtrlRelativeAlignment = .topOrLeft,
            offset: Int32 = 0,
            margins: [CoreHwp.HWPUNIT16] = [0, 0, 0, 0],
            treatAsChar: Bool = false,
            textWrap: CoreHwp.HwpCommonCtrlTextWrap = .topAndBottom
        ) throws -> CoreHwp.HwpParagraph {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "앵커")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: width,
                    rowHeights: Array(repeating: 1500, count: rows),
                    cellParagraphs: try (0 ..< rows).map {
                        [[try HwpSynthetic.textParagraph("행 \($0)")]]
                    }
                ),
                treatAsChar: treatAsChar,
                textWrap: textWrap,
                margins: margins,
                horizontalRelativeTo: relativeTo,
                horizontalAlignment: alignment,
                horizontalOffset: offset
            ))]
            return host
        }

        /// 본문 쪽 기하 — `Support.paginator`의 구역 정의 그대로
        static let geometry = HwpPageGeometry.compute(
            pageDef: HwpSynthetic.sectionDef().pageDef, sectionDef: HwpSynthetic.sectionDef()
        )

        static func tableFrames(of paragraphs: [CoreHwp.HwpParagraph]) async throws -> [CGRect] {
            try await Support.blocks(of: Support.paginator(bodyParagraphs: paragraphs))
                .filter { $0.kind == .table }.map(\.frame)
        }

        /// 기준 × 정렬 — 기준보다 넓은 표는 가운데 정렬이면 양쪽, 오른쪽 정렬이면 왼쪽으로 넘친다.
        /// 한글(본문 85.04–510.24pt, 450pt 표): 문단·단·쪽 왼쪽 85.08·가운데 72.72·오른쪽 60.24, 종이
        /// 0·72.72·145.32 (장치 격자 반올림).
        func testBasisAndAlignmentPlaceTheTableAndLetItOverflow() async throws {
            let content = Self.geometry.contentFrame
            let paper = Self.geometry.pageSize.width
            let width: CGFloat = 450
            struct Reference {
                let basis: CoreHwp.HwpCommonCtrlHorizontalRelativeTo
                let base: CGFloat
                let extent: CGFloat
            }
            let references = [
                Reference(basis: .paragraph, base: content.minX, extent: content.width),
                Reference(basis: .column, base: content.minX, extent: content.width),
                Reference(basis: .page, base: content.minX, extent: content.width),
                Reference(basis: .paper, base: 0, extent: paper),
            ]
            for reference in references {
                let (basis, base, extent) = (reference.basis, reference.base, reference.extent)
                let frames = try await Self.tableFrames(of: [
                    Self.host(width: 45000, relativeTo: basis, alignment: .topOrLeft),
                    Self.host(width: 45000, relativeTo: basis, alignment: .center),
                    Self.host(width: 45000, relativeTo: basis, alignment: .bottomOrRight),
                ])
                expect(frames.count).to(equal(3), description: "\(basis)")
                guard frames.count == 3 else { continue }
                expect(frames[0].minX).to(beCloseTo(base, within: 1e-6), description: "\(basis) 왼쪽")
                expect(frames[1].minX).to(beCloseTo(base + (extent - width) / 2, within: 1e-6),
                                          description: "\(basis) 가운데")
                expect(frames[2].minX).to(beCloseTo(base + extent - width, within: 1e-6),
                                          description: "\(basis) 오른쪽")
                expect(frames.map(\.width))
                    .to(equal([width, width, width]), description: "\(basis)")
            }
        }

        /// 오프셋은 정렬 자리에 더하고, 바깥 여백은 상자로 정렬한 뒤 왼쪽 여백만큼 들인다 — 한글:
        /// 오프셋 ±20pt면 105.12·65.04, 여백 좌우 10pt면 왼쪽 95.04·가운데 72.72(대칭이라 같다)·
        /// 오른쪽 50.28(상자 오른쪽이 본문 오른쪽 510.24).
        func testOffsetAndOuterMarginsShiftTheTable() async throws {
            let left = Self.geometry.contentFrame.minX
            let right = Self.geometry.contentFrame.maxX
            let margins: [CoreHwp.HWPUNIT16] = [1000, 1000, 0, 0]
            let frames = try await Self.tableFrames(of: [
                Self.host(width: 45000, offset: 2000),
                Self.host(width: 45000, offset: -2000),
                Self.host(width: 45000, margins: margins),
                Self.host(width: 45000, alignment: .center, margins: margins),
                Self.host(width: 45000, alignment: .bottomOrRight, margins: margins),
            ])
            expect(frames.map(\.minX)).to(equal([
                left + 20, left - 20, left + 10,
                left + (Self.geometry.contentFrame.width - 450) / 2,
                right - 10 - 450,
            ]))
        }

        /// 어울림(`square`)도 같은 자리다 — 한글: 450pt 표 왼쪽 85.08·가운데 72.72·오른쪽 60.24.
        func testSquareWrapTablesUseTheSamePlacement() async throws {
            let content = Self.geometry.contentFrame
            let frames = try await Self.tableFrames(of: [
                Self.host(width: 45000, alignment: .center, textWrap: .square),
                Self.host(width: 30000, alignment: .bottomOrRight, textWrap: .square),
            ])
            expect(frames.map(\.minX)).to(equal([
                content.minX + (content.width - 450) / 2, content.maxX - 300,
            ]))
        }

        /// 쪽을 넘긴 조각은 그 쪽에서 다시 잰다 — 가운데 정렬 표의 조각이 모두 같은 가로 자리다.
        func testSplitSegmentsKeepTheAnchoredPosition() async throws {
            let content = Self.geometry.contentFrame
            let paginator = Support.paginator(bodyParagraphs: [
                try Self.host(width: 45000, rows: 80, alignment: .center),
            ])
            var frames: [CGRect] = []
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                frames += page.blocks.filter { $0.kind == .table }.map(\.frame)
                pageIndex += 1
            }
            expect(frames.count).to(beGreaterThanOrEqualTo(2))
            for frame in frames {
                expect(frame.minX)
                    .to(beCloseTo(content.minX + (content.width - 450) / 2, within: 1e-6))
            }
        }

        /// 단을 넘긴 조각은 **그 단에서** 다시 잰다 — 비등폭 2단(134.16 / 268.37pt)에서 단 기준 오른쪽
        /// 정렬 100pt 표가 둘째 단으로 넘어가면 그 조각은 둘째 단 오른쪽 끝에 붙는다. 첫 조각의 x를
        /// 다시 쓰면 둘째 조각이 첫 단 자리에 남는다.
        func testSegmentsInAnotherColumnAreAlignedInThatColumn() async throws {
            let sectionDef = HwpSynthetic.sectionDef(pageHeight: 30000)
            let column = HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(sectionDef), .column(column)],
                bodyParagraphs: [
                    try Self.host(
                        width: 10000, rows: 20, relativeTo: .column, alignment: .bottomOrRight
                    ),
                ]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let frames = try await Support.blocks(of: paginator)
                .filter { $0.kind == .table }.map(\.frame)
            let columns = HwpPageGeometry.compute(
                pageDef: sectionDef.pageDef, sectionDef: sectionDef, column: column
            ).columnFrames
            expect(frames.count) == 2
            expect(columns.count) == 2
            guard frames.count == 2, columns.count == 2 else { return }
            expect(frames[0].minX).to(beCloseTo(columns[0].maxX - 100, within: 1e-6))
            expect(frames[1].minX).to(beCloseTo(columns[1].maxX - 100, within: 1e-6))
        }

        /// 쪽 경계에서 나누지 않는 표(표 76 bits 0-1 = 0)는 통째 경로(`appendWholeTable`)를 타지만
        /// 가로 자리는 같다 — 문단 기준 가운데 450pt 표 72.64, 오른쪽 300pt 표는 본문 오른쪽 끝.
        func testUnsplitTablesUseTheSamePlacement() async throws {
            let content = Self.geometry.contentFrame
            let frames = try await Self.tableFrames(of: [
                Self.unsplit(Self.host(width: 45000, alignment: .center)),
                Self.unsplit(Self.host(width: 30000, alignment: .bottomOrRight)),
            ])
            expect(frames.map(\.minX)).to(equal([
                content.minX + (content.width - 450) / 2, content.maxX - 300,
            ]))
            expect(frames.map(\.width)) == [450, 300]
        }

        /// 표 76 bits 0-1을 '나누지 않음'(0)으로 바꾼 문단 — `host`가 만든 표 컨트롤 하나를 고친다.
        static func unsplit(_ paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpParagraph {
            var paragraph = paragraph
            guard case var .table(table) = paragraph.ctrlHeaderArray?.first else {
                return paragraph
            }
            table.tableProperty.property &= ~UInt32(0b11)
            paragraph.ctrlHeaderArray = [.table(table)]
            return paragraph
        }

        /// 줄 앵커를 얻는 글자처럼 취급 표는 이 규칙을 타지 않는다 — 줄 시작(#254 넘친 줄)이다.
        func testInlineTablesStayOnTheirLine() async throws {
            let frames = try await Self.tableFrames(of: [
                Self.host(width: 45000, alignment: .bottomOrRight, treatAsChar: true),
            ])
            expect(frames.first?.minX).to(beCloseTo(Self.geometry.contentFrame.minX, within: 1e-6))
        }

        /// 줄 앵커를 **못 얻은** 글자처럼 취급 표(문단에 컨트롤 문자가 없다)는 흐름 경로로 폴백해도
        /// 앵커 규칙을 타지 않고 종전대로 단 왼쪽이다 — 공통 속성의 가로 기준·정렬은 자리 차지 표의
        /// 것이고, 글자처럼 취급 표에서는 줄 안 자리가 그것을 대신한다.
        func testInlineTablesWithoutALineAnchorStayAtTheColumnLeft() async throws {
            var host = try Self.host(width: 10000, alignment: .center, treatAsChar: true)
            host.paraText = try HwpSynthetic.textParagraph("앵커").paraText
            let frames = try await Self.tableFrames(of: [host])
            expect(frames.count) == 1
            expect(frames.first?.minX).to(beCloseTo(Self.geometry.contentFrame.minX, within: 1e-6))
        }

        /// 글상자 안 문단의 표는 그 글상자의 기하를 모르는 채 본문 흐름에 놓이므로 앵커 규칙을
        /// 적용하지 않고 종전대로 단 왼쪽이다 — 문단 기준 가운데 정렬을 본문 문단으로 풀면 엉뚱한
        /// 자리(한글은 글상자 안 가운데)에 놓인다.
        func testTablesInsideTextboxesStayAtTheColumnLeft() async throws {
            var textbox = try HwpSynthetic.inlineTextboxObject(width: 20000, height: 6000, text: "")
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try Self.host(width: 25000, alignment: .center),
            ]
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            host.ctrlHeaderArray = [.genShapeObject(textbox)]
            let frames = try await Self.tableFrames(of: [host])
            expect(frames.first?.minX).to(beCloseTo(Self.geometry.contentFrame.minX, within: 1e-6))
        }
    }
#endif
