import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `table-cell-spacing` 픽스처 쌍 (#243) — 셀 간격이 있는 표의 셀 테두리를 한글처럼 칸마다 상자로
/// 그리는지 페인트 목록으로 잠근다: 원형 점선의 원은 단 구분선과 같은 점 무늬로 크고 성기며(1mm 간격
/// 10.56·칠 지름 4.44 — 셀 간격 0이면 5.76·3.0), 모서리는 만나는 두 변의 모양·굵기가 같으면 맞물려
/// 원이 모서리에서 시작하고, 다르면 가로 변이 모서리를 덮고 세로 변이 물러난다.
///
/// 오라클은 한글 12.30.0(build 6446, macOS)이 같은 편집 세션에서 `PDF로 저장하기…`로 내보낸 벡터
/// 좌표다 (2026-09-28, PyMuPDF — 한 행 표는 끝의 빨강 기준 칸으로 표 원점을 잡았다). 좌표는 **칸
/// 로컬**(칸 왼 위 모서리 = 0, pt)이고 한글 값은 0.12pt 장치 격자라 0.15 안에서 맞춘다. 굵은 이웃의
/// 반폭은 한글이 굵기를 장치 단위로 반올림해(2mm 5.67 → 5.64) 모서리에 따라 0.12~0.24 갈리므로
/// 그 자리는 따로 적는다. 결정론 글꼴로 조판하므로 기기 독립이다.
final class FixtureTableCellSpacingTests: XCTestCase {
    /// 한글 PDF 장치 격자 한 칸 + 반올림 차
    static let tolerance: CGFloat = 0.15

    /// 표 하나 — 셀 간격과 초록 테두리 조각 (표 로컬 좌표, 표 왼 위 모서리 = 0)
    struct Table {
        let spacing: CGFloat
        let marks: [CGRect]

        /// 칸 로컬로 옮긴 조각 — `cellOrigin`은 표 로컬 칸 모서리
        func local(from cellOrigin: CGPoint) -> [CGRect] {
            marks.map { $0.offsetBy(dx: -cellOrigin.x, dy: -cellOrigin.y) }
        }

        /// 첫 칸(표 로컬 (간격, 간격)) 로컬 조각
        var firstCell: [CGRect] {
            local(from: CGPoint(x: spacing, y: spacing))
        }
    }

    /// 쪽의 표 9개 (문서 순) — 셀 간격은 픽스처의 표 76 값 그대로 (pt)
    static func tables(_ format: String, file: String = #file) async throws -> [Table] {
        let url = FixtureRoot.url(
            from: file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
        ).appendingPathComponent("table-cell-spacing").appendingPathComponent("document.\(format)")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 1
        let page = try XCTUnwrap(document.pages.first)
        let frames = page.blocks.filter { $0.kind == .table }.map(\.frame)
            .sorted { $0.minY < $1.minY }
        expect(frames.count) == 9
        var paths: [CGPath] = []
        for command in page.paintList.commands {
            if case let .drawPath(path, fill, _, _) = command,
               FixtureTableBorderChainTests.ink(of: fill) == .green
            {
                paths.append(path)
            }
        }
        let spacings: [CGFloat] = [2.83, 0.01, 8.5, 0, 2.83, 2.83, 2.83, 2.83, 2.83]
        return zip(frames, spacings).map { frame, spacing in
            let zone = frame.insetBy(dx: -6, dy: -6)
            let marks = paths.flatMap { path in
                FixtureTableBorderChainTests.subpathBoxes(path)
                    .filter { zone.contains(CGPoint(x: $0.midX, y: $0.midY)) }
                    .map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
            }
            return Table(spacing: spacing, marks: marks)
        }
    }

    /// 원(가로·세로가 같은 작은 조각)
    static func circles(_ marks: [CGRect]) -> [CGRect] {
        marks.filter { abs($0.width - $0.height) < 0.01 && $0.width < 10 }
    }

    /// 칸 로컬 가로선 y 위 원 중심 x 가운데 `range`에 드는 것 (오름차순) — 모서리에서 가로·세로 변이
    /// 같은 자리에 그린 원은 한 번으로 센다
    static func centersX(
        _ marks: [CGRect], y: CGFloat, in range: ClosedRange<CGFloat>
    ) -> [CGFloat] {
        unique(circles(marks).filter { abs($0.midY - y) < 0.05 && range.contains($0.midX) }
            .map(\.midX))
    }

    /// 칸 로컬 세로선 x 위 원 중심 y 가운데 `range`에 드는 것 (오름차순, 겹친 원은 한 번)
    static func centersY(
        _ marks: [CGRect], x: CGFloat, in range: ClosedRange<CGFloat>
    ) -> [CGFloat] {
        unique(circles(marks).filter { abs($0.midX - x) < 0.05 && range.contains($0.midY) }
            .map(\.midY))
    }

    static func unique(_ values: [CGFloat]) -> [CGFloat] {
        Array(Set(values.map { ($0 * 1000).rounded() / 1000 })).sorted()
    }

    /// 원 크기 표본 — 한글 값: 간격·칠 지름, 위 변 원 수(90pt 변, 오른 모서리 원 제외), 첫 원 중심
    struct CircleSample {
        let table: Int
        let pitch: CGFloat
        let diameter: CGFloat
        let count: Int
        let first: CGFloat

        static let all = [
            // A 1mm 셀 간격 283 — 88u·37u
            CircleSample(table: 0, pitch: 10.56, diameter: 4.44, count: 9, first: 0.01),
            // B 0.4mm 셀 간격 1HWPUNIT — 35u·15u
            CircleSample(table: 1, pitch: 4.2, diameter: 1.8, count: 22, first: -0.06),
            // C 2mm 셀 간격 850 — 173u·71u
            CircleSample(table: 2, pitch: 20.76, diameter: 8.52, count: 5, first: 0),
            // D 1mm 셀 간격 0 (대조군, 격자) — 48u·25u, 첫 원 −t/2
            CircleSample(table: 3, pitch: 5.76, diameter: 3.0, count: 16, first: -1.4),
        ]
    }

    /// 이웃 원 중심 사이가 모두 `pitch`인가
    static func isEvenlySpaced(_ centers: [CGFloat], pitch: CGFloat) -> Bool {
        zip(centers, centers.dropFirst()).allSatisfy { abs($1 - $0 - pitch) < 1e-6 }
    }

    /// 원 크기·간격 — 셀 간격이 있으면 1HWPUNIT이어도 점 무늬, 없으면 격자 (한글 PDF: 간격·칠 지름)
    func testCircleSizeAndPitchFollowTheCellSpacing() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            for sample in CircleSample.all {
                let label = "\(format) table \(sample.table)"
                let marks = tables[sample.table].firstCell
                var top = Self.centersX(marks, y: 0, in: -3 ... 89)
                if sample.table == 3 {
                    // 격자는 가로 변이 −t/2에서 시작하므로 모서리(0)의 원은 왼 변의 것이다
                    top.removeAll { abs($0) < 0.05 }
                }
                expect(top).to(haveCount(sample.count), description: label)
                expect(top.first).to(beCloseTo(sample.first, within: tolerance), description: label)
                expect(Self.isEvenlySpaced(top, pitch: sample.pitch))
                    .to(beTrue(), description: label)
                let widths = Self.circles(marks).map(\.width)
                expect(widths.allSatisfy { abs($0 - sample.diameter) < 1e-6 })
                    .to(beTrue(), description: label)
            }
        }
    }

    /// 네 변이 같은 원형 점선이면 칸마다 네 모서리에서 시작한다 — 이웃 칸과 잇지 않고 가로 변도
    /// 세로 변 반폭만큼 나가지 않는다 (한글 A: 두 칸 모두 위 변 첫 원 = 칸 모서리, 왼 변 원 3개;
    /// I 2×2 0.4mm: 네 칸 모두 모서리에 원, 다음 원 +4.2)
    func testJoinedCircleCornersStartEachCellAtItsCorner() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            let pair = tables[0]
            let left = Self.centersY(pair.firstCell, x: 0, in: -3 ... 24)
            expect(left).to(haveCount(3), description: format)
            expect(left.first).to(beCloseTo(0, within: tolerance), description: format)
            let second = pair.local(from: CGPoint(x: pair.spacing * 2 + 90, y: pair.spacing))
            // 칸 경계 안만 본다 — 왼쪽 2.83 밖(−2.83)은 앞 칸 오른 변의 원이다
            let secondTop = Self.centersX(second, y: 0, in: -1 ... 89)
            expect(secondTop).to(haveCount(9), description: format)
            expect(secondTop.first).to(beCloseTo(-0.06, within: tolerance), description: format)
            let grid = tables[8]
            for (row, column) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                let origin = CGPoint(
                    x: grid.spacing + CGFloat(column) * (45 + grid.spacing),
                    y: grid.spacing + CGFloat(row) * (20 + grid.spacing)
                )
                let top = Self.centersX(grid.local(from: origin), y: 0, in: -1 ... 44)
                let label = "\(format) cell \(row),\(column)"
                expect(top.first).to(beCloseTo(0, within: tolerance), description: label)
                expect(top.dropFirst().first)
                    .to(beCloseTo(4.2, within: tolerance), description: label)
            }
        }
    }

    /// 이웃이 다른 모서리 — 굵은 실선(2mm) 이웃 옆 원형 점선 가로 변은 이웃 반폭만큼 앞에서, 세로 변은
    /// 그만큼 뒤에서 시작하고, 실선 세로 변도 물러난다 (한글 E −2.70, F +2.88, H y 2.88 ~ 57.36)
    func testUnjoinedCornersLetTheHorizontalEdgeCoverTheCorner() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            let top = Self.centersX(tables[4].firstCell, y: 0, in: -4 ... 95)
            expect(top).to(haveCount(10), description: format)
            expect(top.first).to(beCloseTo(-2.7, within: tolerance), description: format)
            expect(Self.isEvenlySpaced(top, pitch: 10.56)).to(beTrue(), description: format)
            let left = Self.centersY(tables[5].firstCell, x: 0, in: -4 ... 60)
            expect(left).to(haveCount(6), description: format)
            expect(left.first).to(beCloseTo(2.88, within: tolerance), description: format)
            // H 실선 세로 변 — 한글은 위 24u·아래 22u 물러나 끝이 0.19 갈린다 (장치 격자)
            let solid = try XCTUnwrap(
                tables[7].firstCell.filter { abs($0.midX) < 0.1 && $0.height > 10 }.first,
                format
            )
            expect(solid.minY).to(beCloseTo(2.88, within: tolerance), description: format)
            expect(solid.maxY).to(beCloseTo(57.36, within: 0.25), description: format)
        }
    }

    /// 그리기 순서 — 한글은 셀 간격이 있는 표의 세로 변을 먼저, 가로 변을 나중에 그려 모서리에서 가로
    /// 변이 위에 온다 (한글 PDF 그리기 순서: E는 파랑 세로 변 → 초록 위 변, F는 초록 왼 변 → 파랑 위·
    /// 아래 변). F의 물러난 첫 원(중심 +2.88, 반지름 2.22)은 파랑 2mm 위 변 띠에 걸쳐 이 순서가 보인다.
    func testVerticalEdgesArePaintedBeneathHorizontalEdges() async throws {
        for format in ["hwp", "hwpx"] {
            let url = FixtureRoot.url(
                from: #file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
            ).appendingPathComponent("table-cell-spacing")
                .appendingPathComponent("document.\(format)")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            let page = try XCTUnwrap(document.pages.first)
            let frames = page.blocks.filter { $0.kind == .table }.map(\.frame)
                .sorted { $0.minY < $1.minY }
            expect(frames.count) == 9
            // (표, 먼저 그리는 세로 변 색, 나중에 그리는 가로 변 색)
            for (table, vertical, horizontal) in [
                (4, FixtureTableBorderChainTests.Ink.blue, FixtureTableBorderChainTests.Ink.green),
                (5, .green, .blue),
            ] {
                let zone = frames[table].insetBy(dx: -6, dy: -6)
                var order: [FixtureTableBorderChainTests.Ink] = []
                for command in page.paintList.commands {
                    guard case let .drawPath(path, fill, _, _) = command,
                          let ink = FixtureTableBorderChainTests.ink(of: fill),
                          zone.intersects(path.boundingBoxOfPath)
                    else { continue }
                    order.append(ink)
                }
                let label = "\(format) table \(table)"
                let lastVertical = try XCTUnwrap(order.lastIndex(of: vertical), label)
                let firstHorizontal = try XCTUnwrap(order.firstIndex(of: horizontal), label)
                expect(lastVertical).to(beLessThan(firstHorizontal), description: label)
            }
        }
    }

    /// 맞물린 대시 — 네 변 긴 점선(1mm)은 세로 변도 가로 변처럼 반폭 앞에서 첫 대시를 시작한다
    /// (한글 G: 왼 변 첫 대시 −1.44 ~ 19.32, 위 변 −1.38 ~ 19.38; 셀 간격 0이면 세로 변은 모서리)
    func testJoinedDashVerticalsStartBeforeTheCorner() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            let marks = tables[6].firstCell
            let left = marks.filter { abs($0.midX) < 0.1 && $0.height > $0.width }
                .sorted { $0.minY < $1.minY }
            let top = marks.filter { abs($0.midY) < 0.1 && $0.width > $0.height }
                .sorted { $0.minX < $1.minX }
            expect(left.first?.minY).to(beCloseTo(-1.44, within: tolerance), description: format)
            expect(left.first?.maxY).to(beCloseTo(19.32, within: tolerance), description: format)
            expect(left.dropFirst().first?.minY)
                .to(beCloseTo(31.8, within: tolerance), description: format)
            expect(top.first?.minX).to(beCloseTo(-1.38, within: tolerance), description: format)
            expect(top.dropFirst().first?.minX)
                .to(beCloseTo(31.86, within: tolerance), description: format)
        }
    }
}
