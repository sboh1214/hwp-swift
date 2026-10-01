import CoreGraphics
import CoreHwp
import Foundation

/// 표 한 벌의 그린 칸 변을 격자선별로 묶은 것 — 방향마다 가로지르는 좌표 차례. 단선 사슬
/// (`HwpBorderChaining.chains(on:)`)과 여러 줄·물결 변의 모서리 맥락(`corners(of:)`)이 쓴다 (#246).
/// 모서리 질의는 격자선마다 만든 구간 색인(`Coverage`)의 이분 탐색이라 표 하나가 O(n log n)이다 —
/// 격자선의 조각을 훑으면 긴 표(2중선 테두리 2,000행)에서 칸 수 × 행 수로 늘어난다 (PR 리뷰).
struct HwpBorderGrid {
    typealias Piece = HwpBorderChaining.Piece

    /// 격자선 하나 — 그 위의 그린 조각과 그 구간 색인
    struct Line {
        let cross: CGFloat
        let pieces: [Piece]
        /// 모든 조각의 구간
        let coverage: Coverage
        /// 모양·굵기마다의 구간 (색은 보지 않는다 — 이어짐 판정, `HwpBorderCornerContext.continues`)
        let styles: [StyleKey: Coverage]

        init(cross: CGFloat, pieces: [Piece]) {
            self.cross = cross
            self.pieces = pieces
            coverage = Coverage(pieces)
            styles = Dictionary(grouping: pieces) { StyleKey($0.border) }.mapValues(Coverage.init)
        }
    }

    /// 이어짐을 가르는 변의 모양·굵기
    struct StyleKey: Hashable {
        let shape: HwpBorderType
        let width: CGFloat

        init(_ border: HwpBorderSet.Border) {
            shape = border.shape
            width = border.width
        }
    }

    /// 선 방향 구간 [start, end]의 색인 — 시작 차례로 늘어놓고 앞에서부터의 끝 최댓값을 둬, 한 점의
    /// 바로 앞·뒤를 덮는 구간이 있는가를 이분 탐색 한 번으로 답한다.
    struct Coverage {
        private let starts: [CGFloat]
        private let prefixMaxEnd: [CGFloat]

        init(_ pieces: [Piece]) {
            let spans = pieces.map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
            starts = spans.map(\.0)
            var maximum = -CGFloat.infinity
            prefixMaxEnd = spans.map { span in
                maximum = max(maximum, span.1)
                return maximum
            }
        }

        /// 시작 ≤ `point`이고 끝 > `point`인 구간이 있는가 — `point` 바로 뒤를 덮는다
        func coversAfter(_ point: CGFloat) -> Bool {
            let count = prefixCount { $0 <= point }
            return count > 0 && prefixMaxEnd[count - 1] > point
        }

        /// 시작 < `point`이고 끝 ≥ `point`인 구간이 있는가 — `point` 바로 앞을 덮는다
        func coversBefore(_ point: CGFloat) -> Bool {
            let count = prefixCount { $0 < point }
            return count > 0 && prefixMaxEnd[count - 1] >= point
        }

        /// `starts`의 앞에서부터 `predicate`를 만족하는 원소 수 (시작 차례라 앞쪽에 몰려 있다)
        private func prefixCount(_ predicate: (CGFloat) -> Bool) -> Int {
            var low = 0
            var high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if predicate(starts[middle]) {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }
    }

    private static let tolerance = HwpBorderChaining.tolerance

    /// 가로 격자선 (y 차례)
    let horizontal: [Line]
    /// 세로 격자선 (x 차례)
    let vertical: [Line]

    init(_ pieces: [Piece]) {
        func lines(_ pieces: [Piece]) -> [Line] {
            var groups: [(cross: CGFloat, pieces: [Piece])] = []
            for piece in pieces.sorted(by: { $0.cross < $1.cross }) {
                if let last = groups.last, piece.cross - last.cross <= Self.tolerance {
                    groups[groups.count - 1].pieces.append(piece)
                } else {
                    groups.append((piece.cross, [piece]))
                }
            }
            return groups.map { Line(cross: $0.cross, pieces: $0.pieces) }
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
        let tolerance = Self.tolerance
        var continues = false
        if border.isDrawn,
           let same = line(horizontal: isHorizontal, at: cross)?.styles[StyleKey(border)]
        {
            continues = atStart
                ? same.coversBefore(corner - tolerance) : same.coversAfter(corner + tolerance)
        }
        let crossing = line(horizontal: !isHorizontal, at: corner)?.coverage
        let plus = crossing?.coversAfter(cross + tolerance) ?? false
        let minus = crossing?.coversBefore(cross - tolerance) ?? false
        // 칸은 위·왼 변이면 선의 +쪽, 아래·오른 변이면 −쪽이다
        let cellOnPlus = position.outerIsLeading
        return HwpBorderCornerContext(
            continues: continues,
            crossesNear: cellOnPlus ? plus : minus,
            crossesBeyond: cellOnPlus ? minus : plus
        )
    }
}
