import CoreGraphics
import CoreHwp
import Foundation

/// 표 격자선 위에서 이웃 칸과 한 선으로 이은 단선 변의 자리 (#238·#246) — 변의 로컬 축(가로 변은 x,
/// 세로 변은 y)에서 잰다. 사슬 로컬 좌표는 0 = 사슬의 무늬 원점이다.
struct HwpBorderChainPlacement: Hashable, Sendable {
    /// 사슬의 무늬 원점에서 이 변의 모서리 시작(가로 변은 칸 왼 모서리, 세로 변은 위 모서리)까지
    let offset: CGFloat
    /// 사슬 길이 — 무늬 원점에서 사슬 끝(연장 포함)까지
    let length: CGFloat
    /// 이 변이 그리는 요소의 자리 범위 (사슬 로컬) — 사슬의 첫 조각은 −∞부터, 끝에 닿는 조각은
    /// +∞까지다. 맞닿은 두 조각의 경계는 같은 값 하나를 나눠 가져 요소가 빠지거나 겹치지 않는다.
    /// 실선은 자리 0의 요소 하나라 자리 0을 담은 조각(보통 첫 조각 — 첫 칸이 제 물러남보다 좁으면 뒤
    /// 조각)이 사슬 전체를 긋는다 (`HwpLineShapeGeometry.Line`).
    let elementRange: Range<CGFloat>
}

/// 변 한쪽 끝 모서리의 격자 맥락 (#246) — 여러 줄·물결 변의 끝 자리가 이것으로 갈린다
/// (`HwpBorderSet.framedReach`·`nestedStripeOffset`·물결 옮김). 표 맥락이 없으면 그 모서리의 같은 칸
/// 이웃 변만 본다.
struct HwpBorderCornerContext: Hashable, Sendable {
    /// 변의 격자선이 모서리 너머로 같은 모양·굵기의 그린 변으로 이어진다 (색은 보지 않는다)
    var continues = false
    /// 모서리를 지나는 수직 격자선이 칸 쪽으로 그린 변을 갖는다 (같은 칸의 이웃 변이나 맞붙은 칸의
    /// 같은 자리 변)
    var crossesNear: Bool
    /// 수직 격자선이 이 변의 선 너머(칸 반대쪽)로 그린 변을 갖는다
    var crossesBeyond = false
}

/// 변 하나의 시작·끝 모서리 맥락
struct HwpBorderEndContexts: Hashable, Sendable {
    var lead: HwpBorderCornerContext
    var trail: HwpBorderCornerContext
}

/// 칸 네 변의 모서리 맥락
struct HwpBorderCorners: Hashable, Sendable {
    var top, bottom, left, right: HwpBorderEndContexts

    subscript(position: HwpBorderSet.Position) -> HwpBorderEndContexts {
        switch position {
        case .top: top
        case .bottom: bottom
        case .left: left
        case .right: right
        }
    }
}

/// 칸 네 변이 표 안에서 그려지는 차례 (작을수록 먼저, #246). 한글 12.30은 셀 간격이 없는 표를
/// ① 여러 줄·물결 변을 칸 차례로(칸마다 왼·오른·위·아래) ② 단선 세로 무리(격자선 × 모양)를 모양(표 25
/// 값) 차례, 같은 모양 안에서 격자선 x 차례로 ③ 단선 가로 무리를 모양·y 차례로 그리고 — 무리 안에서는
/// 사슬을 만든 차례다 — ④ 세로 마지막·첫 무리(사슬 거꾸로)와 가로 마지막·첫 무리(사슬 거꾸로)를 한 번
/// 더 긋는다 (`HwpBorderChaining.paintSequence` — 덧그은 조각은 마지막 차례가 남는다). 셀 간격이 있는
/// 표는 칸마다 왼·오른·위·아래로 그린다 (실측 `so246-order` 가로·세로 모양 7×7 × 셀 간격 0·283
/// 98표본, `so246-cells`·`solidchain`·`junction`의 다칸 표).
struct HwpBorderPaintOrder: Hashable, Sendable {
    var top = 0, bottom = 0, left = 0, right = 0

    subscript(position: HwpBorderSet.Position) -> Int {
        get {
            switch position {
            case .top: top
            case .bottom: bottom
            case .left: left
            case .right: right
            }
        }
        set {
            switch position {
            case .top: top = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }
}

/// 표가 셀 배치로 셈해 칸에 싣는 테두리 맥락 — 셀 혼자로는 알 수 없는 것들이다 (`HwpTableFrame.init`,
/// `HwpBorderChaining`): 이웃 칸과 이은 단선 변의 자리(#238·#246), 여러 줄·물결 변의 모서리 맥락
/// (#246), 그리는 차례(#246). 기본은 이음·맥락·차례가 없는 칸 혼자의 테두리다.
struct HwpBorderContext: Hashable, Sendable {
    var top: HwpBorderChainPlacement?
    var bottom: HwpBorderChainPlacement?
    var left: HwpBorderChainPlacement?
    var right: HwpBorderChainPlacement?
    /// 여러 줄·물결 변이 있는 칸만 싣는다 — 단선 변은 모서리 맥락을 보지 않는다
    var corners: HwpBorderCorners?
    var paintOrder: HwpBorderPaintOrder?

    static let none = HwpBorderContext()

    subscript(placement position: HwpBorderSet.Position) -> HwpBorderChainPlacement? {
        get {
            switch position {
            case .top: top
            case .bottom: bottom
            case .left: left
            case .right: right
            }
        }
        set {
            switch position {
            case .top: top = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    /// 이웃 칸과 이은 변이 하나라도 있는가
    var hasPlacements: Bool {
        top != nil || bottom != nil || left != nil || right != nil
    }
}

extension HwpTableCellFrame {
    /// 테두리 맥락만 바꾼 사본
    func withBorderContext(_ context: HwpBorderContext) -> HwpTableCellFrame {
        var copy = self
        copy.borderContext = context
        return copy
    }
}
