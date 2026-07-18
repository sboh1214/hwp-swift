import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

final class HwpProgressiveBatchTests: XCTestCase {
    func testExtremeBatchSizeCompletesWithoutTrapping() async throws {
        // 공개 batchSize의 극단값(.max)이 임계 전진 덧셈을 트랩시키지 않고
        // 스트림이 최종 스냅샷까지 정상 완료되는지 (P2). 기하 간격 확장(P1)도
        // 최종 문서 동등성을 깨지 않는다.
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("plain-text-minimal/document.hwp")
        let actor = HwpDocumentActor()
        var final: HwpDocumentSnapshot?
        for try await snapshot in await actor.loadDocumentUpdates(
            from: url, firstBatch: 1, batchSize: .max
        ) {
            final = snapshot
        }

        let snapshot = try XCTUnwrap(final)
        expect(snapshot.isComplete) == true
        expect(snapshot.document.pages.count) >= 1
    }
}
