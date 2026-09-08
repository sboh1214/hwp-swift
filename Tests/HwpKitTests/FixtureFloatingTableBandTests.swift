@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 자리 차지 표의 띠 배치 실물 핀 (#161).
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
}
