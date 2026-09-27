import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 이은 선의 조각(`Line.elementRange`, #238) — 표 격자선 사슬은 칸마다 한 조각씩 그리므로, 조각을
/// 모두 합치면 선 전체와 요소가 같아야 한다 (빠지거나 겹치면 칸 경계에서 원·대시가 사라지거나 진해진다).
extension HwpLineShapeGeometryTests {
    static let partitionShapes: [HwpBorderType] = [
        .circle, .longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash,
    ]

    /// 경계로 나눈 조각 범위 — 첫 조각은 −∞부터, 마지막은 +∞까지 (`HwpBorderChaining`과 같다)
    static func ranges(cuts: [CGFloat]) -> [Range<CGFloat>] {
        let bounds = [-CGFloat.infinity] + cuts + [.infinity]
        return zip(bounds, bounds.dropFirst()).map { $0 ..< $1 }
    }

    static func rounded(_ rects: [CGRect]) -> [CGRect] {
        rects.map {
            CGRect(
                x: ($0.minX * 1e6).rounded() / 1e6, y: ($0.minY * 1e6).rounded() / 1e6,
                width: ($0.width * 1e6).rounded() / 1e6, height: ($0.height * 1e6).rounded() / 1e6
            )
        }.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    /// 조각을 합치면 선 전체와 같다 — 경계가 요소 자리와 정확히 같아도 (원 간격 6의 배수, 대시 주기의
    /// 배수) 그 요소는 뒤 조각 하나가 그린다. 조각마다 선 방향 범위는 제 경로를 담고, 경로가 없으면
    /// 범위도 없다.
    func testElementRangesPartitionTheWholeLine() {
        for shape in Self.partitionShapes {
            for length: CGFloat in [7.3, 30, 90, 123.456] {
                let line = Self.borderLine(shape, thickness: 3, length: length)
                let whole = Self.rounded(Self.pieces(HwpLineShapeGeometry.path(for: line)))
                let period = HwpLineShapeGeometry.patternRepeats(of: line) > 0
                    ? length / HwpLineShapeGeometry.patternRepeats(of: line) : 1
                let cutSets: [[CGFloat]] = [
                    [length / 3, 2 * length / 3],
                    [period, 2 * period, 5 * period],
                    [0, length],
                    [-5, 1e-9, length - 1e-9],
                ]
                for cuts in cutSets {
                    var joined: [CGRect] = []
                    for range in Self.ranges(cuts: cuts) {
                        var piece = line
                        piece.elementRange = range
                        let path = HwpLineShapeGeometry.path(for: piece)
                        let along = HwpLineShapeGeometry.alongExtent(of: piece)
                        expect(path == nil) == (along == nil)
                        if let path, let along {
                            let box = path.boundingBoxOfPath
                            expect(along.lowerBound).to(beCloseTo(box.minX, within: 1e-9))
                            expect(along.upperBound).to(beCloseTo(box.maxX, within: 1e-9))
                        }
                        joined += Self.pieces(path)
                    }
                    expect(Self.rounded(joined)).to(
                        equal(whole), description: "\(shape) \(length) \(cuts)"
                    )
                }
            }
        }
    }

    /// 반복 상한을 넘어 실선 띠로 떨어진 무늬도 조각이 제 몫만 그린다 — 조각 띠를 이으면 선 전체이고
    /// 겹치지 않는다
    func testSolidFallbackIsSplitByElementRanges() {
        let line = Self.borderLine(.dotLine, thickness: 0.001, length: 10000)
        expect(HwpLineShapeGeometry.patternRepeats(of: line))
            > HwpLineShapeGeometry.maxPatternRepeats
        let bands = Self.ranges(cuts: [2500, 7000]).map { range -> CGRect in
            var piece = line
            piece.elementRange = range
            return HwpLineShapeGeometry.path(for: piece)?.boundingBoxOfPath ?? .null
        }
        expect(bands.map(\.minX)) == [0, 2500, 7000]
        expect(bands.map(\.maxX)) == [2500, 7000, 10000]
        var outside = line
        outside.elementRange = 20000 ..< .infinity
        expect(HwpLineShapeGeometry.path(for: outside)).to(beNil())
        expect(HwpLineShapeGeometry.alongExtent(of: outside)).to(beNil())
    }

    /// 대시 주기가 무한대로 넘친 입력(두께가 유한 최댓값 근처)도 조각을 합치면 선 전체다 — 선 전체는
    /// 첫 대시 하나가 길이만큼이고, 그 자리(0)를 맡은 조각 하나가 그린다
    func testInfinitePeriodDashesStillPartition() {
        let line = Self.borderLine(.dotLine, thickness: 1e308, length: 100)
        let whole = Self.pieces(HwpLineShapeGeometry.path(for: line))
        expect(whole.count) == 1
        let joined = Self.ranges(cuts: [40]).flatMap { range -> [CGRect] in
            var piece = line
            piece.elementRange = range
            return Self.pieces(HwpLineShapeGeometry.path(for: piece))
        }
        expect(joined) == whole
    }

    /// 조각 범위는 대시·원형 점선만 본다 — 실선·여러 줄·물결은 범위와 무관하게 선 전체다
    func testElementRangeIsIgnoredByUnpatternedShapes() {
        for shape: HwpBorderType in [.line, .doubleLine, .wave, .doubleWave] {
            let line = Self.borderLine(shape, thickness: 3, length: 60)
            var piece = line
            piece.elementRange = 20 ..< 30
            expect(HwpLineShapeGeometry.path(for: piece)?.boundingBoxOfPath)
                == HwpLineShapeGeometry.path(for: line)?.boundingBoxOfPath
            expect(HwpLineShapeGeometry.alongExtent(of: piece))
                == HwpLineShapeGeometry.alongExtent(of: line)
        }
    }
}
