import CoreGraphics
import CoreHwp
import Foundation

/// 표 한 벌(셀 배치)에서 칸 테두리의 맥락을 셈한다 — 단선 변의 이음(#238·#246), 여러 줄·물결 변의
/// 모서리 맥락(#246), 그리는 차례(#246). 결과는 칸마다 `HwpBorderContext`로 싣는다.
///
/// **이음.** 한글 12.30은 셀 간격이 없는 표의 단선 변(실선·대시·원형 점선 — 3D 넷은 실선으로 대체)을 칸마다
/// 다시 그리지 않고 격자선을 따라 한 선으로 잇는다 (대시·원: #238 실측 1×3·3×1·2×2·병합 칸; 실선:
/// #246 실측 `so246-solidchain` — 원점·끝·끊김 모두 같은 규칙이고 안쪽 모서리의 이웃 변이 2중선·물결·선
/// 없음이어도 이어진다). 규칙은 이렇다:
///
/// - 격자선(가로 변은 같은 y, 세로 변은 같은 x)마다, **선 모양마다** "지금 사슬"이 하나다.
/// - 조각(칸 변)을 선 방향 시작 순으로, 같은 시작이면 **위(왼) 칸의 아래(오른) 변을 먼저** 본다.
/// - 조각이 지금 사슬과 모양·굵기·색이 같고 맞닿거나 겹치면 사슬에 든다. 아니면 새 사슬을 시작해
///   지금 사슬이 된다 — 그래서 같은 모양의 다른 색·굵기 조각은 다른 쪽에 있어도 사슬을 끊고
///   (위 [초록, 초록, 초록] · 아래 [초록, 파랑, 초록]이면 셋째 칸에서 초록이 다시 시작한다),
///   모양이 다른 조각과 칸 변이 없는 쪽(`none`)은 끊지 않는다 — 같은 격자선의 다른 쪽 조각이 잇는다.
/// - 사슬의 무늬 원점은 **첫 조각의 모서리 자리**이고 (`HwpBorderSet.singleLineReach` — 가로 변은 이웃
///   세로 변 굵기의 절반 앞, 세로 변은 모서리, 이웃이 여러 줄·물결이면 둘 다 그 절반 뒤), 뒤에 든 조각의
///   자리는 원점을 바꾸지 않는다. 끝은 반대로 사슬에 든 조각의 끝 자리 가운데 **가장 먼 것**이다 (한글
///   실측 `probes/238/review`·`so246-solidchain`). 안쪽 모서리의 자리는 쓰지 않는다. 원형 점선은 끝에서
///   끝 규칙을 쓴다 (`HwpLineShapeGeometry`).
/// - 여러 줄·물결은 잇지 않는다 (한글도 물결은 칸마다 다시 시작한다).
///
/// 표가 쪽마다 나뉘면 쪽 조각(`HwpTableSplitter.segmentFrame`)마다 새로 셈한다 — 한글도 세로
/// 사슬을 쪽 조각의 위 모서리에서 다시 시작한다. 칸 간격이 있는 표는 잇지 않는다 — 칸이 맞닿지
/// 않고, 한글은 그 표의 변을 칸마다 상자로 그린다 (#243, `HwpBorderSet.cellSpacing`). 칸 간격을 실은
/// 칸은 맞닿은 배치로 옮겨 와도 조각을 내지 않는다 (상자의 모서리 규칙과 사슬 자리가 섞이지 않게).
///
/// **모서리 맥락**과 **그리는 차례**는 `HwpBorderCornerContext`·`HwpBorderPaintOrder`의 설명을 본다.
enum HwpBorderChaining {
    /// 격자선 좌표·맞닿음 판정의 허용 오차 (pt) — 셀 배치의 부동소수 잡음(병합 칸 모서리가 합의
    /// 묶음 순서로 1e-12pt쯤 어긋난다)만 흡수한다. 가장 작은 칸 간격(1 HWPUNIT = 0.01pt)보다 훨씬
    /// 작아야 칸 간격이 있는 표의 칸을 잇지 않는다.
    static let tolerance: CGFloat = 1e-6

    /// `rows`의 칸마다 테두리 맥락을 새로 셈해 실은 사본 (다른 표에서 옮겨 온 칸의 낡은 맥락은
    /// 버린다).
    static func chained(_ rows: [HwpTableRowFrame]) -> [HwpTableRowFrame] {
        let cells = rows.enumerated().flatMap { rowIndex, row in
            row.cells.enumerated().map { (CellKey(row: rowIndex, cell: $0.offset), $0.element) }
        }
        let grid = HwpBorderGrid(cells.flatMap { Piece.pieces(of: $0.1, key: $0.0) })
        var contexts: [CellKey: HwpBorderContext] = [:]
        for (sequence, (key, cell)) in cells.enumerated() {
            var context = HwpBorderContext()
            context.paintOrder = cellPaintOrder(sequence: sequence)
            if !cell.borders.isSpacedCell,
               HwpBorderSet.Position.allCases.contains(where: { cell.borders.border($0).isFramed })
            {
                context.corners = grid.corners(of: cell)
            }
            contexts[key] = context
        }
        // 단선 사슬 — 이음 자리를 싣고, 여러 줄·물결 변 다음 차례를 매긴다 (`paintSequence`). 나중에
        // 다시 그리는 무리는 마지막 차례가 남는다 (같은 경로를 덧그린 것과 보이는 결과가 같다)

        func groups(_ lines: [HwpBorderGrid.Line]) -> [LineGroup] {
            lines.flatMap { line in
                lineGroups(chains(on: line.pieces.filter(\.isSingleLine)), cross: line.cross)
            }
        }
        let (vertical, horizontal) = (groups(grid.vertical), groups(grid.horizontal))
        for (piece, placement) in (vertical + horizontal).flatMap({ $0.chains.joined() }) {
            contexts[piece.key]?[placement: piece.position] = placement
        }
        let sequence = paintSequence(vertical: vertical, horizontal: horizontal)
        for (rank, piece) in sequence.enumerated() {
            contexts[piece.key]?.paintOrder?[piece.position] = cells.count * 4 + rank
        }
        return rows.enumerated().map { rowIndex, row in
            HwpTableRowFrame(
                rowFrame: row.rowFrame,
                cells: row.cells.enumerated().map { cellIndex, cell in
                    cell.withBorderContext(
                        contexts[CellKey(row: rowIndex, cell: cellIndex)] ?? .none
                    )
                }
            )
        }
    }

    /// 칸 혼자의 그리는 차례 — 칸 차례마다 넷씩, 칸 안에서는 왼·오른·위·아래. 셀 간격이 없는 칸의 단선
    /// 변은 사슬이 다시 매긴다 (`chained`).
    private static func cellPaintOrder(sequence: Int) -> HwpBorderPaintOrder {
        var order = HwpBorderPaintOrder()
        for position in HwpBorderSet.Position.allCases {
            order[position] = sequence * 4 + position.paintIndex
        }
        return order
    }

    // MARK: - 그리는 차례

    /// 한 격자선에서 같은 모양의 단선 사슬 무리 — 사슬은 만든 차례, 사슬 안은 든 차례
    struct LineGroup {
        let shape: HwpBorderType
        let cross: CGFloat
        let chains: [[(Piece, HwpBorderChainPlacement?)]]
    }

    /// 한 격자선의 사슬을 모양별 무리로 가른다 (모양마다 사슬을 만든 차례를 지킨다)
    static func lineGroups(
        _ chains: [[(Piece, HwpBorderChainPlacement?)]], cross: CGFloat
    ) -> [LineGroup] {
        var shapes: [HwpBorderType] = []
        var byShape: [HwpBorderType: [[(Piece, HwpBorderChainPlacement?)]]] = [:]
        for chain in chains {
            guard let shape = chain.first?.0.border.shape else { continue }
            if byShape[shape] == nil {
                shapes.append(shape)
            }
            byShape[shape, default: []].append(chain)
        }
        return shapes.map { LineGroup(shape: $0, cross: cross, chains: byShape[$0] ?? []) }
    }

    /// 셀 간격이 없는 표의 단선 변을 한글이 그리는 차례 (#246 실측 `so246-order`·`cells`·`solidchain`·
    /// `junction` — PDF 그리기 순서): 세로 무리를 모양(표 25 값) 차례·격자선 x 차례로, 이어 가로 무리를
    /// 모양·y 차례로 그린 뒤, 바깥 테두리를 한 번 더 긋는다 — 세로에서 마지막으로 그린 무리, 처음 그린
    /// 무리(사슬을 거꾸로), 가로에서 마지막 무리, 처음 무리(사슬을 거꾸로). 보통 표에서 그 넷이 바깥
    /// 오른·왼·아래·위 테두리라 바깥 테두리가 안쪽 선 위에 온다. 조각이 여럿 나오면 마지막이 이긴다.
    static func paintSequence(vertical: [LineGroup], horizontal: [LineGroup]) -> [Piece] {
        func sorted(_ groups: [LineGroup]) -> [LineGroup] {
            groups.enumerated().sorted { lhs, rhs in
                let (left, right) = (lhs.element, rhs.element)
                if left.shape.rawValue != right.shape.rawValue {
                    return left.shape.rawValue < right.shape.rawValue
                }
                if left.cross != right.cross {
                    return left.cross < right.cross
                }
                return lhs.offset < rhs.offset
            }.map(\.element)
        }
        func pieces(_ group: LineGroup?, reversed: Bool = false) -> [Piece] {
            guard let group else { return [] }
            let chains = reversed ? Array(group.chains.reversed()) : group.chains
            return chains.flatMap { $0.map(\.0) }
        }
        let (vertical, horizontal) = (sorted(vertical), sorted(horizontal))
        return (vertical + horizontal).flatMap { pieces($0) }
            + pieces(vertical.last) + pieces(vertical.first, reversed: true)
            + pieces(horizontal.last) + pieces(horizontal.first, reversed: true)
    }

    // MARK: - 조각

    struct CellKey: Hashable {
        let row: Int
        let cell: Int
    }

    struct Style: Equatable {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor
    }

    /// 그린 칸 변 하나 — 표 로컬 좌표. 선 방향 [start, end]는 모서리이고, lead·trail은 단선이 시작·끝
    /// 모서리 밖으로 나가는 길이다 (`HwpBorderSet.singleLineReach` — 음수면 물러난다).
    struct Piece {
        let key: CellKey
        let position: HwpBorderSet.Position
        let border: HwpBorderSet.Border
        /// 가로지르는 축의 모서리 좌표 (가로 변 y, 세로 변 x)
        let cross: CGFloat
        let start: CGFloat
        let end: CGFloat
        let lead: CGFloat
        let trail: CGFloat

        var isHorizontal: Bool {
            position.isHorizontal
        }

        var isSingleLine: Bool {
            HwpBorderSet.isSingleLine(border.shape)
        }

        var style: Style {
            Style(shape: border.shape, width: border.width, color: border.color)
        }

        /// 같은 시작의 두 조각 가운데 먼저 보는 쪽 — 위(왼) 칸의 아래(오른) 변이 0
        var sideOrder: Int {
            position == .bottom || position == .right ? 0 : 1
        }

        /// 칸 간격이 없는 칸의 그린 변 (길이가 있는 것만)
        static func pieces(of cell: HwpTableCellFrame, key: CellKey) -> [Piece] {
            let borders = cell.borders
            guard !borders.isSpacedCell else { return [] }
            let frame = cell.cellFrame
            return HwpBorderSet.Position.allCases.compactMap { position in
                let border = borders.border(position)
                let horizontal = position.isHorizontal
                let (start, end) = horizontal ? (frame.minX, frame.maxX) : (frame.minY, frame.maxY)
                guard border.isDrawn, end - start > tolerance else { return nil }
                let (leadPosition, trailPosition) = position.neighbours
                func reach(_ neighbour: HwpBorderSet.Position) -> CGFloat {
                    HwpBorderSet.singleLineReach(
                        of: border, horizontal: horizontal, neighbour: borders.border(neighbour),
                        spaced: false
                    )
                }
                let cross = switch position {
                case .top: frame.minY
                case .bottom: frame.maxY
                case .left: frame.minX
                case .right: frame.maxX
                }
                return Piece(
                    key: key, position: position, border: border, cross: cross,
                    start: start, end: end, lead: reach(leadPosition), trail: reach(trailPosition)
                )
            }
        }
    }

    // MARK: - 사슬

    /// 사슬 하나 — 표 로컬 좌표
    struct Chain {
        let style: Style
        /// 무늬 원점 (첫 조각의 모서리 자리)
        let origin: CGFloat
        /// 첫 조각의 모서리 시작
        let startCorner: CGFloat
        /// 지금까지 이은 모서리 끝
        var endCorner: CGFloat
        /// 사슬 끝 (든 조각의 끝 자리 가운데 가장 먼 것)
        var end: CGFloat
        /// (조각, 요소 범위의 시작 — 사슬의 첫 자리면 nil)
        var members: [(piece: Piece, lowerBound: CGFloat?)]
    }

    /// 한 격자선의 단선 조각을 사슬로 묶는다 — 사슬을 만든 차례로, 사슬 안은 든 차례로 (조각, 이음
    /// 자리). 조각 하나뿐인 사슬은 자리를 싣지 않는다 (홀로 선 선과 같다).
    static func chains(on pieces: [Piece]) -> [[(Piece, HwpBorderChainPlacement?)]] {
        let ordered = pieces.sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > tolerance {
                return lhs.start < rhs.start
            }
            return lhs.sideOrder < rhs.sideOrder
        }
        var chains: [Chain] = []
        var current: [HwpBorderType: Int] = [:]
        for piece in ordered {
            if let index = current[piece.border.shape], chains[index].style == piece.style,
               piece.start <= chains[index].endCorner + tolerance
            {
                join(piece, to: &chains[index])
                continue
            }
            current[piece.border.shape] = chains.count
            chains.append(Chain(
                style: piece.style, origin: piece.start - piece.lead, startCorner: piece.start,
                endCorner: piece.end, end: piece.end + piece.trail,
                members: [(piece, nil)]
            ))
        }
        return chains.map { chain in
            chain.members.map { member in
                (member.piece, chain.members.count > 1 ? placement(of: member, in: chain) : nil)
            }
        }
    }

    /// 사슬에 조각을 넣는다 — 맞닿은 조각의 요소 범위는 사슬의 지금 끝 값에서 시작해 앞 조각과
    /// 경계를 나눠 갖고, 겹친 조각은 제 시작에서 (같은 구간 두 쪽이면 앞 조각과 같은 요소를 한 번 더
    /// 그린다 — 한글도 그 구간을 두 번 그린다).
    static func join(_ piece: Piece, to chain: inout Chain) {
        let lowerBound: CGFloat? = if abs(piece.start - chain.startCorner) <= tolerance {
            nil
        } else if abs(piece.start - chain.endCorner) <= tolerance {
            chain.endCorner
        } else {
            piece.start
        }
        chain.members.append((piece, lowerBound))
        if piece.end > chain.endCorner + tolerance {
            chain.endCorner = piece.end
        }
        // 끝 모서리에 늦게 닿은 조각의 자리도 사슬 끝을 민다 (원점과 달리 먼저 온 조각이 정하지 않는다)
        chain.end = max(chain.end, piece.end + piece.trail)
    }

    static func placement(
        of member: (piece: Piece, lowerBound: CGFloat?), in chain: Chain
    ) -> HwpBorderChainPlacement {
        let piece = member.piece
        let lower = member.lowerBound.map { $0 - chain.origin } ?? -.infinity
        let upper = piece.end >= chain.endCorner - tolerance
            ? CGFloat.infinity : piece.end - chain.origin
        return HwpBorderChainPlacement(
            offset: piece.start - chain.origin,
            length: chain.end - chain.origin,
            elementRange: lower ..< max(lower, upper)
        )
    }
}
