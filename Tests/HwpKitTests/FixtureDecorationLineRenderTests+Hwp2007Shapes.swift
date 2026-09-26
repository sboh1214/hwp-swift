import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `hwp2007-decorations` 쌍의 **선 모양** 실물 핀 (#227) — 한글 2007 호환 문서의 점선·원형
/// 점선·여러 줄·물결 밑줄·취소선이 글자 크기와 무관한 고정 pt로, 한글이 그린 자리에 그려진다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-26, 벡터 좌표, 쪽 위에서부터
/// pt). 이 문서는 줄 배치 캐시를 한글이 적어 두었으므로 쪽 좌표를 그대로 핀할 수 있다. 표본은
/// 자홍(#FF00FF)이라 #210의 네 색 핀(`+Hwp2007`)과 섞이지 않는다:
///
/// | 쪽 | 문단 | 모양 | 한글 쪽 좌표 (선 중심 y · 조각) |
/// |---|---|---|---|
/// | 1 | L10 10pt | 긴 점선 아래 밑줄 | 538.44 · 선 2.40 / 주기 3.84 |
/// | 1 | L40 40pt | 긴 점선 아래 밑줄 | 581.40 · 선 2.40 / 주기 3.84 (한글 문서라면 11.40 / 18.24) |
/// | 1 | H40 40pt | 점선 위 밑줄 | 593.04 · 선 0.48 / 주기 1.20 |
/// | 1 | O40 40pt | 원형 점선 아래 밑줄 | 685.68 · 지름 1.32 / 간격 3.0 |
/// | 1 | W40 40pt | 2중선 아래 밑줄 | 737.40 · 738.48 (0.36 둘) |
/// | 2 | K40 40pt | 3중선 아래 밑줄 | 139.56 · 141.36 · 143.16 (0.6·1.8·0.6) |
/// | 2 | E40 40pt | 가는+굵은 취소선 | 169.68 · 172.20 (0.96·2.28) |
/// | 2 | V40 40pt | 물결 아래 밑줄 | 꼭짓점 242.16 ~ 245.04 · 획 0.72 · 반주기 3.0 |
/// | 2 | X40 40pt | 2중 물결 취소선 | 꼭짓점 273.96 ~ 276.48 · 획 0.36 |
/// | 2 | M40 40pt | 일점쇄선 가운데 밑줄 | 327.24 · 4.80 / 1.44 / 0.48 / 1.44 |
///
/// 조각 시작 x는 본문 왼쪽 85.08pt다. 우리 PDF를 같은 방식으로 읽으면 열 표본 모두 한글과
/// 0.12pt 안이다 (수정 전에는 긴 점선 40pt가 선 11.4pt·주기 18.24pt, 2중선 간격 3.6pt).
/// 4px/pt 래스터라 조각 길이는 ±0.3pt로 잰다. 글꼴은 `HwpFontResolver.testDeterministic`.
extension FixtureDecorationLineRenderTests {
    private static let hwp2007Shapes = "hwp2007-decorations"
    /// 본문 왼쪽 끝 — 한글 PDF의 run 시작 x
    private static let shapeRunStart: CGFloat = 85.08

    private static func isMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    /// `y`(pt) ± `halfBand` 안에서 자홍 픽셀이 가장 많은 행의 가로 조각 (시작, 길이) 목록 (pt).
    private static func magentaRuns(
        _ raster: Raster, near y: CGFloat, halfBand: CGFloat = 0.6
    ) -> [(start: CGFloat, length: CGFloat)] {
        let rows = Int((y - halfBand) * scale) ... Int((y + halfBand) * scale)
        let counts = rows.map { raster.matches($0, isMagenta) }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return [] }
        let row = rows.lowerBound + best
        var runs: [(start: CGFloat, length: CGFloat)] = []
        var start: Int?
        for x in 0 ... raster.pixelWidth {
            let offset = row * raster.bytesPerRow + x * 4
            let ink = x < raster.pixelWidth
                && isMagenta(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
            if ink, start == nil {
                start = x
            } else if !ink, let first = start {
                runs.append((CGFloat(first) / scale, CGFloat(x - first) / scale))
                start = nil
            }
        }
        return runs
    }

    /// `range`(pt) 안의 자홍 행들을 이어진 띠로 묶은 (위, 아래) 목록 (pt, 픽셀 경계)
    private static func magentaBands(
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

    /// 한 쪽의 자홍 조각이 한글 패턴(`lengths`를 되풀이)대로 run 시작부터 이어지는지 — 앞 `count`개
    private func expectDashPattern(
        _ raster: Raster, center: CGFloat, lengths: [CGFloat], count: Int, label: String
    ) {
        let runs = Self.magentaRuns(raster, near: center)
        expect(runs.count).to(beGreaterThanOrEqualTo(count), description: "\(label) 조각 수")
        guard runs.count >= count else { return }
        var x = Self.shapeRunStart
        var pattern = 0
        for index in 0 ..< count {
            expect(runs[index].start)
                .to(beCloseTo(x, within: 0.3), description: "\(label) 조각 \(index) 시작")
            expect(runs[index].length).to(
                beCloseTo(lengths[pattern], within: 0.3), description: "\(label) 조각 \(index) 길이"
            )
            x += lengths[pattern] + lengths[pattern + 1]
            pattern = (pattern + 2) % lengths.count
        }
    }

    /// 대시 넷(긴 점선 10·40pt·점선 위 밑줄·일점쇄선 가운데 밑줄)이 한글과 같은 자리·같은 고정
    /// 길이로 조각난다. 긴 점선은 10pt와 40pt의 무늬가 같다 — 한글 문서라면 40pt가 4배다.
    func testHwp2007DashedShapesMatchHangulInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page1 = try await Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 0)
            let page2 = try await Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 1)
            for (label, center) in [("L10", CGFloat(538.44)), ("L40", 581.40)] {
                expect(page1.center(in: (center - 0.6) ... (center + 0.6), where: Self.isMagenta))
                    .to(beCloseTo(center, within: 0.35), description: "\(format) \(label) y")
                expectDashPattern(
                    page1, center: center, lengths: [2.40, 1.44], count: 8,
                    label: "\(format) \(label)"
                )
            }
            expect(page1.center(in: 592.4 ... 593.7, where: Self.isMagenta))
                .to(beCloseTo(593.04, within: 0.35), description: "\(format) H40 y")
            // 점선 0.48/0.72pt는 4px/pt에서 2px 남짓이라 주기만 잰다 (1.20pt)
            let dots = Self.magentaRuns(page1, near: 593.04)
            expect(dots.count).to(beGreaterThan(100), description: "\(format) H40 조각 수")
            if dots.count > 21 {
                expect(dots[20].start - dots[0].start)
                    .to(beCloseTo(24, within: 0.3), description: "\(format) H40 주기 × 20")
            }
            expect(page2.center(in: 326.6 ... 327.9, where: Self.isMagenta))
                .to(beCloseTo(327.24, within: 0.35), description: "\(format) M40 y")
            expectDashPattern(
                page2, center: 327.24, lengths: [4.80, 1.44, 0.48, 1.44], count: 8,
                label: "\(format) M40"
            )
        }
    }

    /// 여러 줄(2중선·3중선 밑줄, 가는+굵은 취소선)의 낱낱 선이 한글 자리·두께다 — 두께는 4px/pt
    /// 행 경계라 ±0.3pt, 중심은 ±0.35pt. 한글 문서였다면 40pt 2중선은 1.2pt 두 줄·간격 3.6pt다.
    func testHwp2007MultiLineShapesMatchHangulInBothFormats() async throws {
        struct Sample {
            let page: Int
            let label: String
            let range: ClosedRange<CGFloat>
            /// 위에서부터 (중심, 두께) pt
            let lines: [(CGFloat, CGFloat)]
        }
        let samples = [
            Sample(
                page: 0, label: "W40", range: 736.0 ... 740.0,
                lines: [(737.40, 0.36), (738.48, 0.36)]
            ),
            Sample(
                page: 1, label: "K40", range: 138.5 ... 144.5,
                lines: [(139.56, 0.6), (141.36, 1.8), (143.16, 0.6)]
            ),
            Sample(
                page: 1, label: "E40", range: 168.5 ... 174.0,
                lines: [(169.68, 0.96), (172.20, 2.28)]
            ),
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let pages = try await [
                Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 0),
                Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 1),
            ]
            for sample in samples {
                let label = sample.label
                let lines = sample.lines
                let bands = Self.magentaBands(pages[sample.page], in: sample.range)
                expect(bands.count).to(equal(lines.count), description: "\(format) \(label) 줄 수")
                guard bands.count == lines.count else { continue }
                for (band, (center, thickness)) in zip(bands, lines) {
                    expect((band.top + band.bottom) / 2)
                        .to(beCloseTo(center, within: 0.35), description: "\(format) \(label) 중심")
                    expect(band.bottom - band.top)
                        .to(beCloseTo(thickness, within: 0.3), description: "\(format) \(label) 두께")
                }
            }
        }
    }

    /// 원형 점선 밑줄(지름 1.32·간격 3.0), 물결 밑줄(꼭짓점 242.16~245.04·획 0.72·반주기 3.0),
    /// 2중 물결 취소선(꼭짓점 273.96~276.48·획 0.36)이 한글 자리다. 잉크 띠는 **꼭짓점 띠**로
    /// 잰다 — 꼭짓점 밖으로 나가는 획 반폭은 0.12pt 평탄 조각과 45° 획의 모서리뿐이라 4px/pt
    /// 래스터에서 픽셀 커버리지가 색 판정 임계(61%)에 못 미친다 (벡터로는 한글과 0.12pt 안이다).
    /// 한글 문서였다면 40pt 물결의 꼭짓점 띠가 2.88pt가 아니라 4.48pt다 (한글 HWP201X 대조군:
    /// 베이스라인 아래 4.20~8.76pt, 이 모드는 4.80~7.68pt).
    func testHwp2007CircleAndWaveShapesMatchHangulInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let page1 = try await Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 0)
            let page2 = try await Self.raster(Self.hwp2007Shapes, hwpx: hwpx, pageIndex: 1)
            let circles = Self.magentaRuns(page1, near: 685.68, halfBand: 0.4)
            expect(circles.count).to(beGreaterThan(40), description: "\(format) O40 원 수")
            if circles.count > 11 {
                expect(circles[0].start + circles[0].length / 2).to(
                    beCloseTo(Self.shapeRunStart, within: 0.3), description: "\(format) O40 첫 중심"
                )
                expect(circles[10].start - circles[0].start)
                    .to(beCloseTo(30, within: 0.3), description: "\(format) O40 간격 × 10")
                expect(circles[1].length)
                    .to(beCloseTo(1.32, within: 0.4), description: "\(format) O40 지름")
            }
            expect(page1.center(in: 684.5 ... 687.0, where: Self.isMagenta))
                .to(beCloseTo(685.68, within: 0.35), description: "\(format) O40 y")
            let wave = try XCTUnwrap(page2.band(in: 239.0 ... 248.0, where: Self.isMagenta))
            expect(wave.top).to(beCloseTo(242.16, within: 0.35), description: "\(format) V40 위")
            expect(wave.bottom).to(beCloseTo(245.04, within: 0.35), description: "\(format) V40 아래")
            // 꼭짓점 행(위 꼭짓점)에서 평탄 조각이 반주기 둘(6.0pt)마다 되풀이된다
            let peaks = Self.magentaRuns(page2, near: 242.16, halfBand: 0.2)
            if peaks.count > 6 {
                expect(peaks[6].start - peaks[1].start)
                    .to(beCloseTo(30, within: 0.5), description: "\(format) V40 주기 × 5")
            }
            let double = try XCTUnwrap(page2.band(in: 272.0 ... 278.5, where: Self.isMagenta))
            expect(double.top).to(beCloseTo(273.96, within: 0.35), description: "\(format) X40 위")
            expect(double.bottom)
                .to(beCloseTo(276.48, within: 0.35), description: "\(format) X40 아래")
        }
    }
}
