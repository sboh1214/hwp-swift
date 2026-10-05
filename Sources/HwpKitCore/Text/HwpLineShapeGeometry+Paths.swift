import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 경로 조각 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// `HwpLineShapeGeometry.path(for:)`가 모양마다 부르는 경로 조각 — 대시·원·물결의 부분
/// 경로를 로컬 좌표(x = 선 방향, y = 가로지르는 축, 0 = 단선 중심, 양수 = 아래)에 더한다.
/// 축척·자리는 본체의 헬퍼(`dashPattern(for:)`·`circleDiameter`·`waveTopVertex` …)가 정한다.
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
    /// (없으면 전부) — (시작, 폭). 대시는 `length`에서 잘리고, 시작이 `length`와 같은 자리(주기의 1e-6
    /// 안 — 원·물결의 `patternElementCount`와 같은 오차)인 대시는 그리지 않는다: 한글은 장치 단위 정수로
    /// 셈해 그 자리가 끝과 정확히 같지만 우리는 pt 누적이라 끝 바로 앞에 길이 0에 가까운 대시가 남는다
    /// (#246 — 선 없음 이웃의 굵기 연장으로 0.12mm 긴 점선 330.24pt 선이 주기 3.84의 정확한 배수가 됐다).
    /// 범위가 있으면 자리를 패턴 주기의 곱(주기 색인 × 주기 + 주기 안 자리)으로 셈해 범위 앞 주기를
    /// 건너뛴다 — 같은 사슬의 조각은 같은 `length`·패턴을 받아 같은 자리를 얻으므로 이웃 조각의 경계
    /// 판정이 어긋나지 않고, 긴 사슬도 조각마다 제 몫만 훑는다 (#238). 범위가 없으면 종전의 누적 덧셈
    /// 그대로다.
    static func forEachOwnedDash(
        _ pattern: [CGFloat], line: Line, _ body: (CGFloat, CGFloat) -> Void
    ) {
        let period = pattern.reduce(0, +)
        let lastStart = line.length - (period.isFinite ? period * 1e-6 : 0)
        guard let owned = line.elementRange else {
            var x: CGFloat = 0
            var index = 0
            while x < lastStart {
                let span = pattern[index % pattern.count]
                if index % 2 == 0 {
                    body(x, min(span, line.length - x))
                }
                x += span
                index += 1
            }
            return
        }
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
    /// (끝과 같은 자리 — 주기의 1e-6 안 — 의 대시는 그리지 않는다)
    private static func forEachDash(
        _ pattern: [CGFloat], period: CGFloat, line: Line, owned: Range<CGFloat>,
        _ body: (CGFloat, CGFloat) -> Void
    ) {
        let lastStart = line.length - period * 1e-6
        var slotStarts: [CGFloat] = []
        var cumulative: CGFloat = 0
        for span in pattern {
            slotStarts.append(cumulative)
            cumulative += span
        }
        let end = min(lastStart, owned.upperBound)
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

    /// 실선으로 긋는 모양 — 실선과 그것으로 대체하는 3D 넷
    static func isSolid(_ shape: HwpBorderType) -> Bool {
        switch shape {
        case .line, .thick3D, .thick3DReverse, .single3D, .single3DReverse: true
        default: false
        }
    }

    /// 실선이 이 조각의 몫인가 — 요소 하나가 자리 0에 놓인다 (`elementRange`가 없으면 늘 그린다)
    static func ownsSolidLine(_ line: Line) -> Bool {
        line.elementRange?.contains(0) ?? true
    }

    /// 실선 띠를 더한다 — 이은 실선은 자리 0을 맡은 조각만 (`ownsSolidLine(_:)`)
    static func addOwnedSolidLine(to path: CGMutablePath, line: Line) {
        if ownsSolidLine(line) {
            path.addRect(solidBand(for: line))
        }
    }

    /// 실선 띠로 떨어진 무늬의 제 몫을 더한다 (`ownedSolidBand(for:)` — 몫이 없으면 그대로)
    static func addOwnedSolidBand(to path: CGMutablePath, line: Line) {
        if let band = ownedSolidBand(for: line) {
            path.addRect(band)
        }
    }

    /// 반복 상한을 넘어 실선 띠로 떨어진 무늬의 제 몫 — 대시·원형 점선은 `elementRange`와 [0, `length`]의
    /// 겹침(없으면 띠 전체), 파마다의 범위(`Line.waveSpans`)가 있는 물결은 긋는 파의 범위를 합친 곳(모서리
    /// 자리를 지킨다). 몫이 없으면 nil — 긋는 파가 없는 물결도 실선 띠로 떨어지지 않는다.
    static func ownedSolidBand(for line: Line) -> CGRect? {
        let band = solidBand(for: line)
        if line.waveSpans != nil, line.shape == .wave || line.shape == .doubleWave {
            let spans = drawableWaveSpans(for: line)
            guard let start = spans.map(\.lowerBound).min(),
                  let end = spans.map(\.upperBound).max(), (end - start).isFinite
            else { return nil }
            return CGRect(x: start, y: band.minY, width: end - start, height: band.height)
        }
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
            let pattern = dashPattern(for: line)
            guard pattern.count >= 2, pattern.allSatisfy({ $0 > 0 }) else {
                guard let band = ownedSolidBand(for: line) else { return nil }
                return band.minX ... band.maxX
            }
            forEachOwnedDash(pattern, line: line) { cover($0, $0 + $1) }
        }
        return lower <= upper ? lower ... upper : nil
    }

    /// 45° 지그재그 파 하나 (`index` — 2중 물결의 둘째 파는 1) — 파의 선 방향 범위(`waveSpan(for:index:)`)
    /// 시작의 위 꼭짓점에서 진폭만큼 내려갔다 올라오기를 반복하고, 꼭짓점 사이의 평탄은 짧은 띠로 잇는다.
    /// 둘째 파는 가로지르는 축으로 `Wave.secondOffset`만큼 아래다. 대각선은 획 두께의 평행사변형
    /// (butt cap)이고, 범위 끝 앞에서 시작한 마지막 대각선은 자르지 않고 끝까지 그린다 — 끝과 같은 자리에서
    /// 시작하는 대각선은 그리지 않는다 (한글 실측, #191·#235 — `waveDiagonalCount(for:index:)`;
    /// `alongExtent(of:)`가 그 넘침을 보고한다). 표 셀 테두리·단 구분선은 마지막 대각선 뒤의 평탄도 그 시작이
    /// 끝 앞이면 긋는다 (`drawsTrailingFlat(after:line:span:)`).
    static func addWave(to path: CGMutablePath, line: Line, index: Int) {
        let wave = wave(for: line)
        let stroke = wave.stroke
        guard stroke > 0 else { return }
        let span = waveSpan(for: line, index: index)
        let top = wave.top + CGFloat(index) * wave.secondOffset
        if wave.straight {
            // 대각선이 없는 작은 크기 — 위 평탄 높이에 가로 선 하나 (한글 12.30: 글자선 1.54pt 이하)
            guard span.upperBound > span.lowerBound else { return }
            path.addRect(CGRect(
                x: span.lowerBound, y: top - stroke / 2, width: span.upperBound - span.lowerBound,
                height: stroke
            ))
            return
        }
        guard wave.run > 0 else { return }
        let count = waveDiagonalCount(for: line, index: index)
        for diagonal in 0 ..< count {
            let goingDown = diagonal.isMultiple(of: 2)
            let startX = span.lowerBound + CGFloat(diagonal) * wave.halfPeriod
            let startY = goingDown ? top : top + wave.levelGap
            let end = CGPoint(x: startX + wave.run, y: startY + (goingDown ? wave.run : -wave.run))
            addSegment(from: CGPoint(x: startX, y: startY), to: end, stroke: stroke, into: path)
            let trailing = diagonal + 1 == count
            if wave.flat > 0, !trailing || drawsTrailingFlat(after: end.x, line: line, span: span) {
                // 평탄은 다음 대각선이 시작하는 높이다 — 대각선 끝과 다를 수 있다 (홀수 r)
                let flatY = goingDown ? top + wave.levelGap : top
                path.addRect(CGRect(
                    x: end.x, y: flatY - stroke / 2, width: wave.flat, height: stroke
                ))
            }
        }
    }

    /// 2중 물결 — 같은 물결을 둘째 파 자리(`Wave.secondOffset` 아래, 선 방향은 그 파의 범위)에 한 번 더
    /// 긋는다. 물결이 가로 선으로 접힌 작은 크기(`Wave.straight`)는 두 파가 같은 자리라 한 번만 긋는다
    /// (한글 1.54pt 이하).
    static func addDoubleWave(to path: CGMutablePath, line: Line) {
        addWave(to: path, line: line, index: 0)
        guard !wave(for: line).straight else { return }
        addWave(to: path, line: line, index: 1)
    }

    /// 그리는 파의 수 — 물결 1, 2중 물결 2 (가로 선으로 접힌 2중 물결은 1)
    static func drawnWaveCount(for line: Line) -> Int {
        line.shape == .doubleWave && !wave(for: line).straight ? 2 : 1
    }

    /// 파 `index`의 선 방향 범위 (로컬 x, [시작, 끝)) — `Line.waveSpans`가 있으면 그 `index`번째(모자라면
    /// 마지막), 없으면 [0, `length`). 끝이 시작 앞이면 빈 범위다. 공개 입력이라 끝이 유한하지 않거나 폭이
    /// 넘치는 범위는 빈 범위로 본다 — 그 파는 그리지 않고 범위도 보고하지 않는다 (path == nil ⇔ 범위 == nil).
    static func waveSpan(for line: Line, index: Int) -> Range<CGFloat> {
        guard let spans = line.waveSpans, let last = spans.last else { return 0 ..< line.length }
        let span = index < spans.count ? spans[index] : last
        guard span.lowerBound.isFinite, span.upperBound.isFinite,
              (span.upperBound - span.lowerBound).isFinite
        else { return 0 ..< 0 }
        return span
    }

    /// 긋는 파의 선 방향 범위 — 비었거나(1e-6pt 이하, 요소 개수의 바닥과 같다) 유한하지 않은
    /// (`waveSpan(for:index:)`) 범위는 뺀다. 반복 상한 판정(`patternRepeats(of:)`)과 그 실선 띠
    /// (`ownedSolidBand(for:)`)가 이 범위로 센다.
    static func drawableWaveSpans(for line: Line) -> [Range<CGFloat>] {
        (0 ..< drawnWaveCount(for: line)).map { waveSpan(for: line, index: $0) }
            .filter { $0.upperBound - $0.lowerBound > 1e-6 }
    }

    /// 마지막 대각선 뒤의 평탄을 긋는가 — 표 셀 테두리·단 구분선(`Scale.border`)은 한글처럼 평탄도 따로
    /// 긋는 요소라 시작(대각선 끝 `flatStart`)이 범위 끝 앞이면 긋는다 (#253 실측: 셀 간격 표 0.1mm 세로 변
    /// 666u — 대각선 222개 뒤 평탄 222개). 글자선은 좇지 않는다 (#252 — 남은 격차).
    static func drawsTrailingFlat(
        after flatStart: CGFloat, line: Line, span: Range<CGFloat>
    ) -> Bool {
        guard line.scale == .border else { return false }
        let room = span.upperBound - flatStart
        return room > waveHalfPeriod(for: line) * 1e-6
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
    /// 간격으로 줄 상자 길이 기준 110표본 모두)이 전부 자리 < 길이일 때만 그렸다; #239의
    /// 원형 점선 글자선 434표본도 같다). 끝과 같은 자리는 비율의 오차 1e-6 안이면
    /// 그리지 않는다. `span`이 1e-6pt 이하이거나 간격이 양수가 아니면 0이고, 비율이 반복 상한
    /// (`maxPatternRepeats`)을 넘으면 거기서 잘라 트랩하지 않는다.
    static func patternElementCount(span: CGFloat, period: CGFloat) -> Int {
        guard period > 0, span > 1e-6 else { return 0 }
        let ratio = span / period
        guard ratio.isFinite else { return 0 }
        return max(1, Int((min(ratio, maxPatternRepeats + 1) - 1e-6).rounded(.up)))
    }

    /// 파 `index`의 대각선 개수 — 시작점이 범위 끝 앞에 있는 반주기는 끝까지 그린다 (한글은 마지막
    /// 대각선을 자르지 않는다). 범위가 비었으면 0.
    static func waveDiagonalCount(for line: Line, index: Int) -> Int {
        let span = waveSpan(for: line, index: index)
        return patternElementCount(
            span: span.upperBound - span.lowerBound, period: waveHalfPeriod(for: line)
        )
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

    /// 물결의 가로지르는 범위 (로컬 y) — 실제로 긋는 파만 센다: `Line.waveSpans`가 비운 파는 경로에 없다
    /// (`alongExtent(of:)`와 같은 판정). 반복 상한을 넘으면 실선 띠이고, 긋는 파가 없으면 그 띠도 없다
    /// (대시·원형 점선 조각은 제 몫이 없어도 선 전체의 띠를 내는 것과 갈린다).
    static func waveCrossExtent(of line: Line) -> ClosedRange<CGFloat>? {
        if patternRepeats(of: line) > maxPatternRepeats {
            guard ownedSolidBand(for: line) != nil else { return nil }
            let band = solidBand(for: line)
            return band.minY ... band.maxY
        }
        let wave = wave(for: line)
        let half = wave.stroke / 2
        let range = wave.centerRange
        let offsets = (0 ..< drawnWaveCount(for: line))
            .filter { waveAlongExtent(for: line, index: $0) != nil }
            .map { CGFloat($0) * wave.secondOffset }
        guard let lift = offsets.min(), let drop = offsets.max() else { return nil }
        return (range.lowerBound + lift - half) ... (range.upperBound + drop + half)
    }

    /// 파 `index`가 칠하는 선 방향 범위 (로컬 x) — 첫 대각선 시작부터 마지막 대각선 끝(또는 그 뒤 평탄 끝)
    /// 까지에 45° 획의 butt cap 모서리(획 반폭/√2)를 양 끝에 더한다. 가로 선으로 접힌 물결은 범위 그대로다.
    /// 그릴 대각선이 없으면 nil.
    static func waveAlongExtent(for line: Line, index: Int) -> ClosedRange<CGFloat>? {
        let wave = wave(for: line)
        let span = waveSpan(for: line, index: index)
        if wave.straight {
            return span.upperBound > span.lowerBound ? span.lowerBound ... span.upperBound : nil
        }
        let count = waveDiagonalCount(for: line, index: index)
        guard count > 0 else { return nil }
        let corner = wave.stroke / 2 / 2.0.squareRoot()
        // 첫 대각선 시작은 곱하지 않는다 — 반주기가 무한대로 넘친 입력에서 0 × ∞ = NaN을 피한다
        let lastStart = count > 1
            ? span.lowerBound + CGFloat(count - 1) * wave.halfPeriod : span.lowerBound
        let lastEnd = lastStart + wave.run
        var upper = lastEnd + corner
        if wave.flat > 0, drawsTrailingFlat(after: lastEnd, line: line, span: span) {
            upper = max(upper, lastEnd + wave.flat)
        }
        return (span.lowerBound - corner) ... upper
    }
}
