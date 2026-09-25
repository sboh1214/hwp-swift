import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `mixed-size-decorations` 쌍의 실물 핀 (#226) — 한글 문서에서 한글은 **밑줄을 줄 단위로**
/// 놓는다: 위 가장자리가 줄 상자(한글 줄 캐시의 `vertsize`) 바닥, 글자 위 밑줄의 아래
/// 가장자리가 줄 상자 상단이고, 두께·선 모양 축척은 줄 **글자**의 기본 크기 최댓값이다. 장식선
/// 크기는 슬롯 상대 크기 전 **글자 모양 기본 크기**다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-25, 벡터 좌표, 쪽 위에서부터
/// pt). 이 문서는 줄 배치 캐시를 한글이 적어 두었으므로 베이스라인이 한글과 같고, 밑줄 자리는
/// 줄 상자 높이(글꼴과 무관)의 함수라 쪽 좌표를 그대로 핀할 수 있다:
///
/// | 문단 | 같은 줄 | 선 | 한글 쪽 좌표 | 베이스라인 기준 | 두께 |
/// |---|---|---|---:|---:|---:|
/// | M1 | 40pt 무장식 글자 | 밑줄 (초록) | 1쪽 156.00 | −6.72 | 1.56 |
/// | M2 | 40pt 문단 끝 글자 | 위 밑줄 (파랑) | 1쪽 179.04 | +34.20 | 0.36 |
/// | M3 | 높이 40pt 글자처럼 취급 표 | 밑줄 | 1쪽 283.44 | −6.24 | 0.36 |
/// | M4 | 40pt 글자 모양 책갈피 | 밑줄 | 1쪽 329.40 | −6.12 | 0.36 |
/// | M5 | 20pt 글자 + 40pt 문단 끝 글자 | 밑줄 | 1쪽 393.60 | −6.36 | 0.84 |
/// | M6 | 40pt 한 줄 끝 / (다음 줄) | 밑줄 | 1쪽 457.44 / 491.40 | −6.24 / −1.68 | 0.36 |
/// | M7 | 기본 40pt·상대 크기 50% | 밑줄 | 1쪽 538.08 | −6.84 | 1.56 |
/// | M8 | 기본 40pt·상대 크기 50% | 취소선 (빨강) | 1쪽 581.28 | +13.92 | 1.56 |
/// | M9 | 40pt 무장식 글자 | 긴 점선 밑줄 | 1쪽 666.00 | −6.72 | 1.56 |
/// | M10 | (10pt만) / 40pt 무장식 글자 | 밑줄 | 1쪽 699.48 / 746.04 | −1.68 / −6.84 | 0.36 / 1.56 |
/// | M11 | 기본 20pt·상대 크기 50% 위 첨자 | 취소선 | 2쪽 102.96 | +13.32 | 0.84 |
/// | M12 | 높이 40pt 글자처럼 취급 표 | 위 밑줄 | 2쪽 131.04 | +34.20 | 0.36 |
///
/// 종전 렌더(run 단위·run 글꼴 크기)는 같은 선을 최대 25.5pt 어긋나게 그렸다 — 위 밑줄이 10pt
/// 자리(+8.70), 개체 줄 밑줄이 상자 바닥 몫을 두 번 센 −7.70, 상대 크기 50% run이 20pt 자리.
///
/// `extension`에 두는 이유는 `+Hwp2007`와 같다 (`type_body_length`). 글꼴은
/// `HwpFontResolver.testDeterministic`이라 기기 독립이다.
extension FixtureDecorationLineRenderTests {
    private static let mixedSize = "mixed-size-decorations"

    private static func isBlue(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green < 100 && blue > 150
    }

    /// 한 쪽의 한 색 선들 — 한글 PDF의 쪽 좌표 (위에서부터 pt).
    private struct MixedSizeLines {
        let page: Int
        let name: String
        let expected: [CGFloat]
    }

    /// 쪽·색별 기대값.
    private static let mixedSizeCenters = [
        MixedSizeLines(
            page: 0, name: "밑줄",
            expected: [
                156.00, 283.44, 329.40, 393.60, 457.44, 491.40, 538.08, 666.00, 699.48, 746.04,
            ]
        ),
        MixedSizeLines(page: 0, name: "위 밑줄", expected: [179.04]),
        MixedSizeLines(page: 0, name: "취소선", expected: [581.28]),
        MixedSizeLines(page: 1, name: "취소선", expected: [102.96]),
        MixedSizeLines(page: 1, name: "위 밑줄", expected: [131.04]),
    ]

    private static func mixedSizeMatcher(_ name: String) -> (UInt8, UInt8, UInt8) -> Bool {
        switch name {
        case "위 밑줄":
            isBlue
        case "취소선":
            isRed
        default:
            isGreen
        }
    }

    /// 가로로 8pt 넘게 이어진 색 행들을 위에서부터 선 단위로 묶은 중심 (pt). 긴 점선 한 토막
    /// (11.4pt)도 넘는다.
    private static func mixedSizeLineCenters(
        _ raster: Raster, where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> [CGFloat] {
        let rows = (0 ..< raster.pixelHeight)
            .filter { raster.longestRun($0, where: match) > Int(8 * scale) }
            .map { (CGFloat($0) + 0.5) / scale }
        var groups: [[CGFloat]] = []
        for row in rows {
            if let last = groups.last?.last, row - last < 0.5 / scale + 0.3 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups.map { $0.reduce(0, +) / CGFloat($0.count) }
    }

    /// 열네 장식선이 한글 PDF와 같은 쪽 좌표에 그려지고 두 포맷이 같다.
    func testMixedSizeDecorationLinesMatchHangulPageCoordinatesInBothFormats() async throws {
        var perFormat: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            var rasters: [Int: Raster] = [:]
            var all: [CGFloat] = []
            for lines in Self.mixedSizeCenters {
                let (page, name, expected) = (lines.page, lines.name, lines.expected)
                if rasters[page] == nil {
                    rasters[page] = try await Self.raster(
                        Self.mixedSize, hwpx: hwpx, pageIndex: page
                    )
                }
                let raster = try XCTUnwrap(rasters[page])
                let centers = Self.mixedSizeLineCenters(raster, where: Self.mixedSizeMatcher(name))
                let label = "\(format) \(page + 1)쪽 \(name)"
                expect(centers.count).to(equal(expected.count), description: "\(label) 줄 수")
                guard centers.count == expected.count else { continue }
                for (line, value) in centers.enumerated() {
                    expect(value).to(
                        beCloseTo(expected[line], within: 0.35), description: "\(label) \(line)"
                    )
                }
                all += centers
            }
            perFormat.append(all)
        }
        expect(perFormat[0].count) == perFormat[1].count
        for (index, value) in perFormat[0].enumerated() where index < perFormat[1].count {
            expect(value).to(
                beCloseTo(perFormat[1][index], within: 0.01),
                description: "HWP와 HWPX가 같은 자리 \(index)"
            )
        }
    }

    /// 밑줄 두께는 줄 **글자**의 가장 큰 기본 크기 몫이다 — M1(40pt 무장식 글자 줄)은 1.6pt,
    /// M5(20pt 무장식 글자 + 40pt 문단 끝 글자 줄)는 0.8pt, M4(40pt 책갈피 줄)는 10pt 몫 0.4pt
    /// (한글 1.56·0.84·0.36). 종전 렌더는 셋 다 10pt run 몫 0.4pt였다. 완전 커버 채널값은 두꺼운
    /// M1 선에서 재어 얇은 선에 넘긴다 (`FixtureDecorationLineRenderTests+Thickness`).
    func testMixedSizeUnderlineThicknessFollowsTheLineText() async throws {
        let raster = try await Self.raster(Self.mixedSize, hwpx: false)
        let centers = Self.mixedSizeLineCenters(raster, where: Self.isGreen)
        expect(centers.count) == 10
        guard centers.count == 10 else { return }
        func thickness(_ index: Int, full: UInt8?) throws -> CGFloat {
            let span = try XCTUnwrap(
                raster.longestSpan(Int(centers[index] * Self.scale), where: Self.isGreen),
                "밑줄 \(index) 열"
            )
            return try XCTUnwrap(
                raster.lineThickness(
                    center: centers[index], halfBand: 1.1,
                    columns: (span.lowerBound + 2) ..< (span.upperBound - 2),
                    channel: { red, _, _ in red }, fullChannel: full
                ),
                "밑줄 \(index) 두께"
            )
        }
        let span = try XCTUnwrap(
            raster.longestSpan(Int(centers[0] * Self.scale), where: Self.isGreen)
        )
        let full = raster.fullCoverageChannel(
            center: centers[0], halfBand: 1.1,
            columns: (span.lowerBound + 2) ..< (span.upperBound - 2),
            channel: { red, _, _ in red }
        )
        let wide = try thickness(0, full: full)
        let mixed = try thickness(3, full: full)
        let bookmark = try thickness(2, full: full)
        expect(wide).to(beCloseTo(1.6, within: 0.15), description: "M1")
        expect(mixed).to(beCloseTo(0.8, within: 0.15), description: "M5")
        expect(bookmark).to(beCloseTo(0.4, within: 0.15), description: "M4")
    }

    /// 긴 점선의 한 토막도 줄 글자 기준 크기 몫이다 — 40pt 무장식 글자와 한 줄인 M9의 10pt 긴
    /// 점선은 선 5 × 0.057 × 40 = 11.4pt · 공백 6.84pt (한글 11.40·6.96), 10pt 몫이면 2.85·1.71pt.
    func testMixedSizeDottedUnderlineUsesTheLineTextScale() async throws {
        let raster = try await Self.raster(Self.mixedSize, hwpx: false)
        let centers = Self.mixedSizeLineCenters(raster, where: Self.isGreen)
        expect(centers.count) == 10
        guard centers.count == 10 else { return }
        let row = Int(centers[7] * Self.scale)
        var segments: [Range<Int>] = []
        var start: Int?
        for x in 0 ... raster.pixelWidth {
            var hit = false
            if x < raster.pixelWidth {
                let offset = row * raster.bytesPerRow + x * 4
                hit = Self.isGreen(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }
            if hit, start == nil {
                start = x
            } else if !hit, let begin = start {
                segments.append(begin ..< x)
                start = nil
            }
        }
        expect(segments.count) >= 3
        guard segments.count >= 3 else { return }
        let dash = CGFloat(segments[0].count) / Self.scale
        let gap = CGFloat(segments[1].lowerBound - segments[0].upperBound) / Self.scale
        expect(dash).to(beCloseTo(0.057 * 40 * 5, within: 0.5))
        expect(gap).to(beCloseTo(0.057 * 40 * 3, within: 0.5))
    }
}
