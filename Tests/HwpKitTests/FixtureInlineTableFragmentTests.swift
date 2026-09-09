@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 쪽에 걸친 문단의 글자처럼 취급 표 실물 핀 (#164).
///
/// 헌법주석(`legacy-common-control-property`) 구역 24 문단 490은 줄 캐시 14줄이
/// 6/8로 두 쪽(0-기준 665·666)에 갈리고, 테두리 없는 1×1 인용 표 세 개를 글자처럼
/// 취급으로 품는다 — 앞 두 개는 앞 조각 다섯째 줄, 셋째는 뒤 조각 여섯째 줄에 있다.
/// 고치기 전에는 세 표가 뒤 조각 아래(228.29pt부터 11.08pt씩)에 세로로 쌓여 뒤 문단
/// 두 개(228.29·244.29pt)와 겹쳤다. 한컴오피스 한글은 이 표들을 본문 줄 안에 놓는다.
///
/// 판정 술어와 경계(마커 없는 컨트롤·흐름 분할·다단 run)는 `HwpKitCoreTests`의
/// `HwpInlineControlFragmentTests`가 합성 입력으로 본다. 좌표는 결정론 resolver
/// 기준이라 설치 폰트와 무관하다 (블록 스냅샷과 같은 규약).
final class FixtureInlineTableFragmentTests: XCTestCase {
    private static let quotationTableIds: [UInt32] = [1_719_612_748, 1_719_612_749, 1_719_612_750]

    private static func loadPages() async throws -> (first: [AnyHwpBlock], second: [AnyHwpBlock]) {
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("legacy-common-control-property")
            .appendingPathComponent("document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: url)
        expect(document.pages.count) == 1030
        let body = { (index: Int) in document.pages[index].blocks.filter { $0.role == .body } }
        return (body(665), body(666))
    }

    /// 구역 24 문단 490의 텍스트 조각.
    private static func fragment(of blocks: [AnyHwpBlock]) throws -> AnyHwpBlock {
        try XCTUnwrap(blocks.first {
            $0.kind == .text
                && $0.source?.sectionIndex == 24
                && $0.source?.paragraphIndex == 490
        })
    }

    private static func tables(_ id: UInt32, in blocks: [AnyHwpBlock]) -> [AnyHwpBlock] {
        blocks.filter { $0.kind == .table && $0.source?.controlInstanceId == id }
    }

    /// 앞 조각(665쪽): 문단 여섯 줄이 598.41부터, 표 1·2는 그 안 같은 줄에 나란히.
    func testFirstFragmentKeepsItsTwoQuotationTablesInLine() async throws {
        let (first, _) = try await Self.loadPages()
        let fragment = try Self.fragment(of: first)
        expect(fragment.frame.minY).to(beCloseTo(598.41, within: 0.01))
        expect(fragment.frame.maxY).to(beCloseTo(692.49, within: 0.01))
        let table1 = try XCTUnwrap(Self.tables(Self.quotationTableIds[0], in: first).first)
        let table2 = try XCTUnwrap(Self.tables(Self.quotationTableIds[1], in: first).first)
        expect(table1.frame.minY).to(beCloseTo(647.69, within: 0.01))
        expect(table1.frame.height).to(beCloseTo(11.08, within: 0.01))
        expect(table1.frame.minX).to(beCloseTo(365.57, within: 0.01))
        expect(table2.frame.minY).to(beCloseTo(table1.frame.minY, within: 0.01))
        expect(table2.frame.minX).to(beCloseTo(table1.frame.maxX, within: 0.01))
        for table in [table1, table2] {
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(fragment.frame.minY))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(fragment.frame.maxY))
        }
        Self.expectNoOverlap(of: [table1, table2], with: first)
    }

    /// 뒤 조각(666쪽): 여덟 줄이 99.21~228.29, 표 3은 그 안 — 뒤 문단 둘은 캐시 자리
    /// 그대로다 (고치기 전에는 세 표가 228.29부터 쌓여 이 둘과 겹쳤다).
    func testSecondFragmentKeepsItsQuotationTableAboveTheFollowingParagraphs() async throws {
        let (first, second) = try await Self.loadPages()
        let fragment = try Self.fragment(of: second)
        expect(fragment.frame.minY).to(beCloseTo(99.21, within: 0.01))
        expect(fragment.frame.maxY).to(beCloseTo(228.29, within: 0.01))
        let table3 = try XCTUnwrap(Self.tables(Self.quotationTableIds[2], in: second).first)
        expect(table3.frame.minY).to(beCloseTo(164.85, within: 0.01))
        expect(table3.frame.height).to(beCloseTo(11.08, within: 0.01))
        expect(table3.frame.minX).to(beCloseTo(304.10, within: 0.01))
        expect(table3.frame.maxY).to(beLessThanOrEqualTo(fragment.frame.maxY))
        let emptyFollower = try XCTUnwrap(second.first {
            $0.source?.sectionIndex == 24 && $0.source?.paragraphIndex == 491
        })
        let heading = try XCTUnwrap(second.first {
            $0.source?.sectionIndex == 24 && $0.source?.paragraphIndex == 492
        })
        expect(emptyFollower.frame.minY).to(beCloseTo(228.29, within: 0.01))
        expect(heading.frame.minY).to(beCloseTo(244.29, within: 0.01))
        expect(heading.attributedString?.string.hasPrefix("가. 보상기준")) == true
        Self.expectNoOverlap(of: [table3], with: second)
        // 세 표는 두 쪽에 한 번씩만 있다 — 누락도 중복도 없다.
        for id in Self.quotationTableIds {
            expect(Self.tables(id, in: first).count + Self.tables(id, in: second).count) == 1
        }
    }

    /// 표는 자기 문단 조각 말고는 어떤 본문 블록과도 겹치지 않는다.
    private static func expectNoOverlap(of tables: [AnyHwpBlock], with page: [AnyHwpBlock]) {
        for table in tables {
            for block in page where block.kind != .table && block.source?.paragraphIndex != 490 {
                expect(table.frame.intersects(block.frame.insetBy(dx: 0, dy: 0.01)))
                    .to(beFalse(), description: block.attributedString?.string ?? "")
            }
        }
    }
}
