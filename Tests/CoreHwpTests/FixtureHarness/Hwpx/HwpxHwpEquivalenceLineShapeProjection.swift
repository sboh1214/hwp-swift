@testable import CoreHwp
import Foundation

/// 테두리·단 구분선 등가 투영 (#177) — `DocumentEquivalenceProjection`의 선 종류 축.
///
/// 본체에서 떼어 둔 것은 이 축이 **참조를 따라간 해석 결과**라서다 — 표 셀의
/// `borderFillId`(1-based)를 `borderFillArray`에서 풀어 네 방향·대각선의 종류·굵기를
/// 싣는다. 정의 배열을 순서대로 비교하지 않는 이유는 OLE·그림 축과 같다: id 공간은
/// 재저장이 재생성하므로 순서 등식은 유효한 쌍을 깨뜨릴 수 있다. 글자 모양의
/// 밑줄·취소선 모양은 `ResolvedRun`에 있다.
extension DocumentEquivalenceProjection {
    /// 표 셀 하나가 참조하는 테두리/배경의 선 (`LINETYPE2` 값 = `HwpBorderType` raw · 표 26 굵기 index).
    struct CellBorders: Equatable {
        /// 왼쪽/오른쪽/위쪽/아래쪽 선 종류 (NONE 0 · SOLID 1 · DOT 2 · DASH 3 …).
        let types: [UInt8]
        /// 같은 순서의 굵기 index.
        let thicknesses: [UInt8]
        /// 대각선 종류 — 한글은 대각선을 긋지 않는 기본 테두리/배경에도 `SOLID`(1)를 적는다.
        let diagonalType: UInt8
        /// 대각선 굵기 index.
        let diagonalThickness: UInt8
    }

    /// 단 정의 하나의 구분선 (`hp:colLine` ↔ `HwpColumn.dividerType`·굵기·색).
    struct ColumnDivider: Equatable {
        let type: UInt8
        let thickness: UInt8
        let color: HwpColor
    }

    /// 최상위 표의 셀을 문서 순서로 걷는다 — 셀 속성이 없을 때만 표의 참조로 폴백한다
    /// (`HwpTableLayoutFrames`가 셀 테두리를 푸는 규약과 같다). 참조 0(없음)과 댕글링
    /// 참조는 `nil`로 남겨 등식에 참여시킨다 — HWPX 매퍼가 댕글링을 0으로 접으므로
    /// 여기서 표 참조로 메우면 그 회귀가 숨는다.
    static func cellBorders(of file: HwpFile) -> [CellBorders?] {
        let fills = file.docInfo.idMappings.borderFillArray
        func resolve(_ id: UInt16) -> CellBorders? {
            guard id > 0, Int(id) <= fills.count else {
                return nil
            }
            let fill = fills[Int(id) - 1]
            return CellBorders(
                types: fill.borderType,
                thicknesses: fill.borderThickness,
                diagonalType: fill.diagonalType,
                diagonalThickness: fill.diagonalThickness
            )
        }
        return FixtureDerivedValues.tables(from: file).flatMap { table in
            table.cellArray.map { cell -> CellBorders? in
                resolve(cell.header.cellProperty?.borderFillId ?? table.tableProperty.borderFillId)
            }
        }
    }

    static func columnDividers(of file: HwpFile) -> [ColumnDivider] {
        FixtureDerivedValues.columns(from: file).map { column in
            ColumnDivider(
                type: column.dividerType,
                thickness: column.dividerThickness,
                color: column.dividerColor
            )
        }
    }
}
