import CoreGraphics
import CoreHwp
import Foundation

/// 셀 4방향 테두리 (pt 굵기 + 색상 + 선 모양). 굵기 0이거나 모양이 `none`이면 그리지 않는다 — 다만
/// `none`도 저장된 굵기는 모서리 계산에 쓴다 (한글 12.30 실측, #246: 선 없음·굵기 2mm 세로 변 옆의
/// 가로 실선이 그 굵기의 절반만큼 모서리 밖으로 나간다).
///
/// 선은 한글처럼 **셀 모서리에 중심**을 두고 양쪽으로 폭의 절반씩 걸친다 (#191) — 이웃 셀과 공유하는
/// 모서리는 양쪽 셀이 각자 자기 선을 겹쳐 그린다. 선이 모서리에서 나가고 물러나는 자리는 선 모양의
/// 두 갈래와 그 모서리에서 만나는 이웃 변으로 정한다 (#246 — 규칙과 실측은
/// `Sources/HwpKitCore/AGENTS.md`의 표 셀 테두리 항목):
///
/// - **단선**(실선·대시·원형 점선, 3D 넷은 실선으로 대체)은 셀 간격이 없는 표에서 같은 격자선의 같은
///   모양·굵기·색 변과 한 선으로 이어 그리고 (`HwpBorderChaining` — #238의 대시·원형 점선에 더해
///   실선도), 선 끝 모서리의 이웃 변이 여러 줄·물결이면 가로·세로 모두 그 굵기의 절반만큼 **물러나며**,
///   그 밖이면(단선·선 없음) 가로 변만 그만큼 나간다 (세로 변은 모서리에서). 셀 간격이 있는 표는 칸마다
///   상자다 (#243): 이웃과 모양·굵기가 같은 모서리는 맞물려 나가고 (원형 점선은 모서리에서), 다르면
///   가로 변은 나가고 세로 변은 물러난다.
/// - **여러 줄·물결**은 셀 간격과 무관하다. 이웃 변과 모양·굵기가 같으면 (색은 보지 않는다) 여러 줄은
///   부속선마다 이웃 부속선과 맞물려 겹상자·교차점을 이루고, 물결은 파마다 2중선의 부속선처럼 물려 선
///   전체를 옮긴다 (#253). 다르면 가로 변은 나가고 세로 변은 물러나되, 표 격자의 이어짐·지나감이 그
///   자리를 바꾼다 (`HwpBorderCornerContext` — 표가 셀 배치로 셈해 칸에 싣는다).
///
/// 이은 대시·원형 점선은 사슬의 무늬 자리를 받아 제 몫의 요소만 그리고 (#238), 이은 실선은 자리 0을
/// 담은 조각(보통 첫 조각)이 한 번에 긋는다. 그리는 차례도 표가 정한다 (`EdgeGeometry.order`,
/// `HwpBorderPaintOrder`).
public struct HwpBorderSet: Sendable, Hashable {
    /// 변 굵기 (pt, 표 26) — 모양이 `none`이어도 저장된 굵기를 싣는다 (#246, 모서리 계산에 쓴다)
    public let top, bottom, left, right: CGFloat
    public let topColor, bottomColor, leftColor, rightColor: HwpRGBColor
    /// 선 모양 (표 25) — 점선·파선·여러 줄·물결은 `HwpLineShapeGeometry`가 두께 축척으로
    /// 그린다 (#191). `none`은 굵기와 무관하게 그리지 않는다.
    public let topShape, bottomShape, leftShape, rightShape: HwpBorderType
    /// 이 칸이 속한 표의 셀 간격 (pt, 표 76 `cellSpacing`) — 0보다 크면 단선 변을 한글처럼 칸마다
    /// 상자로 그린다 (#243, 타입 설명). 0이면 이웃 칸과 맞닿은 격자다.
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

    /// 한 변의 그리기 — 페이지 좌표 채우기 경로 + 색 + 히트용 띠 + 차례. 모듈 안(페인터·히트) 전용.
    struct EdgeGeometry: @unchecked Sendable {
        /// 불변 경로 — `Edge.geometry`가 소유권 경계에서 복사해 넣는다 (`HwpPaintCommand`가 retain)
        let path: CGPath
        let color: HwpRGBColor
        /// 이 변이 칠하는 영역의 경계 상자 (모서리에 중심을 둔 띠, 연장·물결 넘침·첫 원 반지름 포함)
        let band: CGRect
        /// 표 안에서 그리는 차례 — 작을수록 먼저다 (`HwpBorderPaintOrder`, #246). 표 맥락이 없는 칸은
        /// 0이라 내는 차례 그대로다.
        let order: Int
    }

    /// rect 둘레에 **실제로 칠하는 변 전부** — 페인터 (`HwpPaintListBuilder.borderCommands`)
    /// 와 히트 (`HwpTableCellFrame.paints`, `bands(around:context:)`) 가 같은 변 기하(`Edge`)를
    /// 공유한다 (R56). 두 곳이 따로 계산하면 보이는 선과 눌리는 선이 갈린다. 히트 띠는 이 변들의
    /// 띠에 더해 칠하지 않는 이은 변(제 몫의 요소가 없는 변)의 띠도 낸다 (`bands(around:context:)`).
    /// `context`는 표가 셀 배치로 셈한 이음 자리·모서리 맥락·그리는 차례다 (#238·#246 — 없으면 이
    /// 칸 혼자의 변). 내는 차례는 셀 간격이 없으면 위·아래·왼·오른, 있으면 왼·오른·위·아래이고 그리는
    /// 차례는 `EdgeGeometry.order`가 정한다.
    func edges(around rect: CGRect, context: HwpBorderContext = .none) -> [EdgeGeometry] {
        drawnEdges(around: rect, context: context).compactMap(\.geometry)
    }

    /// rect 둘레 변들의 히트 띠 — 경로를 만들지 않아 히트 판정마다 싸다. 칠하는 변의 경계 상자는
    /// `edges(around:context:)`가 내는 `EdgeGeometry.band`와 같고, 이웃 칸과 이은 변 가운데 제 몫의
    /// 요소가 없는 변(무늬의 빈 자리, 이웃 칸이 넘겨 그린 대시, 자리 0을 담은 조각이 한 번에 그은 실선만
    /// 지나는 변)도 선 위라 띠를 낸다 — 그 변은 칠하지 않으므로 `edges`에는 없다 (#238).
    func bands(around rect: CGRect, context: HwpBorderContext = .none) -> [CGRect] {
        drawnEdges(around: rect, context: context).compactMap(\.band)
    }

    /// rect와 그 둘레 테두리 띠를 모두 담는 경계 상자 — 히트 자격 영역이 칠한 곳을 다
    /// 덮도록 (R54 `자격 ⊇ 칠`) 셀·표 프레임에 테두리 바깥 절반을 더한다.
    func paintedBounds(around rect: CGRect, context: HwpBorderContext = .none) -> CGRect {
        bands(around: rect, context: context).reduce(rect) { $0.union($1) }
    }

    /// 셀 간격이 있는 표의 칸인가 — 단선 변을 칸마다 상자로 그리고 이웃 칸과 잇지 않는다 (#243).
    /// 무늬 이음(`HwpBorderChaining`)도 같은 술어를 쓴다.
    var isSpacedCell: Bool {
        cellSpacing > 0
    }

    /// 변 폭 — 폭이 있고 모양이 `none`이 아니면 그 폭, 아니면 0 (그리지 않는 변)
    static func visibleWidth(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
        width > 0 && shape != .none ? width : 0
    }

    /// 모서리에서 선이 나가거나 물러나는 길이의 기준 폭 — 이웃 변 굵기를 장치 단위로 반올림한 획
    /// (`HwpLineShapeGeometry.borderStrokeThickness(_:)`)이고 이웃 모양은 보지 않는다 (#245 실측: 파랑
    /// 2mm 실선 세로 변(47u) 사이의 0.4mm 긴 점선 위 변이 양 끝으로 23u·24u 나간다; #243: 같은 굵기면
    /// 실선·대시·원형 점선·여러 줄·물결 이웃이 같은 자리를 낸다). 선 없음(`none`)도 저장된 굵기대로다
    /// (#246 실측: 선 없음 0.5·2·5mm 이웃 옆 실선 위 변이 0.68·2.72·7.04pt 나간다). 여러 줄·물결은 이 획을
    /// 모서리의 장치 단위 행으로 나눠 쓰고 (`framedReach` — #253), 같은 모양 이웃과의 겹상자 물림은 부속선
    /// 행(`HwpLineShapeGeometry.Stripe.slot`)으로 정한다. 히트 띠는 이웃이 **그리는** 폭(`drawnWidth`)을 쓴다.
    static func reachWidth(_ width: CGFloat) -> CGFloat {
        width > 0 && width.isFinite ? HwpLineShapeGeometry.borderStrokeThickness(width) : 0
    }

    /// 이웃 변이 그리는 폭 — 단선은 장치 단위로 반올림한 획(`reachWidth`), 여러 줄·물결은 그 모양이 칠하는
    /// 가로지르는 범위의 폭(장치 단위 띠 — #253; 물결은 띠가 선 중심의 −쪽으로 치우쳐도 범위 전체), 원형
    /// 점선은 명목 폭, 그리지 않는 변은 0이다. 히트 띠의 연장이 이 값의 절반이다.
    static func drawnWidth(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
        let visible = visibleWidth(width, shape)
        guard visible > 0 else { return 0 }
        if HwpLineShapeGeometry.isSolid(shape) || isDashed(shape) {
            return reachWidth(visible)
        }
        guard isFramed(shape) else { return visible }
        let line = HwpLineShapeGeometry.Line(
            shape: shape, length: 1, thickness: visible, scale: .border, placement: .border
        )
        guard let extent = HwpLineShapeGeometry.crossExtent(of: line) else { return visible }
        return extent.upperBound - extent.lowerBound
    }

    /// 대시 5종 (긴 점선·점선·일점쇄선·이점쇄선·긴 파선)
    private static func isDashed(_ shape: HwpBorderType) -> Bool {
        HwpLineShapeGeometry.isPatterned(shape) && shape != .circle
    }

    /// 한 줄로 그리는 모양 — 실선(3D 넷은 실선으로 대체한다)·대시·원형 점선. 셀 간격이 없는 표에서
    /// 격자선을 따라 이어 그리고 (`HwpBorderChaining`), 셀 간격이 있는 표에서 칸마다 상자로 그린다.
    static func isSingleLine(_ shape: HwpBorderType) -> Bool {
        HwpLineShapeGeometry.isSolid(shape) || HwpLineShapeGeometry.isPatterned(shape)
    }

    /// 여러 줄(2중선 셋·3중선)·물결·2중 물결 — 모서리를 이웃과 맞물리거나 띠로 막는 갈래 (#246)
    static func isFramed(_ shape: HwpBorderType) -> Bool {
        shape != .none && !isSingleLine(shape)
    }

    // MARK: - 변

    /// 변의 자리 — 위·아래는 가로 변, 왼·오른은 세로 변
    enum Position: CaseIterable {
        case top, bottom, left, right

        /// 셀 간격이 있는 칸이 변을 내는 차례 (`edges(around:context:)`)
        static let spacedOrder: [Position] = [.left, .right, .top, .bottom]

        var isHorizontal: Bool {
            self == .top || self == .bottom
        }

        /// 띠의 바깥쪽이 −y/−x 쪽인가 (위·왼 변) — 곧 칸이 선의 +쪽에 있다
        var outerIsLeading: Bool {
            self == .top || self == .left
        }

        /// 시작·끝 모서리에서 만나는 이웃 변 — 가로 변은 왼·오른, 세로 변은 위·아래
        var neighbours: (lead: Position, trail: Position) {
            isHorizontal ? (.left, .right) : (.top, .bottom)
        }

        /// 한 칸 안에서 한글이 그리는 차례 — 왼·오른·위·아래 (#243·#246, `HwpBorderPaintOrder`)
        var paintIndex: Int {
            switch self {
            case .left: 0
            case .right: 1
            case .top: 2
            case .bottom: 3
            }
        }
    }

    /// 변 하나의 모양·굵기 속성(그리지 않는 변도 저장된 굵기)·색
    struct Border: Equatable {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor

        /// 그리는 변인가
        var isDrawn: Bool {
            width > 0 && shape != .none
        }

        /// 그리는 폭 (그리지 않으면 0) — 선 기하의 두께
        var visible: CGFloat {
            HwpBorderSet.visibleWidth(width, shape)
        }

        /// 선이 모서리에서 나가거나 물러나는 기준 폭 (`reachWidth`)
        var reach: CGFloat {
            HwpBorderSet.reachWidth(width)
        }

        /// 그리는 폭 — 히트 띠의 기준 (`drawnWidth`)
        var drawn: CGFloat {
            HwpBorderSet.drawnWidth(width, shape)
        }

        /// 그리는 여러 줄·물결인가
        var isFramed: Bool {
            isDrawn && HwpBorderSet.isFramed(shape)
        }

        /// `other`와 모양·굵기가 같은 그리는 변인가 — 색은 보지 않는다 (#243·#246 실측: 초록·파랑이
        /// 맞물린다)
        func matches(_ other: Border) -> Bool {
            isDrawn && other.isDrawn && shape == other.shape && width == other.width
        }
    }

    func border(_ position: Position) -> Border {
        switch position {
        case .top: Border(shape: topShape, width: top, color: topColor)
        case .bottom: Border(shape: bottomShape, width: bottom, color: bottomColor)
        case .left: Border(shape: leftShape, width: left, color: leftColor)
        case .right: Border(shape: rightShape, width: right, color: rightColor)
        }
    }

    private func drawnEdges(around rect: CGRect, context: HwpBorderContext) -> [Edge] {
        let spaced = isSpacedCell
        return (spaced ? Position.spacedOrder : Position.allCases).compactMap { position in
            let own = border(position)
            guard own.isDrawn else { return nil }
            let (leadPosition, trailPosition) = position.neighbours
            let lead = border(leadPosition)
            let trail = border(trailPosition)
            let horizontal = position.isHorizontal
            let corners = context.corners?[position] ?? HwpBorderEndContexts(
                lead: HwpBorderCornerContext(crossesNear: lead.isDrawn),
                trail: HwpBorderCornerContext(crossesNear: trail.isDrawn)
            )
            let cross = switch position {
            case .top: rect.minY
            case .bottom: rect.maxY
            case .left: rect.minX
            case .right: rect.maxX
            }
            return Edge(
                border: own, position: position, lead: lead, trail: trail,
                start: horizontal ? rect.minX : rect.minY, end: horizontal ? rect.maxX : rect.maxY,
                cross: cross, corners: corners, inSpacedTable: spaced,
                chain: context[placement: position],
                order: context.paintOrder?[position] ?? 0
            )
        }
    }

    // MARK: - 모서리 자리

    /// 단선(실선·대시·원형 점선) 변이 모서리 밖으로 나가는 길이 (음수면 안으로 물러난다) — `neighbour`는
    /// 그 모서리에서 만나는 같은 칸의 이웃 변이다. 이은 선(#238)은 사슬의 원점·끝으로 쓴다
    /// (`HwpBorderChaining`).
    ///
    /// - 셀 간격이 없는 표: 이웃이 여러 줄·물결이면 가로·세로 모두 이웃 굵기의 절반만큼 물러나고 (#246
    ///   실측 `so246-single`: 이웃 2중선·3중선·가는+굵은·물결 0.4~2mm × 실선·긴 점선·원형 점선·일점쇄선
    ///   가로·세로 56표본, 이웃 모양·굵기·색과 무관), 그 밖(단선·선 없음)이면 가로 변은 그만큼 나가고
    ///   세로 변은 모서리에서다 (#191 — 가로 변이 모서리를 메운다).
    /// - 셀 간격이 있는 표 (#243): 이웃과 모양·굵기가 같은 **맞물린 모서리**면 원형 점선은 모서리에서,
    ///   실선·대시는 가로·세로 변 모두 굵기의 절반만큼 나간다. 맞물리지 않으면(여러 줄·물결·선 없음 이웃
    ///   포함) 가로 변은 이웃 굵기의 절반만큼 나가고 세로 변은 그만큼 물러난다.
    static func singleLineReach(
        of own: Border, horizontal: Bool, neighbour: Border, spaced: Bool
    ) -> CGFloat {
        let half = neighbour.reach / 2
        guard spaced else {
            if neighbour.isFramed {
                return -half
            }
            return horizontal ? half : 0
        }
        if own.matches(neighbour) {
            return own.shape == .circle ? 0 : half
        }
        return horizontal ? half : -half
    }

    /// 여러 줄·물결 변이 이웃과 모양·굵기가 **다른** 모서리에서 나가는 길이 (음수면 물러난다) — 부속선과
    /// 물결 파 모두 같은 자리다 (겹상자 없음). 셀 간격과 무관하다 (#246 실측 `so246-multi`·`multi283`·
    /// `junction`). 이웃 굵기의 획 B(장치 단위, `reachWidth`)를 모서리에 놓인 행 [−⌊B/2⌋, ⌈B/2⌉)로 본다 (#253):
    ///
    /// - 가로 변: 같은 격자선이 모서리 너머로 같은 모양·굵기의 변으로 이어지면 모서리에서 (색 무관),
    ///   아니면 세로 격자선이 모서리 위·아래로 지나가면 그 행 밖으로 물러나고, 아니면 그 행을 덮는다 —
    ///   시작은 ⌊B/2⌋ 앞에서, 끝은 ⌈B/2⌉ − 1u 뒤에서 (한글은 끝을 행의 마지막 장치 칸에서 멈춘다).
    /// - 세로 변: 가로 격자선이 모서리 좌우로 지나가면 물러나고, 아니면 같은 격자선이 같은 모양·굵기로
    ///   이어지면 모서리에서, 아니면 물러난다.
    ///
    /// 물러나면 시작은 ⌈B/2⌉ 뒤, 끝은 ⌊B/2⌋ 앞이다. 한글 12.30 실측 (#253 `probes/253` `so253-ends` — 1mm
    /// 물결·2중 물결 × 이웃 실선 2·0.5mm·선 없음 0.1·2mm·2중선 1mm × 가로·세로, 칸 길이를 1u씩 늘린 300표본:
    /// 대각선이 느는 자리와 첫 대각선이 모두 이 끝·시작; `so246-multi` 여러 줄 변도 같다). 장치 단위로
    /// 반올림하지 않는 두께(상한 밖)는 행 대신 절반씩이다.
    static func framedReach(
        horizontal: Bool, neighbour: Border, corner: HwpBorderCornerContext, atStart: Bool
    ) -> CGFloat {
        let halves = ReachHalves(neighbour)
        let crossPasses = corner.crossesNear && corner.crossesBeyond
        let recede = atStart ? -halves.high : -halves.low
        if horizontal {
            if corner.continues {
                return 0
            }
            if crossPasses {
                return recede
            }
            return atStart ? halves.low : max(0, halves.high - halves.unit)
        }
        if crossPasses {
            return recede
        }
        return corner.continues ? 0 : recede
    }

    /// 이웃 획(`reachWidth`)을 모서리에 놓인 장치 단위 행 [−⌊B/2⌋, ⌈B/2⌉)로 본 앞·뒤 몫과 장치 단위 (pt) —
    /// 반올림 상한 밖 두께는 절반씩이고 단위는 0이다.
    struct ReachHalves {
        let low: CGFloat
        let high: CGFloat
        let unit: CGFloat

        init(_ neighbour: Border) {
            let reach = neighbour.reach
            guard reach > 0, neighbour.width < HwpLineShapeGeometry.deviceRoundingLimit else {
                (low, high, unit) = (reach / 2, reach / 2, 0)
                return
            }
            unit = HwpRenderTuning.LineShape.deviceUnit
            let units = (reach / unit).rounded()
            let lowUnits = (units / 2).rounded(.down)
            (low, high) = (lowUnits * unit, (units - lowUnits) * unit)
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
