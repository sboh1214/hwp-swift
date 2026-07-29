// 기준선을 **커밋해** CI와 다른 기여자 머신에서 함께 도는 렌더 골든 (#69).
// iOS 시뮬레이터는 호스트 파일시스템의 폰트를 읽어 재현이 안 되므로
// (`ci.yml`의 iOS 잡이 같은 번들을 돌린다) macOS 전용으로 못박는다.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import HwpKit
    import HwpKitCore
    import Nimble
    import XCTest

    /// 폰트 독립 결정론 골든 — 양자화 잉크 그리드로 페이지 2 이후의 레이아웃
    /// 회귀를 CI에서 상시 잡는다.
    ///
    /// 다른 렌더 가드와의 역할 분담:
    /// - `FixtureRenderHashSnapshotTests` — 엄격·비이동 축 (전 픽스처 × 전 페이지
    ///   픽셀 SHA-256). 기준선이 머신 종속이라 커밋하지 못하고 CI에서 돌지 않는다.
    /// - `FixturePreviewFidelityTests` — 정합성 축 (PrvImage 오라클). **1페이지뿐**.
    /// - 이 스위트 — 관대·이동 가능 축. 기준선이 **커밋되고 CI에서 상시 돈다**.
    ///   임계를 여유 있게 잡아 서브픽셀·글리프 잔차는 흡수하고, 줄 단위 이동·
    ///   장식 소실·색 반전 같은 실질 회귀만 잡는다.
    ///
    /// 결정론의 근거는 `HwpFontResolver.testDeterministic` — 폰트 조회 세 축
    /// (시스템 등록 폰트·한컴 번들·문서 대체 글꼴)을 모두 닫아 설치 폰트와
    /// 무관하게 같은 CTFont가 나온다. 완전하지는 않다: Menlo에 한글 글리프가
    /// 없어 한글 폴백이 OS 캐스케이드에 맡겨지므로 macOS 버전 간 잔차가 남는다.
    /// 임계와 그리드 해상도가 그 잔차를 흡수하는 몫이다.
    ///
    /// 갱신: `RECORD_RENDER_GOLDENS=1 swift test --filter FixtureRenderGolden`
    /// (레코딩 후 의도적으로 실패한다 — 블록 스냅샷과 같은 패턴. diff를 리뷰할 것.)
    /// **`skipUnlessOptedIn`을 걸지 않는다** — 기본 `swift test`·CI에서 도는 것이
    /// 이 스위트의 존재 이유다.
    final class FixtureRenderGoldenTests: XCTestCase {
        /// 대조 대상 (픽스처, 0-based 페이지 인덱스 — 블록 스냅샷과 같은 규약).
        /// PrvImage 오라클이 닿지 않는 2쪽 이후만 고른다 — 1쪽은 fidelity가 본다.
        /// legacy 1,030쪽은 로드 비용 때문에 제외한다 (블록 스냅샷이 표본으로 본다).
        ///
        /// `noori` p3(인덱스 2)는 #91이 정리된 뒤 합류시켰다 — 붙임 표가 선언
        /// 높이의 29%(181.6pt)로 접혀 셀 그림이 아래 행들을 덮던 페이지다. 지금은
        /// 표 블록이 문서 선언·한글 캐시와 같은 627.0pt로 조판되므로, 그 값을
        /// 잃는 회귀를 이 골든이 잡는다.
        private static let specs: [(fixture: String, pages: [Int])] = [
            ("footnote-endnote", [1]), // 미주 페이지
            ("multi-section", [1]), // 구역 전환
            ("noori", [1, 2]), // 표 분할·다단 본문 / 셀 안 떠 있는 그림 (#91)
        ]

        /// 렌더 폭 (px). 페이지 종횡비를 유지해 높이를 정한다.
        private static let renderWidth = 850

        /// 잉크 그리드 해상도 — 셀 하나가 대략 35×36px이라 줄 단위 이동은
        /// 확실히 잡고 글리프 모양 차이는 평균에 묻힌다.
        private static let columns = 24
        private static let rows = 32

        /// 잉크 값 양자화 단위 — 0 = 백지, 1000 = 전부 검정 (천분율 정수).
        /// JSON을 diff 가능한 정수로 유지하고 부동소수 인코딩 차를 없앤다.
        private static let inkScale = 1000.0

        /// 이중 임계 — **전역**은 페이지 잉크량에, **국소**는 그 셀 자신의 잉크에
        /// 비례한다. 절대 임계로는 대상 페이지의 밀도 차를 감당할 수 없다:
        /// `noori` p2는 셀 768개 중 369개에 잉크 총합 45,290인데 `multi-section`
        /// p2는 "tw" 두 글자뿐이라 총합 42다. 후자에 맞춘 절대 임계는 전자에서
        /// 무의미하고, 전자에 맞추면 후자는 **내용이 통째로 사라져도 통과한다**.
        ///
        /// - total: 셀별 차의 합 (전역 이동·밀도 변화·색 반전)
        /// - cell: 한 셀의 차 (국소 소실·줄 단위 이동)
        ///
        /// **국소 임계를 페이지 최대 셀에서 뽑으면 안 된다.** 그러면 `noori` p2의
        /// 임계가 최대 셀 295의 35% = 103으로 전 셀에 고정돼, 잉크가 그보다 옅은
        /// 셀은 전량 소실돼도 국소 검사를 통과한다 — 하위 비영 100셀 (합 4,174,
        /// 최대 95)이 통째로 사라져도 전역(5,435)·국소(103)이 함께 통과했고,
        /// 경계를 밀면 112셀 (비영 셀의 30.4%)까지 지워진다. 표 테두리처럼 얇은
        /// 장식이 정확히 이 사각에 들어가는데 그 소실을 잡는 것이 이 스위트의
        /// 목적이므로, 임계는 `max(expected, actual)` — 그 셀 자신의 잉크 — 에서
        /// 뽑는다 (max는 소실과 신설을 같은 잣대로 보기 위해서다).
        ///
        /// 절대 하한은 거의 백지인 셀에서 비율이 0으로 수렴해 안티앨리어싱
        /// 잔차에도 빨개지는 것을 막는다. 대상 3장 중 잉크가 옅은 2장은 본문이
        /// 라틴 문자뿐이라 Menlo로 완결되고 (한글 캐스케이드를 타지 않는다)
        /// 실측 잔차가 거의 0이므로, 하한을 낮게 잡아도 안전하다. 대신 잉크가
        /// 하한 이하인 셀 (noori p2에 10개)은 전량 소실이 여전히 안 잡힌다 —
        /// 하한을 더 낮추면 CI 잔차에 빨개지므로 남겨 둔 사각이다.
        ///
        /// **CI 미캘리브레이션 값이다** — 로컬은 같은 머신이라 차가 0이고,
        /// macos-latest 러너의 실제 잔차는 CI 왕복으로만 잴 수 있다 (#69 위험 4).
        /// 셀별 국소 임계는 **타이트하다** (잉크 20인 셀은 8만 흔들려도 실패) —
        /// 위양성은 전역보다 여기서 먼저 난다. 초과하면 비율을 무한정 올리지
        /// 말고 대상 페이지를 줄이는 쪽을 택할 것.
        private static let totalDifferenceShare = 0.12
        private static let cellDifferenceShare = 0.35
        private static let totalDifferenceFloor = 24
        private static let cellDifferenceFloor = 8

        func testRenderGoldensMatchBaseline() async throws {
            let record = EnvironmentSensitiveTests.isEnabled("RECORD_RENDER_GOLDENS")
            var failures: [String] = []
            var recorded: [String] = []

            for spec in Self.specs {
                let actual = try await Self.golden(for: spec)
                let url = Self.goldenURL(for: spec.fixture)

                if record {
                    try Self.write(actual, to: url)
                    recorded.append(spec.fixture)
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    failures.append(
                        "[\(spec.fixture)] 골든 없음 — RECORD_RENDER_GOLDENS=1로 생성"
                    )
                    continue
                }
                let expected = try JSONDecoder().decode(
                    GoldenDocument.self, from: Data(contentsOf: url)
                )
                failures.append(contentsOf: Self.differences(expected: expected, actual: actual))
            }

            if record {
                fail(
                    "렌더 골든 레코딩 완료 (\(recorded.joined(separator: ", "))) — "
                        + "diff 리뷰 후 RECORD_RENDER_GOLDENS 없이 재실행"
                )
                return
            }
            if !failures.isEmpty {
                fail("렌더 골든 회귀 (\(failures.count)):\n" + failures.joined(separator: "\n"))
            }
        }

        // MARK: - 골든 생성

        private static func golden(
            for spec: (fixture: String, pages: [Int])
        ) async throws -> GoldenDocument {
            let documentURL = FixtureRoot.url(from: #file)
                .appendingPathComponent(spec.fixture)
                .appendingPathComponent("document.hwp")
            // 기기 독립의 전부가 이 한 줄이다 — 기본 resolver로 뜨면 설치 폰트에
            // 따라 골든이 갈려 공유 안전망이 아니라 공유 민폐가 된다.
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: documentURL)

            var pages: [GoldenPage] = []
            for pageIndex in spec.pages {
                guard document.pages.indices.contains(pageIndex) else {
                    throw GoldenError.pageMissing(fixture: spec.fixture, page: pageIndex)
                }
                let page = document.pages[pageIndex]
                let height = max(
                    1,
                    Int((CGFloat(renderWidth) * page.size.height / page.size.width).rounded())
                )
                let image = try await FixturePreview.renderImage(
                    page: page,
                    imageStore: document.imageStore,
                    pixelWidth: renderWidth,
                    pixelHeight: height
                )
                let grid = try FixturePreview.inkGrid(
                    of: image,
                    width: renderWidth,
                    height: height,
                    columns: columns,
                    rows: rows
                )
                pages.append(GoldenPage(
                    page: pageIndex,
                    width: renderWidth,
                    height: height,
                    ink: grid.map { Int(($0 * inkScale).rounded()) }
                ))
            }
            return GoldenDocument(
                fixture: spec.fixture,
                formatVersion: 1,
                columns: columns,
                rows: rows,
                pageCount: document.pages.count,
                pages: pages
            )
        }

        // MARK: - 비교

        private static func differences(
            expected: GoldenDocument,
            actual: GoldenDocument
        ) -> [String] {
            let fixture = actual.fixture
            guard expected.formatVersion == actual.formatVersion,
                  expected.columns == actual.columns,
                  expected.rows == actual.rows
            else {
                return ["[\(fixture)] 골든 포맷/그리드 불일치 — 전체 재레코딩 필요"]
            }
            var failures: [String] = []
            if expected.pageCount != actual.pageCount {
                failures.append(
                    "[\(fixture)] pageCount \(actual.pageCount) != 골든 \(expected.pageCount)"
                )
            }
            let expectedPages = Dictionary(
                uniqueKeysWithValues: expected.pages.map { ($0.page, $0) }
            )
            for actualPage in actual.pages {
                guard let expectedPage = expectedPages[actualPage.page] else {
                    failures.append("[\(fixture)] p\(actualPage.page) 골든에 없음")
                    continue
                }
                if expectedPage.width != actualPage.width
                    || expectedPage.height != actualPage.height
                {
                    failures.append(
                        "[\(fixture)] p\(actualPage.page) 렌더 크기 "
                            + "\(actualPage.width)x\(actualPage.height) != "
                            + "골든 \(expectedPage.width)x\(expectedPage.height)"
                    )
                    continue
                }
                if let failure = compare(
                    fixture: fixture, expected: expectedPage, actual: actualPage
                ) {
                    failures.append(failure)
                }
            }
            return failures
        }

        /// 자기 임계를 가장 크게 넘긴 셀. 임계가 셀마다 다르므로 raw 차가 가장
        /// 큰 셀과 다를 수 있고, 위반을 판정하는 것은 초과분 쪽이다.
        private struct WorstCell {
            var overage = Int.min
            var difference = 0
            var allowance = 0
            var index = 0
        }

        /// 이중 임계 — 어느 쪽을 넘겼는지와 최악 셀 좌표를 함께 찍는다
        /// (그리드 좌표만으로도 페이지의 어느 대역이 움직였는지 짚인다).
        private static func compare(
            fixture: String,
            expected: GoldenPage,
            actual: GoldenPage
        ) -> String? {
            guard expected.ink.count == actual.ink.count else {
                return "[\(fixture)] p\(actual.page) 셀 수 불일치 — 재레코딩 필요"
            }
            var total = 0
            var worst = WorstCell()
            for (index, pair) in zip(expected.ink, actual.ink).enumerated() {
                let difference = abs(pair.0 - pair.1)
                total += difference
                let cellAllowance = allowance(
                    share: cellDifferenceShare,
                    floor: cellDifferenceFloor,
                    of: max(pair.0, pair.1)
                )
                if difference - cellAllowance > worst.overage {
                    worst = WorstCell(
                        overage: difference - cellAllowance,
                        difference: difference,
                        allowance: cellAllowance,
                        index: index
                    )
                }
            }
            let totalAllowance = allowance(
                share: totalDifferenceShare,
                floor: totalDifferenceFloor,
                of: expected.ink.reduce(0, +)
            )
            let withinTotal = total <= totalAllowance
            let withinCell = worst.overage <= 0
            guard !withinTotal || !withinCell else { return nil }

            let column = worst.index % columns
            let row = worst.index / columns
            return "[\(fixture)] p\(actual.page) 잉크 총차 \(total)/\(totalAllowance)"
                + (withinTotal ? " (통과)" : " (초과)")
                + ", 최악 셀 (\(column),\(row)) 차 \(worst.difference)/\(worst.allowance)"
                + (withinCell ? " (통과)" : " (초과)")
                + " — 천분율. HWP_ALLPAGES=\(fixture) HWP_ALLPAGES_DIR=<dir> "
                + "swift test --filter testDumpAllPages 로 육안 확인"
        }

        private static func allowance(share: Double, floor: Int, of reference: Int) -> Int {
            max(floor, Int((Double(reference) * share).rounded()))
        }

        // MARK: - 경로·기록

        private static func goldenURL(for fixture: String) -> URL {
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .appendingPathComponent("RenderGoldens")
                .appendingPathComponent("\(fixture).json")
        }

        private static func write(_ golden: GoldenDocument, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(golden).write(to: url)
        }
    }

    // MARK: - 모델

    private enum GoldenError: Error, CustomStringConvertible {
        case pageMissing(fixture: String, page: Int)

        var description: String {
            switch self {
            case let .pageMissing(fixture, page):
                "[\(fixture)] p\(page)가 렌더되지 않았다 — 결정론 resolver의 페이지 수 변화?"
            }
        }
    }

    private struct GoldenDocument: Codable, Equatable {
        let fixture: String
        let formatVersion: Int
        let columns: Int
        let rows: Int
        let pageCount: Int
        let pages: [GoldenPage]
    }

    private struct GoldenPage: Codable, Equatable {
        /// 0-based 페이지 인덱스 (블록 스냅샷·렌더 해시와 같은 규약)
        let page: Int
        let width: Int
        let height: Int
        /// 셀별 평균 잉크 × 1000 (row-major, columns×rows)
        let ink: [Int]
    }

#endif
