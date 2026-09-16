import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 흐름 배치 문단의 자리 차지(위·아래 배치) 표는 문단 글줄 **앞**에 놓인다 (#190) —
    /// 합성 입력으로 순서·조각·여백·경계를 잠근다.
    ///
    /// 한컴오피스 한글 12.30은 세로 기준이 '문단'인 자리 차지 표를 그 문단의 글줄 위에
    /// 두고, 표가 단·쪽을 넘으면 뒤 조각을 다음 단 첫머리(위 바깥 여백 뒤)에 세운 뒤
    /// 글줄을 마지막 조각 아래(아래 바깥 여백 뒤)에 놓는다. 아래 여백은 조각의 적합
    /// 판정에도 든다. 절대 캐시 배치 문단(1단 + 줄 캐시)은 캐시 간격이 자리라 띠 판정
    /// (`HwpFloatingTableBandTests`, #161)이 맡고, 여기는 흐름 배치 — 다단 밴드와 캐시
    /// 없는 문단 — 를 본다. 실물 핀은 `HwpKitTests`의 `FixtureFloatingTableBandTests`
    /// (`line-shapes` 2단 쌍)다.
    final class HwpFloatingTablePrecedesTextTests: XCTestCase {
        private typealias Support = FloatingTablePrecedesTextSupport

        // MARK: 2단 밴드 (line-shapes 꼴)

        /// 2단 문서에서 표는 문단 진입 자리(위 여백 뒤)에서 시작해 단을 넘고, 뒤 조각은 다음
        /// 단 상단 + 위 여백에서 서며, 글줄은 마지막 조각 아래 + 아래 여백을 따른다. 블록
        /// 순서도 표 → 글줄이다 (한글 12.30 `line-shapes` 실측: 1단 7행 / 2단 10행 / 글줄).
        func testTwoColumnTableSplitsAcrossColumnsBeforeItsParagraphLine() async throws {
            // 쪽 300pt → 본문 200.8pt. 템플릿 문단 + 앞 문단 둘(48pt) 뒤 9행(270pt) 표:
            // 1단 남은 자리에 위·아래 여백 5.66pt를 빼고 들어가는 4행만, 나머지 5행은
            // 2단 상단 + 2.83pt부터.
            let paginator = Support.paginator(columns: 2, pageHeight: 30000, bodyParagraphs: [
                try Support.flow("앞 문단 0"), try Support.flow("앞 문단 1"),
                try Support.host(rowCount: 9), try Support.flow("뒤 문단"),
            ])
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind))
                .to(equal([.text, .text, .text, .table, .table, .text, .text]))
            guard blocks.count == 7 else { return }
            let before = blocks[2], first = blocks[3], second = blocks[4]
            let host = blocks[5], after = blocks[6]
            expect(host.text).to(equal("\u{FFFC}table anchor"))
            let columnTop = blocks[0].frame.minY
            let columnBottom = columnTop + 200.8

            // 1단: 앞 문단 끝 + 위 여백에서 시작, 아래 여백까지 단에 들어가는 행만 담는다.
            expect(first.frame.minX).to(beCloseTo(before.frame.minX, within: 0.01))
            expect(first.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(first.frame.maxY + 2.83).to(beLessThanOrEqualTo(columnBottom + 0.01))
            expect(first.frame.maxY + 30 + 2.83).to(beGreaterThan(columnBottom))
            expect(first.rowCount + second.rowCount).to(equal(9))
            // 2단: 단 상단 + 위 여백에서 이어진다.
            expect(second.frame.minX).to(beGreaterThan(first.frame.maxX))
            expect(second.frame.minY).to(beCloseTo(columnTop + 2.83, within: 0.01))
            expect(second.frame.height).to(beCloseTo(CGFloat(second.rowCount) * 30, within: 0.01))
            // 글줄은 2단의 마지막 조각 아래 + 아래 여백, 뒤 문단은 그 아래.
            expect(host.frame.minX).to(beCloseTo(second.frame.minX, within: 0.01))
            expect(host.frame.minY).to(beCloseTo(second.frame.maxY + 2.83, within: 0.01))
            expect(after.frame.minY).to(beCloseTo(host.frame.maxY, within: 0.01))
        }

        // MARK: 1단 흐름 (캐시 없는 저장본)

        /// 1단 흐름 배치도 같다 — 표가 글줄 앞에 서고 글줄은 표 아래 + 아래 여백이다.
        func testFlowTablePrecedesItsParagraphLineInOneColumn() async throws {
            let paginator = Support.paginator(bodyParagraphs: [
                try Support.flow("앞 문단"), try Support.host(rowCount: 2), try Support.flow("뒤 문단"),
            ])
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .text, .table, .text, .text]))
            guard blocks.count == 5 else { return }
            let before = blocks[1], table = blocks[2], host = blocks[3], after = blocks[4]
            expect(table.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(table.frame.height).to(beCloseTo(60, within: 0.01))
            expect(host.frame.minY).to(beCloseTo(table.frame.maxY + 2.83, within: 0.01))
            expect(after.frame.minY).to(beCloseTo(host.frame.maxY, within: 0.01))
        }

        /// 표 뒤에서 글줄이 쪽에 안 들어가면 글줄만 다음 쪽으로 간다 — 문단을 다시 처리하면
        /// 표가 두 번 놓인다.
        func testParagraphLineOverflowingAfterTheTableMovesAloneToTheNextPage() async throws {
            // 쪽 400pt → 본문 300.8pt: 템플릿 + 앞 문단 둘(48) + 여백 2.83 + 8행 240 +
            // 여백 2.83 = 293.66 → 16pt 글줄은 안 들어간다 (9행이면 표부터 안 들어간다).
            let paginator = Support.paginator(pageHeight: 40000, bodyParagraphs: [
                try Support.flow("앞 문단 0"), try Support.flow("앞 문단 1"),
                try Support.host(rowCount: 8), try Support.flow("뒤 문단"),
            ])
            let first = try await Support.blocks(of: paginator)
            let second = try await Support.blocks(of: paginator, page: 1)
            expect(first.map(\.kind)).to(equal([.text, .text, .text, .table]))
            expect(first.last?.rowCount).to(equal(8))
            expect(second.map(\.kind)).to(equal([.text, .text]))
            expect(second.first?.text).to(equal("\u{FFFC}table anchor"))
            // 표는 두 쪽을 합쳐 하나뿐이다.
            expect((first + second).filter { $0.kind == .table }.count).to(equal(1))
        }

        /// 아래 바깥 여백은 조각의 적합 판정에 든다 (한글 실측: 여백 6pt에서 마지막 행이
        /// 남은 5.05pt에 들어가지 않아 다음 단으로 갔다).
        func testBottomOuterMarginCountsTowardTheSegmentFit() async throws {
            // 본문 200.8pt: 템플릿 문단 16 + 위 여백 2.83 → 181.97 남음. 아래 여백 6pt를
            // 빼면 175.97이라 6행(180)은 안 들어가고 5행(150)까지다. 여백을 안 빼면 6행이
            // 들어간다.
            let paginator = Support.paginator(pageHeight: 30000, bodyParagraphs: [
                try Support.host(rowCount: 6, margins: [283, 283, 283, 600]),
                try Support.flow("뒤 문단"),
            ])
            let first = try await Support.blocks(of: paginator)
            let second = try await Support.blocks(of: paginator, page: 1)
            expect(first.map(\.kind)).to(equal([.text, .table]))
            expect(first.last?.rowCount).to(equal(5))
            expect(second.map(\.kind)).to(equal([.table, .text, .text]))
            guard second.count == 3 else { return }
            expect(second[0].rowCount).to(equal(1))
            // 이어지는 조각도 쪽 상단 + 위 여백에서, 글줄은 그 아래 + 아래 여백 6pt에서.
            expect(second[0].frame.minY).to(beCloseTo(first[0].frame.minY + 2.83, within: 0.01))
            expect(second[1].frame.minY).to(beCloseTo(second[0].frame.maxY + 6, within: 0.01))
        }

        /// 글줄 앞에 표를 놓은 문단은 저작 문단 위 간격을 쓰지 않는다 (한글 실측: 위 간격
        /// 20pt를 준 문단의 표와 글줄이 간격 없는 문단과 같은 자리다).
        func testHostParagraphSpacingBeforeIsNotApplied() async throws {
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 4000, tabDefId: 0
                ),
            ])
            var spaced = try Support.host(rowCount: 2)
            spaced.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 7, paraStyleId: 0)
            var plainAfter = try Support.flow("뒤 문단")
            plainAfter.paraHeader = try HwpSynthetic.outlineParaHeader(
                paraShapeId: 7, paraStyleId: 0
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [try Support.flow("앞 문단"), spaced, plainAfter]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .text, .table, .text, .text]))
            guard blocks.count == 5 else { return }
            let before = blocks[1], table = blocks[2], host = blocks[3], after = blocks[4]
            // 표 앞에도, 표와 글줄 사이에도 20pt가 없다.
            expect(table.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(host.frame.minY).to(beCloseTo(table.frame.maxY + 2.83, within: 0.01))
            // 같은 문단 모양의 보통 문단은 종전대로 20pt 내려간다.
            expect(after.frame.minY).to(beCloseTo(host.frame.maxY + 20, within: 0.01))
        }

        // MARK: 대상이 아닌 표

        /// 어울림(`square`) 표는 종전대로 글줄 뒤 흐름 자리다 — 한글은 그 표 옆으로 글을
        /// 흘리므로 실측한 규칙이 없다.
        func testSquareWrapTableStaysAfterTheParagraphLine() async throws {
            let paginator = Support.paginator(bodyParagraphs: [
                try Support.flow("앞 문단"), try Support.host(rowCount: 2, textWrap: .square),
            ])
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .text, .text, .table]))
            guard blocks.count == 4 else { return }
            expect(blocks[3].frame.minY).to(beGreaterThanOrEqualTo(blocks[2].frame.maxY - 0.01))
        }

        /// 세로 오프셋이 있는 표는 저작이 자리를 직접 지정한 것이라 대상이 아니다.
        func testTableWithVerticalOffsetStaysAfterTheParagraphLine() async throws {
            let paginator = Support.paginator(bodyParagraphs: [
                try Support.flow("앞 문단"), try Support.host(rowCount: 2, verticalOffset: 500),
            ])
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .text, .text, .table]))
        }

        /// 글자처럼 취급 표는 줄 안 앵커 자리 그대로다.
        func testTreatAsCharTableKeepsItsInlineAnchor() async throws {
            let paginator = Support.paginator(bodyParagraphs: [
                try Support.flow("앞 문단"), try Support.host(rowCount: 1, treatAsChar: true),
            ])
            let blocks = try await Support.blocks(of: paginator)
            expect(blocks.map(\.kind)).to(equal([.text, .text, .text, .table]))
            guard blocks.count == 4 else { return }
            // 줄 안 앵커 — 문단 블록의 줄 자리에 놓여 문단 블록과 겹친다.
            expect(blocks[3].frame.minY).to(beLessThan(blocks[2].frame.maxY))
        }
    }
#endif
