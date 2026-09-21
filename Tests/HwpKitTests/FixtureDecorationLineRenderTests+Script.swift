import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `script-decorations` 쌍의 실물 핀 (#179) — 위/아래 첨자 run의 취소선·글자 가운데
/// 밑줄은 첨자로 옮겨진 글리프를 따라가고, 글자 아래·위 밑줄은 첨자에도 글자 위치에도
/// 제자리이며 축소 전 크기 기준이다. 두 포맷이 같은 자리에 그린다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-15, 벡터 좌표, **쪽 위에서부터**
/// pt — 아래가 양수라 베이스라인 위의 선은 뺀다). 문단 k(1부터)의 베이스라인은 줄
/// 캐시대로 107.7 + 16k(PDF 실측 123.72·139.80…)이고 선은 다음 자리다:
///
/// | k | 문단 | 한글 선 y | 기준 (쪽 위에서부터) |
/// |---|---|---:|---|
/// | 1 | 위 첨자 취소선 | 117.12 | 옮겨진 베이스라인 119.40(4.32 위) − 0.35 × 6.36 |
/// | 2 | 아래 첨자 취소선 | 138.72 | 옮겨진 베이스라인 141.00(1.20 아래) − 0.35 × 6.36 |
/// | 3 | 위 첨자 가운데 밑줄 | 149.16 | 1과 같은 규칙 (+32.0) |
/// | 4 | 아래 첨자 가운데 밑줄 | 170.76 | 2와 같은 규칙 (+32.0) |
/// | 5 | 위 첨자 아래 밑줄 | 189.48 | 원래 베이스라인 187.7 + 0.17 × 10 |
/// | 6 | 아래 첨자 아래 밑줄 | 205.44 | 원래 베이스라인 203.7 + 0.17 × 10 |
/// | 7 | 위 첨자 위 밑줄 | 211.08 | 원래 베이스라인 219.7 − 0.87 × 10 |
/// | 8 | 아래 첨자 위 밑줄 | 227.04 | 원래 베이스라인 235.7 − 0.87 × 10 |
/// | 9 | 글자 위치 50 취소선 | 248.28 | 원래 베이스라인 251.7 − 0.35 × 10 (글리프만 5.04 아래) |
/// | 10 | 위 첨자 + 글자 위치 50 취소선 | 261.12 | 1과 같은 자리 (+144.0) — 위치 몫은 안 따라감 |
/// | 11 | 위 첨자 + 글자 위치 50 아래 밑줄 | 285.48 | 원래 베이스라인 283.7 + 0.17 × 10 |
///
/// 첨자 이동에 걸리지 않는 선(5~9·11)은 한글 좌표를 그대로 핀한다. 첨자 취소선·가운데
/// 밑줄(1~4·10)도 #204에서 첨자 글리프 자체를 한글 규칙(0.64배·위 0.44em·아래 0.12em)에
/// 맞춘 뒤로는 한글 좌표를 그대로 핀한다 — 우리 선은 옮겨진 베이스라인(4.40 위·1.20 아래)
/// + 0.35 × 6.4pt라 117.06·138.66·149.06·170.66·261.06으로 한글과 0.06~0.10pt 차다(#204 전
/// 0.33em·0.30em·0.67배에서는 0.9(위)·1.7pt(아래) 낮았다). 덧붙여 **글리프와의 관계**도
/// 핀한다: 선이 옮겨진 첨자 글리프 잉크의 세로 가운데를 지나고, 글자 위치 50을 더해도
/// 같은 자리이며, 가운데 밑줄이 취소선과 같은 규칙이다.
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다.
extension FixtureDecorationLineRenderTests {
    private static let fixture = "script-decorations"
    /// 문단 k(1부터)의 줄 캐시 베이스라인 (쪽 위에서부터 pt).
    private static func baseline(_ paragraph: Int) -> CGFloat {
        107.7 + 16 * CGFloat(paragraph)
    }

    private static func isMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    /// 문단 k의 색 선 중심 — 그 줄의 베이스라인 위 12pt ~ 아래 4pt 안에서 찾는다
    /// (문단 간격 16pt라 이웃 줄의 선은 밖이다).
    private static func lineCenter(
        _ raster: Raster, paragraph: Int, where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> CGFloat? {
        let base = baseline(paragraph)
        return raster.center(in: (base - 12) ... (base + 4), where: match)
    }

    /// 문단 k의 빨강(대상 run) 잉크 띠 — 베이스라인 위 `above`pt ~ 아래 4pt 안에서 찾는다.
    /// 글자 위치 50으로 5pt 내려간 앞 문단의 잉크가 이 창에 걸치면 `above`를 줄인다. 아래
    /// 4pt는 아래 첨자 글리프(1.2 아래 + 6.4pt 글꼴의 descender ≈ 2.8)를 품되 다음 문단의
    /// 위 첨자 잉크(4.4 위로 올라가 문단 간격 16pt에서 base + 6.5쯤부터)는 밖이다.
    private static func redInkBand(
        _ raster: Raster, paragraph: Int, above: CGFloat = 12
    ) -> (top: CGFloat, bottom: CGFloat)? {
        let base = baseline(paragraph)
        return raster.band(in: (base - above) ... (base + 4), where: isRed)
    }

    /// `redInkBand`의 세로 가운데.
    private static func redInkCenter(
        _ raster: Raster, paragraph: Int, above: CGFloat = 12
    ) -> CGFloat? {
        redInkBand(raster, paragraph: paragraph, above: above).map { ($0.top + $0.bottom) / 2 }
    }

    /// 첨자에 걸리지 않는 선 6개는 한글 좌표 그대로다 — 아래쪽 밑줄은 첨자 run에서도
    /// 원래 베이스라인 아래 0.17 × 10pt(줄어든 6.4pt 기준이면 0.61pt 위), 위쪽 밑줄은
    /// 위 0.87 × 10pt, 글자 위치만 준 취소선은 제자리다. 두 포맷이 같은 행이다.
    func testScriptIndependentLinesMatchHancomCoordinatesInBothFormats() async throws {
        struct Pin {
            let paragraph: Int
            let hancom: CGFloat
            let match: (UInt8, UInt8, UInt8) -> Bool
        }
        let pins = [
            Pin(paragraph: 5, hancom: 189.48, match: Self.isGreen),
            Pin(paragraph: 6, hancom: 205.44, match: Self.isGreen),
            Pin(paragraph: 7, hancom: 211.08, match: Self.isGreen),
            Pin(paragraph: 8, hancom: 227.04, match: Self.isGreen),
            Pin(paragraph: 9, hancom: 248.28, match: Self.isCyan),
            Pin(paragraph: 11, hancom: 285.48, match: Self.isGreen),
        ]
        var centers: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.fixture, hwpx: hwpx)
            var rows: [CGFloat] = []
            for pin in pins {
                let center = try XCTUnwrap(
                    Self.lineCenter(raster, paragraph: pin.paragraph, where: pin.match),
                    "\(format): 문단 \(pin.paragraph)의 선을 못 찾았다"
                )
                // 오차 예산: 잉크 가중 중심 추정 ±0.08(4배 래스터의 0.4pt 선) + 우리
                // 렌더의 한글 대비 격차 ≤0.15 + 한글 장치 좌표 0.12pt 양자화. 수정 전
                // 아래 밑줄 격차 0.56은 밖이다.
                expect(center).to(
                    beCloseTo(pin.hancom, within: 0.3),
                    description: "\(format) 문단 \(pin.paragraph)"
                )
                rows.append(center)
            }
            centers.append(rows)
        }
        for (index, pin) in pins.enumerated() {
            expect(centers[0][index]).to(
                beCloseTo(centers[1][index], within: 0.01),
                description: "문단 \(pin.paragraph): HWP와 HWPX가 같은 자리"
            )
        }
    }

    /// 첨자 취소선·가운데 밑줄은 한글 좌표 그대로다 (#204) — 옮겨진 베이스라인(위 첨자
    /// 4.40 위·아래 첨자 1.20 아래) + 0.35 × 6.4pt. #204 전(0.33em·0.30em·0.67배)에는 위
    /// 첨자 선이 0.9pt·아래 첨자 선이 1.7pt 낮아 0.3pt 예산 밖이었다. 두 포맷이 같은 행이다.
    func testScriptLinesMatchHancomCoordinatesInBothFormats() async throws {
        struct Pin {
            let paragraph: Int
            let hancom: CGFloat
            let match: (UInt8, UInt8, UInt8) -> Bool
        }
        let pins = [
            Pin(paragraph: 1, hancom: 117.12, match: Self.isCyan),
            Pin(paragraph: 2, hancom: 138.72, match: Self.isCyan),
            Pin(paragraph: 3, hancom: 149.16, match: Self.isMagenta),
            Pin(paragraph: 4, hancom: 170.76, match: Self.isMagenta),
            Pin(paragraph: 10, hancom: 261.12, match: Self.isCyan),
        ]
        var centers: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.fixture, hwpx: hwpx)
            var rows: [CGFloat] = []
            for pin in pins {
                let center = try XCTUnwrap(
                    Self.lineCenter(raster, paragraph: pin.paragraph, where: pin.match),
                    "\(format): 문단 \(pin.paragraph)의 선을 못 찾았다"
                )
                // 오차 예산은 첨자 무관 선과 같다(잉크 가중 중심 ±0.08 + 우리 격차 ≤0.10 +
                // 한글 장치 양자화 0.12). 위 첨자 취소선 표본의 올림은 4.32라 우리 4.40과
                // 0.08 차이고, 10pt 위 첨자 단독 표본(4.44)과는 0.04 차다.
                expect(center).to(
                    beCloseTo(pin.hancom, within: 0.3),
                    description: "\(format) 문단 \(pin.paragraph)"
                )
                rows.append(center)
            }
            centers.append(rows)
        }
        for (index, pin) in pins.enumerated() {
            expect(centers[0][index]).to(
                beCloseTo(centers[1][index], within: 0.01),
                description: "문단 \(pin.paragraph): HWP와 HWPX가 같은 자리"
            )
        }
    }

    /// 첨자 취소선은 옮겨진 글리프를 따라간다 — 선이 첨자 run의 빨강 잉크 띠의 **가운데
    /// 절반** 안을 지나고, 위 첨자 선은 본문 취소선 자리(베이스라인 위 3.5pt)보다 위, 아래
    /// 첨자 선은 그보다 아래다. #179 전에는 둘 다 원래 베이스라인 위 0.35 × 축소 크기(당시
    /// 6.7pt = 2.3pt)에 그려 위 첨자 글리프 아래·아래 첨자 글리프 위로 2.7·3.6pt 벗어났다.
    /// 선과 잉크 중심의 거리를 좁게 핀하지 않는 이유: 취소선(옮겨진 베이스라인 위 0.35em)과
    /// `대상 Ag` 잉크 중심(약 0.25em)은 원래 0.5pt쯤 어긋나고, 그 값은 래스터 반올림에 따라
    /// macOS 0.50·iOS 시뮬레이터 0.62로 갈린다 — 절대 좌표는
    /// `testScriptLinesMatchHancomCoordinatesInBothFormats`가 0.3pt로 핀한다.
    func testScriptStrikethroughCrossesTheShiftedGlyphsInBothFormats() async throws {
        var rows: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.fixture, hwpx: hwpx)
            var centers: [CGFloat] = []
            for (paragraph, name) in [(1, "위 첨자"), (2, "아래 첨자")] {
                let line = try XCTUnwrap(
                    Self.lineCenter(raster, paragraph: paragraph, where: Self.isCyan),
                    "\(format): \(name) 취소선을 못 찾았다"
                )
                let ink = try XCTUnwrap(
                    Self.redInkBand(raster, paragraph: paragraph),
                    "\(format): \(name) 글리프를 못 찾았다"
                )
                let inkCenter = (ink.top + ink.bottom) / 2
                let quarter = (ink.bottom - ink.top) / 4
                // 6.4pt 글리프의 잉크 띠는 6.5pt쯤이라 가운데 절반은 ±1.6pt — 선이 글리프
                // 밖(#179 전 2.7·3.6pt)이면 갈리고 래스터 반올림(≤0.25pt)에는 무관하다.
                expect(quarter).to(beGreaterThan(1.2), description: "\(format) \(name) 잉크 띠")
                expect(abs(line - inkCenter)).to(
                    beLessThan(quarter),
                    description: "\(format) \(name) 선 \(line) 잉크 \(ink.top)…\(ink.bottom)"
                )
                centers.append(line)
            }
            // 본문 크기 취소선 자리 = 베이스라인 위 0.35 × 10pt.
            let plainStrike1 = Self.baseline(1) - 3.5
            let plainStrike2 = Self.baseline(2) - 3.5
            expect(centers[0]).to(beLessThan(plainStrike1 - 1.5), description: "\(format) 위 첨자")
            expect(centers[1]).to(beGreaterThan(plainStrike2 + 1.5), description: "\(format) 아래 첨자")
            rows.append(centers)
        }
        expect(rows[0][0]).to(beCloseTo(rows[1][0], within: 0.01))
        expect(rows[0][1]).to(beCloseTo(rows[1][1], within: 0.01))
    }

    /// 글자 가운데 밑줄은 취소선과 같은 규칙(3·4는 1·2에서 정확히 두 문단 아래)이고,
    /// 글자 위치 50을 함께 준 위 첨자의 취소선(10)은 위 첨자만 준 것(1)과 같은 자리다
    /// — 선은 첨자 몫만 따라가고 글자 위치 몫(글리프 5.04pt 아래)은 따라가지 않는다.
    func testCenterUnderlineAndFaceLocationFollowTheScriptRuleInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.fixture, hwpx: hwpx)
            let strikeSup = try XCTUnwrap(
                Self.lineCenter(raster, paragraph: 1, where: Self.isCyan), "\(format) 문단 1"
            )
            let strikeSub = try XCTUnwrap(
                Self.lineCenter(raster, paragraph: 2, where: Self.isCyan), "\(format) 문단 2"
            )
            let centerSup = try XCTUnwrap(
                Self.lineCenter(raster, paragraph: 3, where: Self.isMagenta), "\(format) 문단 3"
            )
            let centerSub = try XCTUnwrap(
                Self.lineCenter(raster, paragraph: 4, where: Self.isMagenta), "\(format) 문단 4"
            )
            let located = try XCTUnwrap(
                Self.lineCenter(raster, paragraph: 10, where: Self.isCyan), "\(format) 문단 10"
            )
            expect(centerSup - strikeSup).to(beCloseTo(32, within: 0.15), description: format)
            expect(centerSub - strikeSub).to(beCloseTo(32, within: 0.15), description: format)
            expect(located - strikeSup).to(beCloseTo(144, within: 0.15), description: format)
            // 글자 위치 몫(5.04pt 아래)까지 따라가면 문단 10의 선은 5pt 더 내려간다.
            // 문단 9의 글리프도 5pt 내려가 있어 창을 위로 8pt까지만 연다.
            let glyph = try XCTUnwrap(
                Self.redInkCenter(raster, paragraph: 10, above: 8), "\(format) 문단 10 글리프"
            )
            expect(glyph - located).to(beGreaterThan(4), description: "\(format): 글리프는 내려갔다")
        }
    }
}
