import CoreHwp
import Foundation

/// 조판 중인 문단 하나의 번호 조회 열쇠 — 번호 표(`HwpParagraphNumbering`)와 그
/// 문단의 위치 경로(`HwpParagraphPath`) (#158).
///
/// 최상위 문단은 `HwpPaginator`가 위치 열쇠로 만들고, 컨테이너(표 셀·글상자·각주·
/// 미주·머리말/꼬리말) 안 문단은 그 컨테이너를 품은 문단의 열쇠에서 컨트롤 서수와
/// 자식 문단 서수를 이어 붙여 내려간다 (`container(controlIndex:)` →
/// `Container.paragraph(childIndex:)`). 자식 서수는 번호 생성기가 쓴
/// `HwpPaginator.childParagraphSequence(of:)`의 **평면** 서수와 같아야 하는데,
/// 컨테이너 레이아웃은 그 평면 목록이 아니라 셀·개체 요소·리스트 단위로 문단을
/// 열므로 `TableCells`·`textboxChildOffset`이 접두 합으로 그 서수를 복원한다 —
/// 두 순회가 같은 경로를 내는지는 `HwpNumberingScopeTests`가 컨테이너 종류마다
/// 잠근다. 표는 `cellArray` 순서로 셀을 펼치고, 개체는 개체 요소 순서로 글상자
/// 리스트를 펼치며, 각주·미주·머리말·꼬리말은 리스트 순서를 따른다.
///
/// 값 타입이고 번호 표는 불변이라 같은 문단을 몇 번 재측정·재배치해도 같은 번호가
/// 나온다 — 카운터는 표를 만들 때 한 번만 늘었다(#153).
struct HwpNumberingScope {
    let numbering: HwpParagraphNumbering
    let path: HwpParagraphPath

    /// 이 문단의 번호 — 없으면(머리 종류 0·3, 참조 없음·댕글링, 순회 상한) nil이라
    /// 조판은 글머리표만 본다.
    var number: HwpParagraphNumber? {
        numbering.number(at: path)
    }

    /// 이 문단의 `controlIndex`번째 컨트롤이 품은 자식 문단들의 열쇠.
    func container(controlIndex: Int) -> Container {
        Container(numbering: numbering, hostPath: path, controlIndex: controlIndex)
    }

    /// 컨트롤 하나가 품은 자식 문단들의 열쇠 — 자식 서수는
    /// `HwpPaginator.childParagraphSequence(of:)`의 평면 서수다.
    struct Container {
        let numbering: HwpParagraphNumbering
        let hostPath: HwpParagraphPath
        let controlIndex: Int

        /// `childIndex`번째 자식 문단의 열쇠.
        func paragraph(childIndex: Int) -> HwpNumberingScope {
            HwpNumberingScope(
                numbering: numbering,
                path: hostPath.appending(controlIndex: controlIndex, childIndex: childIndex)
            )
        }

        /// `childIndex`번째 자식 문단의 번호.
        func number(childIndex: Int) -> HwpParagraphNumber? {
            paragraph(childIndex: childIndex).number
        }

        /// 표 하나의 셀 문단 열쇠.
        func tableCells(of table: CoreHwp.HwpTable) -> TableCells {
            TableCells(container: self, table: table)
        }
    }

    /// 표 하나의 셀 문단 열쇠 — 셀은 `cellArray` 순서로, 셀 안 문단은 `paragraphArray`
    /// 순서로 펼친 서수라 셀마다 앞선 셀들의 문단 수를 접두 합으로 더한다.
    struct TableCells {
        let container: Container
        /// `cellArray` 서수 → 그 셀 첫 문단의 자식 서수.
        let offsets: [Int]

        init(container: Container, table: CoreHwp.HwpTable) {
            self.container = container
            offsets = HwpNumberingScope.tableCellOffsets(of: table)
        }

        /// `cellIndex`번째 셀(`cellArray` 서수)의 `paragraphIndex`번째 문단의 열쇠.
        func paragraph(cellIndex: Int, paragraphIndex: Int) -> HwpNumberingScope {
            let offset = offsets.indices.contains(cellIndex) ? offsets[cellIndex] : 0
            return container.paragraph(childIndex: offset + paragraphIndex)
        }
    }

    /// `cellArray` 서수 → 그 셀 첫 문단의 자식 서수 (접두 합).
    static func tableCellOffsets(of table: CoreHwp.HwpTable) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(table.cellArray.count)
        var offset = 0
        for cell in table.cellArray {
            offsets.append(offset)
            offset += cell.paragraphArray.count
        }
        return offsets
    }

    /// 개체 요소 `componentIndex`의 첫 글상자 리스트 첫 문단의 자식 서수 — 앞선
    /// 요소들의 글상자 문단 수를 전부 더한 값. 요소 안에서는 리스트 순서·문단 순서로
    /// 이어 센다 (`childParagraphSequence`가 요소 → 리스트 → 문단으로 펼친다).
    static func textboxChildOffset(
        components: [CoreHwp.HwpShapeComponent],
        componentIndex: Int
    ) -> Int {
        components.prefix(componentIndex).reduce(0) { partial, component in
            partial + component.textBoxListArray.reduce(0) { $0 + $1.paragraphArray.count }
        }
    }
}
