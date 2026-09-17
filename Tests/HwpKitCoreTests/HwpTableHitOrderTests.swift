import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 표 히트가 페인트 역순을 따르는지 (#191 리뷰) — 페인터(`HwpTableCommandBuffer`)는 표 하나를
    /// 모든 셀 채움 → 모든 셀 테두리 → 셀 내용 순으로 내므로, 히트는 모든 셀의 내용을 먼저 보고
    /// 그다음에야 어느 셀의 채움·칸막이든 가림으로 친다. 셀마다 섞어 보면 앞 셀에서 뒤 셀 자리로
    /// 넘친 개체(R44 #2)가 뒤 셀 채움 위에 그려졌는데 히트는 뒤 셀 채움에서 멈춘다.
    final class HwpTableHitOrderTests: XCTestCase {
        private static let black = HwpRGBColor(red: 0, green: 0, blue: 0)

        private static func cell(
            column: Int, fill: HwpRGBColor? = nil, images: [HwpCellImage] = [],
            nestedTables: [HwpNestedTableFrame] = [], width: CGFloat = 100
        ) -> HwpTableCellFrame {
            HwpTableCellFrame(
                cellFrame: CGRect(x: CGFloat(column) * 100, y: 0, width: width, height: 40),
                row: 0, column: column, rowSpan: 1, columnSpan: 1,
                paragraphs: [], borders: .uniform(width: 1, color: black),
                fillColor: fill, nestedTables: nestedTables, images: images
            )
        }

        private static func page(
            cells: [HwpTableCellFrame],
            tableFrame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 40)
        ) -> HwpPage {
            let table = HwpTableFrame(
                outerFrame: CGRect(origin: .zero, size: tableFrame.size),
                rows: [HwpTableRowFrame(
                    rowFrame: CGRect(origin: .zero, size: tableFrame.size), cells: cells
                )],
                borderColor: black, borderWidth: 1
            )
            return HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [
                    AnyHwpBlock(
                        frame: CGRect(x: 0, y: 0, width: 400, height: 100), kind: .text,
                        attributedString: NSAttributedString(string: "본문 링크"),
                        hyperlinkURL: "https://example.com/beneath"
                    ),
                    AnyHwpBlock(frame: tableFrame, kind: .table, payload: .table(table)),
                ],
                pageNumber: 1
            )
        }

        private static func wrappedImage(rect: CGRect) -> HwpCellImage {
            HwpCellImage(
                rect: rect, binItemId: 3, style: nil, clipRect: nil, controlInstanceId: 3,
                controlIndex: 0, paragraphId: 1
            ).withWrapperURL("https://example.com/img")
        }

        /// 앞 셀의 감싼 그림이 뒤 셀(채움 있음)로 넘치면 — 페인트는 그림이 채움 위 — 그 자리의 탭은
        /// 그림 링크다. 거울(뒤 셀 그림이 앞 셀로 넘침)도 같다.
        func testEarlierCellContentOverflowingALaterFilledCellIsHitFirst() {
            let yellow = HwpRGBColor(red: 255, green: 255, blue: 0)
            let forward = Self.page(cells: [
                Self.cell(column: 0, images: [
                    Self.wrappedImage(rect: CGRect(x: 60, y: 0, width: 50, height: 40)),
                ]),
                Self.cell(column: 1, fill: yellow),
            ])
            expect(HwpHitTester().hit(page: forward, point: CGPoint(x: 105, y: 20)))
                == .hyperlink(url: "https://example.com/img", blockIndex: 1)
            // 그림 밖의 뒤 셀 채움은 여전히 가림
            expect(HwpHitTester().hit(page: forward, point: CGPoint(x: 150, y: 20)))
                == .table(blockIndex: 1, row: 0, col: 1)
            let mirrored = Self.page(cells: [
                Self.cell(column: 0, fill: yellow),
                Self.cell(column: 1, images: [
                    Self.wrappedImage(rect: CGRect(x: 90, y: 0, width: 50, height: 40)),
                ]),
            ])
            expect(HwpHitTester().hit(page: mirrored, point: CGPoint(x: 95, y: 20)))
                == .hyperlink(url: "https://example.com/img", blockIndex: 1)
            // 그림이 앞 셀의 칸막이 띠(공유 모서리 100 ± 0.5)를 덮은 자리도 그림이다
            expect(HwpHitTester().hit(page: forward, point: CGPoint(x: 99.8, y: 20)))
                == .hyperlink(url: "https://example.com/img", blockIndex: 1)
        }

        /// 프레임 밖 칸막이 claim은 중첩 표의 칸막이도 든다 — 표 프레임 아래로 넘친 중첩 표의
        /// 아래 변 바깥 절반 위의 탭이 아래 문단 링크로 새지 않는다 (`HwpTableFrame.paints`)
        func testNestedTableBorderOutsideTheOuterFrameIsClaimed() {
            let nestedRect = CGRect(x: 10, y: 10, width: 80, height: 40) // 셀 아래로 10pt 넘침
            let nested = HwpNestedTableFrame(
                rect: nestedRect,
                table: HwpTableFrame(
                    outerFrame: CGRect(origin: .zero, size: nestedRect.size),
                    rows: [HwpTableRowFrame(
                        rowFrame: CGRect(origin: .zero, size: nestedRect.size),
                        cells: [HwpTableCellFrame(
                            cellFrame: CGRect(origin: .zero, size: nestedRect.size),
                            row: 0, column: 0, rowSpan: 1, columnSpan: 1, paragraphs: [],
                            borders: .uniform(width: 2, color: Self.black), fillColor: nil
                        )]
                    )],
                    borderColor: Self.black, borderWidth: 1
                ),
                controlInstanceId: 9
            )
            let page = Self.page(cells: [Self.cell(column: 0, nestedTables: [nested], width: 200)])
            // 중첩 표 아래 변: y 50 ± 1 — 표 프레임(높이 40) 밖
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 50.5)))
                == .table(blockIndex: 1, row: 0, col: 0)
            expect(HwpHitTester().hit(page: page, point: CGPoint(x: 50, y: 52)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
            // 중첩 표가 둘째 셀에 있으면 (행, 열)도 그 셀이다 — claim 판정과 같은 분해
            let shifted = nested.withRect(nestedRect.offsetBy(dx: 100, dy: 0))
            let second = Self.page(cells: [
                Self.cell(column: 0), Self.cell(column: 1, nestedTables: [shifted]),
            ])
            expect(HwpHitTester().hit(page: second, point: CGPoint(x: 150, y: 50.5)))
                == .table(blockIndex: 1, row: 0, col: 1)
        }

        /// 배치 하한(`paintedObjectBounds`)은 셀 테두리 바깥 절반을 더하지 않는다 — 히트 자격
        /// (`paintedRects`)만 넓어진다 (한글이 표 아래 각주 자리를 선 바깥 절반까지 재는지 미실측)
        func testPaintedObjectBoundsKeepTheCellRectWhileEligibilityWidens() {
            let page = Self.page(cells: [Self.cell(column: 0, width: 200)])
            let block = page.blocks[1]
            expect(HwpHitTester.paintedObjectBounds(of: block)) == block.frame
            expect(HwpHitTester().hitEligibleFrame(for: block))
                .to(equal(block.frame.insetBy(dx: -0.5, dy: -0.5)))
        }
    }
#endif
