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
            _ text: String, at location: Int32
        ) throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph(text, segments: [(location: location, height: 1000)])
        }

        /// 캐시 줄 하나 + 자리 차지 표 컨트롤을 품은 문단 (본문은 컨트롤 문자뿐)
        private static func tableHost(
            at location: Int32,
            rowHeight: UInt32 = 3000,
            margins: [CoreHwp.HWPUNIT16] = [283, 283, 283, 283],
            treatAsChar: Bool = false,
            textWrap: CoreHwp.HwpCommonCtrlTextWrap = .topAndBottom,
            verticalRelativeTo: CoreHwp.HwpCommonCtrlVerticalRelativeTo = .paragraph,
            verticalOffset: Int32 = 0
        ) throws -> CoreHwp.HwpParagraph {
            var host = try cached("", at: location)
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 11)]
            host.paraText = paraText
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: [rowHeight],
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
            host: CoreHwp.HwpParagraph? = nil
        ) throws -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [
                    try cached("앞 문단", at: 1600),
                    try host ?? tableHost(at: hostLocation),
                    try cached("뒤 문단", at: hostLocation + 1600),
                ]
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
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
