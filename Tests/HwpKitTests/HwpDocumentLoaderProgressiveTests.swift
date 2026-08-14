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
        expect(final.document.metadata.outline) == full.metadata.outline
    }

    /// 개요·책갈피는 **중간 스냅샷에도** 실린다 (#77) — `unsupportedElements`가
    /// 최종 스냅샷에만 오는 것과 다른 정책이다. 사이드바는 로딩 중에 쓰라고
    /// 있는 물건이라 다 배치될 때까지 비워 두면 쓸모가 없고, 수집이 append-only라
    /// 접두가 최종 목록의 접두로 남아 목록 신원(`ordinal`)이 흔들리지 않는다.
    func testPartialSnapshotsCarryTheOutlinePrefix() async throws {
        // 개요 문단 1,944개가 있는 유일한 픽스처. 1,030쪽이라 중간 스냅샷이
        // 수십 번 오고, 그 각각이 접두여야 한다.
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("legacy-common-control-property")
            .appendingPathComponent("document.hwp")
        let loader = HwpDocumentLoader()

        var snapshots: [HwpDocumentSnapshot] = []
        for try await snapshot in await loader.loadUpdates(from: url) {
            snapshots.append(snapshot)
        }

        let final = try XCTUnwrap(snapshots.last)
        let finalOutline = final.document.metadata.outline
        expect(finalOutline.headings.count) == 1944
        // 부분 스냅샷의 목록은 최종 목록의 prefix이고, 단조 증가한다.
        let partials = snapshots.filter { !$0.isComplete }
        expect(partials.count) >= 2
        var previousCount = 0
        for partial in partials {
            let outline = partial.document.metadata.outline
            expect(outline.count) >= previousCount
            expect(Array(finalOutline.prefix(outline.count))) == outline
            // 그 스냅샷이 담은 쪽 밖을 가리키는 항목은 없다 — 조판은 배치 도중에도
            // 쪽을 확정하므로 수집기가 액터의 `pages`보다 앞선 항목을 이미 들고 있을
            // 수 있고, 그대로 실으면 호스트가 "2 of 1"을 보게 된다.
            expect(outline.map(\.pageNumber).max() ?? 0) <= partial.document.metadata.pageCount
            previousCount = outline.count
        }
        // 중간 스냅샷이 실제로 항목을 들고 왔는지 (전부 비어 있으면 위 접두
        // 단언이 공허하게 통과한다).
        let lastPartialOutline = try XCTUnwrap(partials.last).document.metadata.outline
        expect(lastPartialOutline).toNot(beEmpty())
        expect(lastPartialOutline.count) < finalOutline.count
    }

    /// `unsupportedElements`는 종전 정책 그대로 **최종 스냅샷에만** 온다.
    /// 위 개요 테스트와 짝이 되어 두 정책이 갈린다는 사실을 고정한다 — 개요
    /// 픽스처(헌법주석)는 미지원 요소를 하나도 내지 않아 거기서는 이 단언이
    /// 공허하게 통과한다 (실측: 0건). 수식 픽스처가 그 반대 축이다.
    func testUnsupportedElementsStayFinalOnly() async throws {
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent("equation")
            .appendingPathComponent("document.hwp")
        let loader = HwpDocumentLoader()

        var snapshots: [HwpDocumentSnapshot] = []
        for try await snapshot in await loader.loadUpdates(from: url) {
            snapshots.append(snapshot)
        }

        let final = try XCTUnwrap(snapshots.last)
        let partials = snapshots.filter { !$0.isComplete }

        expect(partials.count) >= 1
        expect(final.document.unsupportedElements).toNot(beEmpty())
        expect(partials.allSatisfy(\.document.unsupportedElements.isEmpty)) == true
    }
}
