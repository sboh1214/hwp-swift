import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `ms-word-line-shapes` 쌍의 **선 모양** 실물 핀 (#244) — MS 워드 호환 문서의 원형 점선·긴 점선·
/// 2중선·물결·가는+굵은 선 밑줄이 글자 크기가 아니라 **줄 글자 상자의 높이**로 잰 무늬로, 여러 줄
/// 띠·물결은 **단선 중심에 가운데** 맞춰 그려지고, 취소선 무늬는 **글자 모양 기본 크기**로 그려진다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-30, 벡터 좌표, 쪽 위에서부터 pt).
/// 이 문서는 한글이 줄 배치 캐시를 적어 두었으므로 쪽 좌표를 그대로 핀한다. 글꼴은 한글 슬롯 Apple SD
/// 산돌고딕 Neo·라틴 슬롯 Menlo라 결정론 resolver(`HwpFontResolver.testDeterministic`)가 같은 글꼴을
/// 고른다. 선 색은 모두 자홍 `#FF00FF`이고 run은 본문 왼쪽 85.08pt에서 시작한다:
///
/// | 문단 | 표본 | 한글 쪽 좌표 (중심 y · 무늬) |
/// |---|---|---|
/// | 1 | Menlo 20pt 원형 점선 밑줄 | 136.44 · 간격 4.20 · 칠 지름 1.80 (한글 문서라면 3.00·1.32) |
/// | 2 | Apple SD 40pt 원형 점선 밑줄 | 204.72 · 9.00 · 3.72 |
/// | 3 | Menlo 40pt 무장식 `A` + 10pt 원형 점선 밑줄 | 284.16 · 8.76 · 3.72 (첫 원 109.20) |
/// | 4 | Menlo 10pt 원형 점선 밑줄 + 40pt 문단 끝 글자 | 371.52 · 2.16 · 1.08 |
/// | 5 | Menlo 20pt 긴 점선 밑줄 | 418.44 · 선 8.64 / 주기 13.92 |
/// | 6 | Menlo 20pt 2중선 밑줄 | 456.48 · 459.00 (0.84 둘) |
/// | 7 | Menlo 20pt 물결 밑줄 | 꼭짓점 494.16 ~ 497.52 |
/// | 8 | Menlo 20pt 가는+굵은 선 위 밑줄 | 510.00 · 513.72 (1.44·3.12) |
/// | 9 | Menlo 기본 20pt·상대 크기 50% 원형 점선 취소선 | 565.68 · 3.00 · 1.32 |
/// | 10 | 기본 20pt·한글 슬롯 50% 긴 점선 밑줄 | 616.08 · 8.88 / 14.16 (슬롯 경계에서 이어진다) |
/// | 11 | 같은 글자 모양의 긴 점선 취소선 | 645.72 · 5.64 / 9.00 |
///
/// 원은 한글처럼 장치 단위로 반올림하므로 우리 PDF와 간격·지름이 같고, 대시는 한글이 단위를 장치
/// 단위로 반올림해(#245 계열 — 한글 문서에도 있는 기존 격차) 주기마다 0.1pt쯤 갈리므로 쪽 좌표를 누적해
/// 대지 않고 이웃 조각 사이의 주기로 잰다. 수정 전에는 1번 원 간격이 3.00pt(글자 크기 몫), 3·4번이
/// 1.56pt(10pt 몫), 2중선 두 줄이 단선 위 가장자리 아래로 몰렸고, 9번 취소선은 1.56pt(상대 크기 10pt
/// 몫), 10번은 슬롯 경계에서 무늬가 다시 시작했다. 10·11번은 x 자리를 핀하지 않는다 — 한글은 이 글자
/// 모양의 빈칸을 5.04pt로, 우리는 라틴 슬롯 Menlo 20pt의 12.04pt로 조판해 슬롯 경계와 run 끝이
/// 약 20pt 갈린다 (선 모양과 무관한 기존 조판 격차 — 픽스처 README의 남은 격차).
extension FixtureDecorationLineRenderTests {
    private static let msWordShapes = "ms-word-line-shapes"
    /// 본문 왼쪽 끝 — 한글 PDF의 run 시작 x
    private static let msWordRunStart: CGFloat = 85.08

    /// `y`(pt) ± `halfBand` 안에서 자홍 픽셀이 가장 많은 행의 가로 조각 (시작, 길이) 목록 (pt)
    private static func msWordMagentaRuns(
        _ raster: Raster, near y: CGFloat, halfBand: CGFloat = 0.4
    ) -> [(start: CGFloat, length: CGFloat)] {
        rowRuns(
            raster, near: y, halfBand: halfBand,
            x: 0 ... CGFloat(raster.pixelWidth - 1) / scale, where: isMagenta
        ).map { ($0.start, $0.end - $0.start) }
    }

    /// `range`(pt) 안의 자홍 행들을 이어진 띠로 묶은 (위, 아래) 목록 (pt, 픽셀 경계)
    private static func msWordMagentaBands(
        _ raster: Raster, in range: ClosedRange<CGFloat>
    ) -> [(top: CGFloat, bottom: CGFloat)] {
        var bands: [(top: CGFloat, bottom: CGFloat)] = []
        var previous = false
        for y in Int(range.lowerBound * scale) ... Int(range.upperBound * scale) {
            let ink = raster.matches(y, isMagenta) > 3
            if ink {
                let top = CGFloat(y) / scale
                let bottom = CGFloat(y + 1) / scale
                if previous, let last = bands.popLast() {
                    bands.append((last.top, bottom))
                } else {
                    bands.append((top, bottom))
                }
            }
            previous = ink
        }
        return bands
    }

    /// 긴 점선 한 줄 — 한글 쪽 좌표(중심 y)와 선·주기 (pt)
    private struct DashSample {
        let label: String
        let y: CGFloat
        let dash: CGFloat
        let period: CGFloat
    }

    /// 여러 줄 한 표본 — 찾을 구간과 위에서부터 (중심, 두께) pt
    private struct StripeSample {
        let label: String
        let range: ClosedRange<CGFloat>
        let lines: [(center: CGFloat, thickness: CGFloat)]
    }

    /// 원형 점선 한 줄 — 한글 쪽 좌표(중심 y·첫 원 중심 x)와 간격·칠 지름
    private struct CircleSample {
        let label: String
        let y: CGFloat
        let firstCenter: CGFloat
        let pitch: CGFloat
        let diameter: CGFloat
    }

    /// 원형 점선 다섯 표본(밑줄 넷 + 상대 크기 취소선)의 원이 한글과 같은 간격·지름·자리다. 간격은
    /// 원 10개 거리로, 지름은 둘째 원의 잉크 폭으로 잰다 (4px/pt라 ±0.4).
    func testMsWordCircleLinesMatchHangulInBothFormats() async throws {
        let samples = [
            CircleSample(
                label: "1 Menlo 20pt", y: 136.44, firstCenter: 85.08, pitch: 4.20, diameter: 1.80
            ),
            CircleSample(
                label: "2 Apple SD 40pt", y: 204.72, firstCenter: 85.08, pitch: 9.00, diameter: 3.72
            ),
            CircleSample(
                label: "3 40pt 무장식 + 10pt", y: 284.16, firstCenter: 109.20, pitch: 8.76,
                diameter: 3.72
            ),
            CircleSample(
                label: "4 10pt + 40pt 끝 글자", y: 371.52, firstCenter: 85.08, pitch: 2.16,
                diameter: 1.08
            ),
            CircleSample(
                label: "9 상대 크기 취소선", y: 565.68, firstCenter: 85.08, pitch: 3.00, diameter: 1.32
            ),
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page = try await Self.raster(Self.msWordShapes, hwpx: hwpx)
            for sample in samples {
                let label = "\(format) \(sample.label)"
                let band = (sample.y - 0.8) ... (sample.y + 0.8)
                expect(page.center(in: band, where: Self.isMagenta))
                    .to(beCloseTo(sample.y, within: 0.35), description: "\(label) y")
                let circles = Self.msWordMagentaRuns(page, near: sample.y)
                expect(circles.count).to(beGreaterThan(10), description: "\(label) 원 수")
                guard circles.count > 10 else { continue }
                expect(circles[0].start + circles[0].length / 2)
                    .to(beCloseTo(sample.firstCenter, within: 0.3), description: "\(label) 첫 중심")
                expect(circles[10].start - circles[0].start)
                    .to(beCloseTo(sample.pitch * 10, within: 0.3), description: "\(label) 간격 × 10")
                expect(circles[1].length)
                    .to(beCloseTo(sample.diameter, within: 0.4), description: "\(label) 지름")
            }
        }
    }

    /// 긴 점선 세 표본 — 무늬 단위가 밑줄은 줄 글자 상자(Menlo 20pt 30.27pt → 선 8.64·주기 13.92;
    /// 한글 슬롯 50% 한 글자 모양은 두 슬롯 상자의 합 Apple SD 31.19pt → 8.88·14.16), 취소선은 기본
    /// 크기 20pt(5.64·9.00)다. 이웃 조각의 주기가 run 끝까지 한결같아야 한다 — 슬롯 경계에서 무늬가
    /// 다시 시작하면 그 자리의 주기가 짧거나 길다.
    func testMsWordDashedLinesMatchHangulInBothFormats() async throws {
        let samples = [
            DashSample(label: "5 Menlo 20pt 밑줄", y: 418.44, dash: 8.64, period: 13.92),
            DashSample(label: "10 슬롯 50% 밑줄", y: 616.08, dash: 8.88, period: 14.16),
            DashSample(label: "11 슬롯 50% 취소선", y: 645.72, dash: 5.64, period: 9.00),
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page = try await Self.raster(Self.msWordShapes, hwpx: hwpx)
            for sample in samples {
                let label = "\(format) \(sample.label)"
                let band = (sample.y - 0.8) ... (sample.y + 0.8)
                expect(page.center(in: band, where: Self.isMagenta))
                    .to(beCloseTo(sample.y, within: 0.35), description: "\(label) y")
                let dashes = Self.msWordMagentaRuns(page, near: sample.y)
                expect(dashes.count).to(beGreaterThan(12), description: "\(label) 조각 수")
                guard dashes.count > 12 else { continue }
                expect(dashes[0].start)
                    .to(beCloseTo(Self.msWordRunStart, within: 0.3), description: "\(label) 시작")
                // run 끝에서 잘린 마지막 조각은 빼고 잰다
                for index in 0 ..< dashes.count - 2 {
                    expect(dashes[index].length).to(
                        beCloseTo(sample.dash, within: 0.3), description: "\(label) 선 \(index)"
                    )
                    expect(dashes[index + 1].start - dashes[index].start).to(
                        beCloseTo(sample.period, within: 0.3), description: "\(label) 주기 \(index)"
                    )
                }
            }
        }
    }

    /// 2중선 밑줄·가는+굵은 선 위 밑줄의 낱낱 선과 물결 밑줄의 꼭짓점 띠가 한글 자리다 — 여러 줄
    /// 띠는 밑줄 단선의 중심에 가운데 놓인다 (2중선 456.48·459.00의 가운데 457.74가 실선 밑줄 중심).
    /// 한글 문서 규칙(아래 밑줄은 단선 위 가장자리에서 아래로, 위 밑줄은 아래 가장자리에서 위로)이면
    /// 2중선이 1.2pt 아래·가는+굵은 선이 2.4pt 위로 간다. 물결은 꼭짓점 띠로 잰다 — 꼭짓점 밖 획
    /// 반폭은 4px/pt에서 색 판정 임계에 못 미친다 (`+Hwp2007Shapes`와 같은 이유).
    func testMsWordMultiLineAndWaveUnderlinesCenterLikeHangulInBothFormats() async throws {
        let multiLines = [
            StripeSample(
                label: "6 2중선 밑줄", range: 454.5 ... 461.0, lines: [(456.48, 0.84), (459.00, 0.84)]
            ),
            StripeSample(
                label: "8 가는+굵은 위 밑줄", range: 507.5 ... 517.0,
                lines: [(510.00, 1.44), (513.72, 3.12)]
            ),
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page = try await Self.raster(Self.msWordShapes, hwpx: hwpx)
            for sample in multiLines {
                let label = "\(format) \(sample.label)"
                let bands = Self.msWordMagentaBands(page, in: sample.range)
                expect(bands.count).to(equal(sample.lines.count), description: "\(label) 줄 수")
                guard bands.count == sample.lines.count else { continue }
                for (band, line) in zip(bands, sample.lines) {
                    let (center, thickness) = (line.center, line.thickness)
                    expect((band.top + band.bottom) / 2)
                        .to(beCloseTo(center, within: 0.35), description: "\(label) 중심")
                    expect(band.bottom - band.top)
                        .to(beCloseTo(thickness, within: 0.3), description: "\(label) 두께")
                }
            }
            let wave = try XCTUnwrap(page.band(in: 492.5 ... 499.5, where: Self.isMagenta))
            expect(wave.top).to(beCloseTo(494.16, within: 0.35), description: "\(format) 7 물결 위")
            expect(wave.bottom)
                .to(beCloseTo(497.52, within: 0.35), description: "\(format) 7 물결 아래")
        }
    }
}
