import CoreGraphics
import CoreHwp
import Foundation

/// 표 격자선 위에서 이웃 칸과 한 선으로 이은 대시·원형 점선 변의 자리 (#238) — 변의 로컬 축(가로
/// 변은 x, 세로 변은 y)에서 잰다. 사슬 로컬 좌표는 0 = 사슬의 무늬 원점이다.
struct HwpBorderChainPlacement: Hashable, Sendable {
    /// 사슬의 무늬 원점에서 이 변의 모서리 시작(가로 변은 칸 왼 모서리, 세로 변은 위 모서리)까지
    let offset: CGFloat
    /// 사슬 길이 — 무늬 원점에서 사슬 끝(연장 포함)까지
    let length: CGFloat
    /// 이 변이 그리는 요소의 자리 범위 (사슬 로컬) — 사슬의 첫 조각은 −∞부터, 끝에 닿는 조각은
    /// +∞까지다. 맞닿은 두 조각의 경계는 같은 값 하나를 나눠 가져 요소가 빠지거나 겹치지 않는다.
    let elementRange: Range<CGFloat>
}

/// 칸 네 변의 이음 자리 — 이웃 칸과 잇지 않는 변은 nil (홀로 선 선)
struct HwpBorderChains: Hashable, Sendable {
    var top: HwpBorderChainPlacement?
    var bottom: HwpBorderChainPlacement?
    var left: HwpBorderChainPlacement?
    var right: HwpBorderChainPlacement?

    static let none = HwpBorderChains()
}

/// 표 한 벌(셀 배치)에서 칸 변의 무늬 이음을 셈한다 (#238).
///
/// 한글 12.30은 표 셀 테두리의 대시(긴 점선·점선·일점쇄선·이점쇄선·파선)와 원형 점선을 칸마다
/// 다시 시작하지 않고 격자선을 따라 한 선으로 잇는다 (실측: 1×3·3×1·2×2·병합 칸, 칸 폭·표 테두리
/// 무관). 규칙은 이렇다:
///
/// - 격자선(가로 변은 같은 y, 세로 변은 같은 x)마다, **선 모양마다** "지금 사슬"이 하나다.
/// - 조각(칸 변)을 선 방향 시작 순으로, 같은 시작이면 **위(왼) 칸의 아래(오른) 변을 먼저** 본다.
/// - 조각이 지금 사슬과 모양·굵기·색이 같고 맞닿거나 겹치면 사슬에 든다. 아니면 새 사슬을 시작해
///   지금 사슬이 된다 — 그래서 같은 모양의 다른 색·굵기 조각은 다른 쪽에 있어도 사슬을 끊고
///   (위 [초록, 초록, 초록] · 아래 [초록, 파랑, 초록]이면 셋째 칸에서 초록이 다시 시작한다),
///   모양이 다른 조각(실선·다른 대시)은 끊지 않는다. 칸 변이 없는 쪽(`none`)도 끊지 않는다 —
///   같은 격자선의 다른 쪽 조각이 잇는다.
/// - 사슬의 무늬 원점은 **첫 조각의 연장 포함 시작**이다 (가로 변은 세로 변 폭의 절반 앞, 세로
///   대시·원은 모서리). 뒤에 든 조각의 연장은 원점을 바꾸지 않는다. 끝은 반대로 사슬에 든 조각의
///   연장 포함 끝 가운데 **가장 먼 것**이다 — 격자선 끝 모서리에 세로 변이 위 칸에만 있든 아래 칸에만
///   있든, 병합 칸이 먼저 끝 모서리에 닿았든 사슬은 그 세로 변 폭의 절반까지 간다 (한글 실측
///   `probes/238/review`: 2×3 긴 점선 격자선의 마지막 대시가 끝 모서리의 1mm 세로 변이 위만·아래만·
///   양쪽·위 병합·아래 병합인 다섯 조합 모두 끝 모서리 + 1.44 — 세로 변이 둘 다 없으면 NONE 변 폭
///   연장만큼인 + 0.12이고, 우리는 NONE 변을 폭 0으로 보아 모서리에서 멈춘다). 원형
///   점선은 거기서 끝 규칙을 쓴다 (`HwpLineShapeGeometry`).
/// - 물결·2중 물결·실선·여러 줄은 잇지 않는다 (한글도 물결은 칸마다 다시 시작한다).
///
/// 표가 쪽마다 나뉘면 쪽 조각(`HwpTableSplitter.segmentFrame`)마다 새로 셈한다 — 한글도 세로
/// 사슬을 쪽 조각의 위 모서리에서 다시 시작한다. 칸 간격이 있는 표는 칸이 맞닿지 않아 잇지 않는다.
enum HwpBorderChaining {
    /// 격자선 좌표·맞닿음 판정의 허용 오차 (pt) — 셀 배치의 부동소수 잡음(병합 칸 모서리가 합의
    /// 묶음 순서로 1e-12pt쯤 어긋난다)만 흡수한다. 가장 작은 칸 간격(1 HWPUNIT = 0.01pt)보다 훨씬
    /// 작아야 칸 간격이 있는 표의 칸을 잇지 않는다.
    static let tolerance: CGFloat = 1e-6

    /// `rows`의 칸마다 이음 자리를 새로 셈해 실은 사본. 이을 변이 없으면 모든 칸의 자리를
    /// 비운다 (다른 표에서 옮겨 온 칸의 낡은 자리를 남기지 않는다).
    static func chained(_ rows: [HwpTableRowFrame]) -> [HwpTableRowFrame] {
        let pieces = rows.enumerated().flatMap { rowIndex, row in
            row.cells.enumerated().flatMap { cellIndex, cell in
                Piece.pieces(of: cell, row: rowIndex, cell: cellIndex)
            }
        }
        var chains: [CellKey: HwpBorderChains] = [:]
        for line in gridLines(pieces) {
            for (piece, placement) in placements(on: line) {
                let key = CellKey(row: piece.row, cell: piece.cell)
                chains[key, default: .none][keyPath: piece.side.keyPath] = placement
            }
        }
        let hasStale = rows.contains { $0.cells.contains { $0.borderChains != .none } }
        guard !chains.isEmpty || hasStale else { return rows }
        return rows.enumerated().map { rowIndex, row in
            HwpTableRowFrame(
                rowFrame: row.rowFrame,
                cells: row.cells.enumerated().map { cellIndex, cell in
                    cell.withBorderChains(chains[CellKey(row: rowIndex, cell: cellIndex)] ?? .none)
                }
            )
        }
    }

    // MARK: - 조각

    struct CellKey: Hashable {
        let row: Int
        let cell: Int
    }

    enum Side {
        case top, bottom, left, right

        var keyPath: WritableKeyPath<HwpBorderChains, HwpBorderChainPlacement?> {
            switch self {
            case .top: \.top
            case .bottom: \.bottom
            case .left: \.left
            case .right: \.right
            }
        }

        var isHorizontal: Bool {
            self == .top || self == .bottom
        }

        /// 같은 시작의 두 조각 가운데 먼저 보는 쪽 — 위(왼) 칸의 아래(오른) 변이 0
        var order: Int {
            self == .bottom || self == .right ? 0 : 1
        }
    }

    struct Style: Equatable {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor
    }

    /// 칸 변 하나 — 표 로컬 좌표. 선 방향 [start, end]는 모서리이고, lead·trail은 가로 변이 이웃
    /// 세로 변 폭의 절반만큼 나가는 연장이다 (`HwpBorderSet`의 가로 변과 같은 값; 세로 대시·원은 0).
    struct Piece {
        let row: Int
        let cell: Int
        let side: Side
        let style: Style
        /// 가로지르는 축의 모서리 좌표 (가로 변 y, 세로 변 x)
        let cross: CGFloat
        let start: CGFloat
        let end: CGFloat
        let lead: CGFloat
        let trail: CGFloat

        static func pieces(of cell: HwpTableCellFrame, row: Int, cell index: Int) -> [Piece] {
            let borders = cell.borders
            let frame = cell.cellFrame
            let visible = HwpBorderSet.visibleWidth
            let widths = (
                top: visible(borders.top, borders.topShape),
                bottom: visible(borders.bottom, borders.bottomShape),
                left: visible(borders.left, borders.leftShape),
                right: visible(borders.right, borders.rightShape)
            )
            let edges: [(Side, Style)] = [
                (.top, Style(shape: borders.topShape, width: widths.top, color: borders.topColor)),
                (.bottom, Style(
                    shape: borders.bottomShape, width: widths.bottom, color: borders.bottomColor
                )),
                (.left, Style(
                    shape: borders.leftShape, width: widths.left, color: borders.leftColor
                )),
                (.right, Style(
                    shape: borders.rightShape, width: widths.right, color: borders.rightColor
                )),
            ]
            return edges.compactMap { side, style in
                guard style.width > 0, HwpLineShapeGeometry.isPatterned(style.shape) else {
                    return nil
                }
                if side.isHorizontal {
                    return Piece(
                        row: row, cell: index, side: side, style: style,
                        cross: side == .top ? frame.minY : frame.maxY,
                        start: frame.minX, end: frame.maxX,
                        lead: widths.left / 2, trail: widths.right / 2
                    )
                }
                return Piece(
                    row: row, cell: index, side: side, style: style,
                    cross: side == .left ? frame.minX : frame.maxX,
                    start: frame.minY, end: frame.maxY, lead: 0, trail: 0
                )
            }
        }
    }

    // MARK: - 격자선

    /// 조각을 격자선별로 묶어 선마다 보는 순서(시작 → 위·왼 칸 변 먼저)로 늘어놓는다
    static func gridLines(_ pieces: [Piece]) -> [[Piece]] {
        let sorted = pieces.sorted { lhs, rhs in
            if lhs.side.isHorizontal != rhs.side.isHorizontal {
                return lhs.side.isHorizontal
            }
            return lhs.cross < rhs.cross
        }
        var lines: [[Piece]] = []
        for piece in sorted {
            if let first = lines.last?.first,
               first.side.isHorizontal == piece.side.isHorizontal,
               piece.cross - first.cross <= tolerance
            {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines.map { line in
            line.sorted { lhs, rhs in
                if abs(lhs.start - rhs.start) > tolerance {
                    return lhs.start < rhs.start
                }
                return lhs.side.order < rhs.side.order
            }
        }
    }

    /// 사슬 하나 — 표 로컬 좌표
    struct Chain {
        let style: Style
        /// 무늬 원점 (첫 조각의 연장 포함 시작)
        let origin: CGFloat
        /// 첫 조각의 모서리 시작
        let startCorner: CGFloat
        /// 지금까지 이은 모서리 끝
        var endCorner: CGFloat
        /// 사슬 끝 (든 조각의 연장 포함 끝 가운데 가장 먼 것)
        var end: CGFloat
        /// (조각, 요소 범위의 시작 — 사슬의 첫 자리면 nil)
        var members: [(piece: Piece, lowerBound: CGFloat?)]
    }

    /// 한 격자선의 조각마다 이음 자리. 조각 하나뿐인 사슬은 자리를 싣지 않는다 (홀로 선 선과
    /// 같다).
    static func placements(on line: [Piece]) -> [(Piece, HwpBorderChainPlacement)] {
        var chains: [Chain] = []
        var current: [HwpBorderType: Int] = [:]
        for piece in line {
            if let index = current[piece.style.shape], chains[index].style == piece.style,
               piece.start <= chains[index].endCorner + tolerance
            {
                join(piece, to: &chains[index])
                continue
            }
            current[piece.style.shape] = chains.count
            chains.append(Chain(
                style: piece.style, origin: piece.start - piece.lead, startCorner: piece.start,
                endCorner: piece.end, end: piece.end + piece.trail,
                members: [(piece, nil)]
            ))
        }
        return chains.filter { $0.members.count > 1 }.flatMap { chain in
            chain.members.map { member in
                (member.piece, placement(of: member, in: chain))
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
        // 끝 모서리에 늦게 닿은 조각의 연장도 사슬 끝을 민다 (원점과 달리 먼저 온 조각이 정하지 않는다)
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

extension HwpTableCellFrame {
    /// 이음 자리만 바꾼 사본
    func withBorderChains(_ chains: HwpBorderChains) -> HwpTableCellFrame {
        var copy = self
        copy.borderChains = chains
        return copy
    }
}
