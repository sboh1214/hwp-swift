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
    /// 온전히 그린다 (#235 — 표 셀 테두리만 끝을 넘지 않는 원까지, `circleCount(for:)`;
    /// `alongExtent(of:)`가 그 넘침을 보고한다)
    static func addCircles(to path: CGMutablePath, line: Line) {
        let diameter = circleDiameter(for: line)
        let pitch = circlePitch(for: line)
        guard diameter > 0, pitch > 0 else { return }
        let centerY = circleCenterY(for: line)
        for index in 0 ..< circleCount(for: line) {
            // 첫 원은 곱하지 않고 0 — 간격이 무한대로 넘친 입력에서 0 × ∞ = NaN을 피한다
            let center = index == 0 ? 0 : CGFloat(index) * pitch
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
    /// 온전히 그리고 끝과 같은 자리의 요소는 그리지 않는다 (#235 — 한글 12.30 실측: 글자선 run의
    /// 자간을 1%씩 바꾼 표본 4,242개(한글 2007 호환 문서 7·12·20pt, 한글 문서 7·12·16·20·40pt ×
    /// 원형 점선·물결·2중 물결 × 밑줄·취소선 — 한글 문서 20·40pt는 밑줄만)와 단 구분선(원은 장치
    /// 한 단위 안)이 전부 자리 < 길이일 때만 그렸다). 끝과 같은 자리는 비율의 오차 1e-6 안이면
    /// 그리지 않는다. `span`이 1e-6pt 이하이거나 간격이 양수가 아니면 0이고, 비율이 반복 상한
    /// (`maxPatternRepeats`)을 넘으면 거기서 잘라 트랩하지 않는다.
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

    /// 원형 점선의 원 개수. 글자선·단 구분선은 중심이 `length` 앞인 원을 끝에 걸쳐도 그리고
    /// (#235), 표 셀 테두리(`Placement.border`)는 마지막 원이 변 끝을 넘지 않는 것까지 그린다
    /// (중심 ≤ `length` − 반지름 — 첫 원은 선 시작에 중심을 두어 앞으로는 반지름만큼 나간다).
    /// 한글은 같은 모양 이웃 칸의 원형 점선 변을 칸 경계에서 다시 시작하지 않고 한 선으로 잇는데
    /// (#235 재검증: 1×3·3×1·2×2 표, 표 테두리 유무·칸 폭과 무관), 우리는 칸마다 무늬를 다시
    /// 시작하므로 끝 규칙을 그대로 쓰면 칸 경계에서 앞 칸의 걸친 원과 다음 칸의 첫 원이 포개지는
    /// 자리가 생긴다 (1mm 22.8pt 칸: 0.12pt 간격). 이 규칙은 그 겹침을 줄일 뿐이고 없애는 것은 이어
    /// 그리기다 — 그때 이은 선의 끝에 끝 규칙을 쓴다.
    static func circleCount(for line: Line) -> Int {
        let pitch = circlePitch(for: line)
        guard line.placement == .border else {
            let count = patternElementCount(span: line.length, period: pitch)
            // 끝을 넘는 마지막 원의 바깥 끝이 무한대로 넘치면(길이가 유한 최댓값 근처) 그 원은
            // 뺀다 — 경로와 `alongExtent(of:)`가 함께 유한하게 남는다 (앞 원은 길이 안에서 끝난다)
            let lastEdge = CGFloat(count - 1) * pitch + circleDiameter(for: line) / 2
            return count > 1 && !lastEdge.isFinite ? count - 1 : count
        }
        return fittingElementCount(span: line.length - circleDiameter(for: line) / 2, period: pitch)
    }

    /// 선 시작에서 `period` 간격으로 놓이는 요소 가운데 자리가 `span` **이하**인 것의 개수
    /// (`span`과 같은 자리는 비율의 오차 1e-6 안이면 든다 — #235 전의 누적 루프 `center += pitch`는
    /// 정확한 동점에서 누적 오차로 그 원을 빼기도 했다). `span`이 음수이거나 간격이 양수가 아니거나
    /// 비율이 유한하지 않으면 0이고, 비율은 반복 상한(`maxPatternRepeats`)에서 자른다.
    static func fittingElementCount(span: CGFloat, period: CGFloat) -> Int {
        guard period > 0, span >= 0 else { return 0 }
        let ratio = span / period
        guard ratio.isFinite else { return 0 }
        return Int((min(ratio, maxPatternRepeats) + 1e-6).rounded(.down)) + 1
    }

    /// `offsetX`에서 시작한 물결의 마지막 대각선이 끝나는 x (대각선이 없으면 `length` 안)
    static func waveEnd(for line: Line, offsetX: CGFloat) -> CGFloat {
        let count = waveDiagonalCount(for: line, offsetX: offsetX)
        guard count > 0 else { return min(offsetX, line.length) }
        return offsetX + CGFloat(count) * waveHalfPeriod(for: line)
            - HwpRenderTuning.LineShape.waveVertexFlat
    }
}
