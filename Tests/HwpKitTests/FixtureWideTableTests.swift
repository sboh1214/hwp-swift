import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `wide-tables` 픽스처 쌍 (#254) — 본문·문단·셀·각주보다 넓은 표를 한글처럼 **저작 폭 그대로** 그리고
/// 한글의 가로 자리에 놓는지 잠근다. 종전에는 그런 표를 가용 폭으로 줄이고 칸을 비례로 좁혔다(450pt 표 →
/// 425.2pt, 시험 칸 420 → 396.85pt).
///
/// - 글자처럼 취급 표는 줄보다 넓으면 문단 정렬(가운데·오른쪽·배분)과 무관하게 **줄 시작**(문단 왼쪽
///   여백 + 첫 줄 들여쓰기)에서 시작해 오른쪽으로 넘친다 (`HwpLineBreaker.overflowStartAligned`).
/// - 자리 차지 표는 가로 기준(문단·종이·단)·정렬·오프셋·바깥 여백으로 놓여 정렬대로 넘친다
///   (`HwpPaginator.flowTableOriginX`).
/// - 폭 기준이 상대값('문단')인 표는 그 기준 폭의 100%다 (`HwpTableLayout.resolvedWidths`). 한글은
///   다시 저장할 때 공통 폭(32520 HWPUNIT)과 첫 칸(295.2pt)까지 문단 폭에 맞춰 고쳐 쓰므로 이 저장본의
///   칸 합은 이미 문단 폭이다 — 이 픽스처가 잠그는 것은 그 저장값을 퍼센트로 읽지 않는 것(읽으면 문단
///   폭의 3.25배)이고, 첫 칸 흡수는 합성 `HwpWideTableWidthTests`가 잠근다.
///
/// 오라클은 한컴오피스 한글 12.30.0(build 6523, macOS)이 같은 편집 세션에서 `PDF로 저장하기…`로 내보낸
/// 벡터 좌표다 (2026-10-05, PyMuPDF). 표본 표는 1행 2열 [시험 칸 | 빨강 기준 칸 30pt]이고 0.12mm 테두리의
/// 세로 선 중심 x — 시험 칸 왼 변(초록)·칸 경계(파랑)·기준 칸 오른 변(빨강) — 를 칸 모서리와 맞댄다. 한글은
/// 좌표를 600dpi 장치 격자(0.12pt)에 반올림하므로 0.13pt 안에서 맞춘다. 결정론 글꼴로 조판하지만 가로
/// 자리는 글꼴과 무관하다(넓은 표는 제 줄에 혼자 놓이고, 자리 차지 표는 앵커 기준으로 놓인다).
final class FixtureWideTableTests: XCTestCase {
    static let fixture = "wide-tables"
    static let tolerance: CGFloat = 0.13

    /// 표 하나의 세로 테두리 중심 x — 한글 PDF 값 (쪽 왼쪽에서 pt)
    struct Sample {
        let label: String
        /// 시험 칸 왼 변
        let left: CGFloat
        /// 시험 칸 | 기준 칸 경계
        let boundary: CGFloat
        /// 기준 칸 오른 변 (한글이 그리지 않은 칸은 nil)
        let right: CGFloat?
        /// 표 바깥 폭 = 저작 폭 (pt, 셀 간격 포함)
        let width: CGFloat

        init(
            _ label: String, _ left: CGFloat, _ boundary: CGFloat, _ right: CGFloat?,
            width: CGFloat = 450
        ) {
            self.label = label
            self.left = left
            self.boundary = boundary
            self.right = right
            self.width = width
        }
    }

    /// 본문 표본 표 17개 (문서 순) — 본문 85.04–510.24pt, A4 595.28pt
    static let body: [Sample] = [
        Sample("#0 글자처럼 450 왼쪽 정렬", 85.08, 505.08, 535.08),
        Sample("#1 글자처럼 450 가운데 정렬 — 줄 시작", 85.08, 505.08, 535.08),
        Sample("#2 글자처럼 450 오른쪽 정렬 — 줄 시작", 85.08, 505.08, 535.08),
        Sample("#3 글자처럼 450 배분 정렬", 85.08, 505.08, 535.08),
        Sample("#4 글자처럼 450 문단 왼 여백 20", 105.12, 525.12, 555.12),
        Sample("#5 글자처럼 400 가운데, 문단 폭 385 — 줄 시작", 105.12, 475.08, 505.08, width: 400),
        Sample("#6 글자처럼 450 첫 줄 들여쓰기 20", 105.12, 525.12, 555.12),
        Sample("#7 글자처럼 450 셀 간격 2.83 (칸은 간격만큼 안)", 87.96, 499.44, 532.2),
        Sample(
            "#8 글자처럼 문단 기준 → 문단 폭 325.2 (저장값 32520·칸 295.2 + 30)", 135.12, 430.32, 460.32,
            width: 325.2
        ),
        Sample("#9 자리 차지 문단 왼쪽 450", 85.08, 505.08, 535.08),
        Sample("#10 자리 차지 문단 가운데 450 — 양쪽으로 넘침", 72.72, 492.72, 522.72),
        Sample("#11 자리 차지 문단 오른쪽 450 — 왼쪽으로 넘침", 60.24, 480.24, 510.24),
        Sample("#12 자리 차지 종이 오른쪽 450", 145.32, 565.32, 595.32),
        Sample("#13 자리 차지 단 가운데 300 (본문 안)", 147.72, 417.72, 447.72, width: 300),
        Sample("#14 자리 차지 문단 왼쪽 450 오프셋 +20", 105.12, 525.12, 555.12),
        Sample("#15 자리 차지 문단 오른쪽 450 바깥 여백 좌우 10", 50.28, 470.28, 500.28),
        Sample("#16 자리 차지 문단 가운데 450, 문단 왼 여백 20", 82.68, 502.68, 532.68),
    ]

    /// 각주 안 표 2개 — 글자처럼 취급(가운데 정렬 문단, 줄 시작)과 자리 차지(문단 가운데)
    static let footnotes: [Sample] = [
        Sample("각주 1 글자처럼 450 가운데 정렬 — 줄 시작", 85.08, 505.08, 535.08),
        Sample("각주 2 자리 차지 문단 가운데 450", 72.72, 492.72, 522.72),
    ]

    /// 바깥 1×1 표(300pt, 셀 안쪽 여백 0)의 셀 안 글자처럼 취급 350pt 표 — 셀 안폭을 넘겨 그린다.
    /// 한글은 바깥 셀 오른쪽 경계(385.08) 밖에서 시작하는 기준 칸을 그리지 않는다 (범위 밖 — 우리는 그린다).
    static let nested = Sample("셀 안 글자처럼 350", 85.08, 405.12, nil, width: 350)

    static func document(_ format: String) async throws -> HwpDocument {
        let url = FixtureRoot.url(
            from: #file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
        ).appendingPathComponent(fixture).appendingPathComponent("document.\(format)")
        return try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
    }

    /// 표 첫 행의 세로 테두리 x (쪽 좌표)
    struct Edges {
        /// 시험 칸 왼 변
        let left: CGFloat
        /// 시험 칸 | 기준 칸 경계
        let boundary: CGFloat
        /// 마지막 칸 오른 변
        let right: CGFloat
    }

    /// 표 프레임(쪽 좌표 원점 `origin`)의 첫 행 세로 테두리 x
    static func edges(of table: HwpTableFrame, origin: CGPoint) -> Edges? {
        guard let cells = table.rows.first?.cells, let first = cells.first, let last = cells.last
        else { return nil }
        return Edges(
            left: origin.x + first.cellFrame.minX,
            boundary: origin.x + first.cellFrame.maxX,
            right: origin.x + last.cellFrame.maxX
        )
    }

    static func assertEdges(_ edges: Edges?, match sample: Sample, format: String) {
        let label = "\(format) \(sample.label)"
        guard let edges else {
            fail("\(label): 표 프레임에 칸이 없다")
            return
        }
        expect(edges.left).to(beCloseTo(sample.left, within: tolerance), description: label)
        expect(edges.boundary).to(beCloseTo(sample.boundary, within: tolerance), description: label)
        if let right = sample.right {
            expect(edges.right).to(beCloseTo(right, within: tolerance), description: label)
        }
    }

    /// 본문 표 블록 (쪽 → 위에서 아래 순)
    static func bodyTables(of document: HwpDocument) -> [AnyHwpBlock] {
        document.pages.flatMap { page in
            page.blocks.filter { $0.kind == .table && $0.role == .body }
                .sorted { $0.frame.minY < $1.frame.minY }
        }
    }

    func testBodyTablesKeepAuthoredWidthAtHangulPositionsInBothFormats() async throws {
        for format in ["hwp", "hwpx"] {
            let document = try await Self.document(format)
            expect(document.pages.count).to(equal(2), description: format)
            // 표본 17개 + 셀 안 표를 품은 바깥 표
            let tables = Self.bodyTables(of: document)
            expect(tables.count).to(equal(Self.body.count + 1), description: format)
            for (block, sample) in zip(tables, Self.body) {
                guard case let .table(frame) = block.payload else {
                    fail("\(format) \(sample.label): 표 페이로드가 없다")
                    continue
                }
                Self.assertEdges(
                    Self.edges(of: frame, origin: block.frame.origin), match: sample, format: format
                )
                // 블록 폭 = 저작 폭 (줄이지 않는다) — 셀 간격 표도 바깥 폭 450
                expect(block.frame.width)
                    .to(
                        beCloseTo(sample.width, within: 0.01),
                        description: "\(format) \(sample.label)"
                    )
            }
        }
    }

    func testFootnoteTablesKeepAuthoredWidthInBothFormats() async throws {
        for format in ["hwp", "hwpx"] {
            let document = try await Self.document(format)
            let notes = document.pages.flatMap { page in
                page.blocks.compactMap { block -> (AnyHwpBlock, HwpFootnoteBlock)? in
                    guard case let .footnote(note) = block.payload, !note.nestedTables.isEmpty
                    else { return nil }
                    return (block, note)
                }
            }
            let tables = notes.flatMap { block, note in
                note.nestedTables.map { (block.frame.origin, $0) }
            }.sorted { $0.0.y + $0.1.rect.minY < $1.0.y + $1.1.rect.minY }
            expect(tables.count).to(equal(Self.footnotes.count), description: format)
            for ((origin, nested), sample) in zip(tables, Self.footnotes) {
                Self.assertEdges(
                    Self.edges(of: nested.table, origin: CGPoint(
                        x: origin.x + nested.rect.minX, y: origin.y + nested.rect.minY
                    )),
                    match: sample, format: format
                )
                expect(nested.rect.width)
                    .to(beCloseTo(sample.width, within: 0.01), description: format)
            }
        }
    }

    func testNestedTableKeepsAuthoredWidthBeyondItsCellInBothFormats() async throws {
        for format in ["hwp", "hwpx"] {
            let document = try await Self.document(format)
            let outer = try XCTUnwrap(Self.bodyTables(of: document).last, format)
            guard case let .table(frame) = outer.payload else {
                fail("\(format): 바깥 표 페이로드가 없다")
                continue
            }
            expect(outer.frame.width).to(beCloseTo(300, within: 0.01), description: format)
            let nested = try XCTUnwrap(frame.rows.first?.cells.first?.nestedTables.first, format)
            // 셀 안폭 300pt를 넘는 350pt — 셀 폭으로 줄이지 않는다
            expect(nested.rect.width)
                .to(beCloseTo(Self.nested.width, within: 0.01), description: format)
            Self.assertEdges(
                Self.edges(of: nested.table, origin: CGPoint(
                    x: outer.frame.minX + nested.rect.minX, y: outer.frame.minY + nested.rect.minY
                )),
                match: Self.nested, format: format
            )
        }
    }
}
