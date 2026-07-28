// 기준선은 macOS에서 레코딩한 것 — iOS 시뮬레이터는 호스트 파일시스템이
// 보여서 한컴 폰트·기준선을 찾아 '실행'돼 버리지만, CoreText 렌더가 달라
// 비교가 무의미하다. macOS 전용으로 못박는다.
#if os(macOS)

    import CoreGraphics
    import CryptoKit
    import Foundation
    import HwpKit
    import HwpKitCore
    import XCTest

    /// 전 픽스처 × 전 페이지 픽셀 해시 기준선 — "렌더 결과물이 바뀌지 않았다"를
    /// 픽셀 단위로 보증하는 회귀 가드. fidelity(MAE 임계 여유·1페이지)와 블록
    /// 스냅샷(4개 픽스처 좌표)이 놓치는 미세 변화(색·장식·서브픽셀 이동·
    /// 2페이지 이후)를 잡는다.
    ///
    /// 기준선은 레코딩 머신 전용이므로 커밋하지 않는다 (`Snapshots/`는 gitignore).
    /// 환경 의존 테스트라 기본 `swift test`·CI에서는 skip되고 opt-in으로만 실행된다.
    ///
    /// **폰트 모드마다 기준선이 갈린다** — 한컴 번들 폰트를 켜면 `<id>.json`,
    /// 배포 기본값(끈 상태)이면 `<id>-nohancom.json`. 사용자가 실제로 받는 구성은
    /// 후자이므로 양쪽 다 잠가 둔다. 두 모드를 각각 돌려야 전부 검증된다:
    /// `HWP_SNAPSHOT_TESTS=1 HWP_HANCOM_FONTS=1 swift test --filter FixtureRenderHash`
    /// `HWP_SNAPSHOT_TESTS=1 swift test --filter FixtureRenderHash`
    /// 레코딩(RECORD_* 변수는 자동 opt-in, 현재 폰트 모드의 기준선만 갱신):
    /// `RECORD_RENDER_HASHES=1 swift test --filter FixtureRenderHash`
    /// 특정 픽스처만 갱신: `RECORD_RENDER_HASHES=noori,chart …`
    /// 레코딩은 의도적으로 실패해 우발적 갱신을 막고, 기존 기준선과의 diff를
    /// 출력하며 이전 파일을 `.json.bak`로 백업한다.
    ///
    /// 해시가 다르면 어느 픽스처의 어느 페이지가 변했는지가 찍힌다 — 그 페이지만
    /// `HWP_ALLPAGES` 덤프로 육안 확인하고, 의도된 개선이면 해당 픽스처만
    /// 재레코딩한다. 해시 불일치가 무더기로 나오면 코드보다 환경 변화(macOS
    /// 업그레이드·한컴 폰트 번들 변경)부터 의심할 것.
    final class FixtureRenderHashSnapshotTests: XCTestCase {
        /// 1pt = 1px. 안티앨리어싱 덕에 서브픽셀 이동도 픽셀 값 변화로 드러난다.
        private static let renderScale: CGFloat = 1

        /// 파싱 자체가 거부되는 픽스처 — 이 목록 밖의 로드 실패는 전부 회귀다
        /// (fidelity 스위트의 unparseableFixtureIds와 동일 목록).
        private static let unparseableFixtureIds: Set<String> = [
            "문서암호설정-보안수준높음",
            "문서암호설정-보안수준보통",
            "배포용문서",
            "drm-unsupported-derived",
        ]

        func testRenderHashesMatchBaseline() async throws {
            try EnvironmentSensitiveTests.skipUnlessOptedIn(
                recordVariables: ["RECORD_RENDER_HASHES"]
            )

            // 폰트 모드마다 기준선 파일이 갈린다 (`baselineSuffix`) — opt-in 모드와
            // 배포 기본 모드를 각각 독립적으로 잠근다. 기본 모드가 사용자가 실제로
            // 받는 구성이므로 여기에도 픽셀 가드가 있어야 한다.
            //
            // opt-in을 켰는데 번들 폰트를 못 찾은 경우만 실패시킨다 — 기준선이
            // 있는 레코딩 머신에서 가드가 조용히 무력화되는 상황이기 때문이다.
            // `isEnabled`를 먼저 봐서 off일 때는 `index` 접근 (앱 번들 폰트 파일
            // 열거)이 아예 일어나지 않게 한다.
            if HwpInstalledHancomFonts.isEnabled, HwpInstalledHancomFonts.index.isEmpty {
                let baselines = Self.existingBaselineNames()
                try XCTSkipIf(
                    baselines.isEmpty,
                    "한컴오피스 번들 폰트를 찾지 못함 — 렌더 해시 기준선은 레코딩 머신 전용"
                )
                XCTFail(
                    "기준선 \(baselines.count)개가 있는데 한컴 번들 폰트를 찾지 못함 — "
                        + "한컴오피스 설치/경로 확인 (skip하면 가드가 무력화된다)"
                )
                return
            }

            let mode = RecordMode.fromEnvironment()
            let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
            var failures: [String] = []
            var recorded: [String] = []
            var baselineChanges: [String] = []

            for fixture in fixtures {
                let outcome = try await Self.checkFixture(fixture, mode: mode)
                failures.append(contentsOf: outcome.failures)
                if outcome.recorded {
                    recorded.append(fixture.id)
                    baselineChanges.append(contentsOf: outcome.baselineChanges)
                }
            }
            failures.append(contentsOf: Self.consistencyFailures(
                mode: mode, fixtures: fixtures, recorded: recorded
            ))

            if mode.isActive {
                XCTFail(Self.recordingSummary(
                    recorded: recorded, baselineChanges: baselineChanges, failures: failures
                ))
                return
            }
            if !failures.isEmpty {
                XCTFail("렌더 해시 회귀 (\(failures.count)):\n" + failures.joined(separator: "\n"))
            }
        }

        // MARK: - 픽스처별 레코딩/비교

        private static func checkFixture(
            _ fixture: FixtureCase,
            mode: RecordMode
        ) async throws -> FixtureOutcome {
            let snapshotURL = snapshotURL(for: fixture.id)
            let hasBaseline = FileManager.default.fileExists(atPath: snapshotURL.path)

            let document: HwpDocument
            do {
                document = try await HwpDocumentLoader().load(from: fixture.documentURL)
            } catch {
                return loadFailureOutcome(fixture: fixture, error: error, hasBaseline: hasBaseline)
            }

            let started = Date()
            let actual = try await snapshot(of: document, fixture: fixture.id)
            print(String(
                format: "RENDERHASH %@ pages=%d elapsed=%.1fs",
                fixture.id, actual.pageCount, Date().timeIntervalSince(started)
            ))

            if mode.shouldRecord(fixture.id) {
                let changes = try record(actual, to: snapshotURL, hadBaseline: hasBaseline)
                return FixtureOutcome(failures: [], recorded: true, baselineChanges: changes)
            }
            guard hasBaseline else {
                return FixtureOutcome(failures: [
                    "[\(fixture.id)] 기준선 없음 — RECORD_RENDER_HASHES=\(fixture.id)로 "
                        + "해당 픽스처만 레코딩 (나머지 비교를 유지하려면 =1 전체 레코딩 금지)",
                ])
            }
            let expected: RenderHashSnapshot
            do {
                expected = try JSONDecoder().decode(
                    RenderHashSnapshot.self,
                    from: Data(contentsOf: snapshotURL)
                )
            } catch {
                return FixtureOutcome(failures: [
                    "[\(fixture.id)] 기준선 읽기/디코드 실패 (\(error)) — "
                        + "RECORD_RENDER_HASHES=\(fixture.id)로 재레코딩",
                ])
            }
            return FixtureOutcome(
                failures: differences(fixture: fixture.id, expected: expected, actual: actual)
            )
        }

        /// 로드 실패는 명시적 파싱 거부 목록에 있을 때만 허용된다.
        private static func loadFailureOutcome(
            fixture: FixtureCase,
            error: Error,
            hasBaseline: Bool
        ) -> FixtureOutcome {
            guard unparseableFixtureIds.contains(fixture.id) else {
                return FixtureOutcome(failures: ["[\(fixture.id)] 로드 실패: \(error)"])
            }
            if hasBaseline {
                return FixtureOutcome(failures: [
                    "[\(fixture.id)] 파싱 거부 픽스처에 기준선이 있음 — 오래된 기준선 삭제 필요",
                ])
            }
            return FixtureOutcome(failures: [])
        }

        /// 레코딩 — 기존 기준선은 `.json.bak`로 백업하고 무엇이 바뀌는지 diff를
        /// 돌려준다 (우발 레코딩이 회귀를 조용히 굽는 것을 막는 마지막 안전망).
        private static func record(
            _ actual: RenderHashSnapshot,
            to url: URL,
            hadBaseline: Bool
        ) throws -> [String] {
            guard hadBaseline else {
                try write(actual, to: url)
                return []
            }
            var changes: [String] = []
            if let expected = try? JSONDecoder().decode(
                RenderHashSnapshot.self, from: Data(contentsOf: url)
            ) {
                changes = differences(fixture: actual.fixture, expected: expected, actual: actual)
            } else {
                changes = ["[\(actual.fixture)] 이전 기준선 디코드 불가 — 전체 교체"]
            }
            let backupURL = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: url, to: backupURL)
            try write(actual, to: url)
            return changes
        }

        // MARK: - 스냅샷 생성

        private static func snapshot(
            of document: HwpDocument,
            fixture: String
        ) async throws -> RenderHashSnapshot {
            var pages: [RenderPageHash] = []
            for (index, page) in document.pages.enumerated() {
                let width = max(1, Int((page.size.width * renderScale).rounded()))
                let height = max(1, Int((page.size.height * renderScale).rounded()))
                let image = try await FixturePreview.renderImage(
                    page: page,
                    imageStore: document.imageStore,
                    pixelWidth: width,
                    pixelHeight: height
                )
                pages.append(RenderPageHash(
                    page: index,
                    width: width,
                    height: height,
                    sha256: try sha256Hex(of: image)
                ))
            }
            return RenderHashSnapshot(
                fixture: fixture,
                formatVersion: 1,
                renderScale: Double(renderScale),
                pageCount: document.pages.count,
                pages: pages
            )
        }

        /// 비트맵 바이트 그대로 해시한다 (PNG 인코딩 변동 배제).
        /// renderImage의 컨텍스트는 bytesPerRow = width×4 고정이라 패딩이 없다.
        private static func sha256Hex(of image: CGImage) throws -> String {
            guard let data = image.dataProvider?.data as Data? else {
                throw FixturePreview.RenderError.imageCreationFailed
            }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        // MARK: - 비교·정합 가드

        private static func differences(
            fixture: String,
            expected: RenderHashSnapshot,
            actual: RenderHashSnapshot
        ) -> [String] {
            if expected.renderScale != actual.renderScale
                || expected.formatVersion != actual.formatVersion
            {
                return ["[\(fixture)] 기준선 포맷/배율 불일치 — 전체 재레코딩 필요"]
            }
            var failures: [String] = []
            if expected.pageCount != actual.pageCount {
                failures.append(
                    "[\(fixture)] pageCount \(actual.pageCount) != 기준선 \(expected.pageCount)"
                )
            }
            for (expectedPage, actualPage) in zip(expected.pages, actual.pages)
                where expectedPage != actualPage
            {
                var parts: [String] = []
                if expectedPage.width != actualPage.width
                    || expectedPage.height != actualPage.height
                {
                    parts.append(
                        "크기 \(actualPage.width)x\(actualPage.height) != "
                            + "기준선 \(expectedPage.width)x\(expectedPage.height)"
                    )
                }
                if expectedPage.sha256 != actualPage.sha256 {
                    parts.append(
                        "해시 \(actualPage.sha256.prefix(8)) != 기준선 \(expectedPage.sha256.prefix(8))"
                    )
                }
                failures.append("[\(fixture)] p\(actualPage.page) " + parts.joined(separator: ", "))
                if failures.count >= 20 {
                    failures.append("[\(fixture)] … (이후 생략)")
                    return failures
                }
            }
            return failures
        }

        /// 파싱 거부 목록·선택 레코딩 대상이 실제 픽스처와 어긋나지 않는지.
        private static func consistencyFailures(
            mode: RecordMode,
            fixtures: [FixtureCase],
            recorded: [String]
        ) -> [String] {
            var failures: [String] = []
            let fixtureIds = Set(fixtures.map(\.id))
            for id in unparseableFixtureIds.subtracting(fixtureIds).sorted() {
                failures.append("[\(id)] 파싱 거부 목록이 실제 픽스처에 없음 (개명/삭제?)")
            }
            if case let .selected(ids) = mode {
                for id in ids.subtracting(fixtureIds).sorted() {
                    failures.append("[\(id)] 레코딩 대상이 픽스처에 없음 (오타?)")
                }
                for id in ids.intersection(fixtureIds).subtracting(recorded).sorted() {
                    failures.append("[\(id)] 레코딩 대상인데 레코딩되지 않음 (파싱 거부 픽스처?)")
                }
            }
            return failures
        }

        private static func recordingSummary(
            recorded: [String],
            baselineChanges: [String],
            failures: [String]
        ) -> String {
            var message = "렌더 해시 기준선 레코딩 완료 (\(recorded.count)개: "
                + "\(recorded.joined(separator: ", "))) — "
                + "RECORD_RENDER_HASHES 없이 재실행해 그린을 확인할 것"
            if !baselineChanges.isEmpty {
                message += "\n기존 기준선 대비 변경 (\(baselineChanges.count)) — "
                    + "이전 기준선은 .json.bak로 백업됨:\n"
                    + baselineChanges.joined(separator: "\n")
            }
            if !failures.isEmpty {
                message += "\n비레코딩 픽스처 실패 (\(failures.count)):\n"
                    + failures.joined(separator: "\n")
            }
            return message
        }

        // MARK: - 경로·기록

        /// 리포 루트의 Snapshots/ (gitignore됨 — 이 머신 전용 기준선)
        private static func snapshotsDirectory() -> URL {
            var url = URL(fileURLWithPath: #file).deletingLastPathComponent()
            while url.lastPathComponent != "Tests", url.path != "/" {
                url.deleteLastPathComponent()
            }
            return url.deletingLastPathComponent().appendingPathComponent("Snapshots")
        }

        /// 폰트 모드별 기준선 파일 접미사. 한컴 번들 폰트를 켠 렌더와 끈 렌더는
        /// 글리프가 달라 같은 파일로 잠글 수 없다. opt-in 모드가 기존 이름
        /// (접미사 없음)을 유지해 이미 레코딩된 기준선이 그대로 유효하다.
        private static var baselineSuffix: String {
            HwpInstalledHancomFonts.isEnabled ? "" : "-nohancom"
        }

        private static func snapshotURL(for fixture: String) -> URL {
            snapshotsDirectory().appendingPathComponent("\(fixture)\(baselineSuffix).json")
        }

        private static func existingBaselineNames() -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(
                atPath: snapshotsDirectory().path
            )) ?? []
            let suffix = "\(baselineSuffix).json"
            return names.filter { $0.hasSuffix(suffix) }
                // 접미사 없는 모드에서는 다른 모드의 파일이 섞이지 않게 걸러낸다
                .filter { baselineSuffix.isEmpty ? !$0.hasSuffix("-nohancom.json") : true }
        }

        private static func write(_ snapshot: RenderHashSnapshot, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url)
        }
    }

    // MARK: - 픽스처별 결과

    private struct FixtureOutcome {
        let failures: [String]
        var recorded = false
        /// 레코딩이 기존 기준선을 덮어쓸 때의 diff (우발 레코딩 감사 로그)
        var baselineChanges: [String] = []
    }

    // MARK: - 레코딩 모드

    private enum RecordMode {
        case off
        case all
        case selected(Set<String>)

        static func fromEnvironment() -> RecordMode {
            guard EnvironmentSensitiveTests.isEnabled("RECORD_RENDER_HASHES"),
                  let raw = ProcessInfo.processInfo.environment["RECORD_RENDER_HASHES"]
            else { return .off }
            if raw == "1" || raw.lowercased() == "all" {
                return .all
            }
            return .selected(Set(
                raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ))
        }

        var isActive: Bool {
            if case .off = self {
                return false
            }
            return true
        }

        func shouldRecord(_ fixtureId: String) -> Bool {
            switch self {
            case .off: false
            case .all: true
            case let .selected(ids): ids.contains(fixtureId)
            }
        }
    }

    // MARK: - 스냅샷 모델

    private struct RenderHashSnapshot: Codable {
        let fixture: String
        let formatVersion: Int
        let renderScale: Double
        let pageCount: Int
        let pages: [RenderPageHash]
    }

    private struct RenderPageHash: Codable, Equatable {
        /// 0-based 페이지 인덱스 (블록 스냅샷과 동일 규약)
        let page: Int
        let width: Int
        let height: Int
        /// 비트맵 (RGBA8, premultipliedLast, width×4 stride) 바이트의 SHA-256
        let sha256: String
    }

#endif
