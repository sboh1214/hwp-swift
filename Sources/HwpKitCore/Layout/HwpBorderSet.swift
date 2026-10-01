import CoreGraphics
import CoreHwp
import Foundation

/// 셀 4방향 테두리 (pt 폭 + 색상 + 선 모양). 폭 0이거나 모양이 `none`이면 그리지 않는다.
///
/// 선은 한글처럼 **셀 모서리에 중심**을 두고 양쪽으로 폭의 절반씩 걸친다 (한글 12.30 실측,
/// #191: 0.1~5mm 16단 모두 위 테두리 중심이 셀 위 모서리, 왼 테두리 중심이 왼 모서리) —
/// 이웃 셀과 공유하는 모서리는 양쪽 셀이 각자 자기 선을 겹쳐 그린다 (한글도 그렇다: 2중선
/// 아래 변 + 가는+굵은 위 변이 한 모서리에 둘 다 남는다). 가로 변은 그 끝에 세로 변이
/// 있으면 세로 변 폭의 절반만큼 밖으로 연장해 모서리를 메우고 (실측: 왼 테두리가 있는 왼쪽
/// 끝은 −t/2, 오른 테두리가 없는 오른쪽 끝은 모서리 그대로), 세로 변의 실선·대시·원형은
/// 연장하지 않는다 (가로 변이 이미 모서리를 메운다). 여러 줄(2중선·3중선)은 부속선마다
/// 바깥쪽에서의 거리만큼 안쪽으로 물러나 모서리에서 겹상자를 이루고 (실측: 1mm 2중선 위
/// 변의 바깥 선은 −t/2에서, 안쪽 선은 +t/4에서 시작; 물러나는 거리의 기준은 **이웃 변**의
/// 폭 절반), 물결·2중 물결은 세로 변도 가로 변 폭의 절반만큼 연장한 곳에서 시작한다 (실측:
/// 위 테두리가 있는 왼 물결 변의 첫 꼭짓점은 모서리 − t/2).
///
/// 대시·원형 점선은 한 변 안에서 끝나지 않는다 — 한글은 같은 격자선에서 모양·굵기·색이 같은
/// 이웃 칸의 변을 한 선으로 이어 무늬를 그린다 (#238). 그 자리는 표가 셀 배치에서 셈해 칸에
/// 싣고 (`HwpBorderChains`, `HwpTableFrame.init`), 이 타입은 변마다 받은 자리로 제 몫의 요소만
/// 그린다. 자리가 없는 변은 홀로 선 선이다.
///
/// 셀 간격(`cellSpacing`)이 있는 표는 칸이 맞닿지 않아 잇지 않고, 한글은 실선·대시·원형 점선 변을
/// 칸마다 네 변의 상자로 그린다 (#243). 원형 점선의 원은 단 구분선과 같은 점 무늬로 크고 성기며
/// (`HwpLineShapeGeometry.Line.inSpacedTable`), 모서리는 **모서리마다** 만나는 두 변으로 정한다 —
/// 두 변의 모양·굵기가 같으면(색은 보지 않는다) 맞물린 모서리라 실선·대시는 가로·세로 변 모두 굵기의
/// 절반만큼 나가고 원형 점선은 둘 다 모서리에서 시작·끝난다. 다르면 가로 변은 위 규칙처럼 세로 변
/// 굵기의 절반만큼 나가고 세로 변은 가로 변 굵기의 절반만큼 **물러난다** (가로 변이 모서리를 덮는다).
/// 세로 변을 먼저, 가로 변을 나중에 그린다 (`Position.spacedOrder`). 여러 줄·물결 변은 셀 간격이
/// 있어도 위 격자 규칙으로 그린다 — 한글도 여러 줄·물결은 셀 간격 0·1·283HWPUNIT에서 같은
/// 벡터다 (이웃이 다른 모양일 때의 모서리는 한글과 다르다 — `Sources/HwpKitCore/AGENTS.md`의 남은
/// 격차).
public struct HwpBorderSet: Sendable, Hashable {
    public let top, bottom, left, right: CGFloat
    public let topColor, bottomColor, leftColor, rightColor: HwpRGBColor
    /// 선 모양 (표 25) — 점선·파선·여러 줄·물결은 `HwpLineShapeGeometry`가 두께 축척으로
    /// 그린다 (#191). `none`은 폭과 무관하게 그리지 않는다.
    public let topShape, bottomShape, leftShape, rightShape: HwpBorderType
    /// 이 칸이 속한 표의 셀 간격 (pt, 표 76 `cellSpacing`) — 0보다 크면 실선·대시·원형 점선 변을
    /// 한글처럼 칸마다 상자로 그린다 (#243, 타입 설명). 0이면 이웃 칸과 맞닿은 격자다.
    public let cellSpacing: CGFloat

    public init(
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat,
        topColor: HwpRGBColor,
        bottomColor: HwpRGBColor,
        leftColor: HwpRGBColor,
        rightColor: HwpRGBColor,
        topShape: HwpBorderType = .line,
        bottomShape: HwpBorderType = .line,
        leftShape: HwpBorderType = .line,
        rightShape: HwpBorderType = .line,
        cellSpacing: CGFloat = 0
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.leftColor = leftColor
        self.rightColor = rightColor
        self.topShape = topShape
        self.bottomShape = bottomShape
        self.leftShape = leftShape
        self.rightShape = rightShape
        self.cellSpacing = cellSpacing
    }

    /// 한 변의 그리기 — 페이지 좌표 채우기 경로 + 색 + 히트용 띠. 모듈 안(페인터·히트) 전용.
    struct EdgeGeometry: @unchecked Sendable {
        /// 불변 경로 — `Edge.geometry`가 소유권 경계에서 복사해 넣는다 (`HwpPaintCommand`가 retain)
        let path: CGPath
        let color: HwpRGBColor
        /// 이 변이 칠하는 영역의 경계 상자 (모서리에 중심을 둔 띠, 연장·물결 넘침·첫 원 반지름 포함)
        let band: CGRect
    }

    /// rect 둘레에 **실제로 칠하는 변 전부** — 페인터 (`HwpPaintListBuilder.borderCommands`)
    /// 와 히트 (`HwpTableCellFrame.paints`, `bands(around:chains:)`) 가 같은 변 기하(`Edge`)를
    /// 공유한다 (R56). 두 곳이 따로 계산하면 보이는 선과 눌리는 선이 갈린다. 히트 띠는 이 변들의
    /// 띠에 더해 칠하지 않는 이은 변(제 몫의 요소가 없는 변)의 띠도 낸다 (`bands(around:chains:)`).
    /// `chains`는 이웃 칸과 이은 대시·원형 점선 변의 자리다 (#238 — 없으면 변마다 홀로 선 선).
    func edges(around rect: CGRect, chains: HwpBorderChains = .none) -> [EdgeGeometry] {
        drawnEdges(around: rect, chains: chains).compactMap(\.geometry)
    }

    /// rect 둘레 변들의 히트 띠 — 경로를 만들지 않아 히트 판정마다 싸다. 칠하는 변의 경계 상자는
    /// `edges(around:chains:)`가 내는 `EdgeGeometry.band`와 같고, 이웃 칸과 이은 변 가운데 제 몫의
    /// 요소가 없는 변(무늬의 빈 자리나 이웃 칸이 넘겨 그린 대시만 지나는 변)도 선 위라 띠를 낸다 —
    /// 그 변은 칠하지 않으므로 `edges`에는 없다 (점선의 빈 자리도 띠로 치는 규약, #238).
    func bands(around rect: CGRect, chains: HwpBorderChains = .none) -> [CGRect] {
        drawnEdges(around: rect, chains: chains).compactMap(\.band)
    }

    /// rect와 그 둘레 테두리 띠를 모두 담는 경계 상자 — 히트 자격 영역이 칠한 곳을 다
    /// 덮도록 (R54 `자격 ⊇ 칠`) 셀·표 프레임에 테두리 바깥 절반을 더한다.
    func paintedBounds(around rect: CGRect, chains: HwpBorderChains = .none) -> CGRect {
        bands(around: rect, chains: chains).reduce(rect) { $0.union($1) }
    }

    /// 셀 간격이 있는 표의 칸인가 — 실선·대시·원형 점선 변을 칸마다 상자로 그리고 이웃 칸과 잇지
    /// 않는다 (#243). 무늬 이음(`HwpBorderChaining`)도 같은 술어를 쓴다.
    var isSpacedCell: Bool {
        cellSpacing > 0
    }

    /// 변 폭 — 폭이 있고 모양이 `none`이 아니면 그 폭, 아니면 0 (그리지 않는 변). 이웃 변의
    /// 연장(폭의 절반)도 이 값으로 셈한다 — 무늬 이음(`HwpBorderChaining`)도 같은 술어를 쓴다.
    static func visibleWidth(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
        width > 0 && shape != .none ? width : 0
    }

    /// 모서리에서 선이 나가거나 물러나는 길이의 기준 폭 — 이웃 변 굵기를 장치 단위로 반올림한 획
    /// (`HwpLineShapeGeometry.borderStrokeThickness(_:)`)이고 이웃 모양은 보지 않는다 (#245 실측: 파랑
    /// 2mm 실선 세로 변(47u) 사이의 0.4mm 긴 점선 위 변이 양 끝으로 23u·24u 나간다 — 명목 두께면
    /// 23.6u씩; #243 실측: 같은 굵기면 실선·대시·원형 점선 이웃이 — 셀 간격 표에서는 여러 줄·물결
    /// 이웃도 — 같은 자리를 낸다). 선 자리(`lineReach`)와 무늬 이음(`HwpBorderChaining`)이 쓴다. 여러 줄
    /// 겹상자 물림과 히트 띠는 이웃이 **그리는** 폭(`drawnWidth`)을 쓴다.
    static func reachWidth(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
        let visible = visibleWidth(width, shape)
        return visible > 0 ? HwpLineShapeGeometry.borderStrokeThickness(visible) : 0
    }

    /// 이웃 변이 그리는 폭 — 실선·대시(3D 넷 대체 포함)는 장치 단위로 반올림한 획
    /// (`reachWidth`), 여러 줄·물결·원형 점선의 띠는 명목 폭(`visibleWidth`)이다. 여러 줄 부속선이
    /// 모서리에서 물러나는 기준(이웃 폭의 절반)과 히트 띠의 연장이 이 값이라 겹상자가 이웃의 실제
    /// 부속선과 맞닿는다.
    static func drawnWidth(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
        switch shape {
        case .line, .thick3D, .thick3DReverse, .single3D, .single3DReverse,
             .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash:
            reachWidth(width, shape)
        case .none, .circle, .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine,
             .thinThickThinTripleLine, .wave, .doubleWave:
            visibleWidth(width, shape)
        }
    }

    /// 변의 자리 — 위·아래는 가로 변, 왼·오른은 세로 변. `edges(around:chains:)`의 차례(곧 그리는
    /// 차례)는 셀 간격이 없는 칸이 `allCases`(위·아래·왼·오른), 셀 간격이 있는 칸이 `spacedOrder`다.
    private enum Position: CaseIterable {
        case top, bottom, left, right

        /// 셀 간격이 있는 칸의 그리는 차례 — 한글은 세로 변을 먼저, 가로 변을 나중에 그려 모서리에서
        /// 가로 변이 위에 온다 (#243, 한글 12.30 PDF의 그리기 순서: 셀 간격 1·283HWPUNIT 표본 74개
        /// 모두). 맞물린 모서리(두 변 모두 나간다)와 물러난 세로 원형 점선(원의 반지름이 가로 변 띠에
        /// 걸친다)에서 색이 다르면 보인다.
        static let spacedOrder: [Position] = [.left, .right, .top, .bottom]

        var isHorizontal: Bool {
            self == .top || self == .bottom
        }

        /// 띠의 바깥쪽이 −y/−x 쪽인가 (위·왼 변)
        var outerIsLeading: Bool {
            self == .top || self == .left
        }

        /// 시작·끝 모서리에서 만나는 이웃 변 — 가로 변은 왼·오른, 세로 변은 위·아래
        var neighbours: (lead: Position, trail: Position) {
            isHorizontal ? (.left, .right) : (.top, .bottom)
        }
    }

    /// 변 하나의 모양·보이는 폭(`visibleWidth` — 없는 변은 0)·색
    private struct Side {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor

        /// 선이 모서리에서 나가거나 물러나는 기준 폭 (`reachWidth`)
        var reach: CGFloat {
            HwpBorderSet.reachWidth(width, shape)
        }

        /// 그리는 폭 — 여러 줄 물림·히트 띠의 기준 (`drawnWidth`)
        var drawn: CGFloat {
            HwpBorderSet.drawnWidth(width, shape)
        }
    }

    private func side(_ position: Position) -> Side {
        let visible = Self.visibleWidth
        return switch position {
        case .top: Side(shape: topShape, width: visible(top, topShape), color: topColor)
        case .bottom:
            Side(shape: bottomShape, width: visible(bottom, bottomShape), color: bottomColor)
        case .left: Side(shape: leftShape, width: visible(left, leftShape), color: leftColor)
        case .right: Side(shape: rightShape, width: visible(right, rightShape), color: rightColor)
        }
    }

    private func drawnEdges(around rect: CGRect, chains: HwpBorderChains) -> [Edge] {
        let spaced = isSpacedCell
        return (spaced ? Position.spacedOrder : Position.allCases).compactMap { position in
            let side = side(position)
            guard side.width > 0 else { return nil }
            let lead = self.side(position.neighbours.lead)
            let trail = self.side(position.neighbours.trail)
            let horizontal = position.isHorizontal
            let (start, end) = horizontal ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
            let cross = switch position {
            case .top: rect.minY
            case .bottom: rect.maxY
            case .left: rect.minX
            case .right: rect.maxX
            }
            let chain = switch position {
            case .top: chains.top
            case .bottom: chains.bottom
            case .left: chains.left
            case .right: chains.right
            }
            let reach = { (neighbour: Side) in
                Self.lineReach(
                    of: side, horizontal: horizontal, neighbour: neighbour, spaced: spaced
                )
            }
            return Edge(
                shape: side.shape, width: side.width, color: side.color,
                start: start, end: end, cross: cross, horizontal: horizontal,
                leadExtension: lead.drawn / 2, trailExtension: trail.drawn / 2,
                lineLead: reach(lead), lineTrail: reach(trail),
                outerIsLeading: position.outerIsLeading, inSpacedTable: spaced, chain: chain
            )
        }
    }

    /// 선이 모서리 밖으로 나가는 길이 (음수면 안으로 물러난다) — `neighbour`는 그 모서리에서 만나는
    /// 이웃 변이다. 이은 선(#238)은 쓰지 않는다 (사슬의 원점·끝이 정한다).
    ///
    /// - 셀 간격이 없는 표(격자, #191): 가로 변은 이웃 세로 변 폭의 절반만큼 나가고, 세로 변은
    ///   물결만 이웃 가로 변 폭의 절반만큼 나간다 (실선·대시·원형은 모서리에서 — 가로 변이 모서리를
    ///   메운다; 여러 줄은 부속선마다 물러나는 겹상자라 선 자체는 모서리에서). 이웃이 여러 줄·물결이거나
    ///   여러 줄·물결 변의 이웃이 다른 모양일 때 한글이 물리는 자리는 따르지 않는다 (남은 격차).
    /// - 셀 간격이 있는 표의 실선·대시·원형 점선(#243, 한글 12.30 실측 `probes/243`): 이웃과 모양·
    ///   굵기가 같은 **맞물린 모서리**면 원형 점선은 모서리에서, 실선·대시는 가로·세로 변 모두 굵기의
    ///   절반만큼 나간다. 맞물리지 않으면 가로 변은 이웃 폭의 절반만큼 나가고 세로 변은 그만큼 물러난다.
    ///   여러 줄·물결 변은 셀 간격이 없는 표와 같은 규칙이다.
    private static func lineReach(
        of side: Side, horizontal: Bool, neighbour: Side, spaced: Bool
    ) -> CGFloat {
        let half = neighbour.reach / 2
        guard spaced, isSingleLine(side.shape) else {
            return horizontal || side.shape == .wave || side.shape == .doubleWave ? half : 0
        }
        let joined = neighbour.width > 0 && neighbour.shape == side.shape
            && neighbour.width == side.width
        if joined {
            return side.shape == .circle ? 0 : half
        }
        return horizontal ? half : -half
    }

    /// 한 줄로 그리는 모양 — 실선(3D 넷은 실선으로 대체한다)·대시·원형 점선. 셀 간격이 있는 표에서
    /// 칸마다 상자로 그리는 갈래다 (#243 — 여러 줄·물결은 한글이 셀 간격과 무관하게 그린다).
    private static func isSingleLine(_ shape: HwpBorderType) -> Bool {
        switch shape {
        case .line, .thick3D, .thick3DReverse, .single3D, .single3DReverse,
             .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash, .circle:
            true
        case .none, .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine,
             .thinThickThinTripleLine, .wave, .doubleWave:
            false
        }
    }

    /// 한 변의 입력 — `HwpLineShapeGeometry`의 로컬 좌표(x = 선 방향, y = 가로지르는 축,
    /// 0 = 모서리)를 페이지 좌표로 옮기는 데 필요한 값
    private struct Edge {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor
        /// 선 방향 축의 셀 모서리 시작·끝
        let start: CGFloat
        let end: CGFloat
        /// 가로지르는 축의 모서리 좌표 (선 중심)
        let cross: CGFloat
        let horizontal: Bool
        /// 시작·끝 쪽 이웃 변 폭의 절반 (없으면 0) — 히트 띠와 여러 줄 겹상자의 기준
        let leadExtension: CGFloat
        let trailExtension: CGFloat
        /// 선 자체가 시작·끝 모서리 밖으로 나가는 길이 (음수면 물러난다, `lineReach`) — 이은 선이면
        /// 쓰지 않는다
        let lineLead: CGFloat
        let lineTrail: CGFloat
        /// 띠의 바깥쪽이 −y/−x 쪽인지 (위·왼 변 true, 아래·오른 변 false)
        let outerIsLeading: Bool
        /// 셀 간격이 있는 표의 변인가 (#243) — 원형 점선의 원 크기·간격이 점 무늬다
        let inSpacedTable: Bool
        /// 이웃 칸과 이은 대시·원형 점선의 자리 (#238) — 있으면 선은 사슬 전체이고 이 변은 제 몫의
        /// 요소만 그린다. 없으면 이 변 혼자의 선.
        let chain: HwpBorderChainPlacement?

        /// 로컬 (x, y) → 페이지: 가로 변은 (lineStart + x, cross + y), 세로 변은
        /// (cross + y, lineStart + x)
        func transform(lineStart: CGFloat) -> CGAffineTransform {
            horizontal
                ? CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: lineStart, ty: cross)
                : CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: cross, ty: lineStart)
        }

        /// 선 시작 — 이은 선이면 사슬의 무늬 원점 (사슬 첫 조각의 연장 포함 시작)
        private var lineStart: CGFloat {
            if let chain {
                return start - chain.offset
            }
            return start - lineLead
        }

        private var lineLength: CGFloat {
            if let chain {
                return chain.length
            }
            return end + lineTrail - lineStart
        }

        private var line: HwpLineShapeGeometry.Line {
            HwpLineShapeGeometry.Line(
                shape: shape, length: lineLength, thickness: width,
                scale: .border, placement: .border, elementRange: chain?.elementRange,
                inSpacedTable: inSpacedTable
            )
        }

        /// 이 변이 칠하는 영역의 경계 상자 (페이지 좌표) — 가로지르는 축은 모양의 띠, 선 방향은
        /// 연장 포함 [start − lead, end + trail]에 물결의 넘침·획 모서리와 원형 점선 첫·끝 원의
        /// 반지름을 더한 범위. 이은 선의 조각은 제 몫의 요소가 칠하는 범위(이웃 칸으로 넘친 대시·원
        /// 포함)를 더하고, 제 몫이 없어도 모서리 구간의 띠는 낸다 (칠하지 않는 빈 자리도 선 위다).
        /// 경로를 만들지 않는다.
        var band: CGRect? {
            guard lineLength > 0, let cross = HwpLineShapeGeometry.crossExtent(of: line) else {
                return nil
            }
            let along = HwpLineShapeGeometry.alongExtent(of: line)
            // 이은 변은 제 몫의 요소가 없어도 제 모서리 구간의 띠를 낸다 (칠하지는 않는다)
            guard along != nil || chain != nil else { return nil }
            let alongStart = min(
                lineStart + (along?.lowerBound ?? .infinity), start - leadExtension
            )
            let alongEnd = max(lineStart + (along?.upperBound ?? -.infinity), end + trailExtension)
            let localBand = CGRect(
                x: alongStart - lineStart, y: cross.lowerBound,
                width: alongEnd - alongStart, height: cross.upperBound - cross.lowerBound
            )
            return localBand.applying(transform(lineStart: lineStart))
        }

        /// 변의 경로 — 여러 줄은 부속선마다 물려 겹상자, 나머지는 연장 길이 전체를 한 경로로
        var geometry: EdgeGeometry? {
            let (lineStart, line) = (lineStart, line)
            guard let band, let extent = HwpLineShapeGeometry.crossExtent(of: line) else {
                return nil
            }
            let transform = transform(lineStart: lineStart)
            let path = CGMutablePath()
            let stripes = HwpLineShapeGeometry.stripes(for: line)
            if stripes.isEmpty {
                guard let shapePath = HwpLineShapeGeometry.path(for: line) else { return nil }
                path.addPath(shapePath, transform: transform)
            } else {
                for stripe in stripes {
                    // 바깥쪽에서의 거리만큼 이웃 변 쪽 끝을 물린다 (이웃 변이 없는 끝은 그대로;
                    // 거리는 **이웃 변 폭** 비율 — 같은 모양의 부속선이 맞닿는 자리, 실측은 같은 폭뿐)
                    let outerDistance = outerIsLeading
                        ? stripe.minY - extent.lowerBound
                        : extent.upperBound - stripe.maxY
                    let inset = outerDistance * 2 / width
                    let stripeStart = start - leadExtension + inset * leadExtension
                    let stripeEnd = end + trailExtension - inset * trailExtension
                    guard stripeEnd > stripeStart else { continue }
                    path.addRect(
                        CGRect(
                            x: stripeStart - lineStart, y: stripe.minY,
                            width: stripeEnd - stripeStart, height: stripe.height
                        ),
                        transform: transform
                    )
                }
            }
            guard !path.isEmpty else { return nil }
            return EdgeGeometry(path: path.copy() ?? path, color: color, band: band)
        }
    }

    public static func uniform(
        width: CGFloat, color: HwpRGBColor, cellSpacing: CGFloat = 0
    ) -> HwpBorderSet {
        HwpBorderSet(
            top: width,
            bottom: width,
            left: width,
            right: width,
            topColor: color,
            bottomColor: color,
            leftColor: color,
            rightColor: color,
            cellSpacing: cellSpacing
        )
    }
}
