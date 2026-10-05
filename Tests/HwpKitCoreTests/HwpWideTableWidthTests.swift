import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 표 폭 규칙 (#254) — 한글 12.30은 표를 놓이는 자리의 폭으로 줄이지 않고, 칸 폭 합을 표 폭으로
    /// 쓰며, 상대 기준 표는 저장값과 무관하게 기준 폭 100%로 맞춘다 (차이는 첫 칸이 흡수).
    /// 실측 근거는 `HwpTableLayout.resolvedWidths` doc-comment.
    final class HwpWideTableWidthTests: XCTestCase {
        private static let index = HwpIndex(from: CoreHwp.HwpFile())

        /// 1행 표 — 칸 폭(HWPUNIT)을 열마다 주고 공통 폭·기준을 따로 준다.
        static func table(
            columns: [UInt32],
            commonWidth: UInt32? = nil,
            basis: CoreHwp.HwpCommonCtrlObjectWidthRelativeTo = .absolute,
            cellSpacing: CoreHwp.HWPUNIT16 = 0
        ) throws -> CoreHwp.HwpTable {
            var table = HwpSynthetic.table(
                cellWidth: 1000,
                rowHeights: [1500],
                cellSpacing: cellSpacing,
                cellParagraphs: [try columns.map { _ in [try HwpSynthetic.textParagraph("가")] }]
            )
            for (index, width) in columns.enumerated() {
                table.cellArray[index].header.cellProperty?.width = width
            }
            if let commonWidth {
                table.commonCtrlProperty.width = commonWidth
            }
            table.commonCtrlProperty.propertyInfo.widthRelativeToRawValue = basis.rawValue
            table.commonCtrlProperty.propertyInfo.widthRelativeTo = basis
            // 줄 예약은 높이도 있어야 한다 (높이 기준 절대값, 15pt)
            table.commonCtrlProperty.height = 1500
            table.commonCtrlProperty.propertyInfo.heightRelativeToRawValue =
                CoreHwp.HwpCommonCtrlObjectHeightRelativeTo.absolute.rawValue
            table.commonCtrlProperty.propertyInfo.heightRelativeTo = .absolute
            return table
        }

        static let resolver = HwpObjectSizeResolver(
            paperSize: CGSize(width: 595.28, height: 841.86),
            contentSize: CGSize(width: 425.2, height: 700),
            columnWidth: 425.2,
            paragraphWidth: 325.2
        )

        static func frame(
            _ table: CoreHwp.HwpTable,
            availableWidth: CGFloat = 425.2,
            resolver: HwpObjectSizeResolver? = resolver
        ) throws -> HwpTableFrame {
            let result = HwpTableLayout(fontResolver: .testDeterministic).layout(
                table: table, availableWidth: availableWidth, index: index, sizeResolver: resolver
            )
            guard case let .success(frame) = result else {
                throw XCTSkip("표 레이아웃 실패")
            }
            return frame
        }

        static func columnWidths(_ frame: HwpTableFrame) -> [CGFloat] {
            frame.rows.first?.cells.map(\.cellFrame.width) ?? []
        }

        /// 한글: 본문 425.2pt에 놓인 450pt 표 [420 | 30]를 그대로 그린다 (종전: 425.2pt로 줄이고 칸을
        /// 396.85 + 28.35로 비례 축소). 셀 간격 2.83pt 표도 바깥 450·시험 칸 411.51pt.
        func testTableWiderThanTheAvailableWidthKeepsItsAuthoredColumns() throws {
            let wide = try Self.frame(Self.table(columns: [42000, 3000], commonWidth: 45000))
            expect(wide.outerFrame.width).to(beCloseTo(450, within: 1e-9))
            expect(Self.columnWidths(wide)).to(equal([420, 30]))
            let spaced = try Self.frame(Self.table(
                columns: [41151, 3000], commonWidth: 45000, cellSpacing: 283
            ))
            expect(spaced.outerFrame.width).to(beCloseTo(450, within: 1e-9))
            expect(Self.columnWidths(spaced)[0]).to(beCloseTo(411.51, within: 1e-9))
            // 셀 안폭(가용 폭) 300pt의 700pt 표도 그대로다
            let nested = try Self.frame(
                Self.table(columns: [67000, 3000], commonWidth: 70000), availableWidth: 300
            )
            expect(nested.outerFrame.width).to(beCloseTo(700, within: 1e-9))
        }

        /// 한글: 공통 폭 450 / 칸 합 400인 표는 400으로, 400 / 450인 표는 450으로 그리고, 다시 저장할
        /// 때 공통 폭을 칸 합으로 고친다 — 칸 폭 합이 표 폭이다.
        func testColumnWidthsDecideTheTableWidthOverTheCommonWidth() throws {
            let narrowCells = try Self.frame(Self.table(columns: [37000, 3000], commonWidth: 45000))
            expect(narrowCells.outerFrame.width).to(beCloseTo(400, within: 1e-9))
            expect(Self.columnWidths(narrowCells)).to(equal([370, 30]))
            let wideCells = try Self.frame(Self.table(columns: [42000, 3000], commonWidth: 40000))
            expect(wideCells.outerFrame.width).to(beCloseTo(450, within: 1e-9))
            expect(Self.columnWidths(wideCells)).to(equal([420, 30]))
        }

        /// 한글: 폭 기준이 '문단'인 표는 저장값(2500·5000·10000·11000, 한글이 다시 저장한 HWPUNIT
        /// 42520)과 무관하게 문단 폭 100%다 — 문단 폭 325.2pt면 칸 370 + 30이 295.2 + 30이 된다.
        /// '단'·'쪽'은 본문 425.2pt, '종이'는 595.28pt이고 칸 셋 [100 | 270 | 30]은 첫 칸만 는다.
        func testRelativeBasisFitsTheWholeBasisWithTheFirstColumnAbsorbing() throws {
            for raw: UInt32 in [2500, 5000, 10000, 11000, 42520] {
                let frame = try Self.frame(Self.table(
                    columns: [37000, 3000], commonWidth: raw, basis: .paragraph
                ))
                expect(frame.outerFrame.width)
                    .to(beCloseTo(325.2, within: 1e-9), description: "\(raw)")
                expect(Self.columnWidths(frame)[0])
                    .to(beCloseTo(295.2, within: 1e-9), description: "\(raw)")
                expect(Self.columnWidths(frame)[1]).to(equal(30), description: "\(raw)")
            }
            let expected: [(CoreHwp.HwpCommonCtrlObjectWidthRelativeTo, CGFloat)] = [
                (.column, 425.2), (.page, 425.2), (.paper, 595.28),
            ]
            for (basis, width) in expected {
                let frame = try Self.frame(Self.table(
                    columns: [37000, 3000], commonWidth: 5000, basis: basis
                ))
                expect(frame.outerFrame.width)
                    .to(beCloseTo(width, within: 1e-9), description: "\(basis)")
            }
            let three = try Self.frame(Self.table(
                columns: [10000, 27000, 3000], commonWidth: 5000, basis: .column
            ))
            let widths = Self.columnWidths(three)
            expect(widths[0]).to(beCloseTo(125.2, within: 1e-9))
            expect(Array(widths.dropFirst())).to(equal([270, 30]))
        }

        /// 기준 해석기가 없으면 기준 폭을 모르므로 칸 폭 합이다 (공개 `layout`을 해석기 없이 부른 경우).
        func testRelativeBasisWithoutAResolverUsesTheColumnWidths() throws {
            let table = try Self.table(columns: [37000, 3000], commonWidth: 5000, basis: .paragraph)
            let frame = try Self.frame(table, resolver: nil)
            expect(frame.outerFrame.width).to(beCloseTo(400, within: 1e-9))
        }

        /// 첫 칸이 차이를 다 흡수하지 못하면(1pt 미만이 되면 — 한글 미실측) 비례로 나눈다.
        func testFirstColumnTooNarrowToAbsorbFallsBackToProportionalScaling() throws {
            let frame = try Self.frame(Self.table(
                columns: [5000, 40000], commonWidth: 10000, basis: .paragraph
            ))
            expect(frame.outerFrame.width).to(beCloseTo(325.2, within: 1e-9))
            let widths = Self.columnWidths(frame)
            expect(widths[0]).to(beCloseTo(325.2 * 50 / 450, within: 1e-9))
            expect(widths[1]).to(beCloseTo(325.2 * 400 / 450, within: 1e-9))
        }

        /// 줄 예약 폭은 레이아웃이 그릴 바깥 폭과 같다 — 한글은 예약한 폭 그대로 그린다. 칸 폭을 모르고
        /// 공통 폭도 없는 표만 예약하지 않는다 (가용 폭 폴백).
        func testReservedWidthEqualsTheLaidOutWidth() throws {
            let tables = [
                try Self.table(columns: [42000, 3000], commonWidth: 45000),
                try Self.table(columns: [37000, 3000], commonWidth: 45000),
                try Self.table(columns: [41151, 3000], commonWidth: 45000, cellSpacing: 283),
                try Self.table(columns: [37000, 3000], commonWidth: 42520, basis: .paragraph),
                try Self.table(columns: [37000, 3000], commonWidth: 5000, basis: .paper),
            ]
            for table in tables {
                let reserved = HwpTableLayout.reservedWidth(of: table, sizeResolver: Self.resolver)
                expect(reserved).to(beCloseTo(try Self.frame(table).outerFrame.width, within: 1e-9))
            }
            var unknown = try Self.table(columns: [0, 0], commonWidth: 0)
            unknown.commonCtrlProperty.width = 0
            expect(HwpTableLayout.reservedWidth(of: unknown, sizeResolver: Self.resolver))
                .to(beNil())
            expect(try Self.frame(unknown).outerFrame.width).to(beCloseTo(425.2, within: 1e-9))
        }

        /// 글자처럼 취급 상대 기준 표의 줄 예약은 **100%**로 다시 풀리는 열쇠를 싣는다 — 다른 단으로
        /// 이월된 조각이 저장값을 퍼센트로 읽으면(42520 → 425%) 예약이 기준 폭의 4.25배가 된다.
        func testInlineRelativeTableReservationRescalesAsTheFullBasis() throws {
            var table = try Self.table(columns: [37000, 3000], commonWidth: 42520, basis: .column)
            table = HwpSynthetic.placed(table, treatAsChar: true)
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "뒤")
            paragraph.ctrlHeaderArray = [.table(table)]
            let built = HwpTextRunBuilder(
                index: Self.index, fontResolver: .testDeterministic, sizeResolver: Self.resolver
            ).build(paragraph: paragraph)
            let marker = (built.string as NSString).range(of: "\u{FFFC}").location
            let raw = built.attribute(
                HwpAttributedStringKey.inlineObjectWidthRaw, at: marker, effectiveRange: nil
            ) as? NSNumber
            expect(raw?.uint32Value) == HwpTableLayout.fullBasisWidthRaw
            let narrow = HwpObjectSizeResolver(
                paperSize: Self.resolver.paperSize, contentSize: Self.resolver.contentSize,
                columnWidth: 200
            )
            let rescaled = HwpInlineObjectReservation.rescaledForColumn(built, resolver: narrow)
            let line = CTLineCreateWithAttributedString(
                rescaled.attributedSubstring(from: NSRange(location: marker, length: 1))
            )
            expect(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
                .to(beCloseTo(200, within: 1e-6))
        }
    }
#endif
