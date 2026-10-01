import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `table-border-corners` 픽스처 쌍 (#246) — 표 셀 테두리의 모서리 끝 자리와 그리는 차례를 한글 12.30
/// 출력에 맞춘다: 단선은 여러 줄·물결 이웃 쪽에서 가로·세로 모두 물러나고 선 없음 이웃도 그 굵기만큼
/// 나가며, 여러 줄·물결은 모양·굵기가 같은 이웃과만 부속선마다 맞물리고(╬ 교차점) 다르면 표 격자의
/// 이어짐·지나감으로 끝 자리가 갈리고, 같은 물결 이웃이면 변 전체를 옮긴다. 셀 간격이 없는 표의 실선은
/// 격자선을 따라 한 선으로 잇고, 그리는 차례는 여러 줄·물결 → 단선 세로 → 단선 가로 → 바깥 테두리
/// 덧긋기다.
///
/// 오라클은 한글 12.30.0(build 6446, macOS)이 같은 편집 세션에서 `PDF로 저장하기…`로 내보낸 벡터
/// 좌표다 (2026-10-02, PyMuPDF — 표마다 끝의 빨강 기준 칸으로 표 원점을 잡았다; 로컬 `probes/246`의
/// `fxdata246.py`가 표본을 뽑는다). 좌표는 **표 로컬**(첫 칸 왼 위 모서리 = 0, pt)이다. 한글은 표
/// 원점을 0.12pt 장치 격자에 맞추고 여러 줄 띠를 장치 단위로 그려 1~2u 흔들리므로 선 끝은 0.2,
/// 가로지르는 자리는 0.6 안에서 짝짓는다 (띠 두께는 남은 격차 — `Sources/HwpKitCore/AGENTS.md`). 물결은
/// 반주기가 남은 격차라 첫 대각선의 시작만 댄다. 결정론 글꼴로 조판하므로 기기 독립이다.
final class FixtureTableBorderCornerTests: XCTestCase {
    static let fixture = "table-border-corners"
    /// 선 끝 자리 — 장치 격자 한 칸 + 반올림 차
    static let tolerance: CGFloat = 0.2

    enum Ink { case green, blue, magenta, cyan }

    /// 한글 PDF의 선 요소 — 색, 가로인가, 가로지르는 띠 가운데, 선 방향 시작·끝 (표 로컬)
    struct Line {
        let ink: Ink
        let horizontal: Bool
        let cross: CGFloat
        let start: CGFloat
        let end: CGFloat

        init(_ ink: Ink, _ horizontal: Bool, _ cross: CGFloat, _ start: CGFloat, _ end: CGFloat) {
            self.ink = ink
            self.horizontal = horizontal
            self.cross = cross
            self.start = start
            self.end = end
        }
    }

    /// 겹친 두 선 요소 가운데 한글에서 위에 보이는 쪽 (`Sample.lines`의 색인)
    struct Above {
        let upper: Int
        let lower: Int

        init(_ upper: Int, _ lower: Int) {
            self.upper = upper
            self.lower = lower
        }
    }

    /// 물결 변 — 색, 가로인가, 띠의 가로지르는 시작, 첫 대각선의 선 방향 시작 (중심선)
    struct Wave {
        let ink: Ink
        let horizontal: Bool
        let cross: CGFloat
        let start: CGFloat

        init(_ ink: Ink, _ horizontal: Bool, _ cross: CGFloat, _ start: CGFloat) {
            self.ink = ink
            self.horizontal = horizontal
            self.cross = cross
            self.start = start
        }
    }

    /// 표 하나의 한글 PDF 값
    struct Sample {
        let lines: [Line]
        let above: [Above]
        let waves: [Wave]
    }

    /// 우리 페인트 목록의 테두리 조각 — 색, 조각 상자, 그 명령의 차례, 같은 명령의 경로 상자 (표 로컬)
    struct Mark {
        let ink: Ink
        let rect: CGRect
        let order: Int
        let command: CGRect

        var isHorizontal: Bool {
            rect.width > rect.height
        }

        func span(horizontal: Bool) -> (start: CGFloat, end: CGFloat) {
            horizontal ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
        }

        func offset(by origin: CGPoint) -> Mark {
            Mark(
                ink: ink, rect: rect.offsetBy(dx: -origin.x, dy: -origin.y), order: order,
                command: command.offsetBy(dx: -origin.x, dy: -origin.y)
            )
        }
    }

    static func ink(of color: CGColor?) -> Ink? {
        guard let components = color?.components, components.count >= 3 else { return nil }
        let full = components.prefix(3).map { $0 > 0.9 }
        let empty = components.prefix(3).map { $0 < 0.1 }
        guard zip(full, empty).allSatisfy({ $0 || $1 }) else { return nil }
        return switch (full[0], full[1], full[2]) {
        case (false, true, false): .green
        case (false, false, true): .blue
        case (true, false, true): .magenta
        case (false, true, true): .cyan
        default: nil
        }
    }

    /// 표마다 조각 (문서 순 — 쪽, 위에서 아래)
    static func marks(_ format: String) async throws -> [[Mark]] {
        let url = FixtureRoot.url(
            from: #file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
        ).appendingPathComponent(fixture).appendingPathComponent("document.\(format)")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 2
        var result: [[Mark]] = []
        for page in document.pages {
            var all: [Mark] = []
            for (order, command) in page.paintList.commands.enumerated() {
                guard case let .drawPath(path, fill, _, _) = command, let ink = ink(of: fill) else {
                    continue
                }
                let box = path.boundingBoxOfPath
                all += FixtureTableBorderChainTests.subpathBoxes(path).map {
                    Mark(ink: ink, rect: $0, order: order, command: box)
                }
            }
            let frames = page.blocks.filter { $0.kind == .table }.map(\.frame)
                .sorted { $0.minY < $1.minY }
            for frame in frames {
                let zone = frame.insetBy(dx: -8, dy: -8)
                let inside = all.filter { zone.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                result.append(inside.map { $0.offset(by: frame.origin) })
            }
        }
        expect(result.count) == samples.count
        return result
    }

    /// 선 조각 — 물결 대각선·꼭짓점 평탄은 뺀다 (축에 맞고 긴 변이 4.5pt를 넘는 것)
    static func lineMarks(_ marks: [Mark]) -> [Mark] {
        marks.filter {
            max($0.rect.width, $0.rect.height) > 4.5 && abs($0.rect.width - $0.rect.height) > 1
        }
    }

    /// 한글 선 요소와 짝지을 우리 조각 — 같은 색·방향, 가로지르는 자리 0.6 안, 선 방향으로 겹치는 것
    /// 가운데 시작·끝이 가장 가까운 것
    static func match(_ line: Line, in marks: [Mark]) -> Mark? {
        func distance(_ mark: Mark) -> CGFloat {
            let span = mark.span(horizontal: line.horizontal)
            return abs(span.start - line.start) + abs(span.end - line.end)
        }
        return lineMarks(marks).filter { mark in
            let span = mark.span(horizontal: line.horizontal)
            let cross = mark.isHorizontal ? mark.rect.midY : mark.rect.midX
            return mark.ink == line.ink && mark.isHorizontal == line.horizontal
                && abs(cross - line.cross) < 0.6
                && min(span.end, line.end) > max(span.start, line.start)
        }.min { distance($0) < distance($1) }
    }

    /// 선 요소마다 같은 색·방향·자리의 우리 조각이 있고 시작·끝이 한글과 같다. 거꾸로 우리 선 조각은
    /// 모두 한글 선 요소 안에 든다 (이은 실선을 우리는 첫 칸이 한 번에 긋고 한글도 한 선이다).
    func testLinesMatchHangul() async throws {
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.marks(format)
            for (index, (sample, marks)) in zip(Self.samples, tables).enumerated() {
                for line in sample.lines {
                    let label = "\(format) #\(index) \(line.ink) \(line.horizontal) \(line.cross)"
                    guard let mark = Self.match(line, in: marks) else {
                        fail("\(label): 짝이 없다")
                        continue
                    }
                    let span = mark.span(horizontal: line.horizontal)
                    let within = Self.tolerance
                    expect(span.start).to(beCloseTo(line.start, within: within), description: label)
                    expect(span.end).to(beCloseTo(line.end, within: within), description: label)
                }
                for mark in Self.lineMarks(marks) {
                    let span = mark.span(horizontal: mark.isHorizontal)
                    let cross = mark.isHorizontal ? mark.rect.midY : mark.rect.midX
                    let covered = sample.lines.contains { line in
                        line.ink == mark.ink && line.horizontal == mark.isHorizontal
                            && abs(line.cross - cross) < 0.6
                            && line.start - Self.tolerance <= span.start
                            && span.end <= line.end + Self.tolerance
                    }
                    expect(covered).to(beTrue(), description: "\(format) #\(index) \(mark.rect)")
                }
            }
        }
    }

    /// 겹친 다른 색 선 요소의 위아래가 한글과 같다 — 셀 간격이 없는 표의 그리는 차례
    func testOverlappingBordersStackLikeHangul() async throws {
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.marks(format)
            var compared = 0
            for (index, (sample, marks)) in zip(Self.samples, tables).enumerated() {
                for pair in sample.above {
                    let label = "\(format) #\(index) \(pair.upper) over \(pair.lower)"
                    guard let upper = Self.match(sample.lines[pair.upper], in: marks),
                          let lower = Self.match(sample.lines[pair.lower], in: marks)
                    else {
                        fail("\(label): 짝이 없다")
                        continue
                    }
                    compared += 1
                    expect(upper.order).to(beGreaterThan(lower.order), description: label)
                }
            }
            expect(compared) == Self.samples.map(\.above.count).reduce(0, +)
        }
    }

    /// 물결 변의 첫 대각선 시작 — 우리 대각선은 45° 평행사변형이라 경로 상자가 획 반폭/√2만큼 앞이다
    func testWaveStartsMatchHangul() async throws {
        let corner = 72 / 25.4 / 4 / 2 / 2.0.squareRoot()
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.marks(format)
            for (index, (sample, marks)) in zip(Self.samples, tables).enumerated() {
                for wave in sample.waves {
                    let label = "\(format) #\(index) \(wave.ink) \(wave.horizontal) \(wave.cross)"
                    let starts = marks.filter { mark in
                        let box = mark.command
                        let horizontal = box.width > box.height
                        return mark.ink == wave.ink && horizontal == wave.horizontal
                            && abs((horizontal ? box.minY : box.minX) - wave.cross) < 1
                    }.map { (wave.horizontal ? $0.command.minX : $0.command.minY) + corner }
                    let nearest = starts.min { abs($0 - wave.start) < abs($1 - wave.start) }
                    expect(nearest)
                        .to(beCloseTo(wave.start, within: Self.tolerance), description: label)
                }
            }
        }
    }
}

extension FixtureTableBorderCornerTests {
    /// 표 12개 (문서 순) — 한글 PDF 값 (`fxdata246.py`)
    static let samples: [Sample] = [
        // #0 A H solid + dbl verticals
        Sample(
            lines: [
                Line(.blue, false, -2.20, 1.44, 29.88), Line(.blue, false, 2.12, 1.44, 29.88),
                Line(.blue, false, 147.80, 1.44, 29.88), Line(.blue, false, 152.12, 1.44, 29.88),
                Line(.green, true, 0.00, 2.72, 147.20),
            ],
            above: [],
            waves: []
        ),
        // #1 B V solid + dbl horizontals
        Sample(
            lines: [
                Line(.blue, true, -2.16, -1.48, 29.96), Line(.blue, true, 2.16, -1.48, 29.96),
                Line(.blue, true, 57.84, -1.48, 29.96), Line(.blue, true, 62.16, -1.48, 29.96),
                Line(.green, false, -0.04, 2.76, 57.24),
            ],
            above: [
                Above(4, 1), Above(4, 2),
            ],
            waves: []
        ),
        // #2 C H solid + none 2mm verticals
        Sample(
            lines: [
                Line(.green, true, 0.00, -2.80, 152.84),
            ],
            above: [],
            waves: []
        ),
        // #3 D H dbl + solid verticals
        Sample(
            lines: [
                Line(.blue, false, -0.04, 1.44, 30.00), Line(.blue, false, 149.96, 1.44, 30.00),
                Line(.green, true, -1.08, -2.80, 152.72), Line(.green, true, 1.08, -2.80, 152.72),
            ],
            above: [],
            waves: []
        ),
        // #4 E V wave + solid horizontals
        Sample(
            lines: [
                Line(.blue, true, 0.00, 1.40, 30.08), Line(.blue, true, 60.00, 1.40, 30.08),
            ],
            above: [],
            waves: [
                Wave(.green, false, -2.56, 2.88),
            ]
        ),
        // #5 F 2x2 dbl colors
        Sample(
            lines: [
                Line(.blue, true, -1.08, 78.60, 161.40), Line(.blue, true, 1.08, 80.76, 159.24),
                Line(.blue, true, 38.88, 80.76, 159.24), Line(.blue, true, 41.04, 80.76, 159.24),
                Line(.blue, false, 78.96, 0.72, 39.24), Line(.blue, false, 81.12, 0.72, 39.24),
                Line(.blue, false, 158.88, 0.72, 39.24), Line(.blue, false, 161.04, -1.44, 41.40),
                Line(.cyan, true, 38.88, 80.76, 159.24), Line(.cyan, true, 41.04, 80.76, 159.24),
                Line(.cyan, true, 78.96, 80.76, 159.24), Line(.cyan, true, 81.12, 78.60, 161.40),
                Line(.cyan, false, 78.96, 40.68, 79.32), Line(.cyan, false, 81.12, 40.68, 79.32),
                Line(.cyan, false, 158.88, 40.68, 79.32), Line(.cyan, false, 161.04, 38.52, 81.48),
                Line(.green, true, -1.08, -1.44, 81.48), Line(.green, true, 1.08, 0.72, 79.32),
                Line(.green, true, 38.88, 0.72, 79.32), Line(.green, true, 41.04, 0.72, 79.32),
                Line(.green, false, -1.08, -1.44, 41.40), Line(.green, false, 1.08, 0.72, 39.24),
                Line(.green, false, 78.96, 0.72, 39.24), Line(.green, false, 81.12, 0.72, 39.24),
                Line(.magenta, true, 38.88, 0.72, 79.32), Line(.magenta, true, 41.04, 0.72, 79.32),
                Line(.magenta, true, 78.96, 0.72, 79.32), Line(.magenta, true, 81.12, -1.44, 81.48),
                Line(.magenta, false, -1.08, 38.52, 81.48),
                Line(.magenta, false, 1.08, 40.68, 79.32),
                Line(.magenta, false, 78.96, 40.68, 79.32),
                Line(.magenta, false, 81.12, 40.68, 79.32),
            ],
            above: [
                Above(0, 16), Above(1, 23), Above(8, 2), Above(2, 23), Above(9, 3), Above(13, 3),
                Above(14, 3), Above(31, 3), Above(4, 17), Above(4, 18), Above(4, 22), Above(24, 4),
                Above(8, 5), Above(5, 23), Above(8, 6), Above(15, 7), Above(8, 23), Above(9, 31),
                Above(10, 31), Above(11, 27), Above(12, 19), Above(12, 25), Above(12, 26),
                Above(12, 30), Above(13, 31), Above(24, 18), Above(25, 19), Above(29, 19),
                Above(30, 19), Above(28, 20), Above(24, 21), Above(24, 22),
            ],
            waves: []
        ),
        // #6 G 3x2 header dbl
        Sample(
            lines: [
                Line(.blue, true, 0.00, -0.12, 160.20), Line(.blue, true, 60.00, -0.12, 160.20),
                Line(.blue, true, 90.00, -0.12, 160.20), Line(.blue, false, 0.00, -0.00, 90.00),
                Line(.blue, false, 80.04, -0.00, 90.00), Line(.blue, false, 159.96, -0.00, 90.00),
                Line(.green, true, 29.40, 0.24, 80.04), Line(.green, true, 29.40, 80.04, 159.84),
                Line(.green, true, 30.48, 0.24, 80.04), Line(.green, true, 30.48, 80.04, 159.84),
            ],
            above: [
                Above(4, 6), Above(4, 7), Above(4, 8), Above(4, 9), Above(5, 7), Above(5, 9),
            ],
            waves: []
        ),
        // #7 H 2x2 solid colors
        Sample(
            lines: [
                Line(.blue, true, 0.00, 78.60, 161.40), Line(.blue, true, 40.08, 78.60, 161.40),
                Line(.blue, false, 80.04, 0.00, 40.08), Line(.blue, false, 159.96, 0.00, 40.08),
                Line(.cyan, true, 40.08, 78.60, 161.40), Line(.cyan, true, 80.04, 78.60, 161.40),
                Line(.cyan, false, 80.04, 40.08, 80.04), Line(.cyan, false, 159.96, 40.08, 80.04),
                Line(.green, true, 0.00, -1.44, 81.48), Line(.green, true, 40.08, -1.44, 81.48),
                Line(.green, false, 0.00, 0.00, 40.08), Line(.green, false, 80.04, 0.00, 40.08),
                Line(.magenta, true, 40.08, -1.44, 81.48),
                Line(.magenta, true, 80.04, -1.44, 81.48),
                Line(.magenta, false, 0.00, 40.08, 80.04),
                Line(.magenta, false, 80.04, 40.08, 80.04),
            ],
            above: [
                Above(8, 0), Above(0, 11), Above(4, 1), Above(1, 6), Above(1, 7), Above(1, 9),
                Above(1, 11), Above(1, 12), Above(1, 15), Above(4, 2), Above(8, 2), Above(9, 2),
                Above(2, 11), Above(12, 2), Above(4, 3), Above(4, 9), Above(4, 11), Above(4, 12),
                Above(4, 15), Above(5, 13), Above(5, 15), Above(9, 6), Above(12, 6), Above(13, 6),
                Above(6, 15), Above(12, 9), Above(14, 9), Above(9, 15), Above(10, 12),
                Above(12, 11),
            ],
            waves: []
        ),
        // #8 I 1x3 solid chain inner dbl
        Sample(
            lines: [
                Line(.blue, false, 57.80, 1.44, 29.88), Line(.blue, false, 62.12, 1.44, 29.88),
                Line(.blue, false, 117.80, 1.44, 29.88), Line(.blue, false, 122.12, 1.44, 29.88),
                Line(.green, true, 0.00, -0.16, 180.08),
            ],
            above: [],
            waves: []
        ),
        // #9 J 1x3 solid chain mid magenta
        Sample(
            lines: [
                Line(.blue, false, 57.80, 1.44, 29.88), Line(.blue, false, 62.12, 1.44, 29.88),
                Line(.blue, false, 117.80, 1.44, 29.88), Line(.blue, false, 122.12, 1.44, 29.88),
                Line(.green, true, 0.00, -0.16, 57.20), Line(.green, true, 0.00, 122.72, 180.08),
                Line(.magenta, true, 0.00, 62.72, 117.20),
            ],
            above: [],
            waves: []
        ),
        // #10 K 2x2 wave colors
        Sample(
            lines: [],
            above: [],
            waves: [
                Wave(.green, false, -2.52, -1.44), Wave(.green, false, 77.52, 0.72),
                Wave(.green, true, -2.52, -1.44), Wave(.green, true, 37.56, 0.72),
                Wave(.blue, false, 77.52, 0.72), Wave(.blue, false, 157.44, 0.72),
                Wave(.blue, true, -2.52, 78.60), Wave(.blue, true, 37.56, 80.76),
                Wave(.magenta, false, -2.52, 38.64), Wave(.magenta, false, 77.52, 40.80),
                Wave(.magenta, true, 37.56, 0.72), Wave(.magenta, true, 77.52, 0.72),
                Wave(.cyan, false, 77.52, 40.80), Wave(.cyan, false, 157.44, 40.80),
                Wave(.cyan, true, 37.56, 80.76), Wave(.cyan, true, 77.52, 80.76),
            ]
        ),
        // #11 L slim-thick box
        Sample(
            lines: [
                Line(.blue, false, -1.12, -1.44, 41.52), Line(.blue, false, 0.68, 0.00, 39.36),
                Line(.blue, false, 148.88, 0.00, 39.36), Line(.blue, false, 150.68, -1.44, 41.52),
                Line(.green, true, -1.08, -1.48, 151.40), Line(.green, true, 0.72, -0.04, 149.24),
                Line(.green, true, 39.00, -0.04, 149.24), Line(.green, true, 40.80, -1.48, 151.40),
            ],
            above: [
                Above(4, 0), Above(7, 0), Above(5, 1), Above(6, 1), Above(5, 2), Above(6, 2),
                Above(4, 3), Above(7, 3),
            ],
            waves: []
        ),
    ]
}
