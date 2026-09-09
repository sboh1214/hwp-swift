import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽·단에 걸친 문단의 글자처럼 취급 표·개체는 **앵커가 있는 조각의 쪽·단**에 놓인다 (#164).
    ///
    /// 종전엔 문단의 모든 조각을 놓은 뒤 컨트롤을 한 번에 방출했다 — 앞 조각의 쪽은 그때
    /// 이미 확정돼 줄 앵커를 잃었고, 표는 마지막 조각 뒤 흐름 위치로 갔다. 절대 캐시
    /// 모드에서는 다음 문단이 캐시 y에 놓이므로 그 표가 다음 문단과 겹쳤다 (헌법주석
    /// 667쪽 — 실물 핀은 `HwpKitTests`의 `FixtureInlineTableFragmentTests`).
    final class HwpInlineControlFragmentTests: XCTestCase {
        // MARK: 합성 입력

        /// 절대 캐시 문서를 만들어 모든 쪽을 낸다 (`InlineControlFragmentSupport`).
        private static func pages(host: CoreHwp.HwpParagraph) async throws -> [HwpPage] {
            try await pages(of: try InlineControlFragmentSupport.absolutePaginator(host: host))
        }

        private static func inlineTable(instanceId: UInt32) throws -> CoreHwp.HwpCtrlId {
            try InlineControlFragmentSupport.inlineTable(instanceId: instanceId)
        }

        private static func objectBlocks(on page: HwpPage, instanceId: UInt32) -> [AnyHwpBlock] {
            InlineControlFragmentSupport.objectBlocks(on: page, instanceId: instanceId)
        }

        private static func hostFragment(on page: HwpPage) -> AnyHwpBlock? {
            InlineControlFragmentSupport.hostFragment(on: page)
        }

        private static func pages(of paginator: HwpPaginator) async throws -> [HwpPage] {
            try await InlineControlFragmentSupport.pages(of: paginator)
        }

        // MARK: 절대 캐시 (쪽 경계)

        /// 앞 조각의 표는 앞 쪽의 조각 줄 안에, 뒤 조각의 표는 뒤 쪽의 조각 줄 안에 —
        /// 각각 한 번씩만 놓이고 뒤 문단과 겹치지 않는다.
        func testEachFragmentPlacesItsOwnInlineTable() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                try Self.inlineTable(instanceId: 1),
                try Self.inlineTable(instanceId: 2),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            let first = try XCTUnwrap(Self.objectBlocks(on: pages[0], instanceId: 1).first)
            let firstHost = try XCTUnwrap(Self.hostFragment(on: pages[0]))
            let second = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 2).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))

            // 표는 자기 조각 블록 안 — 첫 줄(글자 5개 뒤) 위치다.
            expect(first.frame.minY).to(beGreaterThanOrEqualTo(firstHost.frame.minY - 0.01))
            expect(first.frame.maxY).to(beLessThanOrEqualTo(firstHost.frame.maxY + 0.01))
            expect(first.frame.minX) > firstHost.frame.minX + 1
            expect(second.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.minY - 0.01))
            expect(second.frame.maxY).to(beLessThanOrEqualTo(secondHost.frame.maxY + 0.01))
            expect(second.frame.minX) > secondHost.frame.minX + 1
            // 뒤 조각의 표는 종전처럼 뒤 문단 자리(4820 = 조각 아래)로 흘러 겹치지 않는다.
            for block in pages[1].blocks
                where block.kind == .text && block.attributedString?.string.contains("뒤 문단") == true
            {
                expect(second.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01))).to(beFalse())
            }
            // 누락도 중복도 없다.
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 1) }.count) == 1
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 2) }.count) == 1
            expect(Self.objectBlocks(on: pages[1], instanceId: 1)).to(beEmpty())
            expect(Self.objectBlocks(on: pages[0], instanceId: 2)).to(beEmpty())
        }

        /// 표가 아닌 글자처럼 취급 개체(도형)도 같은 앵커 경로(`appendInlineAnchoredBlock`)다.
        func testEachFragmentPlacesItsOwnInlineShapeObject() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 6000, height: 1000, instanceId: 11
                )),
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 6000, height: 1000, instanceId: 12
                )),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            let first = try XCTUnwrap(Self.objectBlocks(on: pages[0], instanceId: 11).first)
            let firstHost = try XCTUnwrap(Self.hostFragment(on: pages[0]))
            let second = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 12).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            expect(first.kind) == .shape
            expect(first.frame.minY).to(beGreaterThanOrEqualTo(firstHost.frame.minY - 0.01))
            expect(first.frame.maxY).to(beLessThanOrEqualTo(firstHost.frame.maxY + 0.01))
            expect(second.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.minY - 0.01))
            expect(second.frame.maxY).to(beLessThanOrEqualTo(secondHost.frame.maxY + 0.01))
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 11) }.count) == 1
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 12) }.count) == 1
        }

        /// 도형 컨트롤(`HwpShapeControl` — 사각형·타원·그림·수식 계열)도 조각별로 자기
        /// 줄 안에 놓인다. 묶음 개체와 달리 이쪽은 공통 속성이 optional이라 글자처럼
        /// 취급 판정과 방출이 별도 갈래이고, 그 갈래가 조각 경로에서 빠지면 도형이
        /// 앵커를 잃고 마지막 조각 뒤 흐름 위치로 간다.
        func testEachFragmentPlacesItsOwnInlineShapeControl() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                InlineControlFragmentSupport.inlineRectangle(instanceId: 21),
                InlineControlFragmentSupport.inlineRectangle(instanceId: 22),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            let first = try XCTUnwrap(Self.objectBlocks(on: pages[0], instanceId: 21).first)
            let firstHost = try XCTUnwrap(Self.hostFragment(on: pages[0]))
            let second = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 22).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            expect(first.kind) == .shape
            expect(second.kind) == .shape
            // 각 도형은 자기 조각의 줄 안에 있다 — 조각 블록의 세로 범위를 벗어나지 않는다.
            expect(first.frame.minY).to(beGreaterThanOrEqualTo(firstHost.frame.minY - 0.01))
            expect(first.frame.maxY).to(beLessThanOrEqualTo(firstHost.frame.maxY + 0.01))
            expect(second.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.minY - 0.01))
            expect(second.frame.maxY).to(beLessThanOrEqualTo(secondHost.frame.maxY + 0.01))
            // 앞 조각의 도형이 뒤 쪽으로 새거나 두 번 그려지지 않는다.
            expect(Self.objectBlocks(on: pages[1], instanceId: 21)).to(beEmpty())
            expect(Self.objectBlocks(on: pages[0], instanceId: 22)).to(beEmpty())
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 21) }.count) == 1
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 22) }.count) == 1
        }

        /// 마커가 없는 컨트롤(어느 조각의 줄에도 앵커가 없다)은 종전대로 마지막 조각 뒤
        /// 문단 단위 방출이 한 번만 놓는다 — 앞 조각이 가로채지도, 두 번 그리지도 않는다.
        func testControlWithoutMarkerIsPlacedOnceAfterTheLastFragment() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                try Self.inlineTable(instanceId: 1),
                try Self.inlineTable(instanceId: 2),
                try Self.inlineTable(instanceId: 3),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            expect(Self.objectBlocks(on: pages[0], instanceId: 1).count) == 1
            expect(Self.objectBlocks(on: pages[1], instanceId: 2).count) == 1
            // 마커 없는 표 3은 마지막 조각의 쪽에 흐름 위치로 한 번.
            expect(Self.objectBlocks(on: pages[0], instanceId: 3)).to(beEmpty())
            expect(Self.objectBlocks(on: pages[1], instanceId: 3).count) == 1
            let orphan = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 3).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            expect(orphan.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.maxY - 0.01))
        }

        /// 한 run(쪽 하나)에 머무는 문단은 종전 경로 그대로다 — 조각 배치가 끼어들지 않아
        /// 블록 순서(문단 텍스트 → 컨트롤 서수 순)가 불변이다.
        func testSingleRunParagraphKeepsWholeParagraphPlacement() async throws {
            var host = try HwpSynthetic.splitParagraphWithControlMarkers(
                lines: [(characters: 5, marker: true), (characters: 5, marker: true)],
                segments: [
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 14),
                ],
                markerCode: 11
            )
            host.ctrlHeaderArray = [
                try Self.inlineTable(instanceId: 1),
                try Self.inlineTable(instanceId: 2),
            ]
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let hostBlock = try XCTUnwrap(Self.hostFragment(on: page))
            // 구역 첫 문단 → 본문 문단 → 표 1·2 (서수 순) → 뒤 문단 둘.
            let bodyIds = page.blocks
                .filter { $0.role == .body }
                .map { $0.source?.controlInstanceId ?? 0 }
            expect(bodyIds).to(equal([0, 0, 1, 2, 0, 0]))
            for instanceId in UInt32(1) ... 2 {
                let table = try XCTUnwrap(Self.objectBlocks(on: page, instanceId: instanceId).first)
                expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.minY - 0.01))
                expect(table.frame.maxY).to(beLessThanOrEqualTo(hostBlock.frame.maxY + 0.01))
            }
        }

        /// 안에 각주를 품은 글자처럼 취급 글상자는 조각에서 놓지 않는다 — 그 각주는 조각
        /// 단위 귀속이 마지막 조각에서 걷어 그 쪽에 싣기 때문에, 개체만 앞 쪽에 두면
        /// 참조와 각주가 다른 쪽에 갈린다. 종전대로 마지막 조각 뒤 흐름 위치로 간다.
        func testObjectWithNestedFootnoteStaysWithTheLastFragment() async throws {
            var noteHost = try HwpSynthetic.textParagraph("글상자 안")
            noteHost.paraText?.charArray.append(CoreHwp.HwpChar(type: .extended, value: 17))
            noteHost.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 글상자 각주",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            var textbox = HwpSynthetic.inlineShapeObject(width: 6000, height: 1000, instanceId: 21)
            textbox.shapeComponentArray[0].textBoxListArray = [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [noteHost]
            )]
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .genShapeObject(textbox),
                try Self.inlineTable(instanceId: 2),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            // 글상자는 앞 조각 줄에 앵커가 있어도 마지막 조각 뒤(둘째 쪽 조각 아래)에 놓인다.
            expect(Self.objectBlocks(on: pages[0], instanceId: 21)).to(beEmpty())
            let textboxBlock = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 21).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            expect(textboxBlock.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.maxY - 0.01))
            // 그 각주도 같은 쪽(둘째 쪽)에 있다.
            let notes = pages.map { page in
                page.blocks.filter { $0.kind == .footnote }
                    .compactMap { $0.attributedString?.string }
            }
            expect(notes[0]).to(beEmpty())
            expect(notes[1].count) == 1
            expect(notes[1].first).to(contain("글상자 각주"))
            // 각주 없는 표는 여전히 자기 조각에 놓인다.
            expect(Self.objectBlocks(on: pages[1], instanceId: 2).count) == 1
        }

        /// 각주가 **한 겹 더 안쪽**(글상자 안 표의 셀)에 있어도 조각에서 놓지 않는다 —
        /// 노트 탐지가 중첩 컨트롤을 타고 내려가지 않으면 개체만 앞 쪽에 놓여 참조와
        /// 각주가 다른 쪽으로 갈린다. 바로 안쪽만 보는 판정으로는 못 잡는 경계다.
        func testObjectWithDeeplyNestedFootnoteStaysWithTheLastFragment() async throws {
            var noteHost = try HwpSynthetic.textParagraph("셀 안")
            noteHost.paraText?.charArray.append(CoreHwp.HwpChar(type: .extended, value: 17))
            noteHost.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 깊은 각주",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            // 글상자 문단은 각주가 아니라 **표**를 품는다 — 그 표의 셀에 각주가 있다.
            var wrapper = try HwpSynthetic.textParagraph("바깥")
            wrapper.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 3000, rowHeights: [500], cellParagraphs: [[[noteHost]]]
            ))]
            var textbox = HwpSynthetic.inlineShapeObject(width: 6000, height: 1000, instanceId: 41)
            textbox.shapeComponentArray[0].textBoxListArray = [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [wrapper]
            )]
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .genShapeObject(textbox),
                try Self.inlineTable(instanceId: 2),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            // 앞 조각 줄에 앵커가 있어도 마지막 조각 뒤로 미뤄진다.
            expect(Self.objectBlocks(on: pages[0], instanceId: 41)).to(beEmpty())
            let textboxBlock = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 41).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            expect(textboxBlock.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.maxY - 0.01))
            // 두 겹 안쪽의 각주도 개체와 같은 쪽에 실린다.
            let notes = pages.map { page in
                page.blocks.filter { $0.kind == .footnote }
                    .compactMap { $0.attributedString?.string }
            }
            expect(notes[0]).to(beEmpty())
            expect(notes[1].count) == 1
            expect(notes[1].first).to(contain("깊은 각주"))
            // 각주 없는 표는 여전히 자기 조각에 놓인다.
            expect(Self.objectBlocks(on: pages[1], instanceId: 2).count) == 1
        }

        /// 앞 조각과 함께 놓인 **미지원** 개체의 진단 쪽은 그 조각의 쪽이다 — 문단이 끝난
        /// 뒤 보고하는 `cachedPages.count + 1`(마지막 조각의 쪽)을 그대로 쓰면 사용자가
        /// 개체를 찾아갈 수 없는 쪽 번호가 나온다 (PR 리뷰).
        func testUnsupportedObjectReportsThePageItsFragmentWasPlacedOn() async throws {
            let object = HwpSynthetic.inlineShapeObject(width: 6000, height: 1000, instanceId: 31)
            var component = object.shapeComponentArray[0]
            component.oleArray = [CoreHwp.HwpShapeComponentOLE(
                rawPayload: Data(), binaryDataId: nil, rawTrailing: nil, unknownChildren: []
            )]
            let ole = CoreHwp.HwpShapeControl(
                ctrlId: .ole,
                commonCtrlProperty: object.commonCtrlProperty,
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [component],
                eqEditArray: [],
                eqEditRecords: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .ole(ole),
                try Self.inlineTable(instanceId: 2),
            ])
            let paginator = try InlineControlFragmentSupport.absolutePaginator(host: host)
            let pages = try await Self.pages(of: paginator)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            // 전제: OLE는 앞 쪽 조각의 줄 안에 실제로 놓였다.
            expect(Self.objectBlocks(on: pages[0], instanceId: 31).count) == 1
            expect(Self.objectBlocks(on: pages[1], instanceId: 31)).to(beEmpty())

            let unsupported = await paginator.unsupportedElements()
            let olePages = unsupported.filter { $0.hint.contains("OLE") }.map(\.page)
            expect(olePages) == [1]
        }

        /// BinData가 없는 글자처럼 취급 그림은 흐름 자리표시자로 폴백하므로 조각에서 놓지
        /// 않는다 — 조각 사이에서 흐름 블록이 쪽을 넘기면 절대 캐시 run 루프가 빈 쪽을
        /// 만든다. 종전대로 마지막 조각 뒤에 자리표시자를 한 번만 낸다.
        func testPictureWithoutDataIsNotPlacedPerFragment() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .genShapeObject(HwpSynthetic.inlinePictureObject(
                    width: 6000, height: 1000, binItemId: 9, instanceId: 31
                )),
                try Self.inlineTable(instanceId: 2),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            let placeholders = pages.map { page in
                page.blocks.filter { $0.attributedString?.string.contains("[이미지]") == true }
            }
            expect(placeholders[0]).to(beEmpty())
            expect(placeholders[1].count) == 1
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            let placeholder = try XCTUnwrap(placeholders[1].first)
            expect(placeholder.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.maxY - 0.01))
            expect(Self.objectBlocks(on: pages[1], instanceId: 2).count) == 1
        }

        /// 셀에 각주를 품은 글자처럼 취급 표 — 마커가 **마지막 조각**의 줄에 있으면 마지막
        /// 조각의 문맥으로 줄 안에 놓이는데, 줄 안 배치 경로가 셀 각주를 담지 않으면 그
        /// 각주가 통째로 빠진다 (종전엔 문맥이 없어 흐름 폴백이 담았다). 이제 줄 안 배치도
        /// 띠·세그먼트 경로처럼 표가 그려지는 쪽에 셀 각주를 담는다.
        func testInlineTableWithCellFootnoteKeepsItsFootnoteOnTheTablePage() async throws {
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.paraText?.charArray.append(CoreHwp.HwpChar(type: .extended, value: 17))
            cell.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 셀 각주",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            guard case var .table(noteTable) = try Self.inlineTable(instanceId: 8) else {
                fail("표가 아니다")
                return
            }
            noteTable.cellArray[0].paragraphArray = [cell]
            // 첫 줄의 표는 조각에서 놓고, 셋째 줄(마지막 조각)의 표는 각주를 품는다.
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                try Self.inlineTable(instanceId: 1),
                .table(noteTable),
            ])
            let pages = try await Self.pages(host: host)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }

            let table = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 8).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            // 줄 안에 놓였고 (조각 블록 안), 셀 각주는 같은 쪽에 한 번 있다.
            expect(table.frame.maxY).to(beLessThanOrEqualTo(secondHost.frame.maxY + 0.01))
            let notes = pages.map { page in
                page.blocks.filter { $0.kind == .footnote }
                    .compactMap { $0.attributedString?.string }
            }
            expect(notes[0]).to(beEmpty())
            expect(notes[1].count) == 1
            expect(notes[1].first).to(contain("셀 각주"))
        }
    }
#endif
