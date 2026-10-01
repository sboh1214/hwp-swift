import CoreGraphics
import CoreHwp
import Foundation

/// 표 한 벌의 그린 칸 변을 격자선별로 묶은 것 — 방향마다 가로지르는 좌표 차례. 단선 사슬
/// (`HwpBorderChaining.chains(on:)`)과 여러 줄·물결 변의 모서리 맥락(`corners(of:)`)이 쓴다 (#246).
struct HwpBorderGrid {
    typealias Piece = HwpBorderChaining.Piece

    struct Line {
        let cross: CGFloat
        var pieces: [Piece]
    }

    private static let tolerance = HwpBorderChaining.tolerance

    /// 가로 격자선 (y 차례)
    let horizontal: [Line]
    /// 세로 격자선 (x 차례)
    let vertical: [Line]

    init(_ pieces: [Piece]) {
        func lines(_ pieces: [Piece]) -> [Line] {
            var lines: [Line] = []
            for piece in pieces.sorted(by: { $0.cross < $1.cross }) {
                if let last = lines.last, piece.cross - last.cross <= Self.tolerance {
                    lines[lines.count - 1].pieces.append(piece)
                } else {
                    lines.append(Line(cross: piece.cross, pieces: [piece]))
                }
            }
            return lines
        }
        horizontal = lines(pieces.filter(\.isHorizontal))
        vertical = lines(pieces.filter { !$0.isHorizontal })
    }

    /// 가로지르는 좌표 `cross`의 격자선 (없으면 nil) — 이분 탐색
    func line(horizontal isHorizontal: Bool, at cross: CGFloat) -> Line? {
        let lines = isHorizontal ? horizontal : vertical
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].cross < cross - Self.tolerance {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < lines.count, abs(lines[low].cross - cross) <= Self.tolerance else { return nil }
        return lines[low]
    }

    /// 칸 네 변의 시작·끝 모서리 맥락
    func corners(of cell: HwpTableCellFrame) -> HwpBorderCorners {
        func ends(_ position: HwpBorderSet.Position) -> HwpBorderEndContexts {
            HwpBorderEndContexts(
                lead: corner(of: cell, position, atStart: true),
                trail: corner(of: cell, position, atStart: false)
            )
        }
        return HwpBorderCorners(
            top: ends(.top), bottom: ends(.bottom), left: ends(.left), right: ends(.right)
        )
    }

    /// 변 하나의 한쪽 끝 모서리 맥락 — 같은 격자선이 모서리 너머로 같은 모양·굵기 변으로 이어지는가,
    /// 모서리를 지나는 수직 격자선이 이 변의 선 양쪽에 그린 변을 갖는가 (`HwpBorderCornerContext`)
    func corner(
        of cell: HwpTableCellFrame, _ position: HwpBorderSet.Position, atStart: Bool
    ) -> HwpBorderCornerContext {
        let frame = cell.cellFrame
        let border = cell.borders.border(position)
        let isHorizontal = position.isHorizontal
        let corner = isHorizontal
            ? (atStart ? frame.minX : frame.maxX) : (atStart ? frame.minY : frame.maxY)
        let cross = switch position {
        case .top: frame.minY
        case .bottom: frame.maxY
        case .left: frame.minX
        case .right: frame.maxX
        }
        let continues = line(horizontal: isHorizontal, at: cross)?.pieces.contains { other in
            guard other.border.width == border.width, other.border.shape == border.shape,
                  border.isDrawn
            else { return false }
            return atStart
                ? other.start < corner - Self.tolerance && other.end >= corner - Self.tolerance
                : other.end > corner + Self.tolerance && other.start <= corner + Self.tolerance
        } ?? false
        let crossing = line(horizontal: !isHorizontal, at: corner)?.pieces ?? []
        let (after, before) = (cross + Self.tolerance, cross - Self.tolerance)
        let plus = crossing.contains { $0.start <= after && $0.end > after }
        let minus = crossing.contains { $0.start < before && $0.end >= before }
        // 칸은 위·왼 변이면 선의 +쪽, 아래·오른 변이면 −쪽이다
        let cellOnPlus = position.outerIsLeading
        return HwpBorderCornerContext(
            continues: continues,
            crossesNear: cellOnPlus ? plus : minus,
            crossesBeyond: cellOnPlus ? minus : plus
        )
    }
}
