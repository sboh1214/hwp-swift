import Foundation

/// 표 하나의 페인트 명령을 **채움 → 테두리 → 내용** 순으로 모은다 (#191 리뷰).
///
/// 셀 테두리는 셀 모서리에 중심을 둬 이웃 셀 안으로 t/2 걸치므로, walker의 셀 순서대로
/// (채움 → 테두리 → 내용)를 섞어 내면 나중 셀의 채움이 앞 셀 테두리의 바깥 절반을 덮어 선이
/// 반 굵기로 보인다. 그래서 한 표의 모든 셀 채움을 먼저, 테두리를 그 뒤에, 셀 내용(텍스트·
/// 개체·중첩 표)은 종전처럼 테두리 **위에** 낸다 — 히트(`HwpHitTester.tableHit`)가 내용 →
/// 칸막이 역순으로 훑는 페인트 역순 계약이 그대로 선다. 중첩 표는 자기 버퍼로 같은 순서를
/// 만들어 부모 셀 내용의 제 자리(walker가 방문한 위치)에 한 덩어리로 들어가므로, 각주처럼
/// 표가 글 뒤로/글 앞으로 평면 정렬에 끼는 컨테이너(R47 #1)에서도 표의 z 순서가 바뀌지
/// 않는다.
struct HwpTableCommandBuffer {
    private struct Table {
        var fills: [HwpPaintCommand] = []
        var borders: [HwpPaintCommand] = []
        var contents: [HwpPaintCommand] = []
        var commands: [HwpPaintCommand] {
            fills + borders + contents
        }
    }

    /// 열린 표 (안쪽이 뒤)
    private var stack: [Table] = []
    /// 열린 표가 없을 때 받은 명령 — 컨테이너(각주) 자신의 텍스트·개체
    private(set) var output: [HwpPaintCommand] = []

    /// 표 시작 (`onNestedTable`, 최상위 표는 순회 전에 한 번)
    mutating func beginTable() {
        stack.append(Table())
    }

    /// 표 끝 (`onNestedTableEnd`, 최상위 표는 순회 뒤에 한 번) — 모은 명령을 부모의 내용
    /// 자리(부모가 없으면 출력)에 붙인다
    mutating func endTable() {
        guard let table = stack.popLast() else { return }
        append(contentsOf: table.commands)
    }

    /// 셀 채움 (`onCellStart`)
    mutating func appendFill(_ command: HwpPaintCommand) {
        guard !stack.isEmpty else { return output.append(command) }
        stack[stack.count - 1].fills.append(command)
    }

    /// 셀 테두리 (`onCellStart`)
    mutating func appendBorders(_ commands: [HwpPaintCommand]) {
        guard !stack.isEmpty else { return output.append(contentsOf: commands) }
        stack[stack.count - 1].borders.append(contentsOf: commands)
    }

    /// 셀·컨테이너 내용 (텍스트·그림·도형·글상자)
    mutating func append(contentsOf commands: [HwpPaintCommand]) {
        guard !stack.isEmpty else { return output.append(contentsOf: commands) }
        stack[stack.count - 1].contents.append(contentsOf: commands)
    }

    mutating func append(_ command: HwpPaintCommand) {
        append(contentsOf: [command])
    }
}
