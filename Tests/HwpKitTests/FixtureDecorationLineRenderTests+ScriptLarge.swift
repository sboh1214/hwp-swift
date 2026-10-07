import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `script-strikethrough-large` 쌍의 실물 핀 (#258) — 한글 문서의 위·아래 첨자 취소선(글자 가운데 밑줄
/// 포함)은 **첨자로 옮겨진 베이스라인** 위, 보통 글자 취소선 높이(0.35 × 기본 크기)의 89/140배
/// (`HwpRenderTuning.Text.scriptStrikethroughScale`)에 그려진다 — 첨자 글리프 축소 비율 0.64가 아니다.
/// 두 배율의 차는 기본 크기의 0.0015배라 `script-decorations`(10pt)·`mixed-size-decorations`(20pt)에서는
/// 한글 PDF의 장치 좌표(0.12pt) 안에 묻혀, 그 차가 0.075–0.24pt인 50–160pt로 따로 만든 쌍이다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-07, 벡터 좌표, 쪽 위에서부터 pt).
/// 이 문서는 한글이 줄 배치 캐시를 적어 두었으므로 쪽 좌표를 그대로 핀한다. 글꼴은 한글 슬롯 Apple SD
/// 산돌고딕 Neo·라틴 슬롯 Menlo라 결정론 resolver(`HwpFontResolver.testDeterministic`)가 같은 글꼴을
/// 고른다. 문단마다 보통(청록)·위 첨자(자홍)·아래 첨자(초록) run이 한 줄에 나란하다:
///
/// | 문단 | 표본 | 베이스라인 | 보통 | 위 첨자 | 아래 첨자 |
/// |---|---|---:|---:|---:|---:|
/// | 1 | Menlo 50pt | 151.80 | 134.28 | 118.68 | 146.64 |
/// | 2 | Menlo 80pt | 227.28 | 199.20 | 174.24 | 219.00 |
/// | 3 | Apple SD 100pt | 324.24 | 289.20 | 258.00 | 314.04 |
/// | 4 | Menlo 100pt 글자 가운데 밑줄 | 424.20 | 389.28 | 357.96 | 414.00 |
/// | 5 | Menlo 150pt | 566.76 | 514.20 | 467.40 | 551.40 |
/// | 6 | Menlo 160pt | 725.28 | 669.24 | 619.20 | 708.84 |
///
/// 한글은 첨자 선을 줄 캐시 베이스라인에서 첨자 이동(0.44·0.12 × 기본 크기)만큼 옮긴 자리 위
/// ⌊89 × 기본 크기(HWPUNIT) ÷ 400⌋에 두고 쪽 좌표를 장치 단위로 떨어뜨린다 — 연속 모형(기본 크기의
/// 0.2225배)을 한글 PDF의 베이스라인에 얹으면 12선 모두 0.08pt 안이다. 우리 렌더는 베이스라인을 줄 캐시의
/// 연속값으로 두어 12선이 한글과 최대 0.105pt(1번 위 첨자)이고, 0.64배(0.224배)로 그리면 문단마다
/// 0.12–0.30pt 갈린다 (위/아래 첨자: 1번 0.18/0.14, 2번 0.16/0.12, 3번 0.20/0.24, 4번 0.16/0.20,
/// 5번 0.30/0.30, 6번 0.24/0.28).
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다.
extension FixtureDecorationLineRenderTests {
    private static let scriptLarge = "script-strikethrough-large"

    /// 문단 하나의 한글 쪽 좌표 (pt, 쪽 위에서부터) — 기본 크기와 보통·위 첨자·아래 첨자 선 중심
    /// (베이스라인은 위 표에만 적는다 — 핀은 선끼리의 간격과 쪽 좌표로 잡는다)
    private struct ScriptLargeRow {
        let paragraph: Int
        let size: CGFloat
        let plain: CGFloat
        let superscript: CGFloat
        let `subscript`: CGFloat

        init(_ paragraph: Int, size: CGFloat, _ lines: [CGFloat]) {
            self.paragraph = paragraph
            self.size = size
            plain = lines[0]
            superscript = lines[1]
            `subscript` = lines[2]
        }
    }

    private static let scriptLargeRows = [
        ScriptLargeRow(1, size: 50, [134.28, 118.68, 146.64]),
        ScriptLargeRow(2, size: 80, [199.20, 174.24, 219.00]),
        ScriptLargeRow(3, size: 100, [289.20, 258.00, 314.04]),
        ScriptLargeRow(4, size: 100, [389.28, 357.96, 414.00]),
        ScriptLargeRow(5, size: 150, [514.20, 467.40, 551.40]),
        ScriptLargeRow(6, size: 160, [669.24, 619.20, 708.84]),
    ]

    /// 선 색 — 흰 바탕에 칠한 순색 선의 커버리지를 픽셀에서 되읽는다 (`+MsWordScript`와 같은 방식).
    private enum ScriptLargeColor {
        case cyan, magenta, green

        func coverage(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
            let (red, green, blue) = (Double(red), Double(green), Double(blue))
            switch self {
            case .cyan: return max(0, min(green, blue) - red) / 255
            case .magenta: return max(0, min(red, blue) - green) / 255
            case .green: return max(0, green - max(red, blue)) / 255
            }
        }
    }

    /// 이 픽스처의 쪽 높이 (A4, `hp:pagePr@height` 84186 HWPUNIT)
    private static let scriptLargePageHeight: CGFloat = 841.86

    /// `near`(pt) ± `reach`(pt) 행에서 잰 선 중심 — 행마다 선 색 커버리지를 더한 가중 중심을 **실제 세로
    /// 배율**(`raster(_:hwpx:)`는 쪽을 `Int(쪽 높이 × 4)`행에 그린다)로 pt에 옮긴다 (`+MsWordScript`의
    /// `coverageCenter`와 같은 방식). 160pt 선은 두께가 6.24pt라 창을 선 두께보다 넓게 잡는다.
    private static func scriptLargeCenter(
        _ raster: Raster, near center: CGFloat, color: ScriptLargeColor, reach: CGFloat = 5
    ) -> CGFloat? {
        let pixelsPerPoint = CGFloat(raster.pixelHeight) / scriptLargePageHeight
        let top = max(0, Int(((center - reach) * pixelsPerPoint).rounded(.down)))
        let bottom = min(
            raster.pixelHeight - 1, Int(((center + reach) * pixelsPerPoint).rounded(.up))
        )
        guard top <= bottom else { return nil }
        var weighted = 0.0
        var total = 0.0
        for y in top ... bottom {
            for x in 0 ..< raster.pixelWidth {
                let offset = y * raster.bytesPerRow + x * 4
                let weight = color.coverage(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
                guard weight > 0.02 else { continue }
                weighted += (Double(y) + 0.5) * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        return CGFloat(weighted / total) / pixelsPerPoint
    }

    /// 18선이 한글 쪽 좌표에 있고, 첨자 선과 같은 줄 보통 선의 간격이 모형(위 첨자 (0.44 + 0.2225 −
    /// 0.35) × 기본 크기 = 0.3125배, 아래 첨자 (0.35 + 0.12 − 0.2225)배 = 0.2475배)과 같다. 두 포맷이 같은
    /// 행이다. 오차 예산: 커버리지 중심은 벡터 좌표와 0.01pt 안이고, 한글 PDF는 베이스라인과 선 중심을
    /// 저마다 장치 좌표(0.12pt)로 떨어뜨린다 — 쪽 좌표 핀은 0.12, 한글 간격 핀은 0.12, 모형 간격 핀은
    /// 0.03이다. 수정 전(0.64배)에는 모형 간격이 기본 크기의 0.0015배(50pt 0.075 … 160pt 0.24pt)씩 갈리고,
    /// 1–6번 첨자 선 11개의 쪽 좌표가 한글과 0.14–0.30pt 갈려 빨개진다 (2번 아래 첨자만 0.12 경계 안).
    func testLargeScriptStrikethroughsMatchHancomCoordinatesInBothFormats() async throws {
        var centers: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.scriptLarge, hwpx: hwpx)
            var lines: [CGFloat] = []
            for row in Self.scriptLargeRows {
                let label = "\(format) 문단 \(row.paragraph) (\(Int(row.size))pt)"
                let plain = try XCTUnwrap(
                    Self.scriptLargeCenter(raster, near: row.plain, color: .cyan),
                    "\(label): 보통 선을 못 찾았다"
                )
                let superscript = try XCTUnwrap(
                    Self.scriptLargeCenter(raster, near: row.superscript, color: .magenta),
                    "\(label): 위 첨자 선을 못 찾았다"
                )
                let `subscript` = try XCTUnwrap(
                    Self.scriptLargeCenter(raster, near: row.subscript, color: .green),
                    "\(label): 아래 첨자 선을 못 찾았다"
                )
                expect(plain).to(beCloseTo(row.plain, within: 0.12), description: "\(label) 보통")
                expect(superscript)
                    .to(beCloseTo(row.superscript, within: 0.12), description: "\(label) 위 첨자")
                expect(`subscript`)
                    .to(beCloseTo(row.subscript, within: 0.12), description: "\(label) 아래 첨자")
                expect(plain - superscript).to(
                    beCloseTo(row.plain - row.superscript, within: 0.12),
                    description: "\(label) 위 첨자 − 보통 간격 (한글)"
                )
                expect(`subscript` - plain).to(
                    beCloseTo(row.subscript - row.plain, within: 0.12),
                    description: "\(label) 아래 첨자 − 보통 간격 (한글)"
                )
                expect(plain - superscript).to(
                    beCloseTo(0.3125 * row.size, within: 0.03),
                    description: "\(label) 위 첨자 − 보통 간격 (모형)"
                )
                expect(`subscript` - plain).to(
                    beCloseTo(0.2475 * row.size, within: 0.03),
                    description: "\(label) 아래 첨자 − 보통 간격 (모형)"
                )
                lines += [plain, superscript, `subscript`]
            }
            centers.append(lines)
        }
        for index in centers[0].indices {
            expect(centers[0][index]).to(
                beCloseTo(centers[1][index], within: 0.01),
                description: "선 \(index): HWP와 HWPX가 같은 자리"
            )
        }
    }
}
