import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `compat-decorations` 쌍과 `track-changes-native`의 실물 핀 (#187).
///
/// **MS 워드 호환 문서**(`compat-decorations`, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯
/// Menlo)에서 밑줄·취소선은 글꼴 지표 기하다. 오라클은 한글.app 12.30.0의 PDF 내보내기
/// (2026-09-15, 벡터 좌표, 베이스라인 기준 em):
///
/// | 문단 | 글꼴·크기 | 밑줄 | 취소선 | 밑줄 두께 |
/// |---|---|---:|---:|---:|
/// | 1 | Apple SD 10pt | −0.3012 | +0.2530 | 0.0602 |
/// | 2 | Menlo 10pt | −0.2651 | +0.2530 | 0.0602 |
/// | 3 | Apple SD 20pt | −0.2994 | +0.2455 | 0.0599 |
/// | 4 | Menlo 20pt | −0.2575 | +0.2575 | 0.0599 |
/// | 8 | Apple SD 10pt 밑줄 + Menlo 20pt 무장식 | −0.2575 × 20 | +0.2515 × 20 (10pt) | 0.0599 × 20 |
/// | 9 | Menlo 10pt 무장식 run + Apple SD 10pt 밑줄 run | −0.3012 | +0.2410 | 0.0602 |
/// | 10 | Apple SD 10pt + 20pt 밑줄 run | −0.2994 × 20 한 줄 | | 0.0599 × 20 |
///
/// 우리 줄 상자·베이스라인은 호환 문서에서 아직 한글과 다르므로(#194) 쪽 좌표 대신
/// **같은 줄 안의 밑줄–취소선 간격**과 두께, 두 포맷의 동일성을 핀한다 — 두 선이 베이스
/// 라인을 공유하니 간격은 줄 자리와 무관하다. 기대값은 결정론 resolver가 고르는 같은
/// 글꼴(Menlo + Apple SD Gothic Neo)의 지표에서 `HwpDecorationLineGeometry`로 계산하고
/// 한글 값과 0.15pt 안에서 만난다 (10pt 문단은 장치 0.12pt 양자화 한 단위).
///
/// **한글 문서**(`track-changes-native`)에서는 변경 추적 삽입 밑줄·삭제선이 같은 줄의
/// 일반 밑줄·취소선과 **같은 자리·같은 두께**다 (한글 PDF: 네 문단 전부 장치 좌표까지
/// 같음). 종전(#176)의 전용 상수 −0.26em·0.29em은 여기서 0.9·0.6pt 어긋났다.
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다.
extension FixtureDecorationLineRenderTests {
    private static let compat = "compat-decorations"

    private static func isBlue(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green < 100 && blue > 150
    }

    private static func isMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    /// 가로로 `minimumLength`pt 넘게 이어진 색 행들을 위에서부터 선 단위로 묶은 중심(pt)과
    /// 행 수. 기본 8pt는 선 색 글리프가 없는 초록·청록·자홍·파랑용이고, 빨강은 변경 추적
    /// 글자 자체가 빨강이라 20pt 글리프의 가로 획(≤ 16pt)보다 긴 선만 세야 한다.
    private static func lineGroups(
        _ raster: Raster, minimumLength: CGFloat = 8,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> [(center: CGFloat, rows: Int)] {
        let rows = (0 ..< raster.pixelHeight)
            .filter { raster.longestRun($0, where: match) > Int(minimumLength * scale) }
            .map { (CGFloat($0) + 0.5) / scale }
        var groups: [[CGFloat]] = []
        for row in rows {
            if let last = groups.last?.last, row - last < 0.5 / scale + 0.3 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups.map { ($0.reduce(0, +) / CGFloat($0.count), $0.count) }
    }

    private static func box(_ name: String, _ size: CGFloat) -> HwpMsWordLineBox {
        HwpMsWordLineBox.metrics(of: CTFontCreateWithName(name as CFString, size, nil))
            .scaled(by: size)
    }

    /// `lineGroups` 항목 — 선의 중심(pt)과 행 수.
    private typealias Line = (center: CGFloat, rows: Int)

    /// 채널 고르기 — 초록·청록·파랑 선은 R, 자홍·빨강 선은 G가 선 색에서 가장 낮다.
    private static func redChannel(_ red: UInt8, _: UInt8, _: UInt8) -> UInt8 {
        red
    }

    private static func greenChannel(_: UInt8, _ green: UInt8, _: UInt8) -> UInt8 {
        green
    }

    /// 선의 색이 이어진 열 구간 — 양 끝 2px는 뺀다.
    private static func columns(
        _ raster: Raster, of line: Line, where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> Range<Int>? {
        guard let span = raster.longestSpan(Int(line.center * scale), where: match),
              span.count > 8
        else { return nil }
        return (span.lowerBound + 2) ..< (span.upperBound - 2)
    }

    /// 선의 두께 (pt, `Raster.lineThickness`) — `halfBand`는 기대 두께의 반 + 0.35pt.
    private static func thickness(
        _ raster: Raster, of line: Line, halfBand: CGFloat,
        where match: (UInt8, UInt8, UInt8) -> Bool,
        channel: (UInt8, UInt8, UInt8) -> UInt8, fullChannel: UInt8? = nil
    ) -> CGFloat? {
        guard let columns = columns(raster, of: line, where: match) else { return nil }
        return raster.lineThickness(
            center: line.center, halfBand: halfBand, columns: columns,
            channel: channel, fullChannel: fullChannel
        )
    }

    /// 2px 넘는 선에서 잰 완전 커버 채널값 (`Raster.fullCoverageChannel`).
    private static func fullChannel(
        _ raster: Raster, of line: Line, halfBand: CGFloat,
        where match: (UInt8, UInt8, UInt8) -> Bool,
        channel: (UInt8, UInt8, UInt8) -> UInt8
    ) -> UInt8? {
        guard let columns = columns(raster, of: line, where: match) else { return nil }
        return raster.fullCoverageChannel(
            center: line.center, halfBand: halfBand, columns: columns, channel: channel
        )
    }

    /// 선의 시작 열부터 `width`pt 폭 안에서 `rows` 구간의 글리프 잉크 위 끝 (pt).
    private static func inkTop(
        _ raster: Raster, of line: Line, rows: ClosedRange<CGFloat>, width: CGFloat,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> CGFloat? {
        guard let columns = columns(raster, of: line, where: match) else { return nil }
        let end = min(columns.lowerBound + Int(width * scale), raster.pixelWidth)
        return raster.inkTop(in: rows, columns: columns.lowerBound ..< end, where: isDark)
    }

    /// `compat-decorations`의 기대값 — 문단 1·2·3·4·8·9의 (산식 간격, 한글 실측 간격)과
    /// 두께 핀(밑줄 색인, 줄 상자 cell).
    private struct GapExpectations {
        let gaps: [(gap: CGFloat, hancom: CGFloat)]
        let cells: [(index: Int, cell: CGFloat)]
    }

    /// 결정론 글꼴(Apple SD 산돌고딕 Neo·Menlo)의 상자로 산식을 풀고 한글 PDF 값과 0.15pt
    /// 안에서 만나는지 확인한다. 문단 끝 글자(Menlo, 마지막 run 크기)가 줄 상자에 든다.
    private static func gapExpectations() throws -> GapExpectations {
        let appleSD10 = box("Apple SD Gothic Neo", 10)
        let appleSD20 = box("Apple SD Gothic Neo", 20)
        let menlo10 = box("Menlo", 10)
        let menlo20 = box("Menlo", 20)
        try XCTSkipUnless(appleSD10.cellHeight > 1.15 * 10, "Apple SD Gothic Neo 없음")
        let hangul10 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo10]))
        let hangul20 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD20, menlo20]))
        let line8 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo20]))
        let line10 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, appleSD20, menlo20]))
        func gap(line: HwpMsWordLineBox, strike: HwpMsWordLineBox, size: CGFloat) -> CGFloat {
            HwpDecorationLineGeometry.msWordStrikethrough(runBox: strike, thicknessFontSize: size)
                .center - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: line).center
        }
        let gaps: [(gap: CGFloat, hancom: CGFloat)] = [
            (gap(line: hangul10, strike: appleSD10, size: 10), (0.2530 + 0.3012) * 9.96),
            (gap(line: menlo10, strike: menlo10, size: 10), (0.2530 + 0.2651) * 9.96),
            (gap(line: hangul20, strike: appleSD20, size: 20), (0.2455 + 0.2994) * 20.04),
            (gap(line: menlo20, strike: menlo20, size: 20), (0.2575 + 0.2575) * 20.04),
            (gap(line: line8, strike: appleSD10, size: 10), (0.1257 + 0.2575) * 20.04),
            (gap(line: hangul10, strike: appleSD10, size: 10), (0.2410 + 0.3012) * 9.96),
        ]
        for (index, pair) in gaps.enumerated() {
            expect(pair.gap).to(
                beCloseTo(pair.hancom, within: 0.15), description: "산식 vs 한글 문단 \(index)"
            )
        }
        // 두께 핀: 밑줄 색인 → 줄 상자 (문단 1·3·8·10 — 라틴 run의 g·p·y 획이 선을
        // 가로지르는 문단 2·4는 뺀다).
        expect(hangul10.cellHeight * 0.05).to(beCloseTo(0.6, within: 0.001))
        expect(line8.cellHeight * 0.05).to(beCloseTo(1.164, within: 0.001))
        return GapExpectations(gaps: gaps, cells: [
            (0, hangul10.cellHeight), (2, hangul20.cellHeight),
            (4, line8.cellHeight), (6, line10.cellHeight),
        ])
    }

    /// 문단 1·2·3·4·8·9의 밑줄(초록)–취소선(청록) 간격이 글꼴 지표 산식과 같고 두 포맷이
    /// 같다. 문단 10은 10pt·20pt 두 밑줄 run이 20pt 상자의 **한 줄**로 이어진다. 밑줄 두께는
    /// 줄 상자의 0.05 cell — 10pt 줄 0.6pt·20pt 줄 1.2pt (한글 문서 기하라면 0.4·0.8pt).
    func testCompatUnderlineAndStrikethroughGapsFollowFontMetricsInBothFormats() async throws {
        let expected = try Self.gapExpectations()
        var perFormat: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.compat, hwpx: hwpx)
            let underlines = Self.lineGroups(raster, where: Self.isGreen)
            let strikes = Self.lineGroups(raster, where: Self.isCyan)
            expect(underlines.count).to(equal(7), description: "\(format) 밑줄 7줄 (문단 10은 한 줄)")
            expect(strikes.count).to(equal(6), description: "\(format) 취소선 6줄")
            guard underlines.count == 7, strikes.count == 6 else { return }
            let gaps = (0 ..< 6).map { underlines[$0].center - strikes[$0].center }
            for (index, pair) in expected.gaps.enumerated() {
                expect(gaps[index]).to(
                    beCloseTo(pair.gap, within: 0.2), description: "\(format) 문단 \(index) 간격"
                )
            }
            try assertUnderlineThicknesses(
                raster, format: format, underlines: underlines, cells: expected.cells
            )
            perFormat.append(gaps + underlines.map(\.center))
        }
        expect(perFormat[0].count) == perFormat[1].count
        for (index, value) in perFormat[0].enumerated() where index < perFormat[1].count {
            expect(value).to(
                beCloseTo(perFormat[1][index], within: 0.01),
                description: "HWP와 HWPX가 같은 자리 \(index)"
            )
        }
    }

    /// 초록 밑줄의 두께가 줄 상자의 0.05 cell이다.
    private func assertUnderlineThicknesses(
        _ raster: Raster, format: String, underlines: [Line], cells: [(index: Int, cell: CGFloat)]
    ) throws {
        for (index, cell) in cells {
            let thickness = try XCTUnwrap(
                Self.thickness(
                    raster, of: underlines[index], halfBand: cell * 0.025 + 0.35,
                    where: Self.isGreen, channel: Self.redChannel
                ),
                "\(format) 밑줄 \(index) 두께"
            )
            expect(thickness).to(
                beCloseTo(cell * 0.05, within: 0.06), description: "\(format) 밑줄 \(index) 두께"
            )
        }
    }

    /// 위 밑줄 문단(5·6)과 같은 글리프로 시작하는 아래 밑줄 문단(1·2)의 짝.
    private struct AbovePair {
        let above: Int
        let below: Int
        /// 위 밑줄 − 아래 밑줄 (pt, 같은 줄 상자).
        let span: CGFloat
        /// 두 문단이 공유하는 앞 글리프의 폭 (pt) — `가나다` 30, `Agpy` 24.
        let inkWidth: CGFloat
    }

    /// 문단 5·6의 글자 위 밑줄(자홍)은 문단 1·2의 아래 밑줄과 같은 줄 상자의 `ascent` 위에
    /// 놓인다 — 두 선의 세로 거리는 cell × 1.042다. 줄 자리는 우리 줄 상자 모델(#194)이
    /// 한글과 달라 쪽 좌표를 못 쓰고, 두 문단은 다른 줄이라 직접 못 재므로 **같은 글리프의
    /// 잉크 위 끝**을 다리로 삼는다: 문단 5와 1은 같은 글꼴·크기로 `가나다`로 시작하고
    /// 6과 2는 `Agpy`로 시작하니 (잉크 위 끝 − 위 밑줄) + (아래 밑줄 − 잉크 위 끝) = 위
    /// 밑줄 − 아래 밑줄 = 1.042 cell(문단 5·1: 12.50pt, 6·2: 12.13pt)이다. 한글 문서
    /// 기하라면 0.87em + 0.17em = 10.4pt. 문단 7의 가운데 밑줄(파랑)은 취소선 자리 —
    /// 문단 1의 취소선과 잉크 위 끝에서 같은 거리다 (한글 문서 기하라면 1.04pt 위).
    func testCompatAboveAndCenterUnderlinesFollowTheBoxInBothFormats() async throws {
        let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
        let menlo10 = Self.box("Menlo", 10)
        try XCTSkipUnless(appleSD10.cellHeight > 1.15 * 10, "Apple SD Gothic Neo 없음")
        let hangul10 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo10]))
        func span(_ box: HwpMsWordLineBox) -> CGFloat {
            HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box).center
                - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box).center
        }
        let pairs = [
            AbovePair(above: 0, below: 0, span: span(hangul10), inkWidth: 30),
            AbovePair(above: 1, below: 1, span: span(menlo10), inkWidth: 24),
        ]
        expect(span(hangul10)).to(beCloseTo(12.504, within: 0.01))
        expect(span(menlo10)).to(beCloseTo(12.13, within: 0.01))
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.compat, hwpx: hwpx)
            let underlines = Self.lineGroups(raster, where: Self.isGreen)
            let strikes = Self.lineGroups(raster, where: Self.isCyan)
            let aboves = Self.lineGroups(raster, where: Self.isMagenta)
            let centers = Self.lineGroups(raster, where: Self.isBlue)
            expect(aboves.count).to(equal(2), description: "\(format) 위 밑줄 2줄")
            expect(centers.count).to(equal(1), description: "\(format) 가운데 밑줄 1줄")
            guard underlines.count == 7, strikes.count == 6, aboves.count == 2,
                  centers.count == 1
            else { return }
            for pair in pairs {
                try assertAboveUnderline(
                    raster, format: format, pair: pair,
                    above: aboves[pair.above], below: underlines[pair.below]
                )
            }
            try assertCenterUnderline(
                raster, format: format, center: centers[0], strike: strikes[0]
            )
        }
    }

    /// 위 밑줄(자홍)의 자리를 같은 글리프의 잉크 위 끝을 거쳐 아래 밑줄(초록)과 잇고,
    /// 두께가 0.05 cell(0.6pt)임을 잰다.
    private func assertAboveUnderline(
        _ raster: Raster, format: String, pair: AbovePair, above: Line, below: Line
    ) throws {
        let inkBelowAbove = try XCTUnwrap(
            Self.inkTop(
                raster, of: above, rows: (above.center + 0.5) ... (above.center + 9),
                width: pair.inkWidth, where: Self.isMagenta
            ),
            "\(format) 위 밑줄 \(pair.above) 아래 글자 잉크"
        )
        let inkAboveBelow = try XCTUnwrap(
            Self.inkTop(
                raster, of: below, rows: (below.center - 13) ... (below.center - 0.5),
                width: pair.inkWidth, where: Self.isGreen
            ),
            "\(format) 아래 밑줄 \(pair.below) 위 글자 잉크"
        )
        let measured = (inkBelowAbove - above.center) + (below.center - inkAboveBelow)
        expect(measured).to(
            beCloseTo(pair.span, within: 0.45), description: "\(format) 위 밑줄 \(pair.above)"
        )
        // 자홍 선은 G 채널이 가장 낮다.
        let thickness = try XCTUnwrap(
            Self.thickness(
                raster, of: above, halfBand: 0.65, where: Self.isMagenta,
                channel: Self.greenChannel
            ),
            "\(format) 위 밑줄 \(pair.above) 두께"
        )
        expect(thickness).to(
            beCloseTo(0.6, within: 0.06), description: "\(format) 위 밑줄 \(pair.above) 두께"
        )
    }

    /// 가운데 밑줄(문단 7, 파랑)은 취소선 산식 — 문단 1의 취소선(청록)과 `가나다` 잉크 위
    /// 끝에서 같은 거리다.
    private func assertCenterUnderline(
        _ raster: Raster, format: String, center: Line, strike: Line
    ) throws {
        let inkAboveCenter = try XCTUnwrap(
            Self.inkTop(
                raster, of: center, rows: (center.center - 9) ... (center.center - 0.5),
                width: 30, where: Self.isBlue
            ),
            "\(format) 가운데 밑줄 위 글자 잉크"
        )
        let inkAboveStrike = try XCTUnwrap(
            Self.inkTop(
                raster, of: strike, rows: (strike.center - 9) ... (strike.center - 0.5),
                width: 30, where: Self.isCyan
            ),
            "\(format) 취소선 위 글자 잉크"
        )
        expect(center.center - inkAboveCenter).to(
            beCloseTo(strike.center - inkAboveStrike, within: 0.3),
            description: "\(format) 가운데 밑줄 = 취소선 자리"
        )
    }

    /// 한글 문서 변경 추적 문단 — 일반 선(밑줄 또는 취소선)과 그 크기.
    private struct TrackedLine {
        let ordinary: Line
        let size: CGFloat
        let isStrikethrough: Bool
        /// 20pt 선(3.2px)에서 잰 일반 선 색의 완전 커버 채널값.
        let fullChannel: UInt8?
    }

    /// `track-changes-native` — 한글 문서에서 삽입 밑줄(빨강)은 같은 줄의 일반 밑줄(초록)
    /// 과, 삭제선(빨강)은 같은 줄의 취소선(청록)과 같은 행·같은 두께다. 종전 상수로는
    /// 10pt에서 밑줄이 0.9pt 낮고 두께가 1.6배, 삭제선이 0.6pt 낮았다. 변경 추적 글자
    /// 자체가 빨강이라 빨강 선은 일반 선의 행 근처(±2pt)에서 12pt 넘게 이어진 행으로만
    /// 센다 — 20pt 글리프의 가로 획은 11pt를 넘지 않고 10pt 삭제 run의 선은 17pt다.
    /// 두께는 커버리지 합(`Raster.lineThickness`)으로 0.04em(10pt 0.4·20pt 0.8pt)을 핀한다
    /// — 10pt 선은 1.6px라 완전 커버 행이 없을 수 있어 같은 색 20pt 선(3.2px)에서 잰
    /// 완전 커버 값으로 정규화한다.
    func testNativeTrackChangeLinesCoincideWithOrdinaryLines() async throws {
        let raster = try await Self.raster("track-changes-native", hwpx: false)
        let greens = Self.lineGroups(raster, where: Self.isGreen)
        let cyans = Self.lineGroups(raster, where: Self.isCyan)
        expect(greens.count).to(equal(2), description: "일반 밑줄 10·20pt")
        expect(cyans.count).to(equal(2), description: "취소선 10·20pt")
        guard greens.count == 2, cyans.count == 2 else { return }
        // 완전 커버 값은 20pt 선(0.8pt = 3.2px)에서 — 문단 3·4.
        let fullGreen = Self.fullChannel(
            raster, of: greens[1], halfBand: 0.75, where: Self.isGreen, channel: Self.redChannel
        )
        let fullCyan = Self.fullChannel(
            raster, of: cyans[1], halfBand: 0.75, where: Self.isCyan, channel: Self.redChannel
        )
        let fullRed = try Self.reds(raster, near: greens[1]).first.flatMap {
            Self.fullChannel(
                raster, of: $0, halfBand: 0.75, where: Self.isRed, channel: Self.greenChannel
            )
        }.map { try XCTUnwrap($0) }
        expect(fullGreen).toNot(beNil())
        expect(fullCyan).toNot(beNil())
        expect(fullRed).toNot(beNil())
        // 문단 순서: 밑줄+삽입(10) · 취소+삭제(10) · 밑줄+삽입(20) · 취소+삭제(20).
        let lines = [
            TrackedLine(
                ordinary: greens[0], size: 10, isStrikethrough: false, fullChannel: fullGreen
            ),
            TrackedLine(ordinary: cyans[0], size: 10, isStrikethrough: true, fullChannel: fullCyan),
            TrackedLine(
                ordinary: greens[1], size: 20, isStrikethrough: false, fullChannel: fullGreen
            ),
            TrackedLine(ordinary: cyans[1], size: 20, isStrikethrough: true, fullChannel: fullCyan),
        ]
        for (index, line) in lines.enumerated() {
            try assertTrackedLine(raster, paragraph: index + 1, line: line, fullRed: fullRed)
        }
    }

    /// 일반 선 근처(±2pt)의 빨강 선들.
    private static func reds(_ raster: Raster, near ordinary: Line) -> [Line] {
        lineGroups(raster, minimumLength: 12, where: isRed)
            .filter { abs($0.center - ordinary.center) < 2 }
    }

    /// 빨강 표시선이 일반 선과 같은 자리·같은 두께이고, 일반 선 두께가 0.04em이다.
    private func assertTrackedLine(
        _ raster: Raster, paragraph: Int, line: TrackedLine, fullRed: UInt8?
    ) throws {
        let candidates = Self.reds(raster, near: line.ordinary)
        expect(candidates.count).to(equal(1), description: "문단 \(paragraph) 빨강 선")
        guard let red = candidates.first else { return }
        expect(red.center).to(
            beCloseTo(line.ordinary.center, within: 0.2), description: "문단 \(paragraph) 자리"
        )
        let expected = line.size * 0.04
        let halfBand = expected / 2 + 0.35
        let ordinary = try XCTUnwrap(
            Self.thickness(
                raster, of: line.ordinary, halfBand: halfBand,
                where: line.isStrikethrough ? Self.isCyan : Self.isGreen,
                channel: Self.redChannel, fullChannel: line.fullChannel
            ),
            "문단 \(paragraph) 일반 선 두께"
        )
        let tracked = try XCTUnwrap(
            Self.thickness(
                raster, of: red, halfBand: halfBand, where: Self.isRed,
                channel: Self.greenChannel, fullChannel: fullRed
            ),
            "문단 \(paragraph) 빨강 선 두께"
        )
        expect(ordinary).to(
            beCloseTo(expected, within: 0.06), description: "문단 \(paragraph) 일반 선 두께"
        )
        expect(tracked).to(
            beCloseTo(ordinary, within: 0.06), description: "문단 \(paragraph) 두께 일치"
        )
    }
}
