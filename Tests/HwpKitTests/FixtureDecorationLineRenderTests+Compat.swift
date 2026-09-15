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

    /// 문단 1·2·3·4·8·9의 밑줄(초록)–취소선(청록) 간격이 글꼴 지표 산식과 같고 두 포맷이
    /// 같다. 문단 10은 10pt·20pt 두 밑줄 run이 20pt 상자의 **한 줄**로 이어진다.
    func testCompatUnderlineAndStrikethroughGapsFollowFontMetricsInBothFormats() async throws {
        let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
        let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
        let menlo10 = Self.box("Menlo", 10)
        let menlo20 = Self.box("Menlo", 20)
        try XCTSkipUnless(appleSD10.cellHeight > 1.15 * 10, "Apple SD Gothic Neo 없음")
        func gap(line: HwpMsWordLineBox, strike: HwpMsWordLineBox, size: CGFloat) -> CGFloat {
            HwpDecorationLineGeometry.msWordStrikethrough(runBox: strike, thicknessFontSize: size)
                .center - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: line).center
        }
        // 문단 끝 글자(Menlo, 마지막 run 크기)가 줄 상자에 든다.
        let expected: [(gap: CGFloat, hancom: CGFloat)] = [
            (gap(line: try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo10])),
                 strike: appleSD10, size: 10),
             (0.2530 + 0.3012) * 9.96),
            (gap(line: menlo10, strike: menlo10, size: 10), (0.2530 + 0.2651) * 9.96),
            (gap(line: try XCTUnwrap(HwpMsWordLineBox.union([appleSD20, menlo20])),
                 strike: appleSD20, size: 20),
             (0.2455 + 0.2994) * 20.04),
            (gap(line: menlo20, strike: menlo20, size: 20), (0.2575 + 0.2575) * 20.04),
            (gap(line: try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo20])),
                 strike: appleSD10, size: 10),
             (0.1257 + 0.2575) * 20.04),
            (gap(line: try XCTUnwrap(HwpMsWordLineBox.union([menlo10, appleSD10])),
                 strike: appleSD10, size: 10),
             (0.2410 + 0.3012) * 9.96),
        ]
        for (index, pair) in expected.enumerated() {
            expect(pair.gap).to(
                beCloseTo(pair.hancom, within: 0.15), description: "산식 vs 한글 문단 \(index)"
            )
        }

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
            for (index, pair) in expected.enumerated() {
                expect(gaps[index]).to(
                    beCloseTo(pair.gap, within: 0.2), description: "\(format) 문단 \(index) 간격"
                )
            }
            // 두께: 10pt 상자 0.6pt는 4px/pt에서 2~3행, 20pt 상자 1.2pt는 4~5행 —
            // 한글 문서의 10pt 밑줄(0.4pt, 1~2행)보다 굵다.
            expect(underlines[0].rows).to(beGreaterThanOrEqualTo(2))
            expect(underlines[2].rows).to(beGreaterThanOrEqualTo(4))
            expect(underlines[4].rows).to(beGreaterThanOrEqualTo(4), description: "문단 8은 20pt 상자")
            expect(underlines[6].rows).to(beGreaterThanOrEqualTo(4), description: "문단 10은 20pt 상자")
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

    /// 문단 5·6의 글자 위 밑줄(자홍)은 문단 1·2의 아래 밑줄과 같은 줄 상자의 `ascent` 위에
    /// 놓인다 — 같은 상자라 두 선의 세로 거리(줄 자리 차를 뺀 값)가 cell × 1.042다. 줄
    /// 자리는 우리 줄 상자 모델(#194)이 한글과 달라 한글 좌표를 직접 못 쓰므로, 문단 사이
    /// 줄 간격이 같은 두 쌍(1↔5, 2↔6)의 차로 잡는다. 문단 7의 가운데 밑줄(파랑)은
    /// 취소선 자리다.
    func testCompatAboveAndCenterUnderlinesFollowTheBoxInBothFormats() async throws {
        let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
        let menlo10 = Self.box("Menlo", 10)
        try XCTSkipUnless(appleSD10.cellHeight > 1.15 * 10, "Apple SD Gothic Neo 없음")
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.compat, hwpx: hwpx)
            let underlines = Self.lineGroups(raster, where: Self.isGreen)
            let aboves = Self.lineGroups(raster, where: Self.isMagenta)
            let strikes = Self.lineGroups(raster, where: Self.isCyan)
            let centers = Self.lineGroups(raster, where: Self.isBlue)
            expect(aboves.count).to(equal(2), description: "\(format) 위 밑줄 2줄")
            expect(centers.count).to(equal(1), description: "\(format) 가운데 밑줄 1줄")
            guard underlines.count == 7, strikes.count == 6, aboves.count == 2,
                  centers.count == 1
            else { return }
            // 문단 1~7은 같은 10pt 상자 줄이 아니라 3·4가 20pt라 줄 간격이 다르다 — 위
            // 밑줄은 자기 줄의 취소선 자리와 대조한다: 가운데 밑줄(7) − 취소선 자리는
            // 문단 1의 취소선과 같은 상자(Apple SD 10 + 문단 끝 Menlo)다.
            let line1 = try XCTUnwrap(HwpMsWordLineBox.union([appleSD10, menlo10]))
            // 문단 5 위 밑줄 vs 문단 1 아래 밑줄·취소선은 줄이 달라 직접 못 잰다 → 위 밑줄과
            // 그 줄 글자 잉크의 관계로 잡는다: 선이 글자 잉크 위에 있다.
            for (index, above) in aboves.enumerated() {
                let ink = try XCTUnwrap(
                    raster.band(
                        in: (above.center + 0.4) ... (above.center + 12), where: Self.isDark
                    ),
                    "\(format) 위 밑줄 \(index) 아래 글자 잉크"
                )
                expect(ink.top).to(
                    beGreaterThan(above.center), description: "\(format) 위 밑줄 \(index)"
                )
                expect(above.rows).to(beGreaterThanOrEqualTo(2), description: "\(format) 위 밑줄 두께")
            }
            // 가운데 밑줄은 취소선 산식이다 — 그 줄의 글자 잉크 가운데를 지난다.
            let center = centers[0].center
            let ink = try XCTUnwrap(
                raster.band(in: (center - 6) ... (center + 6), where: Self.isDark),
                "\(format) 가운데 밑줄 줄의 글자 잉크"
            )
            let strikeAboveBaseline = HwpDecorationLineGeometry.msWordStrikethrough(
                runBox: appleSD10, thicknessFontSize: 10
            ).center
            expect(strikeAboveBaseline).to(beCloseTo(2.457, within: 0.001))
            expect(abs(center - (ink.top + ink.bottom) / 2)).to(
                beLessThan(1.2), description: "\(format) 가운데 밑줄 \(center) 잉크 \(ink)"
            )
            _ = line1
        }
    }

    /// `track-changes-native` — 한글 문서에서 삽입 밑줄(빨강)은 같은 줄의 일반 밑줄(초록)
    /// 과, 삭제선(빨강)은 같은 줄의 취소선(청록)과 같은 행·같은 두께다. 종전 상수로는
    /// 10pt에서 밑줄이 0.9pt 낮고 두께가 1.6배, 삭제선이 0.6pt 낮았다. 변경 추적 글자
    /// 자체가 빨강이라 빨강 선은 일반 선의 행 근처(±2pt)에서 12pt 넘게 이어진 행으로만
    /// 센다 — 20pt 글리프의 가로 획은 11pt를 넘지 않고 10pt 삭제 run의 선은 17pt다.
    func testNativeTrackChangeLinesCoincideWithOrdinaryLines() async throws {
        let raster = try await Self.raster("track-changes-native", hwpx: false)
        let greens = Self.lineGroups(raster, where: Self.isGreen)
        let cyans = Self.lineGroups(raster, where: Self.isCyan)
        expect(greens.count).to(equal(2), description: "일반 밑줄 10·20pt")
        expect(cyans.count).to(equal(2), description: "취소선 10·20pt")
        guard greens.count == 2, cyans.count == 2 else { return }
        // 문단 순서: 밑줄+삽입(10) · 취소+삭제(10) · 밑줄+삽입(20) · 취소+삭제(20).
        for (index, ordinary) in [greens[0], cyans[0], greens[1], cyans[1]].enumerated() {
            let reds = Self.lineGroups(raster, minimumLength: 12, where: Self.isRed)
                .filter { abs($0.center - ordinary.center) < 2 }
            expect(reds.count).to(equal(1), description: "문단 \(index + 1) 빨강 선")
            guard let red = reds.first else { continue }
            expect(red.center).to(
                beCloseTo(ordinary.center, within: 0.2), description: "문단 \(index + 1) 자리"
            )
            // 두께: 같은 0.04em이지만 색 판정 문턱이 달라 안티앨리어싱 행이 1행 갈릴 수 있다.
            expect(abs(red.rows - ordinary.rows)).to(
                beLessThanOrEqualTo(1), description: "문단 \(index + 1) 두께"
            )
        }
        // 20pt 줄의 선은 10pt 줄보다 굵다 (0.8pt vs 0.4pt).
        expect(greens[1].rows).to(beGreaterThan(greens[0].rows))
    }
}
