@testable import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// 프로그레시브 로딩 — 스냅샷 스트림의 형태(첫 스냅샷 조기 도착, 토큰
/// 연속성, 진행률 단조)와 최종 결과가 일괄 로드와 동일함(결정성)을 검증.
final class HwpDocumentLoaderProgressiveTests: XCTestCase {
    func testProgressiveSnapshotsConvergeToFullLoad() async throws {
        // noori: 3쪽 — firstBatch 1이라 최소 (부분 1쪽) + (최종) 2개 스냅샷
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("noori")
            .appendingPathComponent("document.hwp")
        let loader = HwpDocumentLoader()

        var snapshots: [HwpDocumentSnapshot] = []
        for try await snapshot in await loader.loadUpdates(from: url) {
            snapshots.append(snapshot)
        }

        expect(snapshots.count) >= 2
        let first = try XCTUnwrap(snapshots.first)
        expect(first.isComplete) == false
        expect(first.document.pages.count) >= 1

        let final = try XCTUnwrap(snapshots.last)
        expect(final.isComplete) == true
        expect(final.progress) == 1

        // 토큰 연속성 — 모든 스냅샷이 같은 loadToken
        let token = final.document.metadata.loadToken
        expect(token).toNot(beNil())
        expect(Set(snapshots.map(\.document.metadata.loadToken))) == [token]

        // 진행률 단조 비감소
        let progresses = snapshots.compactMap(\.progress)
        expect(progresses) == progresses.sorted()

        // 부분 스냅샷의 페이지는 최종 페이지의 prefix와 동일 (증분 안정)
        expect(Array(final.document.pages.prefix(first.document.pages.count)))
            == first.document.pages

        // 결정성: 최종 스냅샷 == 일괄 로드 결과 (loadToken 제외)
        let full = try await HwpDocumentLoader().load(from: url)
        expect(final.document.pages) == full.pages
        expect(final.document.metadata.pageCount) == full.metadata.pageCount
        expect(final.document.unsupportedElements) == full.unsupportedElements
    }
}
