import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `hwp2007-decorations` 쌍의 실물 핀 (#210) — 한글 2007 호환 문서(대상 프로그램 1,
/// `HWP200X`)의 장식선은 두께가 글자 크기와 무관한 **고정 0.36pt**이고, 밑줄은 한글
/// 문서와 **같은 가장자리**(글자 아래 0.15em·글자 위 0.85em)에 그 얇은 선을 얹는다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-22, 벡터 좌표, 쪽
/// 위에서부터 pt). 이 문서는 줄 배치 캐시를 한글이 적어 두었으므로 베이스라인이 한글과
/// 같고, `compat-decorations`(#187·#194)와 달리 **쪽 좌표를 그대로 핀**할 수 있다:
///
/// | 문단 | 크기 | 선 | 한글 쪽 좌표 | 베이스라인 기준 |
/// |---|---|---|---:|---:|
/// | U10 | 10pt | 아래 밑줄 (초록) | 122.40 | −1.68 |
/// | U20 | 20pt | 아래 밑줄 | 145.44 | −3.24 |
/// | U40 | 40pt | 아래 밑줄 | 191.40 | −6.12 |
/// | U60 | 60pt | 아래 밑줄 | 263.40 | −9.12 |
/// | T40 | 40pt | 위 밑줄 (파랑) | 281.04 | +34.20 |
/// | T60 | 60pt | 위 밑줄 | 333.12 | +51.18 |
/// | S10 | 10pt | 취소선 (청록) | 416.28 | +3.48 |
/// | S40 | 40pt | 취소선 | 444.24 | +14.04 |
/// | C40 | 40pt | 가운데 밑줄 (주황) | 496.20 | +14.04 |
///
/// 한글 문서 기하로 그리면 같은 문단의 밑줄이 0.18~1.2pt 아래, 위 밑줄이 그만큼 위,
/// 두께가 0.4~2.4pt가 된다. 두께는 4px/pt에서 0.36pt = 1.44px라 행 수로는 못 가르므로
/// 커버리지 합(`Raster.lineThickness`)의 **크기 사이 일치**로 잡는다 — 같은 두께는 같은
/// 안티앨리어싱 편향을 받으므로 10pt 줄과 60pt 줄의 값이 같다는 것이 고정 두께의 증거다
/// (한글 문서 기하라면 0.4pt와 2.4pt로 갈린다).
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다. 글꼴은 `HwpFontResolver.testDeterministic`
/// 이라 기기 독립이다.
extension FixtureDecorationLineRenderTests {
    private static let hwp2007 = "hwp2007-decorations"

    private static func isBlueLine(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green < 100 && blue > 150
    }

    private static func isOrange(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green > 80 && green < 200 && blue < 100
    }

    /// 가로로 8pt 넘게 이어진 색 행들을 위에서부터 선 단위로 묶은 중심 (pt).
    private static func lineCenters(
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

    /// 선이 지나는 열 구간 (양 끝 2px 제외).
    private static func lineColumns(
        _ raster: Raster, center: CGFloat, where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> Range<Int>? {
        guard let span = raster.longestSpan(Int(center * scale), where: match),
              span.count > 8
        else { return nil }
        return (span.lowerBound + 2) ..< (span.upperBound - 2)
    }

    /// 한글 PDF의 쪽 좌표 (위에서부터 pt) — 색과 크기별 기대값.
    private static let hancomCenters: [(name: String, expected: [CGFloat])] = [
        ("아래 밑줄", [122.40, 145.44, 191.40, 263.40]),
        ("위 밑줄", [281.04, 333.12]),
        ("취소선", [416.28, 444.24]),
        ("가운데 밑줄", [496.20]),
    ]

    /// 아홉 장식선이 한글 PDF와 같은 쪽 좌표에 그려지고 두 포맷이 같다.
    func testHwp2007DecorationLinesMatchHangulPageCoordinatesInBothFormats() async throws {
        var perFormat: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.hwp2007, hwpx: hwpx)
            let matchers: [(UInt8, UInt8, UInt8) -> Bool] = [
                Self.isGreen, Self.isBlueLine, Self.isCyan, Self.isOrange,
            ]
            var all: [CGFloat] = []
            for (index, matcher) in matchers.enumerated() {
                let (name, expected) = Self.hancomCenters[index]
                let centers = Self.lineCenters(raster, where: matcher)
                expect(centers.count).to(
                    equal(expected.count), description: "\(format) \(name) 줄 수"
                )
                guard centers.count == expected.count else { continue }
                for (line, value) in centers.enumerated() {
                    expect(value).to(
                        beCloseTo(expected[line], within: 0.35),
                        description: "\(format) \(name) \(line)"
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

    /// 네 크기(10·20·40·60pt)의 아래 밑줄 두께가 **서로 같다** — 고정 0.36pt의 증거다
    /// (한글 문서 기하라면 0.4·0.8·1.6·2.4pt). 절대값도 0.36pt 근처이고, 가장 큰 줄조차
    /// 한글 문서 20pt 값(0.8pt)에 못 미친다.
    func testHwp2007DecorationLineThicknessIsFixedAcrossSizes() async throws {
        let raster = try await Self.raster(Self.hwp2007, hwpx: false)
        let centers = Self.lineCenters(raster, where: Self.isGreen)
        expect(centers.count).to(equal(4), description: "아래 밑줄 4줄")
        guard centers.count == 4 else { return }
        var thicknesses: [CGFloat] = []
        for (index, center) in centers.enumerated() {
            let columns = try XCTUnwrap(
                Self.lineColumns(raster, center: center, where: Self.isGreen), "밑줄 \(index) 열"
            )
            let thickness = try XCTUnwrap(
                raster.lineThickness(
                    center: center, halfBand: 0.53, columns: columns,
                    channel: { red, _, _ in red }
                ),
                "밑줄 \(index) 두께"
            )
            thicknesses.append(thickness)
        }
        for (index, thickness) in thicknesses.enumerated() {
            expect(thickness).to(
                beCloseTo(thicknesses[0], within: 0.1), description: "밑줄 \(index) 두께 일치"
            )
            expect(thickness).to(beLessThan(0.8), description: "밑줄 \(index) 두께 상한")
        }
        expect(thicknesses[3]).to(
            beCloseTo(HwpRenderTuning.Text.hwp200XDecorationLineThickness, within: 0.15),
            description: "60pt 밑줄 두께"
        )
    }
}
