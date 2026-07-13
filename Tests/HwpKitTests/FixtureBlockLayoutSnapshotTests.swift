@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 다중 페이지 블록 좌표 스냅샷 — 페이지 절단·각주 이월·표 분할·다단 배치의
/// 회귀 가드. fidelity(PrvImage MAE)가 1페이지만 보는 사각을 메운다.
///
/// 좌표는 0.1pt 단위 정수로 반올림해 부동소수 노이즈를 흡수하고, 줄 단위
/// 이동(수 pt)은 확실히 검출한다. 좌표가 설치 폰트 메트릭에 의존하는 환경
/// 의존 테스트라 기본 `swift test`·CI에서는 skip된다. 실행:
/// `HWP_SNAPSHOT_TESTS=1 swift test --filter FixtureBlockLayout`
/// 스냅샷 갱신 (RECORD_* 변수는 자동 opt-in):
/// `RECORD_BLOCK_SNAPSHOTS=1 swift test --filter FixtureBlockLayout`
/// (레코딩 후 의도적으로 실패해 우발적 갱신을 막는다 — diff를 리뷰할 것).
final class FixtureBlockLayoutSnapshotTests: XCTestCase {
    /// (픽스처, 스냅샷할 페이지 — nil이면 전체)
    private static let specs: [(fixture: String, samplePages: [Int]?)] = [
        ("footnote-endnote", nil), // 2쪽 — 각주 이월·미주
        ("multi-section", nil), // 2쪽 — 구역 전환
        ("noori", nil), // 3쪽 — 표 분할·셀 그림·다단
        // 1,030쪽 절대 캐시 — 표본만 (p484-485는 셀 각주 귀속 실측 지점)
        ("legacy-common-control-property", [0, 250, 484, 485, 1029]),
    ]

    func testBlockLayoutMatchesSnapshots() async throws {
        try EnvironmentSensitiveTests.skipUnlessOptedIn(
            recordVariables: ["RECORD_BLOCK_SNAPSHOTS"]
        )

        let record = EnvironmentSensitiveTests.isEnabled("RECORD_BLOCK_SNAPSHOTS")
        var failures: [String] = []
        var recorded: [String] = []

        for spec in Self.specs {
            let documentURL = FixtureRoot.url(from: #file)
                .appendingPathComponent(spec.fixture)
                .appendingPathComponent("document.hwp")
            let document = try await HwpDocumentLoader().load(from: documentURL)
            let actual = Self.snapshot(
                of: document,
                fixture: spec.fixture,
                samplePages: spec.samplePages
            )
            let snapshotURL = Self.snapshotURL(for: spec.fixture)

            if record {
                try Self.write(actual, to: snapshotURL)
                recorded.append(spec.fixture)
                continue
            }

            guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
                failures.append(
                    "[\(spec.fixture)] 스냅샷 없음 — RECORD_BLOCK_SNAPSHOTS=1로 생성"
                )
                continue
            }
            let expected = try JSONDecoder().decode(
                BlockSnapshotDocument.self,
                from: Data(contentsOf: snapshotURL)
            )
            failures.append(contentsOf: Self.differences(
                fixture: spec.fixture,
                expected: expected,
                actual: actual
            ))
        }

        if record {
            fail(
                "블록 스냅샷 레코딩 완료 (\(recorded.joined(separator: ", "))) — "
                    + "diff 리뷰 후 RECORD_BLOCK_SNAPSHOTS 없이 재실행"
            )
            return
        }
        if !failures.isEmpty {
            fail("블록 레이아웃 회귀 (\(failures.count)):\n" + failures.joined(separator: "\n"))
        }
    }

    // MARK: - 스냅샷 생성

    private static func snapshot(
        of document: HwpDocument,
        fixture: String,
        samplePages: [Int]?
    ) -> BlockSnapshotDocument {
        let pageIndexes = samplePages ?? Array(document.pages.indices)
        let pages = pageIndexes.compactMap { pageIndex -> BlockPageSnapshot? in
            guard document.pages.indices.contains(pageIndex) else { return nil }
            let page = document.pages[pageIndex]
            let blocks = page.blocks.enumerated().map { blockIndex, block in
                BlockSnapshot(
                    index: blockIndex,
                    kind: block.kind.rawValue,
                    role: block.role.rawValue,
                    frame: [
                        deciPoints(block.frame.origin.x),
                        deciPoints(block.frame.origin.y),
                        deciPoints(block.frame.size.width),
                        deciPoints(block.frame.size.height),
                    ],
                    payload: payloadName(of: block),
                    textPrefix: textPrefix(of: block),
                    textLength: block.attributedString?.length
                )
            }
            return BlockPageSnapshot(page: pageIndex, blocks: blocks)
        }
        return BlockSnapshotDocument(
            fixture: fixture,
            pageCount: document.pages.count,
            pages: pages
        )
    }

    /// 0.1pt 단위 정수 (부동소수 인코딩 차이 원천 제거)
    private static func deciPoints(_ value: CGFloat) -> Int {
        Int((value * 10).rounded())
    }

    private static func payloadName(of block: AnyHwpBlock) -> String {
        switch block.payload {
        case .table: "table"
        case .textbox: "textbox"
        case .footnote: "footnote"
        case .shape: "shape"
        case .image: "image"
        case .chart: "chart"
        case nil: "none"
        }
    }

    private static func textPrefix(of block: AnyHwpBlock) -> String? {
        guard let string = block.attributedString?.string else { return nil }
        let cleaned = string.filter { $0 != "\u{FFFC}" && $0 != "\n" && $0 != "\r" }
        return String(cleaned.prefix(8))
    }

    // MARK: - 비교·기록

    private static func differences(
        fixture: String,
        expected: BlockSnapshotDocument,
        actual: BlockSnapshotDocument
    ) -> [String] {
        var failures: [String] = []
        if expected.pageCount != actual.pageCount {
            failures.append(
                "[\(fixture)] pageCount \(actual.pageCount) != 스냅샷 \(expected.pageCount)"
            )
        }
        let expectedPages = Dictionary(
            uniqueKeysWithValues: expected.pages.map { ($0.page, $0) }
        )
        for actualPage in actual.pages {
            guard let expectedPage = expectedPages[actualPage.page] else {
                failures.append("[\(fixture)] p\(actualPage.page) 스냅샷에 없음")
                continue
            }
            if expectedPage.blocks.count != actualPage.blocks.count {
                failures.append(
                    "[\(fixture)] p\(actualPage.page) 블록 수 "
                        + "\(actualPage.blocks.count) != 스냅샷 \(expectedPage.blocks.count)"
                )
            }
            for (expectedBlock, actualBlock) in zip(expectedPage.blocks, actualPage.blocks)
                where expectedBlock != actualBlock
            {
                failures.append(
                    "[\(fixture)] p\(actualPage.page) 블록#\(actualBlock.index): "
                        + "\(actualBlock) != 스냅샷 \(expectedBlock)"
                )
                if failures.count > 20 {
                    failures.append("[\(fixture)] … (이후 생략)")
                    return failures
                }
            }
        }
        return failures
    }

    private static func snapshotURL(for fixture: String) -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("BlockSnapshots")
            .appendingPathComponent("\(fixture).json")
    }

    private static func write(_ snapshot: BlockSnapshotDocument, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url)
    }
}

// MARK: - 스냅샷 모델

private struct BlockSnapshotDocument: Codable, Equatable {
    let fixture: String
    let pageCount: Int
    let pages: [BlockPageSnapshot]
}

private struct BlockPageSnapshot: Codable, Equatable {
    let page: Int
    let blocks: [BlockSnapshot]
}

private struct BlockSnapshot: Codable, Equatable, CustomStringConvertible {
    let index: Int
    let kind: String
    let role: String
    /// [x, y, w, h] — 0.1pt 단위 정수
    let frame: [Int]
    let payload: String
    let textPrefix: String?
    let textLength: Int?

    var description: String {
        let frameText = frame.map { String(format: "%.1f", Double($0) / 10) }
            .joined(separator: ",")
        return "\(kind)/\(role)/\(payload) frame=[\(frameText)] "
            + "text='\(textPrefix ?? "")'(\(textLength.map(String.init) ?? "-"))"
    }
}
