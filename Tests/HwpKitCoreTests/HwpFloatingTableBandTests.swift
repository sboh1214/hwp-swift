import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 자리 차지(위·아래 배치) 표의 띠 배치 (#161) — 합성 입력으로 판정 경계를 잠근다.
    ///
    /// 한컴오피스 한글 12.30 저장본은 세로 기준이 '문단'인 자리 차지 표를 그 문단의
    /// 글줄 **앞**에 두고 문단 줄을 표 높이 + 위·아래 바깥 여백만큼 내린다. 그 결정은
    /// 줄 캐시의 간격으로 남는다. 2007 계열 저장본은 반대로 표를 글줄 **뒤**에 두고
    /// 간격을 비우지 않는다 — 같은 술어가 두 저장본을 갈라야 한다.
    /// 실물 핀은 `HwpKitTests`의 `FixtureFloatingTableBandTests`(numbering-sequence 쌍)다.
    final class HwpFloatingTableBandTests: XCTestCase {
        /// 캐시 줄 하나짜리 문단 (단위 HWPUNIT — 줄 높이 1000 + 줄 간격 600 = 16pt 전진)
        private static func cached(
            _ text: String, at location: Int32, paraShapeId: UInt16? = nil
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.lineSegParagraph(
                text, segments: [(location: location, height: 1000)]
            )
            if let paraShapeId {
                paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: paraShapeId, paraStyleId: 0
                )
            }
            return paragraph
        }

        /// 캐시 줄 하나 + 자리 차지 표 컨트롤을 품은 문단 (본문은 컨트롤 문자뿐)
        private static func tableHost(
            at location: Int32,
            rowHeight: UInt32 = 3000,
            margins: [CoreHwp.HWPUNIT16] = [283, 283, 283, 283],
            treatAsChar: Bool = false,
            textWrap: CoreHwp.HwpCommonCtrlTextWrap = .topAndBottom,
            verticalRelativeTo: CoreHwp.HwpCommonCtrlVerticalRelativeTo = .paragraph,
            verticalOffset: Int32 = 0,
            cellSpacing: CoreHwp.HWPUNIT16 = 0
        ) throws -> CoreHwp.HwpParagraph {
            var host = try cached("", at: location)
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 11)]
            host.paraText = paraText
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: [rowHeight],
                    cellSpacing: cellSpacing,
                    cellParagraphs: [[[try HwpSynthetic.textParagraph("셀")]]]
                ),
                treatAsChar: treatAsChar,
                verticalRelativeTo: verticalRelativeTo,
                verticalOffset: verticalOffset,
                textWrap: textWrap,
                margins: margins
            ))]
            return host
        }

        /// 캐시가 절대 y인 문단 3개 (앞·표를 품은 문단·뒤)로 만든 조판기.
        /// `hostLocation`이 앞 문단이 끝난 자리(3200)에서 얼마나 떨어졌는지가 띠다.
        private static func paginator(
            hostLocation: Int32,
            host: CoreHwp.HwpParagraph? = nil,
            index: HwpIndex = HwpIndex(from: CoreHwp.HwpFile()),
            precedingParaShapeId: UInt16? = nil,
            precedingIsCached: Bool = true
        ) throws -> HwpPaginator {
            let preceding: CoreHwp.HwpParagraph = if precedingIsCached {
                try cached("앞 문단", at: 1600, paraShapeId: precedingParaShapeId)
            } else {
                // 캐시 없는 문단 — 같은 문서 안에서도 흐름 배치를 탄다.
                try HwpSynthetic.styledParagraph("앞 문단", paraShapeId: precedingParaShapeId ?? 0)
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [
                    preceding,
                    try host ?? tableHost(at: hostLocation),
                    try cached("뒤 문단", at: hostLocation + 1600),
                ]
            )
            return HwpPaginator(
                sections: [section],
                index: index,
                fontResolver: .testDeterministic
            )
        }

        /// 첫 쪽 본문 블록의 종류·문자열·프레임
        private struct Placed {
            let kind: HwpBlockKind
            let text: String
            let frame: CGRect
        }

        private static func blocks(of paginator: HwpPaginator) async throws -> [Placed] {
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            return page.blocks.filter { $0.role == .body }.map {
                Placed(
                    kind: $0.kind,
                    text: ($0.attributedString?.string ?? "")
                        .replacingOccurrences(of: "\r", with: ""),
                    frame: $0.frame
                )
            }
        }

        // MARK: 띠가 있는 저장본 (한글 12.30 계열)

        /// 캐시가 표 높이 + 바깥 여백 이상을 비워 두었으면 표는 그 띠에 놓이고,
        /// 문단의 자기 줄과 다음 문단은 캐시 자리 그대로 남아 겹치지 않는다.
        func testTableGoesIntoTheBandTheCacheReservedBeforeTheHostLine() async throws {
            let blocks = try await Self.blocks(of: try Self.paginator(hostLocation: 10000))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let host = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            let before = try XCTUnwrap(blocks.first { $0.text == "앞 문단" })
            let after = try XCTUnwrap(blocks.first { $0.text == "뒤 문단" })

            // 표는 앞 문단이 끝난 자리 + 위쪽 바깥 여백 2.83pt에서 시작한다.
            expect(table.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            // 표 아래에 아래쪽 바깥 여백을 두고도 문단 줄 앞에서 끝난다.
            expect(table.frame.maxY + 2.83).to(beLessThanOrEqualTo(host.frame.minY + 0.01))
            // 캐시 자리는 표와 무관하게 그대로다 (앞 문단 16pt, 문단 줄 100pt, 뒤 116pt).
            expect(host.frame.minY - before.frame.minY).to(beCloseTo(84, within: 0.01))
            expect(after.frame.minY - host.frame.minY).to(beCloseTo(16, within: 0.01))
            // 어떤 본문 블록과도 겹치지 않는다.
            for block in blocks where block.kind != .table {
                expect(table.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01)))
                    .to(beFalse(), description: block.text)
            }
            // 블록 배열 순서는 문서 순서 그대로다 (선택·복사 단위 순서).
            expect(blocks.map(\.kind)).to(equal([.text, .text, .text, .table, .text]))
        }

        // MARK: 띠가 없는 저장본 (2007 계열) · 조건 미달

        /// 캐시가 간격을 비우지 않았으면(2007 계열) 표는 종전대로 문단 글줄 **뒤**에
        /// 흐름 위치로 간다 — 그 저장본에서는 그 자리가 맞다.
        func testTableStaysAfterTheHostLineWhenTheCacheReservedNothing() async throws {
            let blocks = try await Self.blocks(of: try Self.paginator(hostLocation: 3200))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let host = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(host.frame.maxY - 0.01))
        }

        /// 띠가 표보다 좁으면 (표 30pt + 여백 5.66pt > 간격 18.48pt) 판정하지 않는다.
        func testTableStaysAfterTheHostLineWhenTheBandIsTooNarrow() async throws {
            let blocks = try await Self.blocks(of: try Self.paginator(hostLocation: 5048))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let host = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(host.frame.maxY - 0.01))
        }

        /// 세로 오프셋이 0이 아니면 저작이 자리를 직접 지정한 것이라 띠 판정에서 뺀다.
        func testTableWithVerticalOffsetIsNotBanded() async throws {
            let host = try Self.tableHost(at: 10000, verticalOffset: 500)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// 한 문단에 조건을 만족하는 표가 둘이면 띠를 **나눠** 쓴다 — 둘째 표는 첫째
        /// 표 아래(여백 포함)에서 시작하고, 남은 띠에 안 들어가면 종전 흐름 배치로 간다.
        func testSecondTableInTheSameParagraphDoesNotReuseTheBand() async throws {
            var host = try Self.tableHost(at: 10000)
            let second = try Self.tableHost(at: 10000)
            host.ctrlHeaderArray = (host.ctrlHeaderArray ?? []) + (second.ctrlHeaderArray ?? [])
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host
            ))
            let tables = blocks.filter { $0.kind == .table }
            expect(tables.count).to(equal(2))
            guard tables.count == 2 else { return }
            // 두 표가 같은 자리에 겹치지 않는다.
            expect(tables[0].frame.intersects(tables[1].frame.insetBy(dx: 0, dy: 0.01)))
                .to(beFalse())
            // 첫 표만 띠에 들어간다 (30 + 2.83 × 2 = 35.66pt짜리 둘은 68pt 띠에 못 든다).
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            let before = try XCTUnwrap(blocks.first { $0.text == "앞 문단" })
            expect(tables[0].frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(tables[1].frame.minY)
                .to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// 어울림(`square`) 표는 띠 대상이 아니다 — 한글은 그 표 **옆**으로 글을 흘리므로
        /// 위·아래 배치의 띠 규칙을 실측한 적이 없다 (`consumesFlow`는 둘을 함께 담는다).
        func testSquareWrapTableIsNotBanded() async throws {
            let host = try Self.tableHost(at: 10000, textWrap: .square)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// 앞선 표가 띠에 못 들어가 흐름(글줄 뒤)으로 갔으면, 그 뒤 표는 남은 띠를 쓰지
        /// 않는다 — 쓰면 뒤 표가 앞 표보다 **위에** 그려져 문서 순서가 뒤집힌다.
        func testTableAfterAFlowFallbackDoesNotRewindIntoTheBand() async throws {
            // 첫 표 65pt + 여백 5.66 > 띠 68pt → 흐름으로. 둘째 표 30pt는 띠에 들어간다.
            var host = try Self.tableHost(at: 10000, rowHeight: 6500)
            let second = try Self.tableHost(at: 10000, rowHeight: 3000)
            host.ctrlHeaderArray = (host.ctrlHeaderArray ?? []) + (second.ctrlHeaderArray ?? [])
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host
            ))
            let tables = blocks.filter { $0.kind == .table }
            expect(tables.count).to(equal(2))
            guard tables.count == 2 else { return }
            // 문서 순서 = 그리는 순서: 둘째 표가 첫째 표보다 위로 가면 안 된다.
            expect(tables[1].frame.minY)
                .to(beGreaterThanOrEqualTo(tables[0].frame.minY - 0.01))
        }

        /// 저작 문단 위 간격은 캐시 줄 위치에 이미 들어 있다 — 그 몫까지 표 자리로 세면
        /// 문단이 의도한 여백에 표가 들어간다. 간격을 뺀 나머지가 띠다.
        func testAuthoredParagraphSpacingIsNotCountedAsBand() async throws {
            // 간격 13600 HWPUNIT → beforeGap 68pt = 캐시 간격 전부. 남는 띠는 0이다.
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 13600, tabDefId: 0
                ),
            ])
            var host = try Self.tableHost(at: 10000)
            host.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 7, paraStyleId: 0)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host, index: index
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// **앞 문단**의 저작 아래 여백도 캐시 간격에 들어 있다 — 절대 캐시 블록 높이는
        /// 줄 위치·높이만으로 만들어져 그 몫을 담지 않으므로, 빼지 않으면 앞 문단이
        /// 의도한 여백을 표 자리로 오인한다.
        func testPrecedingParagraphBottomSpacingIsNotCountedAsBand() async throws {
            // 앞 문단 아래 간격 13600 HWPUNIT → 68pt = 캐시 간격 전부. 남는 띠는 0이다.
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingBottom: 13600, tabDefId: 0
                ),
            ])
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, index: index, precedingParaShapeId: 7
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// **앞 문단이 흐름 배치**됐으면 그 아래 간격은 이미 커서가 소비했다 — 또 빼면
        /// 같은 여백이 두 번 빠져 유효한 띠가 좁다고 오판되고, 표가 글줄 뒤로 밀려
        /// 절대 캐시로 고정된 뒷 문단을 덮는다.
        func testFlowPlacedPredecessorSpacingIsNotSubtractedTwice() async throws {
            // 앞 문단(캐시 없음) 아래 간격 4000 HWPUNIT = 20pt. 캐시 간격 48pt는
            // 표 30 + 여백 5.66 = 35.66pt를 담고도 남는다.
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingBottom: 4000, tabDefId: 0
                ),
            ])
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, index: index,
                precedingParaShapeId: 7, precedingIsCached: false
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let before = try XCTUnwrap(blocks.first { $0.text == "앞 문단" })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            // 흐름 블록이 아래 간격까지 소비했으므로 띠는 그 블록 하단부터다.
            expect(table.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(hostBlock.frame.minY + 0.01))
            for block in blocks where block.kind != .table {
                expect(table.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01)))
                    .to(beFalse(), description: block.text)
            }
        }

        /// 띠 적합성은 **실제로 방출하는 높이**로 잰다 — `cellSpacing`이 있는 표는
        /// `rowFrame.maxY` 최댓값이 선행 간격 한 칸을 더 담아, 방출되는 블록이 들어가는
        /// 띠를 거부하고 표를 글줄 뒤로 보내 뒷 문단을 덮는다.
        func testBandFitUsesTheEmittedHeightForSpacedTables() async throws {
            // 간격 36pt 띠 · 표 방출 높이 30pt + 여백 5.66pt = 35.66pt는 들어간다.
            // cellSpacing 283이 판정에만 더해지면 38.49pt가 돼 거부된다.
            let host = try Self.tableHost(at: 6800, cellSpacing: 283)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 6800, host: host
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let before = try XCTUnwrap(blocks.first { $0.text == "앞 문단" })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beCloseTo(before.frame.maxY + 2.83, within: 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(hostBlock.frame.minY + 0.01))
            for block in blocks where block.kind != .table {
                expect(table.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01)))
                    .to(beFalse(), description: block.text)
            }
        }

        /// 문서가 절대 캐시 모드여도 **이 문단**이 캐시 없이 흐름 배치됐으면 판정하지
        /// 않는다 — 그 간격은 한글이 표에 내준 띠가 아니라 문단 위 간격이다.
        func testFlowPlacedParagraphInAnAbsoluteCacheDocumentIsNotBanded() async throws {
            // 문단 위 간격 8000 HWPUNIT → beforeGap 40pt > 표 30 + 여백 5.66pt
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 8000, tabDefId: 0
                ),
            ])
            var host = try Self.tableHost(at: 10000)
            host.paraLineSeg.paraLineSegInternalArray = [] // 캐시 없음 → 흐름 배치
            host.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 7, paraStyleId: 0)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host, index: index
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }

        /// 세로 기준이 '쪽'인 표도 뺀다 — 그 오프셋은 쪽 상단 기준 절대 좌표다.
        func testTableRelativeToPageIsNotBanded() async throws {
            let host = try Self.tableHost(at: 10000, verticalRelativeTo: .page)
            let blocks = try await Self.blocks(of: try Self.paginator(
                hostLocation: 10000, host: host
            ))
            let table = try XCTUnwrap(blocks.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(blocks.first { $0.text == "\u{FFFC}" })
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(hostBlock.frame.maxY - 0.01))
        }
    }
#endif
