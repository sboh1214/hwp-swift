import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `dash-patterns` 픽스처 쌍 (#245) — 대시 무늬(긴 점선·점선·일점쇄선·이점쇄선·긴 파선)의 선·공백을
/// 한글처럼 600dpi 장치 단위(u = 0.12pt) 정수로 그리는지 잠근다. 표 셀 테두리는 셀 간격이 없으면 격자
/// 식, 있으면 단 구분선과 같은 점 무늬 식이고(1mm 점선 35·52u vs 35·53u), 획 두께도 장치 단위로
/// 반올림한다(0.12mm 3u·1mm 24u·2mm 47u). 글자선은 무늬 두께 round(글자 크기 × 0.039)의 식이다.
///
/// 오라클은 한글 12.30.0(build 6446, macOS)이 같은 편집 세션에서 `PDF로 저장하기…`로 내보낸 벡터
/// 좌표다 (2026-10-01, PyMuPDF — 표는 끝의 빨강 기준 칸으로 시험 칸 원점을 잡았다). 표의 좌표는 **칸
/// 로컬**(칸 왼 위 모서리 = 0, pt)이고, 한글은 표 원점을 장치 격자에 맞춰 두어 첫 대시가 −0.06~−0.08pt에서
/// 시작하고 선 끝은 장치 한 칸을 더 그린다(330.16~330.18 — #235의 포함 끝) — 그래서 시작은 0.15, 끝은
/// 0.2 안에서 맞추고, **첫 대시에서 잰 대시 자리는 무늬의 장치 단위 누적 그대로**(1e-6) 맞춘다. 글자선은
/// 결정론 글꼴(Menlo)과 한글 글꼴의 진행 폭이 달라 run 길이가 갈리므로 run 시작에서 잰 대시 자리만
/// 대고(4px/pt 래스터라 0.3 안), 단 구분선은 밴드 첫 줄에서 잰 대시 자리와 조각 수를 댄다. 결정론 글꼴로
/// 조판하므로 기기 독립이다.
final class FixtureDashPatternTests: XCTestCase {
    static let fixture = "dash-patterns"
    static let unit: CGFloat = 0.12

    /// 표 하나의 시험 변 — 한글 PDF 값
    struct TableSample {
        let label: String
        /// 셀 간격 (pt)
        let spacing: CGFloat
        /// 선·공백 (u) — 한글 PDF에서 잰 한 주기
        let pattern: [CGFloat]
        let count: Int
        /// 칸 로컬 첫 대시 시작·마지막 대시 끝 (pt)
        let firstStart: CGFloat
        let lastEnd: CGFloat
        /// 획 두께 (u)
        let thickness: CGFloat

        static let all = [
            TableSample(
                label: "#0 긴 점선 0.12mm 격자", spacing: 0, pattern: [20, 12], count: 86,
                firstStart: -0.08, lastEnd: 328.72, thickness: 3
            ),
            TableSample(
                label: "#1 긴 점선 0.12mm 셀 간격", spacing: 2.83, pattern: [20, 12], count: 86,
                firstStart: -0.06, lastEnd: 328.74, thickness: 3
            ),
            TableSample(
                label: "#2 점선 1mm 격자", spacing: 0, pattern: [35, 52], count: 32,
                firstStart: -0.08, lastEnd: 327.76, thickness: 24
            ),
            TableSample(
                label: "#3 점선 1mm 셀 간격", spacing: 2.83, pattern: [35, 53], count: 32,
                firstStart: -0.06, lastEnd: 330.18, thickness: 24
            ),
            TableSample(
                label: "#4 긴 파선 2mm 격자", spacing: 0, pattern: [693, 207], count: 4,
                firstStart: -0.08, lastEnd: 330.16, thickness: 47
            ),
            TableSample(
                label: "#5 긴 파선 2mm 셀 간격", spacing: 2.83, pattern: [693, 208], count: 4,
                firstStart: -0.06, lastEnd: 330.18, thickness: 47
            ),
            TableSample(
                label: "#6 일점쇄선 0.5mm 격자", spacing: 0, pattern: [172, 51, 17, 51], count: 19,
                firstStart: -0.08, lastEnd: 330.16, thickness: 12
            ),
            TableSample(
                label: "#7 이점쇄선 1.5mm 셀 간격", spacing: 2.83,
                pattern: [518, 156, 52, 156, 52, 156], count: 7,
                firstStart: -0.06, lastEnd: 323.7, thickness: 35
            ),
            // 1×2 표 — 두 칸의 위 변이 한 사슬(#238)이고, 양 끝은 파랑 2mm 세로 변 획(47u)의 절반만큼
            // 나간다 (한글은 23u·24u로 격자에 맞춘다 — 우리는 23.5u씩)
            TableSample(
                label: "#8 긴 점선 0.4mm 1×2 사슬", spacing: 0, pattern: [69, 42], count: 26,
                firstStart: -2.72, lastEnd: 332.92, thickness: 9
            ),
        ]
    }

    /// 쪽의 표 9개 (문서 순) — 시험 칸 로컬 초록 조각 (위 변 위의 것, x 순)
    static func testEdges(_ format: String) async throws -> [[CGRect]] {
        let url = FixtureRoot.url(
            from: #file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
        ).appendingPathComponent(fixture).appendingPathComponent("document.\(format)")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 2
        let page = try XCTUnwrap(document.pages.first)
        let frames = page.blocks.filter { $0.kind == .table }.map(\.frame)
            .sorted { $0.minY < $1.minY }
        expect(frames.count) == TableSample.all.count
        var boxes: [CGRect] = []
        for command in page.paintList.commands {
            if case let .drawPath(path, fill, _, _) = command,
               FixtureTableBorderChainTests.ink(of: fill) == .green
            {
                boxes += FixtureTableBorderChainTests.subpathBoxes(path)
            }
        }
        return zip(frames, TableSample.all).map { frame, sample in
            let origin = CGPoint(x: frame.minX + sample.spacing, y: frame.minY + sample.spacing)
            return boxes.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
                .filter { abs($0.midY) < 0.5 && $0.minX > -6 && $0.maxX < 345 }
                .sorted { $0.minX < $1.minX }
        }
    }

    /// 무늬를 되풀이한 대시 자리 — 첫 대시 시작에서 잰 (시작, 길이) pt
    static func dashes(_ pattern: [CGFloat], count: Int) -> [(start: CGFloat, length: CGFloat)] {
        var result: [(start: CGFloat, length: CGFloat)] = []
        var units: CGFloat = 0
        var index = 0
        while result.count < count {
            let span = pattern[index % pattern.count]
            if index.isMultiple(of: 2) {
                result.append((units * unit, span * unit))
            }
            units += span
            index += 1
        }
        return result
    }

    /// 표 셀 테두리 대시 아홉 표본 — 대시 수·첫 시작·마지막 끝이 한글과 같고, 대시 자리는 첫 대시에서
    /// 한글의 장치 단위 무늬를 누적한 자리 그대로다 (마지막 대시는 선 끝에서 잘린다). 획 두께도 한글이다.
    func testTableBorderDashesMatchHangul() async throws {
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.testEdges(format)
            for (sample, marks) in zip(TableSample.all, tables) {
                let label = "\(format) \(sample.label)"
                expect(marks).to(haveCount(sample.count), description: label)
                guard let first = marks.first, let last = marks.last else { continue }
                expect(first.minX)
                    .to(beCloseTo(sample.firstStart, within: 0.15), description: label)
                expect(last.maxX).to(beCloseTo(sample.lastEnd, within: 0.2), description: label)
                let expected = Self.dashes(sample.pattern, count: marks.count)
                for (index, (mark, dash)) in zip(marks, expected).enumerated() {
                    expect(mark.minX - first.minX).to(
                        beCloseTo(dash.start, within: 1e-6), description: "\(label) 대시 \(index)"
                    )
                    if index < marks.count - 1 {
                        expect(mark.width).to(
                            beCloseTo(dash.length, within: 1e-6),
                            description: "\(label) 길이 \(index)"
                        )
                    }
                    expect(mark.height).to(
                        beCloseTo(sample.thickness * Self.unit, within: 1e-6),
                        description: "\(label) 두께 \(index)"
                    )
                }
            }
        }
    }

    /// 2쪽 단 구분선(일점쇄선 0.4mm) — 한글 PDF: 조각 15개, 긴 선 138u·공백 42u·점 14u·공백 42u, 획 9u,
    /// 마지막 조각 끝은 첫 조각에서 212.16pt (우리 밴드 높이는 0.16pt 짧다 — 마지막 줄 줄 간격의 기존
    /// 격차라 끝은 0.3 안에서 댄다)
    func testColumnDividerDashesMatchHangul() async throws {
        for format in ["hwp", "hwpx"] {
            let url = FixtureRoot.url(
                from: #file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
            ).appendingPathComponent(Self.fixture).appendingPathComponent("document.\(format)")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            let page = try XCTUnwrap(document.pages.last)
            var marks: [CGRect] = []
            for command in page.paintList.commands {
                if case let .drawPath(path, fill, _, _) = command,
                   FixtureTableBorderChainTests.ink(of: fill) == .green
                {
                    marks += FixtureTableBorderChainTests.subpathBoxes(path)
                }
            }
            marks.sort { $0.minY < $1.minY }
            expect(marks).to(haveCount(15), description: format)
            guard let first = marks.first, let last = marks.last else { continue }
            expect(last.maxY - first.minY).to(beCloseTo(212.16, within: 0.3), description: format)
            let expected = Self.dashes([138, 42, 14, 42], count: marks.count)
            for (index, (mark, dash)) in zip(marks, expected).enumerated() {
                expect(mark.minY - first.minY)
                    .to(beCloseTo(dash.start, within: 1e-6), description: "\(format) 조각 \(index)")
                if index < marks.count - 1 {
                    expect(mark.height).to(
                        beCloseTo(dash.length, within: 1e-6), description: "\(format) 길이 \(index)"
                    )
                }
                expect(mark.width).to(beCloseTo(9 * Self.unit, within: 1e-6))
            }
        }
    }

    /// 글자선 한 표본 — 꼬리표와 한글 PDF의 무늬 (u)
    struct CharacterSample {
        let tag: String
        let label: String
        let pattern: [CGFloat]
    }

    /// 한글 문서 취소선 다섯 표본 — run 시작에서 잰 대시 자리가 한글의 장치 단위 무늬 그대로다 (20pt 긴
    /// 점선 47·28u, 11.54pt 점선 6·9u — 무늬 두께 45의 점 단위 동점을 올린다, 10pt 긴 파선 48·14u, 40pt
    /// 일점쇄선 191·58·19·58u, 7pt 긴 점선 16·10u). 반올림 전 비례(0.057em)면 20pt 주기가 9.12pt라 열째
    /// 대시가 1.08pt 밀린다.
    func testStrikethroughDashesMatchHangul() async throws {
        let samples = [
            CharacterSample(tag: " #9", label: "긴 점선 20pt", pattern: [47, 28]),
            CharacterSample(tag: " #10", label: "점선 11.54pt", pattern: [6, 9]),
            CharacterSample(tag: " #11", label: "긴 파선 10pt", pattern: [48, 14]),
            CharacterSample(tag: " #12", label: "일점쇄선 40pt", pattern: [191, 58, 19, 58]),
            CharacterSample(tag: " #13", label: "긴 점선 7pt", pattern: [16, 10]),
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
                .appendingPathComponent(Self.fixture)
                .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            let page = try XCTUnwrap(document.pages.first)
            let raster = try await FixtureDecorationLineRenderTests.raster(Self.fixture, hwpx: hwpx)
            for sample in samples {
                let label = "\(format) \(sample.label)"
                let block = try XCTUnwrap(page.blocks.first {
                    $0.kind == .text && ($0.attributedString?.string.hasSuffix(sample.tag) ?? false)
                }, label)
                let runs = Self.greenRuns(raster, in: block.frame)
                expect(runs.count).to(beGreaterThan(8), description: "\(label) 대시 수")
                guard runs.count > 8, let first = runs.first else { continue }
                let expected = Self.dashes(sample.pattern, count: runs.count)
                // 마지막 대시는 run 끝에서 잘린다 — 시작만 본다
                for (index, (run, dash)) in zip(runs, expected).enumerated() {
                    expect(run.start - first.start).to(
                        beCloseTo(dash.start, within: 0.3), description: "\(label) 대시 \(index)"
                    )
                }
            }
        }
    }

    /// 블록 안에서 초록 잉크가 가장 많은 행의 가로 조각 (시작, 끝) pt — 취소선 한 줄
    static func greenRuns(
        _ raster: FixtureDecorationLineRenderTests.Raster, in frame: CGRect
    ) -> [(start: CGFloat, end: CGFloat)] {
        let scale = FixtureDecorationLineRenderTests.scale
        let rows = Int(frame.minY * scale) ... min(Int(frame.maxY * scale), raster.pixelHeight - 1)
        let isGreen = FixtureDecorationLineRenderTests.isGreen
        guard let row = rows.max(by: { raster.matches($0, isGreen) < raster.matches($1, isGreen) })
        else { return [] }
        return FixtureDecorationLineRenderTests.rowRuns(
            raster, near: (CGFloat(row) + 0.5) / scale, halfBand: 0,
            x: 0 ... CGFloat(raster.pixelWidth - 1) / scale, where: isGreen
        )
    }
}
