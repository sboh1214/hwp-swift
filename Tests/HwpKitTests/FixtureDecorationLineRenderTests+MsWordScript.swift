import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `ms-word-script-strikethrough` 쌍의 실물 핀 (#248) — MS 워드 호환 문서의 위·아래 첨자 취소선은
/// **첨자로 옮겨진 베이스라인** 위, 같은 글꼴·기본 크기 보통 글자 취소선 높이의 0.696배
/// (`HwpRenderTuning.Text.msWordScriptStrikethroughScale`)에 그려진다. 글자 가운데 밑줄·원형 점선
/// 취소선도 같은 자리이고, 상대 크기는 그 자리를 바꾸지 않으며(기본 크기 몫), 글자 위치로 옮겨진
/// 몫은 선이 따라가지 않는다. 두 포맷이 같은 자리에 그린다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-02, 벡터 좌표, 쪽 위에서부터 pt).
/// 이 문서는 한글이 줄 배치 캐시를 적어 두었으므로 쪽 좌표를 그대로 핀한다. 글꼴은 한글 슬롯 Apple SD
/// 산돌고딕 Neo·라틴 슬롯 Menlo라 결정론 resolver(`HwpFontResolver.testDeterministic`)가 같은 글꼴을
/// 고른다. 문단마다 보통(청록)·위 첨자(자홍)·아래 첨자(초록) run이 한 줄에 나란하다:
///
/// | 문단 | 표본 | 베이스라인 | 보통 | 위 첨자 | 아래 첨자 |
/// |---|---|---:|---:|---:|---:|
/// | 1 | Menlo 20pt | 133.44 | 128.28 | 121.08 | 132.24 |
/// | 2 | Apple SD 20pt | 181.92 | 176.88 | 169.56 | 180.84 |
/// | 3 | Menlo 40pt | 253.80 | 243.60 | 229.20 | 251.52 |
/// | 4 | Apple SD 40pt | 350.76 | 340.80 | 326.16 | 348.60 |
/// | 5 | Menlo 20pt 글자 가운데 밑줄 | 428.40 | 423.36 | 416.04 | 427.32 |
/// | 6 | Menlo 20pt 원형 점선 취소선 | 476.88 | 471.84 | 464.52 | 475.68 |
/// | 7 | Menlo 기본 40pt·상대 크기 50% | 547.44 | 537.24 | 522.72 | 545.16 |
/// | 8 | Menlo 20pt, 첨자 run만 글자 위치 30% | 622.20 | 617.16 | 609.84 | 621.12 |
///
/// 우리 렌더는 24선 모두 한글과 0.12pt 안이다 (PDF 내보내기 대조). 수정 전(첨자 배율 = 글리프 축소
/// 비율 0.64)에는 첨자 선이 20pt 표본에서 0.20~0.30pt, 40pt 표본(3·4·7번)에서 0.45~0.59pt 낮았다 —
/// 위 첨자 3번 229.65, 7번 523.24. 선 두께는 글자 모양 기본 크기의 장치 단위 획이라 첨자·상대 크기
/// run도 한글과 같은 0.84·1.56pt다 (#252 — 종전 0.04em은 0.80·1.60pt).
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다.
extension FixtureDecorationLineRenderTests {
    private static let msWordScript = "ms-word-script-strikethrough"

    /// 문단 하나의 한글 쪽 좌표 (pt, 쪽 위에서부터) — 베이스라인과 보통·위 첨자·아래 첨자 선 중심
    private struct MsWordScriptRow {
        let paragraph: Int
        let baseline: CGFloat
        let plain: CGFloat
        let superscript: CGFloat
        let `subscript`: CGFloat

        init(_ paragraph: Int, _ lines: [CGFloat]) {
            self.paragraph = paragraph
            baseline = lines[0]
            plain = lines[1]
            superscript = lines[2]
            `subscript` = lines[3]
        }
    }

    private static let msWordScriptRows = [
        MsWordScriptRow(1, [133.44, 128.28, 121.08, 132.24]),
        MsWordScriptRow(2, [181.92, 176.88, 169.56, 180.84]),
        MsWordScriptRow(3, [253.80, 243.60, 229.20, 251.52]),
        MsWordScriptRow(4, [350.76, 340.80, 326.16, 348.60]),
        MsWordScriptRow(5, [428.40, 423.36, 416.04, 427.32]),
        MsWordScriptRow(6, [476.88, 471.84, 464.52, 475.68]),
        MsWordScriptRow(7, [547.44, 537.24, 522.72, 545.16]),
        MsWordScriptRow(8, [622.20, 617.16, 609.84, 621.12]),
    ]

    /// 우리 렌더의 한 문단 세 선 중심 (pt, 쪽 위에서부터)
    private struct MsWordScriptLines {
        let plain: CGFloat
        let superscript: CGFloat
        let `subscript`: CGFloat
    }

    /// 선 색 — 흰 바탕에 칠한 순색 선의 **커버리지**(0…1에 비례)를 픽셀에서 되읽는다. 청록은 R,
    /// 자홍은 G, 초록은 R·B가 빠진 몫이라 가장자리 행의 부분 커버리지가 그대로 비례해 나오고(색 공간
    /// 변환으로 선 색 채널이 0이 아니어도 비례 상수만 바뀐다), 무채색인 글리프 잉크·안티앨리어싱은 0이다.
    private enum MsWordScriptColor {
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
    private static let msWordScriptPageHeight: CGFloat = 841.86

    /// `near`(pt) ± 2pt 행에서 잰 선 중심 — 행마다 선 색 커버리지를 더한 가중 중심이다. 선은
    /// 글리프 위에 칠해지고(`HwpPageLayerDecorations`가 글리프 다음에 그린다) 커버리지는 무채색
    /// 바탕과 섞여도 비례하므로 글리프 열을 가를 필요가 없다. 행은 **실제 세로 배율**로 pt에
    /// 옮긴다 — `raster(_:hwpx:)`는 쪽을 `Int(쪽 높이 × 4)`행에 맞춰 그리므로 배율이 4가 아니라
    /// 3367/841.86 = 3.99948이고, 4로 나누면 620pt 근처에서 0.08pt 위로 치우친다. 문턱을 넘는 행을
    /// 세는 `Raster.center`는 그 치우침에 경계 행의 계단(±0.125pt)이 더해져 선마다 −0.18pt까지
    /// 갈려(8번 아래 첨자: PDF 621.05 / 래스터 620.88) 한글과의 0.1pt대 차를 가를 수 없었다.
    private static func coverageCenter(
        _ raster: Raster, near center: CGFloat, color: MsWordScriptColor
    ) -> CGFloat? {
        let pixelsPerPoint = CGFloat(raster.pixelHeight) / msWordScriptPageHeight
        let top = max(0, Int(((center - 2) * pixelsPerPoint).rounded(.down)))
        let bottom = min(
            raster.pixelHeight - 1, Int(((center + 2) * pixelsPerPoint).rounded(.up))
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

    /// 문단의 세 선 중심 (보통·위 첨자·아래 첨자) — 한글 선 자리 ± 2pt에서 색으로 찾는다 (같은 색 선은
    /// 다른 문단에만 있어 40pt 넘게 떨어져 있고, 수정 전 자리도 0.6pt 안이라 창 안이다).
    private static func msWordScriptLines(
        _ raster: Raster, row: MsWordScriptRow, label: String
    ) throws -> MsWordScriptLines {
        try MsWordScriptLines(
            plain: XCTUnwrap(
                coverageCenter(raster, near: row.plain, color: .cyan),
                "\(label): 보통 선을 못 찾았다"
            ),
            superscript: XCTUnwrap(
                coverageCenter(raster, near: row.superscript, color: .magenta),
                "\(label): 위 첨자 선을 못 찾았다"
            ),
            subscript: XCTUnwrap(
                coverageCenter(raster, near: row.subscript, color: .green),
                "\(label): 아래 첨자 선을 못 찾았다"
            )
        )
    }

    /// 24선이 한글 쪽 좌표에 있고, 첨자 선과 같은 줄 보통 선의 간격도 한글과 같다. 두 포맷이 같은
    /// 행이다. 오차 예산: 커버리지 중심은 우리 PDF 내보내기의 벡터 좌표와 0.01pt 안이고, 한글 PDF는
    /// 선 중심을 장치 좌표(0.12pt)로 반올림한다 — 실측 최대 차는 쪽 좌표 0.12pt(줄 자리 차 포함)·
    /// 간격 0.12pt라 쪽 좌표 핀은 0.2, 간격 핀은 0.18이다. 수정 전(0.64배)에는 간격이 16개 모두
    /// 0.21~0.58pt, 첨자 선의 쪽 좌표가 20pt 표본에서 0.13~0.30pt·40pt 표본(3·4·7번)에서 0.41~0.59pt
    /// 갈려 빨개진다.
    func testMsWordScriptStrikethroughsMatchHancomCoordinatesInBothFormats() async throws {
        var centers: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.msWordScript, hwpx: hwpx)
            var rows: [CGFloat] = []
            for row in Self.msWordScriptRows {
                let label = "\(format) 문단 \(row.paragraph)"
                let lines = try Self.msWordScriptLines(raster, row: row, label: label)
                let plain = lines.plain
                let superscript = lines.superscript
                let `subscript` = lines.subscript
                expect(plain).to(beCloseTo(row.plain, within: 0.2), description: "\(label) 보통")
                expect(superscript)
                    .to(beCloseTo(row.superscript, within: 0.2), description: "\(label) 위 첨자")
                expect(`subscript`)
                    .to(beCloseTo(row.subscript, within: 0.2), description: "\(label) 아래 첨자")
                expect(plain - superscript).to(
                    beCloseTo(row.plain - row.superscript, within: 0.18),
                    description: "\(label) 위 첨자 − 보통 간격"
                )
                expect(`subscript` - plain).to(
                    beCloseTo(row.subscript - row.plain, within: 0.18),
                    description: "\(label) 아래 첨자 − 보통 간격"
                )
                rows += [plain, superscript, `subscript`]
            }
            centers.append(rows)
        }
        for index in centers[0].indices {
            expect(centers[0][index]).to(
                beCloseTo(centers[1][index], within: 0.01),
                description: "선 \(index): HWP와 HWPX가 같은 자리"
            )
        }
    }

    /// 상대 크기·글자 위치는 첨자 선 자리를 바꾸지 않는다 — 기본 40pt·상대 크기 50%(7번)의 첨자 선은
    /// 기본 40pt(3번)와, 첨자 run만 글자 위치 30%(8번)의 첨자 선은 위치 없는 20pt(1번)와 베이스라인에서
    /// 같은 거리다 (한글: 24.72·24.60, 2.28·2.28 / 12.36·12.36, 1.08·1.20 — 장치 좌표 양자화 안). 우리
    /// 렌더도 같아야 한다 — 상대 크기를 곱하면 7번이 0.5배 자리로, 글자 위치를 따르면 8번이 6pt
    /// 아래로 간다.
    func testMsWordScriptStrikethroughIgnoresRelativeSizeAndFaceLocation() async throws {
        let raster = try await Self.raster(Self.msWordScript, hwpx: false)
        func offsets(_ paragraph: Int) throws -> (superscript: CGFloat, subscript: CGFloat) {
            let row = try XCTUnwrap(Self.msWordScriptRows.first { $0.paragraph == paragraph })
            let lines = try Self.msWordScriptLines(raster, row: row, label: "문단 \(paragraph)")
            return (row.baseline - lines.superscript, row.baseline - lines.subscript)
        }
        let large = try offsets(3)
        let relative = try offsets(7)
        expect(relative.superscript).to(beCloseTo(large.superscript, within: 0.2))
        expect(relative.subscript).to(beCloseTo(large.subscript, within: 0.2))
        let plain = try offsets(1)
        let located = try offsets(8)
        expect(located.superscript).to(beCloseTo(plain.superscript, within: 0.2))
        expect(located.subscript).to(beCloseTo(plain.subscript, within: 0.2))
    }
}
