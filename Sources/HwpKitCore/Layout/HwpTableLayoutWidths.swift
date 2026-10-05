import CoreGraphics
import CoreHwp
import Foundation

/// 표 폭 결정 (#254) — 레이아웃(`HwpTableLayout.layout`)과 줄 예약
/// (`HwpTextRunBuilder.inlineObjectReservation`)이 같은 규칙을 쓴다.
extension HwpTableLayout {
    /// 표의 바깥 폭과 칸 폭 (pt) — 한컴오피스 한글 12.30(build 6523) 실측 규칙 (#254).
    ///
    /// **표는 놓이는 자리의 폭으로 줄이지 않는다.** 한글은 본문·단·문단·셀·각주·글상자보다
    /// 넓은 표를 저작 폭 그대로 그려 오른쪽(정렬에 따라 왼쪽·양쪽)으로 넘긴다 — 합성 HWPX를
    /// 한글이 내보낸 PDF(2026-10-05, `probes/254`): 본문 425.2pt에 놓인 450·461.32·700pt 표,
    /// 셀 안폭 300pt의 350·700pt 중첩 표, 단 폭 201.26pt의 250·450pt 표, 각주·글상자 안의
    /// 450·250pt 표가 모두 저작 칸 폭(시험 칸 420·320pt)으로 그려졌다. 헌법주석 인쇄 666·667쪽의
    /// 419.54pt 자리 차지 표(단 408.2pt)도 칸 59.76 + 359.76pt다. 종전 클램프(f4237ba6)는 실측
    /// 근거 없이 들어와 그런 표의 칸을 비례로 줄였다.
    ///
    /// 폭의 출처는 셋이다.
    /// - **칸 폭 합이 표 폭이다** — 열마다 열 병합 1인 셀이 하나라도 있어 모든 칸 폭을 알면
    ///   바깥 폭 = 칸 폭 합 + 셀 간격 × (칸 수 + 1)이고 공통 속성의 저작 폭(표 69 `width`)은
    ///   보지 않는다. 한글은 저작 폭 450 / 칸 합 400인 표를 400으로, 400 / 450인 표를 450으로
    ///   그리고 다시 저장할 때 저작 폭을 칸 합으로 고쳐 쓴다(글자처럼 취급·자리 차지 모두).
    ///   한글이 저장한 문서는 둘이 늘 같다 (픽스처 표 162개 전부 0.5pt 안).
    /// - **크기 기준이 상대값(종이·쪽·단·문단)이면 그 기준 폭의 100%다** — 저장값(퍼센트로
    ///   읽히는 2500·5000·10000·11000, 한글이 다시 저장한 HWPUNIT 42520)과 무관하게 한글은
    ///   표를 기준 폭에 맞추고, 차이는 **첫 칸**이 흡수한다(칸 370 + 30 → 395.2 + 30, 문단 폭
    ///   325.2pt면 295.2 + 30, 칸 셋 100 + 270 + 30 → 125.2 + 270 + 30). 다시 저장한 파일은
    ///   그 폭을 HWPUNIT 절대값으로 쓰면서 기준은 그대로 두므로(문단 기준·42520), 저장값을
    ///   퍼센트로 읽으면 같은 표가 기준 폭의 4.25배가 된다 — 종전에는 클램프가 이를 우연히
    ///   가렸다. 기준 해석기가 없으면 기준 폭을 모르므로 절대값 규칙을 따른다.
    /// - 폭을 모르는 칸이 있으면 종전대로 저작 폭(없으면 `availableWidth`)을 나눠 채우고
    ///   칸 합이 그 폭과 0.5pt 넘게 다르면 비례로 맞춘다 (한글 미실측 — 픽스처에 그런 표는 없다).
    static func resolvedWidths(
        of table: CoreHwp.HwpTable,
        columnCount: Int,
        availableWidth: CGFloat,
        sizeResolver: HwpObjectSizeResolver?
    ) -> (outer: CGFloat, columns: [CGFloat]) {
        let spacing = TableMetrics(property: table.tableProperty).spacing
        let totalSpacing = spacing * CGFloat(columnCount + 1)
        var widths = authoredColumnWidths(of: table, columnCount: columnCount)
        let unknownCount = widths.filter { $0 <= 0 }.count
        if unknownCount == 0, !widths.isEmpty {
            let natural = widths.reduce(CGFloat(0), +) + totalSpacing
            guard let target = basisFittedWidth(of: table, sizeResolver: sizeResolver) else {
                return (natural, widths)
            }
            // 기준 폭 맞춤 — 차이는 첫 칸이 흡수한다. 첫 칸이 다 못 흡수하면(미실측) 비례로 나눈다.
            let difference = target - natural
            if widths[0] + difference >= 1 {
                widths[0] += difference
            } else {
                widths = proportionallyScaled(widths, to: max(1, target - totalSpacing))
            }
            return (target, widths)
        }

        let outerWidth = authoredWidthIgnoringColumns(of: table, sizeResolver: sizeResolver)
            ?? availableWidth
        let contentWidth = max(1, outerWidth - totalSpacing)
        let knownSum = widths.reduce(CGFloat(0), +)
        if unknownCount > 0 {
            let fallback = max(1, (contentWidth - knownSum) / CGFloat(unknownCount))
            widths = widths.map { $0 > 0 ? $0 : fallback }
        }
        // 저작된 폭 합계가 표 폭과 다르면 비례 배분으로 맞춘다.
        let sum = widths.reduce(CGFloat(0), +)
        if sum > 0, abs(sum - contentWidth) > 0.5 {
            widths = proportionallyScaled(widths, to: contentWidth)
        }
        return (outerWidth, widths)
    }

    /// 줄이 예약할 표 폭 (pt, 바깥 여백 제외) — 레이아웃(`resolvedWidths`)이 그릴 바깥 폭과
    /// 같은 값이다 (#254: 한글은 예약한 폭 그대로 그린다). 저작 폭이 없어 가용 폭으로
    /// 폴백할 표는 nil이다 (예약하지 않는다 — 종전과 같다).
    static func reservedWidth(
        of table: CoreHwp.HwpTable,
        sizeResolver: HwpObjectSizeResolver?
    ) -> CGFloat? {
        guard let grid = grid(of: table) else {
            return authoredWidthIgnoringColumns(of: table, sizeResolver: sizeResolver)
        }
        let columns = authoredColumnWidths(of: table, columnCount: grid.columns)
        guard columns.allSatisfy({ $0 > 0 }) else {
            return authoredWidthIgnoringColumns(of: table, sizeResolver: sizeResolver)
        }
        return resolvedWidths(
            of: table, columnCount: grid.columns, availableWidth: 0, sizeResolver: sizeResolver
        ).outer
    }

    /// 상대 크기 기준(종이·쪽·단·문단)의 저장값을 **100%**로 고친 저장값 — 한글은 표의 상대
    /// 폭을 늘 기준 폭에 맞춘다 (`resolvedWidths`). 해석기가 없으면 기준 폭을 모르므로 nil
    /// (저장값을 HWPUNIT으로 읽는다 — 한글이 다시 저장한 파일의 값이 그것이다).
    static func basisFittedWidth(
        of table: CoreHwp.HwpTable,
        sizeResolver: HwpObjectSizeResolver?
    ) -> CGFloat? {
        let basis = table.commonCtrlProperty.propertyInfo.widthRelativeTo
        guard let sizeResolver, let basis, basis != .absolute else { return nil }
        return sizeResolver.width(fullBasisWidthRaw, basis: basis)
    }

    /// 크기 기준 100% (표 70 상대 크기 저장값, 10000 = 100%).
    static let fullBasisWidthRaw: UInt32 = 10000

    /// 칸 폭을 모를 때 쓰는 공통 속성의 저작 폭 (pt) — 상대 기준은 기준 폭 100%
    /// (`basisFittedWidth`), 절대값은 HWPUNIT. 1pt 이하면 nil (가용 폭 폴백).
    fileprivate static func authoredWidthIgnoringColumns(
        of table: CoreHwp.HwpTable,
        sizeResolver: HwpObjectSizeResolver?
    ) -> CGFloat? {
        let property = table.commonCtrlProperty
        let authored = basisFittedWidth(of: table, sizeResolver: sizeResolver)
            ?? HwpUnits.points(fromHwpUnitU: property.width)
        return authored > 1 ? authored : nil
    }

    /// colSpan == 1 셀의 저작된 폭으로 복원한 칸 폭 — 그런 셀이 없는 칸은 0.
    fileprivate static func authoredColumnWidths(
        of table: CoreHwp.HwpTable,
        columnCount: Int
    ) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: columnCount)
        for cell in table.cellArray {
            guard let property = cell.header.cellProperty,
                  property.columnSpan == 1,
                  Int(property.columnAddress) < columnCount
            else { continue }
            let width = HwpUnits.points(fromHwpUnitU: property.width)
            guard width > 0 else { continue }
            widths[Int(property.columnAddress)] = max(widths[Int(property.columnAddress)], width)
        }
        return widths
    }

    fileprivate static func proportionallyScaled(
        _ widths: [CGFloat], to total: CGFloat
    ) -> [CGFloat] {
        let sum = widths.reduce(CGFloat(0), +)
        guard sum > 0 else { return widths }
        let scale = total / sum
        return widths.map { max(1, $0 * scale) }
    }
}
