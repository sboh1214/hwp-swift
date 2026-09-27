import CoreGraphics
import Foundation

// MARK: - 경로 조각 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// `HwpLineShapeGeometry.path(for:)`가 모양마다 부르는 경로 조각 — 대시·원·물결의 부분
/// 경로를 로컬 좌표(x = 선 방향, y = 가로지르는 축, 0 = 단선 중심, 양수 = 아래)에 더한다.
/// 축척·자리는 본체의 헬퍼(`dashUnit`·`circleDiameter`·`waveTopVertex` …)가 정한다.
extension HwpLineShapeGeometry {
    static func addDashes(_ pattern: [CGFloat], to path: CGMutablePath, line: Line) {
        guard pattern.count >= 2, pattern.allSatisfy({ $0 > 0 }) else {
            addOwnedSolidBand(to: path, line: line)
            return
        }
        let band = solidBand(for: line)
        forEachOwnedDash(pattern, line: line) { x, width in
            path.addRect(CGRect(x: x, y: band.minY, width: width, height: band.height))
        }
    }

    /// 선 시작에서 패턴을 되풀이해 놓이는 대시 가운데 시작 자리가 `elementRange`에 드는 것
    /// (없으면 전부) — (시작, 폭). 대시는 `length`에서 잘린다. 범위가 있으면 자리를 패턴 주기의
    /// 곱(주기 색인 × 주기 + 주기 안 자리)으로 셈해 범위 앞 주기를 건너뛴다 — 같은 사슬의 조각은 같은
    /// `length`·패턴을 받아 같은 자리를 얻으므로 이웃 조각의 경계 판정이 어긋나지 않고, 긴 사슬도
    /// 조각마다 제 몫만 훑는다 (#238). 범위가 없으면 종전의 누적 덧셈 그대로다.
    static func forEachOwnedDash(
        _ pattern: [CGFloat], line: Line, _ body: (CGFloat, CGFloat) -> Void
    ) {
        guard let owned = line.elementRange else {
            var x: CGFloat = 0
            var index = 0
            while x < line.length {
                let span = pattern[index % pattern.count]
                if index % 2 == 0 {
                    body(x, min(span, line.length - x))
                }
                x += span
                index += 1
            }
            return
        }
        let period = pattern.reduce(0, +)
        guard period.isFinite else {
            // 주기가 무한대로 넘친 입력(두께가 유한 최댓값 근처)은 누적 덧셈처럼 첫 대시 하나다 —
            // 그 자리(0)를 맡은 조각이 그린다
            if owned.contains(0) {
                body(0, min(pattern[0], line.length))
            }
            return
        }
        guard period > 0 else { return }
        forEachDash(pattern, period: period, line: line, owned: owned, body)
    }

    /// `forEachOwnedDash`의 범위 갈래 — 범위 앞 주기를 건너뛰고 주기마다 대시 자리를 곱으로 셈한다
    private static func forEachDash(
        _ pattern: [CGFloat], period: CGFloat, line: Line, owned: Range<CGFloat>,
        _ body: (CGFloat, CGFloat) -> Void
    ) {
        var slotStarts: [CGFloat] = []
        var cumulative: CGFloat = 0
        for span in pattern {
            slotStarts.append(cumulative)
            cumulative += span
        }
        let end = min(line.length, owned.upperBound)
        let guess = (owned.lowerBound / period).rounded(.down) - 1
        var cycle = guess.isFinite && guess > 0 ? Int(min(guess, maxPatternRepeats)) : 0
        while true {
            let base = cycle == 0 ? 0 : CGFloat(cycle) * period
            guard base < end else { return }
            for slot in stride(from: 0, to: pattern.count, by: 2) {
                let x = base + slotStarts[slot]
                guard x < end else { return }
                if x >= owned.lowerBound {
                    body(x, min(pattern[slot], line.length - x))
                }
            }
            cycle += 1
        }
    }

    /// 채운 원 — 첫 원의 중심이 선 시작이고, 중심이 `length` 앞인 마지막 원은 끝에 걸쳐도
    /// 온전히 그린다 (#235·#238 — `alongExtent(of:)`가 그 넘침을 보고한다)
    static func addCircles(to path: CGMutablePath, line: Line) {
        let diameter = circleDiameter(for: line)
        guard diameter > 0 else { return }
        let centerY = circleCenterY(for: line)
        forEachOwnedCircle(line) { center in
            path.addEllipse(in: CGRect(
                x: center - diameter / 2, y: centerY - diameter / 2,
                width: diameter, height: diameter
            ))
        }
    }

    /// 원 중심 가운데 `elementRange`에 드는 것 (없으면 전부, `circleCount(for:)`개). 중심은 조각마다
    /// 같은 곱셈(색인 × 간격)으로 셈한다 — 첫 원은 곱하지 않고 0이라 간격이 무한대로 넘친 입력에서
    /// 0 × ∞ = NaN을 피한다.
    static func forEachOwnedCircle(_ line: Line, _ body: (CGFloat) -> Void) {
        let pitch = circlePitch(for: line)
        guard pitch > 0 else { return }
        let count = circleCount(for: line)
        let owned = line.elementRange ?? -CGFloat.infinity ..< .infinity
        // 범위 앞 원은 건너뛴다 — 판정은 아래 비교가 하므로 한 칸 앞에서 시작해도 된다
        let guess = (owned.lowerBound / pitch).rounded(.down) - 1
        var index = guess.isFinite && guess > 0 ? Int(min(guess, CGFloat(count))) : 0
        while index < count {
            let center = index == 0 ? 0 : CGFloat(index) * pitch
            if center >= owned.upperBound {
                break
            }
            if center >= owned.lowerBound {
                body(center)
            }
            index += 1
        }
    }

    /// 실선 띠로 떨어진 무늬의 제 몫을 더한다 (`ownedSolidBand(for:)` — 몫이 없으면 그대로)
    static func addOwnedSolidBand(to path: CGMutablePath, line: Line) {
        if let band = ownedSolidBand(for: line) {
            path.addRect(band)
        }
    }

    /// 반복 상한을 넘어 실선 띠로 떨어진 무늬의 제 몫 — `elementRange`와 [0, `length`]의 겹침
    /// (없으면 띠 전체). 겹침이 없으면 nil.
    static func ownedSolidBand(for line: Line) -> CGRect? {
        let band = solidBand(for: line)
        guard let owned = line.elementRange, isPatterned(line.shape) else { return band }
        let start = max(0, owned.lowerBound)
        let end = min(line.length, owned.upperBound)
        guard end > start else { return nil }
        return CGRect(x: start, y: band.minY, width: end - start, height: band.height)
    }

    /// `elementRange`가 있는 대시·원형 점선의 선 방향 범위 — 그 범위에 자리를 둔 요소가 칠하는
    /// 곳. 요소가 없으면 nil (`path(for:)`도 nil이다).
    static func ownedAlongExtent(of line: Line) -> ClosedRange<CGFloat>? {
        var lower = CGFloat.infinity
        var upper = -CGFloat.infinity
        func cover(_ start: CGFloat, _ end: CGFloat) {
            lower = min(lower, start)
            upper = max(upper, end)
        }
        if patternRepeats(of: line) > maxPatternRepeats {
            guard let band = ownedSolidBand(for: line) else { return nil }
            return band.minX ... band.maxX
        }
        if line.shape == .circle {
            let radius = circleDiameter(for: line) / 2
            forEachOwnedCircle(line) { cover($0 - radius, $0 + radius) }
        } else {
            let pattern = dashPattern(for: line.shape, unit: dashUnit(for: line))
            guard pattern.count >= 2, pattern.allSatisfy({ $0 > 0 }) else {
                guard let band = ownedSolidBand(for: line) else { return nil }
                return band.minX ... band.maxX
            }
            forEachOwnedDash(pattern, line: line) { cover($0, $0 + $1) }
        }
        return lower <= upper ? lower ... upper : nil
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
    /// 원형 점선·물결·2중 물결 × 밑줄·취소선 — 한글 문서 20·40pt는 밑줄만)와 단 구분선(원은 #239의
    /// 간격으로 110표본 중 109개 정확, 하나는 장치 한 단위 안)이 전부 자리 < 길이일 때만 그렸다; #239의
    /// 원형 점선 글자선 434표본도 같다). 끝과 같은 자리는 비율의 오차 1e-6 안이면
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

    /// 원형 점선의 원 개수 — 중심이 `length` 앞인 원을 끝에 걸쳐도 그린다 (#235). 표 셀 테두리도
    /// 같다: 한글은 같은 모양 이웃 칸의 원형 점선 변을 한 선으로 이어 그 끝에서 이 규칙을 쓴다
    /// (#238 — 한글 12.30 실측: 이웃 세로 변이 없는 가로 사슬은 칸 1·2·3개 모두 정확히 이 규칙이고,
    /// 이웃 세로 변이 굵거나 세로 사슬이면 한글이 끝에서 3~10u(0.12pt) 더 엄격하다). 이은 선의 조각은
    /// 사슬 전체를 `length`로 받으므로 개수도 사슬 전체의 것이다.
    static func circleCount(for line: Line) -> Int {
        let pitch = circlePitch(for: line)
        let count = patternElementCount(span: line.length, period: pitch)
        // 끝을 넘는 마지막 원의 바깥 끝이 무한대로 넘치면(길이가 유한 최댓값 근처) 그 원은
        // 뺀다 — 경로와 `alongExtent(of:)`가 함께 유한하게 남는다 (앞 원은 길이 안에서 끝난다)
        let lastEdge = CGFloat(count - 1) * pitch + circleDiameter(for: line) / 2
        return count > 1 && !lastEdge.isFinite ? count - 1 : count
    }

    /// `offsetX`에서 시작한 물결의 마지막 대각선이 끝나는 x (대각선이 없으면 `length` 안)
    static func waveEnd(for line: Line, offsetX: CGFloat) -> CGFloat {
        let count = waveDiagonalCount(for: line, offsetX: offsetX)
        guard count > 0 else { return min(offsetX, line.length) }
        return offsetX + CGFloat(count) * waveHalfPeriod(for: line)
            - HwpRenderTuning.LineShape.waveVertexFlat
    }
}
