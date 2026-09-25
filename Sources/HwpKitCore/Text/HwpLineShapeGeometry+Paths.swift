import CoreGraphics
import Foundation

// MARK: - 경로 조각 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// `HwpLineShapeGeometry.path(for:)`가 모양마다 부르는 경로 조각 — 대시·원·물결의 부분
/// 경로를 로컬 좌표(x = 선 방향, y = 가로지르는 축, 0 = 단선 중심, 양수 = 아래)에 더한다.
/// 축척·자리는 본체의 헬퍼(`dashUnit`·`circleDiameter`·`waveTopVertex` …)가 정한다.
extension HwpLineShapeGeometry {
    static func addDashes(_ pattern: [CGFloat], to path: CGMutablePath, line: Line) {
        guard pattern.count >= 2, pattern.allSatisfy({ $0 > 0 }) else {
            path.addRect(solidBand(for: line))
            return
        }
        let band = solidBand(for: line)
        var x: CGFloat = 0
        var index = 0
        while x < line.length {
            let span = pattern[index % pattern.count]
            if index % 2 == 0 {
                path.addRect(CGRect(
                    x: x, y: band.minY, width: min(span, line.length - x), height: band.height
                ))
            }
            x += span
            index += 1
        }
    }

    static func addCircles(to path: CGMutablePath, line: Line) {
        let diameter = circleDiameter(for: line)
        let pitch = circlePitch(for: line)
        guard diameter > 0, pitch > 0 else { return }
        let centerY = circleCenterY(for: line)
        var center: CGFloat = 0
        while center + diameter / 2 <= line.length {
            path.addEllipse(in: CGRect(
                x: center - diameter / 2, y: centerY - diameter / 2,
                width: diameter, height: diameter
            ))
            center += pitch
        }
    }

    /// 45° 지그재그 — 위 꼭짓점에서 시작해 진폭만큼 내려갔다 올라오기를 반복하고, 꼭짓점
    /// 사이의 평탄(`waveVertexFlat`)은 짧은 띠로 잇는다. 대각선은 획 두께의 평행사변형
    /// (butt cap)이고, `length` 앞에서 시작한 마지막 대각선은 자르지 않고 끝까지 그린다
    /// (한글 실측 — `alongExtent(of:)`가 그 넘침을 보고한다).
    static func addWave(to path: CGMutablePath, line: Line, offset: CGPoint) {
        let amplitude = waveAmplitude(for: line)
        let stroke = waveStroke(for: line)
        guard amplitude > 0, stroke > 0 else { return }
        let flat = HwpRenderTuning.LineShape.waveVertexFlat
        let halfPeriod = waveHalfPeriod(for: line)
        let top = waveTopVertex(for: line) + offset.y
        let bottom = top + amplitude
        let count = waveDiagonalCount(for: line, offsetX: offset.x)
        for index in 0 ..< count {
            let goingDown = index.isMultiple(of: 2)
            let startX = offset.x + CGFloat(index) * halfPeriod
            let start = CGPoint(x: startX, y: goingDown ? top : bottom)
            let end = CGPoint(x: startX + amplitude, y: goingDown ? bottom : top)
            addSegment(from: start, to: end, stroke: stroke, into: path)
            if index + 1 < count, flat > 0 {
                path.addRect(CGRect(
                    x: end.x, y: end.y - stroke / 2, width: flat, height: stroke
                ))
            }
        }
    }

    /// 두 점을 잇는 획 두께 `stroke`의 평행사변형 (butt cap). 꼭짓점 평탄 띠(`addRect`, 부호
    /// 있는 넓이 양수)와 겹치므로 같은 회전 방향으로 둔다 — 반대면 nonzero 채우기
    /// (`CGContext.fillPath`)에서 겹친 자리의 감김수가 0이 돼 꼭짓점에 구멍이 난다 (PR 리뷰).
    static func addSegment(
        from start: CGPoint, to end: CGPoint, stroke: CGFloat, into path: CGMutablePath
    ) {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > 0 else { return }
        let scale = stroke / 2 / lengthSquared.squareRoot()
        let normal = CGPoint(x: -delta.y * scale, y: delta.x * scale)
        path.move(to: CGPoint(x: start.x - normal.x, y: start.y - normal.y))
        path.addLine(to: CGPoint(x: end.x - normal.x, y: end.y - normal.y))
        path.addLine(to: CGPoint(x: end.x + normal.x, y: end.y + normal.y))
        path.addLine(to: CGPoint(x: start.x + normal.x, y: start.y + normal.y))
        path.closeSubpath()
    }
}
