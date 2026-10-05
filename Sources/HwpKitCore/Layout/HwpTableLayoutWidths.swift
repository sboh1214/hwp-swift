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
    /// 한글이 내보낸 PDF(2026-10-05, `probes/254`): 본문 425.2pt에 놓인 450·700pt 표(셀 간격 표 포함),
    /// 셀 안폭 300pt의 350·700pt 중첩 표, 단 폭 201.26pt의 250·450pt 표, 각주·글상자 안의
    /// 450·250pt 표가 모두 저작 칸 폭(시험 칸 420·320·220pt)으로 그려졌다. 헌법주석 인쇄 666·667쪽의
    /// 419.54pt 자리 차지 표(단 408.2pt)도 칸 59.76 + 359.76pt다. 종전 클램프(f4237ba6)는 실측
    /// 근거 없이 들어와 그런 표의 칸을 비례로 줄였다.
    ///
    /// 폭의 출처는 셋이다. 칸 폭은 **배치가 받아들인 셀**(`accepted` — `acceptedCells`)에서만
    /// 읽는다 (`authoredColumnWidths`).
    /// - **칸 폭 합이 표 폭이다** — 열마다 열 병합 1인 셀이 하나라도 있어 모든 칸 폭을 알면
    ///   바깥 폭 = 칸 폭 합 + 셀 간격 × (칸 수 + 1)이고 공통 속성의 저작 폭(표 69 `width`)은
    ///   보지 않는다. 한글은 저작 폭 450 / 칸 합 400인 표를 400으로, 400 / 450인 표를 450으로
    ///   그리고 다시 저장할 때 저작 폭을 칸 합으로 고쳐 쓴다(글자처럼 취급·자리 차지 모두).
    ///   한글이 저장한 문서는 둘이 늘 같다 (2026-10-05 픽스처 표 204개 전부 0.5pt 안).
    /// - **크기 기준이 상대값(종이·쪽·단·문단)이면 그 기준 폭의 100%다** — 저장값(퍼센트로
    ///   읽히는 2500·5000·10000·11000, 한글이 다시 저장한 HWPUNIT 42520)과 무관하게 한글은
    ///   표를 기준 폭에 맞추고, 차이는 **첫 칸**이 흡수한다(칸 370 + 30 → 395.2 + 30, 문단 폭
    ///   325.2pt면 295.2 + 30, 칸 셋 100 + 270 + 30 → 125.2 + 270 + 30). 다시 저장한 파일은
    ///   그 폭을 HWPUNIT 절대값으로 쓰면서 기준은 그대로 두므로(문단 기준·42520), 저장값을
    ///   퍼센트로 읽으면 같은 표가 기준 폭의 4.25배가 된다 — 종전에는 클램프가 이를 우연히
    ///   가렸다. 기준 해석기가 없으면 기준 폭을 모르므로 절대값 규칙을 따른다.
    /// - 폭을 모르는 칸이 있으면 종전대로 저작 폭(없으면 `availableWidth`)을 나눠 채우고
    ///   칸 합이 그 폭과 0.5pt 넘게 다르면 비례로 맞춘다 (한글 미실측 — 픽스처에 그런 표는 없다).
    ///
    /// 칸 하나라도 1pt 하한에 걸려 칸 합(+ 셀 간격)이 선언 폭을 넘으면 바깥 폭은 그린 칸을 덮는다
    /// (`coveringWidth` — 한글 미실측).
    static func resolvedWidths(
        of table: CoreHwp.HwpTable,
        accepted: [AcceptedCell],
        columnCount: Int,
        availableWidth: CGFloat,
        sizeResolver: HwpObjectSizeResolver?
    ) -> (outer: CGFloat, columns: [CGFloat]) {
        let spacing = TableMetrics(property: table.tableProperty).spacing
        let totalSpacing = spacing * CGFloat(columnCount + 1)
        var widths = authoredColumnWidths(of: accepted, columnCount: columnCount)
        let unknownCount = widths.filter { $0 <= 0 }.count
        if unknownCount == 0, !widths.isEmpty {
            let natural = widths.reduce(CGFloat(0), +) + totalSpacing
            guard let target = basisFittedWidth(of: table, sizeResolver: sizeResolver) else {
                return (natural, widths)
            }
            // 기준 폭 맞춤 — 차이는 첫 칸이 흡수한다. 첫 칸이 다 못 흡수하면(미실측) 비례로 나눈다.
            let difference = target - natural
            guard widths[0] + difference < 1 else {
                widths[0] += difference
                return (target, widths)
            }
            widths = proportionallyScaled(widths, to: max(1, target - totalSpacing))
            return (coveringWidth(target, columns: widths, spacing: totalSpacing), widths)
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
        // 비례 배분 없이 돌아가는 길에도 하한이 걸린다 — 셀 간격이 저작 폭을 다 먹어 안쪽 폭이
        // 1pt로 올라가거나 빈 칸이 1pt로 채워져, 칸 합이 안쪽 폭의 0.5pt 안이어도 선언 폭을 넘는다.
        return (coveringWidth(outerWidth, columns: widths, spacing: totalSpacing), widths)
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
        let accepted = acceptedCells(of: table, rowCount: grid.rows, columnCount: grid.columns)
        let columns = authoredColumnWidths(of: accepted, columnCount: grid.columns)
        // 칸 폭을 다 모르면 저작 폭이 있어야 예약한다 — 그때 레이아웃의 바깥 폭은 저작 폭이고,
        // 칸이 1pt 하한에 걸린 표만 그린 칸 폭으로 넓어진다 (`coveringWidth`).
        guard columns.allSatisfy({ $0 > 0 })
            || authoredWidthIgnoringColumns(of: table, sizeResolver: sizeResolver) != nil
        else { return nil }
        return resolvedWidths(
            of: table, accepted: accepted, columnCount: grid.columns, availableWidth: 0,
            sizeResolver: sizeResolver
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

    /// 배치가 받아들인 열 병합 1인 셀의 저작된 폭으로 복원한 칸 폭 — 그런 셀이 없는 칸은 0.
    ///
    /// 셀은 **배치된 칸**에 쓴다(`placement.column`). `cellArray`의 주소를 그대로 읽으면 배치가
    /// 버린 셀(격자가 다 찬 뒤 범위 밖 주소를 가진 셀)이나 범위 밖 주소라 빈 칸으로 옮겨진 셀의
    /// 폭이 주소의 칸을 정해, 그리지 않는 셀이 표 폭과 줄 예약을 키운다 (#254 PR 리뷰 — 칸 폭 합이
    /// 표 폭이 된 뒤로는 그 폭이 그대로 그려진다). 저작 열 병합과 배치된 열 병합이 모두 1인
    /// 셀만 쓴다 — 마지막 칸에서 열 병합이 잘린 셀의 폭은 여러 칸의 몫이다.
    fileprivate static func authoredColumnWidths(
        of accepted: [AcceptedCell],
        columnCount: Int
    ) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: columnCount)
        for entry in accepted {
            let column = entry.placement.column
            guard let property = entry.cell.header.cellProperty,
                  property.columnSpan == 1, entry.placement.columnSpan == 1,
                  column < columnCount
            else { continue }
            let width = HwpUnits.points(fromHwpUnitU: property.width)
            guard width > 0 else { continue }
            widths[column] = max(widths[column], width)
        }
        return widths
    }

    /// 그린 칸(칸 합 + 셀 간격)을 덮는 바깥 폭 — 칸 폭의 1pt 하한(비례 배분 `proportionallyScaled`,
    /// 빈 칸 채우기, 셀 간격을 뺀 안쪽 폭)에 칸 하나라도 걸리면 칸 합이 선언 폭을 넘는데, 선언 폭을
    /// 그대로 돌려주면 행·셀 프레임이 바깥 상자를 넘고 줄 예약(`reservedWidth`)·가로 정렬이 그리는
    /// 폭보다 좁은 상자를 써 뒤 내용과 겹친다 (#254 PR 리뷰). 선언 폭이 칸 수 × 1pt + 셀 간격보다
    /// 좁을 때만이 아니다 — 문단 폭 50pt의 [1 | 100]pt 문단 기준 표는 첫 칸이 차이를 흡수하지 못해
    /// 비례로 줄면 첫 칸이 하한에 걸려 50.505pt가 된다. 한글 미실측이다. 하한에 걸리지 않으면 칸 합이
    /// 안쪽 폭과 같아 부동소수 오차(1e-6 미만)만 남으므로 선언 폭을 그대로 둔다.
    fileprivate static func coveringWidth(
        _ declared: CGFloat,
        columns: [CGFloat],
        spacing: CGFloat
    ) -> CGFloat {
        let drawn = columns.reduce(CGFloat(0), +) + spacing
        return drawn > declared + 1e-6 ? drawn : declared
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
