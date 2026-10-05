import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

// MARK: - 값 표의 형과 우리 경로 읽기

extension HwpBorderBandsTests {
    struct StripeSample {
        let shape: HwpBorderType
        let index: Int
        let stripes: [(center: CGFloat, width: CGFloat)]

        init(_ shape: HwpBorderType, _ index: Int, _ stripes: [(CGFloat, CGFloat)]) {
            self.shape = shape
            self.index = index
            self.stripes = stripes.map { (center: $0.0, width: $0.1) }
        }
    }

    struct WaveSample {
        let index: Int
        let stroke: CGFloat
        let run: CGFloat
        let halfPeriod: CGFloat
        let levels: (CGFloat, CGFloat)
        let second: CGFloat

        init(
            _ index: Int, stroke: CGFloat, run: CGFloat, halfPeriod: CGFloat,
            levels: (CGFloat, CGFloat), second: CGFloat
        ) {
            (self.index, self.stroke, self.run) = (index, stroke, run)
            (self.halfPeriod, self.levels, self.second) = (halfPeriod, levels, second)
        }
    }

    enum Side: Hashable {
        case top, bottom, left, right

        var horizontal: Bool {
            self == .top || self == .bottom
        }
    }

    /// 파 하나 — 첫 대각선 시작, 대각선 수, 마지막 요소 끝 − 선 길이 (u). 값 표는 [시작, 수, 끝 − 길이]다.
    struct WaveSummary {
        let start: CGFloat
        let count: Int
        let endPastLength: CGFloat

        init(start: CGFloat, count: Int, endPastLength: CGFloat) {
            (self.start, self.count, self.endPastLength) = (start, count, endPastLength)
        }

        init(_ values: [CGFloat]) {
            start = values[0]
            count = Int(values[1])
            endPastLength = values[2]
        }
    }

    /// 부속선 하나 — 가로지르는 중심, 폭, 시작, 끝 − 선 길이 (u). 값 표는 그 차례의 배열이다.
    struct StripeSpan {
        let cross: CGFloat
        let width: CGFloat
        let start: CGFloat
        let endPastLength: CGFloat

        init(_ values: [CGFloat]) {
            (cross, width, start, endPastLength) = (values[0], values[1], values[2], values[3])
        }
    }

    struct TableSample {
        let shape: HwpBorderType
        let index: Int
        let width: CGFloat
        let height: CGFloat
        let stripes: [Side: [StripeSpan]]
        let waves: [Side: [WaveSummary]]

        init(
            _ shape: HwpBorderType, _ index: Int, width: CGFloat, height: CGFloat,
            stripes: [Side: [[CGFloat]]]
        ) {
            (self.shape, self.index, self.width, self.height) = (shape, index, width, height)
            self.stripes = stripes.mapValues { $0.map(StripeSpan.init) }
            waves = [:]
        }

        init(
            _ shape: HwpBorderType, _ index: Int, width: CGFloat, height: CGFloat,
            waves: [Side: [[CGFloat]]]
        ) {
            (self.shape, self.index, self.width, self.height) = (shape, index, width, height)
            stripes = [:]
            self.waves = waves.mapValues { $0.map(WaveSummary.init) }
        }
    }

    struct FramedSample {
        let shape: HwpBorderType
        let millimetres: CGFloat
        let horizontal: Bool
        let neighbour: (shape: HwpBorderType, millimetres: CGFloat)
        let length: CGFloat
        let waves: [WaveSummary]

        init(
            _ shape: HwpBorderType, _ millimetres: CGFloat, _ horizontal: Bool,
            _ neighbour: (HwpBorderType, CGFloat), _ length: CGFloat, _ waves: [[CGFloat]]
        ) {
            (self.shape, self.millimetres, self.horizontal) = (shape, millimetres, horizontal)
            self.neighbour = (shape: neighbour.0, millimetres: neighbour.1)
            self.length = length
            self.waves = waves.map(WaveSummary.init)
        }
    }

    /// 한쪽 모서리만 같은 물결 이웃인 표본의 갈래
    enum HalfJoinedMode {
        /// 시작 이웃 실선 2mm (다른 모양) · 끝 이웃 같은 물결
        case endJoined
        /// 시작 이웃 같은 물결 · 끝 이웃 실선 2mm
        case startJoined
    }

    struct HalfJoinedSample {
        let shape: HwpBorderType
        let millimetres: CGFloat
        let horizontal: Bool
        let mode: HalfJoinedMode
        let length: CGFloat
        let waves: [WaveSummary]

        init(
            _ shape: HwpBorderType, _ millimetres: CGFloat, _ horizontal: Bool,
            _ mode: HalfJoinedMode,
            _ length: CGFloat, _ waves: [[CGFloat]]
        ) {
            (self.shape, self.millimetres, self.horizontal) = (shape, millimetres, horizontal)
            (self.mode, self.length) = (mode, length)
            self.waves = waves.map(WaveSummary.init)
        }
    }

    // MARK: - 우리 경로 읽기

    /// 부분 경로 하나 — 대각선인가, 선 방향 시작·끝, 가로지르는 중심, 획 폭 (u, 선 로컬)
    struct Element {
        let diagonal: Bool
        let start: CGFloat
        let end: CGFloat
        let cross: CGFloat
        let width: CGFloat
    }

    /// 부분 경로마다의 꼭짓점 (그린 차례)
    static func polygons(of path: CGPath) -> [[CGPoint]] {
        var polygons: [[CGPoint]] = []
        var current: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                if !current.isEmpty {
                    polygons.append(current)
                }
                current = [element.pointee.points[0]]
            case .addLineToPoint:
                current.append(element.pointee.points[0])
            case .closeSubpath:
                polygons.append(current)
                current = []
            default:
                break
            }
        }
        if !current.isEmpty {
            polygons.append(current)
        }
        return polygons
    }

    /// 변 경로의 부분 경로를 그린 차례대로 — 사각형은 선 방향 범위와 가로지르는 가운데·두께, 45°
    /// 평행사변형은 양 끝 획 단면의 가운데를 잇는 중심선과 단면 길이(획 폭)다. `cross`는 가로지르는 축의
    /// 원점(pt)이다.
    static func elements(of path: CGPath, horizontal: Bool, cross: CGFloat) -> [Element] {
        polygons(of: path).map { points in
            let local = points.map {
                horizontal
                    ? (along: $0.x / unit, cross: ($0.y - cross) / unit)
                    : (along: $0.y / unit, cross: ($0.x - cross) / unit)
            }
            if Set(local.map { ($0.along * 1e6).rounded() }).count <= 2 {
                let crosses = local.map(\.cross)
                let (low, high) = (crosses.min() ?? 0, crosses.max() ?? 0)
                return Element(
                    diagonal: false, start: local.map(\.along).min() ?? 0,
                    end: local.map(\.along).max() ?? 0, cross: (low + high) / 2, width: high - low
                )
            }
            let ordered = local.sorted { $0.along < $1.along }
            let head = Array(ordered.prefix(2))
            let tail = Array(ordered.suffix(2))
            return Element(
                diagonal: true, start: (head[0].along + head[1].along) / 2,
                end: (tail[0].along + tail[1].along) / 2,
                cross: (head[0].cross + head[1].cross) / 2,
                width: hypot(head[0].along - head[1].along, head[0].cross - head[1].cross)
            )
        }
    }

    /// 물결 변의 파마다 요약 — 파는 그린 차례로 이어지고 다음 파는 선 방향 앞에서 다시 시작한다
    static func waveSummaries(_ elements: [Element], length: CGFloat) -> [WaveSummary] {
        var waves: [[Element]] = []
        for element in elements {
            if let last = waves.last?.last, element.start >= last.start - 1e-6 {
                waves[waves.count - 1].append(element)
            } else {
                waves.append([element])
            }
        }
        return waves.map { wave in
            let diagonals = wave.filter(\.diagonal)
            return WaveSummary(
                start: diagonals.map(\.start).min() ?? .nan, count: diagonals.count,
                endPastLength: (wave.map(\.end).max() ?? .nan) - length
            )
        }
    }

    static func expectWaves(
        _ actual: [WaveSummary], _ expected: [WaveSummary], _ label: String
    ) {
        expect(actual.count).to(equal(expected.count), description: label)
        for (got, want) in zip(actual, expected) {
            expect(got.start).to(beCloseTo(want.start, within: 1e-6), description: label)
            expect(got.count).to(equal(want.count), description: label)
            expect(got.endPastLength)
                .to(beCloseTo(want.endPastLength, within: 1e-6), description: label)
        }
    }

    /// 칸 하나의 테두리에서 `ink` 색 변 — 시험 변과 이웃 변을 색으로 가른다 (맞물림은 색을 보지 않는다)
    static func edge(
        _ set: HwpBorderSet, around rect: CGRect, ink: HwpRGBColor
    ) -> HwpBorderSet.EdgeGeometry? {
        set.edges(around: rect).first { $0.color == ink }
    }

    static func expectStripes(
        _ elements: [Element], _ want: [StripeSpan], length: CGFloat, _ label: String
    ) {
        let got = elements.sorted { $0.cross < $1.cross }
        expect(got.count).to(equal(want.count), description: label)
        for (stripe, value) in zip(got, want) {
            expect(stripe.cross).to(beCloseTo(value.cross, within: 1e-6), description: label)
            expect(stripe.width).to(beCloseTo(value.width, within: 1e-6), description: label)
            expect(stripe.start).to(beCloseTo(value.start, within: 1e-6), description: label)
            expect(stripe.end - length)
                .to(beCloseTo(value.endPastLength, within: 1e-6), description: label)
        }
    }
}
