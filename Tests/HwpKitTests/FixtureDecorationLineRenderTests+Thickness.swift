import CoreGraphics
import Foundation
import XCTest

/// `FixtureDecorationLineRenderTests.Raster`의 선 두께·글리프 잉크 위치 헬퍼 (#187 리뷰).
/// 행 수 세기는 4px/pt에서 0.4pt(한글 문서 10pt)와 0.6pt(MS 워드 호환 10pt 상자)를
/// 못 가르므로, 선이 지나는 열의 **커버리지 합**으로 두께를 잰다 —
/// `HwpDecorationLineGeometryTests.lineThickness`와 같은 원리이되 글리프 잉크가 있는
/// 쪽이라 선을 가로지르는 획이 있는 열은 거른다.
extension FixtureDecorationLineRenderTests.Raster {
    private var scale: CGFloat {
        FixtureDecorationLineRenderTests.scale
    }

    /// 행 `y`에서 조건에 맞는 픽셀이 가로로 가장 길게 이어진 열 구간 (px).
    func longestSpan(_ y: Int, where match: (UInt8, UInt8, UInt8) -> Bool) -> Range<Int>? {
        var best: Range<Int>?
        var start: Int?
        for x in 0 ... pixelWidth {
            var hit = false
            if x < pixelWidth {
                let offset = y * bytesPerRow + x * 4
                hit = match(data[offset], data[offset + 1], data[offset + 2])
            }
            if hit {
                if start == nil {
                    start = x
                }
            } else if let begin = start {
                if best == nil || x - begin > (best?.count ?? 0) {
                    best = begin ..< x
                }
                start = nil
            }
        }
        return best
    }

    /// 선의 두께 (pt). `center` ± `halfBand`pt 행을 선의 몫으로, 그 바깥 0.5pt 행을 보호
    /// 띠로 잡아 **보호 띠가 흰 열**(글리프 획이 선을 가로지르지 않는 열)만 센다. 열의
    /// 두께는 흰 바탕(255) 대비 `channel`(선 색에서 가장 낮은 채널)의 감소량 합을 완전
    /// 커버 값으로 정규화한 값이고, 열들의 중앙값을 돌려준다. 완전 커버 값은
    /// `fullChannel`(같은 래스터의 2px 넘는 같은 색 선에서 `fullCoverageChannel`로 잰 값 —
    /// 색 공간 변환으로 선 색 채널이 0이 아니다), 없으면 그 열의 최솟값(선이 2px 이상일
    /// 때만 정확)이다. 축 정렬 사각형은 CG가 면적 그대로 덮으므로 커버리지 합이 곧 두께다.
    func lineThickness(
        center: CGFloat, halfBand: CGFloat, columns: Range<Int>,
        channel: (UInt8, UInt8, UInt8) -> UInt8, fullChannel: UInt8? = nil
    ) -> CGFloat? {
        var sums: [Double] = []
        for x in columns {
            guard let values = cleanColumn(x, center: center, halfBand: halfBand, channel: channel),
                  let least = values.min(), least < 200
            else { continue }
            let full = Double(fullChannel ?? least)
            sums.append(values.reduce(0) { $0 + (255 - Double($1)) / (255 - full) })
        }
        guard !sums.isEmpty else { return nil }
        sums.sort()
        return CGFloat(sums[sums.count / 2]) / scale
    }

    /// 선의 완전 커버 채널값 — 보호 띠가 흰 열들의 최솟값. 2px 넘는 선에서 재어 같은 색
    /// 얇은 선의 `lineThickness(fullChannel:)`에 넘긴다.
    func fullCoverageChannel(
        center: CGFloat, halfBand: CGFloat, columns: Range<Int>,
        channel: (UInt8, UInt8, UInt8) -> UInt8
    ) -> UInt8? {
        var least: UInt8?
        for x in columns {
            guard let values = cleanColumn(x, center: center, halfBand: halfBand, channel: channel),
                  let minimum = values.min()
            else { continue }
            least = min(least ?? minimum, minimum)
        }
        return least
    }

    /// 열 `x`의 선 몫 행 채널값들 — 보호 띠(`halfBand` 밖 0.5pt)에 흰색 아닌 픽셀이 있으면 nil.
    private func cleanColumn(
        _ x: Int, center: CGFloat, halfBand: CGFloat,
        channel: (UInt8, UInt8, UInt8) -> UInt8
    ) -> [UInt8]? {
        var values: [UInt8] = []
        for y in 0 ..< pixelHeight {
            let distance = abs((CGFloat(y) + 0.5) / scale - center)
            guard distance <= halfBand + 0.5 else { continue }
            let offset = y * bytesPerRow + x * 4
            let (red, green, blue) = (data[offset], data[offset + 1], data[offset + 2])
            if distance <= halfBand {
                values.append(channel(red, green, blue))
            } else if min(red, green, blue) < 235 {
                return nil
            }
        }
        return values
    }

    /// `rows`(pt, 위에서부터) 안에서 `columns`의 픽셀이 3개 넘게 조건에 맞는 첫 행의 위치
    /// (pt) — 글리프 잉크의 위 끝.
    func inkTop(
        in rows: ClosedRange<CGFloat>, columns: Range<Int>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> CGFloat? {
        for y in 0 ..< pixelHeight {
            let point = (CGFloat(y) + 0.5) / scale
            guard rows.contains(point) else { continue }
            var count = 0
            for x in columns {
                let offset = y * bytesPerRow + x * 4
                if match(data[offset], data[offset + 1], data[offset + 2]) {
                    count += 1
                }
            }
            if count > 3 {
                return point
            }
        }
        return nil
    }
}
