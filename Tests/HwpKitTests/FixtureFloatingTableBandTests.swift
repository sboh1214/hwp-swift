@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 자리 차지 표의 실물 핀 — 1단 절대 캐시 문단의 띠 배치(#161)와 2단 흐름 배치 문단의
/// 글줄 앞 배치(#190).
///
/// `numbering-sequence` 쌍(한컴오피스 한글 12.30 macOS 저장본) 3쪽의 표는
/// 세로 기준 '문단'·자리 차지(표 70 `topAndBottom`)·오프셋 0·바깥 여백 283×4다.
/// 한글은 이 표를 품은 문단의 글줄 **앞**에 놓고 문단 줄을 표 높이 + 위·아래
/// 바깥 여백만큼 내리며, 그 결정이 줄 캐시에 남아 있다 — 구역 2에서 `4.` 줄이
/// 3200에서 끝나는데 표를 품은 문단의 줄은 5048에서 시작한다(간격 1848 =
/// 표 1282 + 283 × 2). 고치기 전에는 표를 문단 줄 **뒤**에 방출해 다음 문단
/// `6. After table numbered`와 같은 y에서 시작했다(둘 다 165.68pt, 12.82pt 전부 겹침).
///
/// 판정 술어와 경계(2007 계열 저장본·좁은 띠·오프셋)는
/// `HwpKitCoreTests`의 `HwpFloatingTableBandTests`가 합성 입력으로 본다.
final class FixtureFloatingTableBandTests: XCTestCase {
    func testNumberingSequenceTableSitsInTheReservedBandInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
                .appendingPathComponent("numbering-sequence")
                .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            expect(document.pages.count).to(equal(3), description: format)
            let page = document.pages[2]
            let body = page.blocks.filter { $0.role == .body }

            // 문서 순서(= 선택·복사 단위 순서)는 그대로다 — 표는 자기 문단 뒤에 남는다.
            expect(body.map { ($0.attributedString?.string ?? "")
                    .replacingOccurrences(of: "\r", with: "")
            }).to(equal([
                "7. \u{FFFC}\u{FFFC}Section three outline",
                "4. Section three numbered",
                "5. \u{FFFC}",
                "",
                "6. After table numbered",
                "11. Numbered restart nine",
            ]), description: format)

            let table = try XCTUnwrap(body.first { $0.kind == .table })
            let host = try XCTUnwrap(body.first {
                ($0.attributedString?.string ?? "").hasPrefix("5. ")
            })
            let before = try XCTUnwrap(body.first {
                ($0.attributedString?.string ?? "").hasPrefix("4. ")
            })
            let after = try XCTUnwrap(body.first {
                ($0.attributedString?.string ?? "").hasPrefix("6. ")
            })

            // 한글이 비워 둔 띠 134.03~146.85pt (= `4.` 줄 끝 131.20 + 여백 2.83, 높이 12.82).
            expect(table.frame.minY).to(beCloseTo(134.03, within: 0.01), description: format)
            expect(table.frame.maxY).to(beCloseTo(146.85, within: 0.01), description: format)
            expect(table.frame.minY)
                .to(beCloseTo(before.frame.maxY + 2.83, within: 0.01), description: format)
            // 문단 줄과 다음 문단은 캐시 자리 그대로다.
            expect(host.frame.minY).to(beCloseTo(149.68, within: 0.01), description: format)
            expect(after.frame.minY).to(beCloseTo(165.68, within: 0.01), description: format)
            // 표는 어떤 본문 블록과도 겹치지 않는다 (고치기 전 `6.`과 12.82pt 겹쳤다).
            for block in body where block.kind != .table {
                expect(table.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01)))
                    .to(beFalse(), description: "\(format) \(block.attributedString?.string ?? "")")
            }
        }
    }

    /// 2단 문서의 자리 차지 표는 문단 글줄 **앞**에 흐름으로 놓인다 (#190).
    ///
    /// `line-shapes` 쌍(한글 12.30 저장본)은 2단이고 마지막 문단이 17행 표와 `table anchor`
    /// 글줄을 품는다. 다단 밴드는 절대 캐시 모드라도 흐름 배치를 타므로 띠 판정이 아니라
    /// 표 → 글줄 순서 자체가 답이다. 한글 PDF 실측(2026-09-16, 글자 baseline, 쪽 상단 기준
    /// pt): 1단 첫 행 `border SOLID` 672.00 · 7행째 `border CIRCLE` 748.92 · 2단 첫 행
    /// `border DOUBLE_SLIM` 111.96 · `table anchor` 241.56. 우리 블록에서 같은 baseline은
    /// 표 상단 + 셀 위 여백 1.41 + 0.85 × 10pt = 662.03 + 9.91 = 671.94 / 102.03 + 9.91 =
    /// 111.94 / 글줄 상단 233.06 + 8.5 = 241.56이라 0.06pt 안이다 (캐시 `vertpos` 13386 =
    /// 233.06 − 99.20 = 133.86pt 도 같다). 고치기 전에는 글줄을 1단 659.20에 먼저 놓고 표를
    /// 6행/11행으로 갈랐다. 남은 격차는 표 x의 바깥 왼쪽 여백 2.83pt(#161부터)뿐이다.
    func testLineShapesTablePrecedesItsParagraphLineAcrossColumnsInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
                .appendingPathComponent("line-shapes")
                .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            expect(document.pages.count).to(equal(1), description: format)
            let body = document.pages[0].blocks.filter { $0.role == .body }
            let tables = body.filter { $0.kind == .table }
            expect(tables.count).to(equal(2), description: format)
            guard tables.count == 2 else { continue }
            let host = try XCTUnwrap(body.first {
                ($0.attributedString?.string ?? "").contains("table anchor")
            })
            let before = try XCTUnwrap(body.first {
                ($0.attributedString?.string ?? "").hasPrefix("strikeout REV3D")
            })

            // 블록 순서: 표 두 조각이 글줄 앞이다.
            let hostIndex = try XCTUnwrap(body.firstIndex { $0 == host })
            for table in tables {
                expect(try XCTUnwrap(body.firstIndex { $0 == table }))
                    .to(beLessThan(hostIndex), description: format)
            }
            // 1단 조각: 앞 문단 끝 659.20 + 위 여백 2.83 = 662.03, 7행 89.74pt.
            expect(tables[0].frame.minX)
                .to(beCloseTo(before.frame.minX, within: 0.01), description: format)
            expect(tables[0].frame.minY)
                .to(beCloseTo(before.frame.maxY + 2.83, within: 0.01), description: format)
            expect(tables[0].frame.minY).to(beCloseTo(662.03, within: 0.01), description: format)
            expect(tables[0].frame.height).to(beCloseTo(89.74, within: 0.01), description: format)
            // 2단 조각: 단 상단 99.20 + 위 여백 2.83, 10행 128.20pt.
            expect(tables[1].frame.minX).to(beCloseTo(303.31, within: 0.01), description: format)
            expect(tables[1].frame.minY).to(beCloseTo(102.03, within: 0.01), description: format)
            expect(tables[1].frame.height).to(beCloseTo(128.20, within: 0.01), description: format)
            // 글줄: 2단의 표 아래 + 아래 여백 = 233.06 (한글 캐시 vertpos 13386).
            expect(host.frame.minX).to(beCloseTo(303.31, within: 0.01), description: format)
            expect(host.frame.minY)
                .to(beCloseTo(tables[1].frame.maxY + 2.83, within: 0.01), description: format)
            expect(host.frame.minY).to(beCloseTo(233.06, within: 0.01), description: format)
        }
    }
}
