import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 변 기하 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

extension HwpBorderSet {
    /// 여러 줄 부속선 하나 — 로컬 띠와 선 방향 [시작, 끝] (페이지 축, `Edge.stripeSpans`)
    fileprivate struct StripeSpan {
        let stripe: CGRect
        let start: CGFloat
        let end: CGFloat
    }

    /// 한 변의 입력 — `HwpLineShapeGeometry`의 로컬 좌표(x = 선 방향, y = 가로지르는 축, 0 = 모서리)를
    /// 페이지 좌표로 옮기는 데 필요한 값
    struct Edge {
        let border: Border
        let position: Position
        /// 시작·끝 모서리에서 만나는 같은 칸의 이웃 변 (가로 변은 왼·오른, 세로 변은 위·아래)
        let lead: Border
        let trail: Border
        /// 선 방향 축의 셀 모서리 시작·끝
        let start: CGFloat
        let end: CGFloat
        /// 가로지르는 축의 모서리 좌표 (선 중심)
        let cross: CGFloat
        /// 시작·끝 모서리의 격자 맥락 (#246 — 표 맥락이 없으면 이 칸의 이웃 변만으로)
        let corners: HwpBorderEndContexts
        /// 셀 간격이 있는 표의 변인가 (#243) — 원형 점선의 원 크기·간격이 점 무늬다
        let inSpacedTable: Bool
        /// 이웃 칸과 이은 단선의 자리 (#238·#246) — 있으면 선은 사슬 전체이고 이 변은 제 몫의 요소만
        /// 그린다 (실선은 자리 0을 담은 조각이 통째로). 없으면 이 변 혼자의 선.
        let chain: HwpBorderChainPlacement?
        /// 표 안에서 그리는 차례 (`EdgeGeometry.order`)
        let order: Int

        private var horizontal: Bool {
            position.isHorizontal
        }

        /// 히트 띠가 시작·끝 이웃 쪽으로 넓어지는 길이 — 이웃 변이 그리는 폭의 절반
        private var leadExtension: CGFloat {
            lead.drawn / 2
        }

        private var trailExtension: CGFloat {
            trail.drawn / 2
        }

        /// 여러 줄(2중선 셋·3중선)인가 — 부속선마다 끝 자리가 다를 수 있다 (`stripeSpans`)
        private var isMultiLine: Bool {
            HwpBorderSet.isFramed(border.shape) && border.shape != .wave
                && border.shape != .doubleWave
        }

        /// 선이 시작 모서리 밖으로 나가는 길이 (음수면 물러난다) — 단선은 `singleLineReach`, 여러
        /// 줄·물결은 이웃이 같으면 물결의 옮김(`waveShift`)이고 다르면 `framedReach`다. 여러 줄은 이웃이
        /// 같은 끝을 부속선마다 따로 정한다 (`stripeSpans`).
        private var lineLead: CGFloat {
            if HwpBorderSet.isSingleLine(border.shape) {
                return HwpBorderSet.singleLineReach(
                    of: border, horizontal: horizontal, neighbour: lead, spaced: inSpacedTable
                )
            }
            if border.matches(lead) {
                return -waveShift
            }
            return HwpBorderSet.framedReach(
                horizontal: horizontal, neighbour: lead, corner: corners.lead
            )
        }

        /// 선이 끝 모서리 밖으로 나가는 길이 (음수면 물러난다)
        private var lineTrail: CGFloat {
            if HwpBorderSet.isSingleLine(border.shape) {
                return HwpBorderSet.singleLineReach(
                    of: border, horizontal: horizontal, neighbour: trail, spaced: inSpacedTable
                )
            }
            if border.matches(trail) {
                return waveShift
            }
            return HwpBorderSet.framedReach(
                horizontal: horizontal, neighbour: trail, corner: corners.trail
            )
        }

        /// 같은 모양·굵기 이웃과 맞물린 물결이 변을 통째로 옮기는 길이 (선 방향, 양수 = 끝 쪽) — 한글은
        /// 그 물결을 칸 변과 같은 길이로 두고 **시작** 모서리의 수직 격자선이 물결 띠 쪽(가로 변은 위,
        /// 세로 변은 왼쪽 — 띠가 그쪽으로 치우친다)에 그린 변을 가지면 굵기 획의 1/4만큼 뒤로, 아니면
        /// 절반만큼 앞으로 옮긴다 (#246 실측 `so246-wave`: 1mm 물결의 칸 폭·높이를 1u씩 늘린 1×1·1×2·
        /// 2×1·2×2 표 156개에서 대각선이 느는 자리가 모두 끝 모서리 + 이 길이; 끝 모서리의 맥락은 보지
        /// 않는다). 다른 모양 이웃 쪽 끝은 `framedReach`다.
        private var waveShift: CGFloat {
            let reach = border.reach
            // 위·왼 변은 띠 쪽이 칸 바깥(모서리 너머), 아래·오른 변은 칸 쪽이다
            let bandSideDrawn = position.outerIsLeading
                ? corners.lead.crossesBeyond : corners.lead.crossesNear
            return bandSideDrawn ? reach / 4 : -reach / 2
        }

        /// 로컬 (x, y) → 페이지: 가로 변은 (lineStart + x, cross + y), 세로 변은
        /// (cross + y, lineStart + x)
        private func transform(lineStart: CGFloat) -> CGAffineTransform {
            horizontal
                ? CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: lineStart, ty: cross)
                : CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: cross, ty: lineStart)
        }

        /// 선 시작 — 이은 선이면 사슬의 무늬 원점 (사슬 첫 조각의 연장 포함 시작), 여러 줄은 모서리
        /// (부속선 자리는 `stripeSpans`가 정한다)
        private var lineStart: CGFloat {
            if let chain {
                return start - chain.offset
            }
            return isMultiLine ? start : start - lineLead
        }

        private var lineLength: CGFloat {
            if let chain {
                return chain.length
            }
            return isMultiLine ? end - start : end + lineTrail - lineStart
        }

        private var line: HwpLineShapeGeometry.Line {
            HwpLineShapeGeometry.Line(
                shape: border.shape, length: lineLength, thickness: border.visible,
                scale: .border, placement: .border, elementRange: chain?.elementRange,
                inSpacedTable: inSpacedTable
            )
        }

        /// 여러 줄 부속선마다의 자리. 이웃과 모양·굵기가 다른 끝은 부속선 모두 `framedReach` 자리이고,
        /// 같은 끝은 부속선마다 이웃의 부속선과 맞물린다 (`nestedStripeOffset`). 그릴 길이가 없는
        /// 부속선은 뺀다.
        private func stripeSpans(of line: HwpLineShapeGeometry.Line) -> [StripeSpan] {
            let stripes = HwpLineShapeGeometry.stripes(for: line)
            let ranges = stripes.map { $0.minY ... $0.maxY }
            let band = HwpLineShapeGeometry.multiLineBand(for: line)
            let leadSides = drawnSides(at: corners.lead)
            let trailSides = drawnSides(at: corners.trail)
            let joinsLead = border.matches(lead)
            let joinsTrail = border.matches(trail)
            let leadReach = HwpBorderSet.framedReach(
                horizontal: horizontal, neighbour: lead, corner: corners.lead
            )
            let trailReach = HwpBorderSet.framedReach(
                horizontal: horizontal, neighbour: trail, corner: corners.trail
            )
            return zip(stripes, ranges).compactMap { stripe, range in
                let spanStart = joinsLead
                    ? start + HwpBorderSet.nestedStripeOffset(
                        range, among: ranges, band: band, atStart: true, drawn: leadSides
                    )
                    : start - leadReach
                let spanEnd = joinsTrail
                    ? end + HwpBorderSet.nestedStripeOffset(
                        range, among: ranges, band: band, atStart: false, drawn: trailSides
                    )
                    : end + trailReach
                return spanEnd > spanStart
                    ? StripeSpan(stripe: stripe, start: spanStart, end: spanEnd) : nil
            }
        }

        /// 모서리의 수직 격자선이 이 변의 선 −쪽·+쪽에 그린 변을 갖는가 — 칸은 위·왼 변이면 +쪽,
        /// 아래·오른 변이면 −쪽이다
        private func drawnSides(at corner: HwpBorderCornerContext) -> (minus: Bool, plus: Bool) {
            position.outerIsLeading
                ? (corner.crossesBeyond, corner.crossesNear)
                : (corner.crossesNear, corner.crossesBeyond)
        }

        /// 이 변이 칠하는 영역의 경계 상자 (페이지 좌표) — 가로지르는 축은 모양의 띠, 선 방향은
        /// 연장 포함 [start − lead, end + trail]에 칠하는 범위(물결의 넘침·획 모서리, 원형 점선 첫·끝 원의
        /// 반지름, 여러 줄 부속선의 끝)를 더한 범위. 이은 선의 조각은 제 몫의 요소가 칠하는 범위(이웃
        /// 칸으로 넘친 대시·원, 자리 0을 담은 조각이 그은 실선 사슬 전체)를 더하고, 제 몫이 없어도 모서리 구간의
        /// 띠는 낸다 (칠하지 않는 빈 자리도 선 위다). 경로를 만들지 않는다.
        var band: CGRect? {
            let (lineStart, line) = (lineStart, line)
            guard lineLength > 0, let crossRange = HwpLineShapeGeometry.crossExtent(of: line) else {
                return nil
            }
            let along: ClosedRange<CGFloat>? = if isMultiLine {
                stripeSpans(of: line).reduce(nil) { extent, span in
                    guard let extent else { return span.start ... span.end }
                    return min(extent.lowerBound, span.start) ... max(extent.upperBound, span.end)
                }
            } else {
                HwpLineShapeGeometry.alongExtent(of: line).map {
                    (lineStart + $0.lowerBound) ... (lineStart + $0.upperBound)
                }
            }
            // 이은 변은 제 몫의 요소가 없어도 제 모서리 구간의 띠를 낸다 (칠하지는 않는다)
            guard along != nil || chain != nil else { return nil }
            let alongStart = min(along?.lowerBound ?? .infinity, start - leadExtension)
            let alongEnd = max(along?.upperBound ?? -.infinity, end + trailExtension)
            let localBand = CGRect(
                x: alongStart - lineStart, y: crossRange.lowerBound,
                width: alongEnd - alongStart, height: crossRange.upperBound - crossRange.lowerBound
            )
            return localBand.applying(transform(lineStart: lineStart))
        }

        /// 변의 경로 — 여러 줄은 부속선마다 제 끝 자리의 띠, 나머지는 선 전체를 한 경로로
        var geometry: EdgeGeometry? {
            let (lineStart, line) = (lineStart, line)
            guard let band else { return nil }
            let transform = transform(lineStart: lineStart)
            let path = CGMutablePath()
            if isMultiLine {
                for span in stripeSpans(of: line) {
                    path.addRect(
                        CGRect(
                            x: span.start - lineStart, y: span.stripe.minY,
                            width: span.end - span.start, height: span.stripe.height
                        ),
                        transform: transform
                    )
                }
            } else if let shapePath = HwpLineShapeGeometry.path(for: line) {
                path.addPath(shapePath, transform: transform)
            }
            guard !path.isEmpty else { return nil }
            return EdgeGeometry(
                path: path.copy() ?? path, color: border.color, band: band, order: order
            )
        }
    }

    /// 같은 모양·굵기 이웃과 맞물린 모서리에서 여러 줄 부속선 하나가 끝나는 자리 — 모서리에서 선
    /// 방향으로 잰 거리 (양수 = 끝 쪽). 이웃 변의 부속선은 이 변과 같은 띠(`among`)다. 한글 12.30 실측
    /// (#246 `so246-junction`·`so246-multi` — 2중선·3중선·가는+굵은 1×1 모서리와 2×2·3×3 격자의
    /// T·+ 교차점):
    ///
    /// - 선 중심을 걸친 부속선(3중선 가운데)은 이웃의 가운데 부속선 먼 가장자리까지 간다 (교차점에서도
    ///   가운데 부속선끼리는 엇갈려 지난다).
    /// - 한쪽 부속선은 모서리의 수직 격자선이 **그 쪽에** 그린 변을 가지면 이웃 부속선 가운데 다가오는
    ///   쪽에서 가장 가까운 것의 먼 가장자리에서 멈추고 (그 부속선과 맞붙어 모서리가 닫힌다 — 겹상자와
    ///   교차점 ╬), 아니면 이웃 띠의 먼 가장자리까지 나간다 (바깥 테두리의 바깥 부속선이 이어진다).
    ///   칸 쪽에는 늘 이웃 변이 있다.
    ///
    /// `drawn`은 수직 격자선이 이 변의 선 −쪽·+쪽에 그린 변을 갖는가다. 시작 모서리에서는 +쪽에서,
    /// 끝 모서리에서는 −쪽에서 다가온다.
    static func nestedStripeOffset(
        _ stripe: ClosedRange<CGFloat>, among stripes: [ClosedRange<CGFloat>],
        band: ClosedRange<CGFloat>, atStart: Bool, drawn: (minus: Bool, plus: Bool)
    ) -> CGFloat {
        let epsilon = 1e-9 * max(1, band.upperBound - band.lowerBound)
        func straddles(_ range: ClosedRange<CGFloat>) -> Bool {
            range.lowerBound < -epsilon && range.upperBound > epsilon
        }
        if straddles(stripe), let center = stripes.first(where: straddles) {
            return atStart ? center.lowerBound : center.upperBound
        }
        let onPlusSide = stripe.lowerBound >= -epsilon
        guard onPlusSide ? drawn.plus : drawn.minus else {
            return atStart ? band.lowerBound : band.upperBound
        }
        if atStart {
            return stripes.max { $0.upperBound < $1.upperBound }?.lowerBound ?? band.lowerBound
        }
        return stripes.min { $0.lowerBound < $1.lowerBound }?.upperBound ?? band.upperBound
    }
}
