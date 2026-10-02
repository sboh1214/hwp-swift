import Foundation

/// 표 하나의 페인트 명령을 **채움 → 테두리 → 내용** 순으로 모은다 (#191 리뷰).
///
/// 테두리는 표 안에서 한글의 그리는 차례로 다시 늘어놓는다 (#246, `HwpBorderPaintOrder`) — 셀 간격이
/// 없는 표는 여러 줄·물결 변을 먼저, 단선은 세로 격자선 → 가로 격자선의 사슬 차례로 긋기 때문에 셀
/// 차례대로 두면 색이 다른 두 변이 겹친 모서리에서 위에 보이는 선이 한글과 갈린다. 차례가 같으면
/// (표 맥락 없는 칸) 받은 차례 그대로다.
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
    /// 테두리 명령 하나 — 표 안 그리는 차례, 받은 차례
    private struct Border {
        let order: Int
        let sequence: Int
        let command: HwpPaintCommand
    }

    private struct Table {
        var fills: [HwpPaintCommand] = []
        var borders: [Border] = []
        var contents: [HwpPaintCommand] = []
        var commands: [HwpPaintCommand] {
            let ordered = borders.sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.sequence < rhs.sequence
            }
            return fills + ordered.map(\.command) + contents
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

    /// 셀 테두리와 그 표 안 그리는 차례 (`onCellStart`) — 표가 닫힐 때 차례대로 늘어놓는다
    mutating func appendBorders(_ commands: [(order: Int, command: HwpPaintCommand)]) {
        guard !stack.isEmpty else { return output.append(contentsOf: commands.map(\.command)) }
        let table = stack.count - 1
        for (order, command) in commands {
            let sequence = stack[table].borders.count
            stack[table].borders.append(Border(order: order, sequence: sequence, command: command))
        }
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
