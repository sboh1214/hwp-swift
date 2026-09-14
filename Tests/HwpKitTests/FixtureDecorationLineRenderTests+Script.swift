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
/// 첨자 이동에 걸리지 않는 선(5~9·11)은 한글 좌표를 그대로 핀한다. 첨자 취소선(1~4·10)은
/// 우리 첨자 글리프 자체가 한글과 다르게 놓여(위 첨자 올림 0.33em vs 한글 0.446em,
/// 아래 첨자 내림 0.30em vs 0.12em — 이 축은 #179 밖이라 #204) 절대 좌표 대신
/// **글리프와의 관계**를 핀한다: 선이 옮겨진 첨자 글리프 잉크의 세로 가운데를 지나고,
/// 글자 위치 50을 더해도 같은 자리이며, 가운데 밑줄이 취소선과 같은 규칙이다.
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

    /// 문단 k의 빨강(대상 run) 잉크 띠의 세로 가운데 — 베이스라인 위 `above`pt ~ 아래
    /// 6pt 안에서 찾는다. 글자 위치 50으로 5pt 내려간 앞 문단의 잉크가 이 창에 걸치면
    /// `above`를 줄인다.
    private static func redInkCenter(
        _ raster: Raster, paragraph: Int, above: CGFloat = 12
    ) -> CGFloat? {
        let base = baseline(paragraph)
        guard let band = raster.band(in: (base - above) ... (base + 6), where: isRed) else {
            return nil
        }
        return (band.top + band.bottom) / 2
    }

    /// 첨자에 걸리지 않는 선 6개는 한글 좌표 그대로다 — 아래쪽 밑줄은 첨자 run에서도
    /// 원래 베이스라인 아래 0.17 × 10pt(줄어든 6.7pt 기준이면 0.56pt 위), 위쪽 밑줄은
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

    /// 첨자 취소선은 옮겨진 글리프를 따라간다 — 선이 첨자 run의 빨강 잉크 세로 가운데를
    /// 지나고, 위 첨자 선은 본문 취소선 자리(베이스라인 위 3.5pt)보다 위, 아래 첨자 선은
    /// 그보다 아래다. 종전에는 둘 다 원래 베이스라인 위 0.35 × 6.7pt = 2.3pt에 그려
    /// 위 첨자 글리프 아래·아래 첨자 글리프 위로 벗어났다.
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
                    Self.redInkCenter(raster, paragraph: paragraph),
                    "\(format): \(name) 글리프를 못 찾았다"
                )
                expect(abs(line - ink)).to(
                    beLessThan(0.6), description: "\(format) \(name) 선 \(line) 잉크중심 \(ink)"
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
