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

    /// 채운 원 — 첫 원의 중심이 선 시작이고, 중심이 `length` 앞인 마지막 원은 끝에 걸쳐도
    /// 온전히 그린다 (#235 — `circleCount(for:)`; `alongExtent(of:)`가 그 넘침을 보고한다)
    static func addCircles(to path: CGMutablePath, line: Line) {
        let diameter = circleDiameter(for: line)
        let pitch = circlePitch(for: line)
        guard diameter > 0, pitch > 0 else { return }
        let centerY = circleCenterY(for: line)
        for index in 0 ..< circleCount(for: line) {
            let center = CGFloat(index) * pitch
            path.addEllipse(in: CGRect(
                x: center - diameter / 2, y: centerY - diameter / 2,
                width: diameter, height: diameter
            ))
        }
    }

    /// 45° 지그재그 — 위 꼭짓점에서 시작해 진폭만큼 내려갔다 올라오기를 반복하고, 꼭짓점
    /// 사이의 평탄(`waveVertexFlat`)은 짧은 띠로 잇는다. 대각선은 획 두께의 평행사변형
    /// (butt cap)이고, `length` 앞에서 시작한 마지막 대각선은 자르지 않고 끝까지 그린다 —
    /// `length`와 같은 자리에서 시작하는 대각선은 그리지 않는다 (한글 실측, #191·#235 —
    /// `waveDiagonalCount(for:offsetX:)`; `alongExtent(of:)`가 그 넘침을 보고한다).
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

    // MARK: - 무늬 요소 개수 (원·물결 — 경로와 `alongExtent(of:)`가 함께 쓴다)

    /// 선 시작에서 `period` 간격으로 놓이는 무늬 요소(원 중심·물결 대각선 시작 — 0, `period`,
    /// 2`period` …) 가운데 자리가 `span` **앞**인 것의 개수. 한글은 그 요소를 끝을 넘더라도
    /// 온전히 그리고 끝과 같은 자리의 요소는 그리지 않는다 (#235 — 한글 12.30 실측: 자간을
    /// 0.12pt씩 바꾼 글자선 run 1,818개(한글 문서 12·20·40pt와 한글 2007 호환 문서 12pt × 원형
    /// 점선·물결·2중 물결 × 밑줄·취소선)와 단 구분선이 전부 자리 < 길이일 때만 그렸다). 끝과 같은
    /// 자리는 상대 오차 1e-6 안이면 그리지 않는다. `span`이 1e-6pt 이하이거나 간격이 양수가
    /// 아니면 0이고, 비율이 반복 상한(`maxPatternRepeats`)을 넘으면 거기서 잘라 트랩하지 않는다.
    static func patternElementCount(span: CGFloat, period: CGFloat) -> Int {
        guard period > 0, span > 1e-6 else { return 0 }
        let ratio = span / period
        guard ratio.isFinite else { return 0 }
        return max(1, Int((min(ratio, maxPatternRepeats + 1) - 1e-6).rounded(.up)))
    }

    /// `offsetX`에서 시작한 물결의 대각선 개수 — 시작점이 `length` 앞에 있는 반주기는 끝까지
    /// 그린다 (한글은 마지막 대각선을 자르지 않는다). 시작점이 `length` 밖이면 0.
    static func waveDiagonalCount(for line: Line, offsetX: CGFloat) -> Int {
        patternElementCount(span: line.length - offsetX, period: waveHalfPeriod(for: line))
    }

    /// 원형 점선의 원 개수 — 중심이 `length` 앞인 원은 끝에 걸쳐도 그린다 (#235)
    static func circleCount(for line: Line) -> Int {
        patternElementCount(span: line.length, period: circlePitch(for: line))
    }

    /// `offsetX`에서 시작한 물결의 마지막 대각선이 끝나는 x (대각선이 없으면 `length` 안)
    static func waveEnd(for line: Line, offsetX: CGFloat) -> CGFloat {
        let count = waveDiagonalCount(for: line, offsetX: offsetX)
        guard count > 0 else { return min(offsetX, line.length) }
        return offsetX + CGFloat(count) * waveHalfPeriod(for: line)
            - HwpRenderTuning.LineShape.waveVertexFlat
    }
}
