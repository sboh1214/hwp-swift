@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 표 행 높이의 실물 핀 (#160).
///
/// `numbering-sequence` 쌍(한컴오피스 한글 12.30 macOS 저장본)은 3쪽 1×2 표의
/// 셀 높이(표 80)를 위아래 안쪽 여백 합 282 HWPUNIT로 저장했다 — 줄 높이가 들지
/// 않은 값이라 그대로 믿으면 행이 2.82pt로 접혀 셀 글자가 다음 문단과 겹친다.
/// 한글.app은 줄 1000 + 여백 282 = 12.82pt(표 공통 속성 height 1282)로 그린다.
/// 블록 순서와 절대 y는 #161에서 바뀔 수 있어 여기서 고정하지 않는다.
final class FixtureTableRowHeightTests: XCTestCase {
    func testNumberingSequenceTableRowIsLineBoxPlusMarginsInBothFormats() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
                .appendingPathComponent("numbering-sequence")
                .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: url)
            let tables = document.pages.flatMap(\.blocks).compactMap { block -> HwpTableFrame? in
                guard case let .table(frame)? = block.payload else { return nil }
                return frame
            }
            expect(tables.count).to(equal(1), description: format)
            guard let table = tables.first else { continue }
            expect(table.rows.count).to(equal(1), description: format)
            expect(table.rows.first?.rowFrame.height ?? 0)
                .to(beCloseTo(12.82, within: 0.01), description: format)
            expect(table.outerFrame.height)
                .to(beCloseTo(12.82, within: 0.01), description: format)
            let cells = table.rows.first?.cells ?? []
            expect(cells.count).to(equal(2), description: format)
            for cell in cells {
                expect(cell.cellFrame.height)
                    .to(beCloseTo(12.82, within: 0.01), description: format)
                // 셀 글자는 위 여백 1.41pt 아래에서 시작해 셀 안에 있다.
                let paragraph = cell.paragraphs.first
                expect(paragraph?.rect.minY ?? -1)
                    .to(beCloseTo(cell.cellFrame.minY + 1.41, within: 0.01), description: format)
            }
            expect(cells.map { $0.paragraphs.first?.attributedString.string ?? "" })
                .to(equal(["9. Cell one", "10. Cell two"]), description: format)
        }
    }
}
