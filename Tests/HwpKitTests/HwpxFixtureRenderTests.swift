@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// HWPX 변환 쌍 픽스처(`Tests/CoreHwpTests/HwpxFixtures/<id>/document.hwpx`)를
/// **뷰어 계층**으로 연다 — `HwpDocumentLoader` → `HwpFile` 선두 바이트 자동
/// 감지, Sample 앱과 같은 경로다. CoreHwp의 `HwpxHwpEquivalenceTests`는 파싱
/// 투영만 비교하고 조판 캐시(`<hp:linesegarray>`)는 비교에서 제외하므로, 그
/// 캐시가 폐기돼 reflow로 강등되는 회귀는 여기 쪽수 가드만이 잡는다.
///
/// 쪽수는 `.testDeterministic` resolver로 폰트 축을 닫는다 — HWP 쪽
/// `testPageCountsMatchManifest`(#69)와 같은 근거다.
final class HwpxFixtureRenderTests: XCTestCase {
    /// manifest `expectations.pageCount`(출처는 `pageCountSource`)와 실제 렌더
    /// 쪽수가 정확히 일치해야 한다.
    ///
    /// 핀은 **파싱 가능한 픽스처 전부**에 강제한다 — 하한(`>= 10`)만 두면
    /// `pageCount` 없는 새 픽스처가 조판 캐시 회귀 가드에서 조용히 빠진다.
    /// 등식만 두면 반대로 픽스처가 전부 유실돼도 0 == 0으로 통과하므로 하한도
    /// 남긴다. `expectedError` 픽스처(암호·배포용·DRM)는 HWP 하니스가 33종 중
    /// 29종만 요구하는 것과 같은 이유로 분모에서 뺀다.
    func testHwpxPageCountsMatchManifest() async throws {
        let fixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let parseable = fixtures.filter { !$0.hasExpectedError }
        let withPageCount = parseable.filter { $0.expectedPageCount != nil }
        // 픽스처 유실 가드 — 변환 쌍 10종
        expect(fixtures.count) >= 10
        // 파싱 가능한 픽스처는 전부 pageCount 핀이 있어야 한다 (AGENTS.md "HWPX 픽스처 추가")
        expect(withPageCount.count) == parseable.count
        for fixture in withPageCount {
            // 출처 없는 핀은 핀이 아니다 (HwpxFixtures/README.md)
            expect(fixture.expectedPageCountSource?.isEmpty)
                .to(equal(false), description: "[\(fixture.id)] pageCountSource 누락")
        }

        var failures: [String] = []
        for fixture in withPageCount {
            guard let expected = fixture.expectedPageCount else { continue }
            do {
                let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                    .load(from: fixture.documentURL)
                if document.pages.count != expected {
                    failures.append(
                        "[\(fixture.id)] pages \(document.pages.count) != expected \(expected)"
                    )
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("HWPX page count failures (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// 같은 문서를 한글.app이 재저장한 쌍이므로 HWP↔HWPX 렌더 쪽수가 같아야
    /// 한다 — 다르면 매핑된 조판 캐시가 한글.app의 쪽나눔을 잃었다는 뜻이다.
    /// 쌍은 manifest `sourceHwpFixture`가 잇는다.
    ///
    /// 순회 대상은 CoreHwp의 `HwpxHwpEquivalenceTests`와 같은 규약이다 — 어느
    /// 쪽이든 `expectedError`(암호·배포용·DRM)면 열 수 없어 비교가 성립하지
    /// 않으므로 건너뛰고, 실제로 비교한 쌍 수에 하한을 건다.
    func testHwpxPageCountsMatchHwpPairs() async throws {
        let hwpxFixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let hwpFixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let hwpByID = Dictionary(uniqueKeysWithValues: hwpFixtures.map { ($0.id, $0) })
        let parseable = hwpxFixtures.filter { !$0.hasExpectedError }

        var failures: [String] = []
        var comparedCount = 0
        for fixture in parseable {
            guard let pairID = fixture.sourceHwpFixture, let pair = hwpByID[pairID] else {
                failures.append("[\(fixture.id)] no HWP pair (sourceHwpFixture)")
                continue
            }
            guard !pair.hasExpectedError else { continue }
            comparedCount += 1
            do {
                let loader = HwpDocumentLoader(fontResolver: .testDeterministic)
                let hwpx = try await loader.load(from: fixture.documentURL)
                let hwp = try await loader.load(from: pair.documentURL)
                if hwpx.pages.count != hwp.pages.count {
                    failures.append(
                        "[\(fixture.id)] hwpx pages \(hwpx.pages.count)"
                            + " != hwp pages \(hwp.pages.count)"
                    )
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        // 비교 가능한 변환 쌍 10종 — 하한은 유실 가드
        expect(comparedCount) >= 10
        if !failures.isEmpty {
            fail("HWP↔HWPX page count mismatches (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// manifest `visibleTextContains`가 조판된 블록 텍스트에 그대로 있어야 한다 —
    /// HWP 쪽 `testAllFixturesRenderExpectedText`의 HWPX 판이다. 열 수 없는
    /// 픽스처(`expectedError`)는 문구를 갖지 않지만 규약을 한 곳에 모으려고
    /// 명시적으로 뺀다.
    func testHwpxFixturesRenderExpectedText() async throws {
        let fixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let withText = fixtures.filter { !$0.hasExpectedError && !$0.expectedVisibleText.isEmpty }
        expect(withText.count) >= 8

        var failures: [String] = []
        for fixture in withText {
            do {
                let document = try await HwpDocumentLoader().load(from: fixture.documentURL)
                let rendered = FixtureText.extract(from: document)
                for phrase in fixture.expectedVisibleText where !rendered.contains(phrase) {
                    let preview = String(rendered.prefix(200))
                        .replacingOccurrences(of: "\n", with: "\\n")
                    failures.append("[\(fixture.id)] missing '\(phrase)' — got: '\(preview)'")
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        if !failures.isEmpty {
            fail("HWPX render failures (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }
}
