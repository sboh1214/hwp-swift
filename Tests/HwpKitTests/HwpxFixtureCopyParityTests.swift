@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// HWP↔HWPX 변환 쌍의 전체 선택 복사 평문이 같아야 한다 (#145). 빈 문단이 두
/// 포맷에서 같은 앵커로 모이지 않으면(HWP는 PARA_TEXT 없음, HWPX는 문단 끝 코드
/// 13뿐) 빈 줄 수가 갈린다. noori는 2쪽 본문에 빈 문단이 있어 빈 줄이 실제로
/// 복사에 실리는지, 그리고 서로 다른 문단이 한 줄로 붙지 않는지도 직접 핀한다 —
/// 등식만 두면 양쪽이 같은 방식으로 틀려도 통과한다.
final class HwpxFixtureCopyParityTests: XCTestCase {
    func testHwpxFullSelectionCopyMatchesHwpPairs() async throws {
        let hwpxFixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let hwpFixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let hwpByID = Dictionary(uniqueKeysWithValues: hwpFixtures.map { ($0.id, $0) })
        let loader = HwpDocumentLoader(fontResolver: .testDeterministic)

        var failures: [String] = []
        var comparedCount = 0
        var nooriCopy: String?
        for fixture in hwpxFixtures where !fixture.hasExpectedError {
            guard let pairID = fixture.sourceHwpFixture, let pair = hwpByID[pairID],
                  !pair.hasExpectedError
            else { continue }
            comparedCount += 1
            do {
                let hwpx = try await loader.load(from: fixture.documentURL)
                let hwp = try await loader.load(from: pair.documentURL)
                let hwpxText = Self.fullCopy(of: hwpx)
                let hwpText = Self.fullCopy(of: hwp)
                if hwpxText != hwpText {
                    failures.append(
                        "[\(fixture.id)] copy differs: hwpx \(Self.shape(hwpxText))"
                            + " != hwp \(Self.shape(hwpText))"
                    )
                }
                if fixture.id == "noori" {
                    nooriCopy = hwpText
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        // 비교 가능한 변환 쌍 11종 — 하한은 유실 가드
        expect(comparedCount) >= 11
        if !failures.isEmpty {
            fail("HWP↔HWPX copy mismatches (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }

        // noori: 2쪽 본문의 빈 문단이 빈 줄로 실리고 (#145), 본문 문단 10개가
        // 한 줄로 붙던 종전 결과(줄수 12)보다 줄이 많다.
        let noori = try XCTUnwrap(nooriCopy)
        expect(noori).to(contain("\n\n"))
        expect(noori.split(separator: "\n", omittingEmptySubsequences: false).count)
            .to(beGreaterThan(12))
    }

    private static func fullCopy(of document: HwpDocument) -> String {
        let geometry = HwpSelectionGeometry(document: document)
        guard let selection = geometry.documentSelection() else { return "" }
        return geometry.plainText(for: selection)
    }

    private static func shape(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(text.count)자/\(lines)줄"
    }
}
