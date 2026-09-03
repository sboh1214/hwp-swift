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

    /// 쪽 크롬(머리말/꼬리말/쪽 번호) 블록 텍스트가 HWP 쌍과 같아야 한다 —
    /// HWPX `hp:pageNum`이 typed 승격돼야 noori 꼬리 쪽 번호가 선다 (#135).
    /// 10쌍 중 쪽 크롬을 가진 문서는 noori(쪽 번호 위치 1건)뿐이라 나머지는
    /// 빈 배열 등식이고, noori는 #138 이후 줄표 없는 "1"·"2"·"3"으로 직접
    /// 핀한다 — 등식만 두면 양쪽이 함께 비어도 통과하기 때문이다.
    func testHwpxPageChromeMatchesHwpPairs() async throws {
        let hwpxFixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let hwpFixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let hwpByID = Dictionary(uniqueKeysWithValues: hwpFixtures.map { ($0.id, $0) })
        let loader = HwpDocumentLoader(fontResolver: .testDeterministic)

        var failures: [String] = []
        var comparedCount = 0
        var nooriChrome: [[String]]?
        for fixture in hwpxFixtures where !fixture.hasExpectedError {
            guard let pairID = fixture.sourceHwpFixture, let pair = hwpByID[pairID],
                  !pair.hasExpectedError
            else { continue }
            comparedCount += 1
            do {
                let hwpx = try await loader.load(from: fixture.documentURL)
                let hwp = try await loader.load(from: pair.documentURL)
                let hwpxChrome = Self.pageChromeTexts(of: hwpx)
                let hwpChrome = Self.pageChromeTexts(of: hwp)
                if hwpxChrome != hwpChrome {
                    failures.append("[\(fixture.id)] hwpx chrome \(hwpxChrome) != hwp \(hwpChrome)")
                }
                if fixture.id == "noori" {
                    nooriChrome = hwpxChrome
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        expect(comparedCount) >= 10
        expect(nooriChrome) == [["1"], ["2"], ["3"]]
        if !failures.isEmpty {
            fail("HWP↔HWPX page chrome mismatches (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// 내장 차트 블록(`.chart` payload) 수가 HWP 쌍과 같아야 한다 — HWPX `hp:ole`이
    /// `.ole`로 typed 승격돼야 `HwpPaginator.chartFrame`이 chart 쌍의 차트를 그린다
    /// (#134). 10쌍 중 차트를 가진 문서는 chart뿐이라 나머지는 0 == 0 등식이고,
    /// chart는 1로 직접 핀한다 — 등식만 두면 양쪽이 함께 0이어도 통과하기 때문이다.
    /// 미지원 힌트도 HWP 쌍과 같은 "OLE"여야 한다 (`HwpUnsupportedDetector`가
    /// `.ole` 컨트롤과 gso의 OLE 개체 요소에 같은 힌트를 낸다 — 근사 렌더라 힌트는
    /// 유지된다).
    func testHwpxChartBlocksMatchHwpPairs() async throws {
        let hwpxFixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let hwpFixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let hwpByID = Dictionary(uniqueKeysWithValues: hwpFixtures.map { ($0.id, $0) })
        let loader = HwpDocumentLoader(fontResolver: .testDeterministic)

        var failures: [String] = []
        var comparedCount = 0
        var chartHwpxCount: Int?
        var chartHwpCount: Int?
        var chartHints: [String]?
        for fixture in hwpxFixtures where !fixture.hasExpectedError {
            guard let pairID = fixture.sourceHwpFixture, let pair = hwpByID[pairID],
                  !pair.hasExpectedError
            else { continue }
            comparedCount += 1
            do {
                let hwpx = try await loader.load(from: fixture.documentURL)
                let hwp = try await loader.load(from: pair.documentURL)
                let hwpxCharts = Self.chartBlockCount(of: hwpx)
                let hwpCharts = Self.chartBlockCount(of: hwp)
                if hwpxCharts != hwpCharts {
                    failures.append("[\(fixture.id)] hwpx charts \(hwpxCharts) != hwp \(hwpCharts)")
                }
                let hwpxHints = hwpx.unsupportedElements.map(\.hint)
                let hwpHints = hwp.unsupportedElements.map(\.hint)
                if hwpxHints != hwpHints {
                    failures.append("[\(fixture.id)] hwpx hints \(hwpxHints) != hwp \(hwpHints)")
                }
                if fixture.id == "chart" {
                    chartHwpxCount = hwpxCharts
                    chartHwpCount = hwpCharts
                    chartHints = hwpxHints
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        expect(comparedCount) >= 10
        expect(chartHwpxCount) == 1
        expect(chartHwpCount) == 1
        expect(chartHints) == ["OLE"]
        if !failures.isEmpty {
            fail("HWP↔HWPX chart block mismatches (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// 글머리표 문단 머리는 PARA_TEXT가 아니라 조판이 만드는 라벨이라 파싱
    /// 등가로는 잡히지 않는다 (#133). `hh:bullet` 정의가 비어 있으면
    /// `HwpTextRunBuilder.appendBulletHeading`이 조기 반환해 선행 `- `가
    /// 통째로 사라지므로, 라벨이 붙은 줄만 뽑아 HWP 쌍과 등식으로 건다.
    ///
    /// 페인트 리스트 전량 등식은 축이 아니다 — noori HWPX 렌더에는 빈 문단
    /// draw(`"\r"`)가 4건 더 있어(2쪽 3건·3쪽 1건, drawText 64 대 68) 이
    /// 이슈와 무관하게 문자열이 갈린다. 등식만 두면 양쪽이 함께 비어도
    /// 통과하므로 HWPX 쪽에 직접 핀을 함께 둔다.
    func testHwpxBulletHeadingsMatchHwpPairs() async throws {
        let hwpxFixtures = try FixtureRoot.loadAllHwpxFixtures(from: #file)
        let hwpFixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let hwpByID = Dictionary(uniqueKeysWithValues: hwpFixtures.map { ($0.id, $0) })
        let loader = HwpDocumentLoader(fontResolver: .testDeterministic)

        var failures: [String] = []
        var comparedCount = 0
        var nooriBulletLines: [String]?
        for fixture in hwpxFixtures where !fixture.hasExpectedError {
            guard let pairID = fixture.sourceHwpFixture, let pair = hwpByID[pairID],
                  !pair.hasExpectedError
            else { continue }
            comparedCount += 1
            do {
                let hwpx = try await loader.load(from: fixture.documentURL)
                let hwp = try await loader.load(from: pair.documentURL)
                let hwpxLines = Self.bulletHeadingLines(of: hwpx)
                let hwpLines = Self.bulletHeadingLines(of: hwp)
                if hwpxLines != hwpLines {
                    failures.append(
                        "[\(fixture.id)] hwpx bullet lines \(hwpxLines) != hwp \(hwpLines)"
                    )
                }
                if fixture.id == "noori" {
                    nooriBulletLines = hwpxLines
                }
            } catch {
                failures.append("[\(fixture.id)] load threw: \(error)")
            }
        }

        expect(comparedCount) >= 10
        // 두 문단은 표 셀 안이라 `page.blocks`에는 잡히지 않는다 — 추출은
        // 페인트 리스트여야 한다. 본문 자체가 `-`로 끝나므로 `contains("-")`
        // 검사는 무의미하고, 선행 `- `를 문자열로 직접 핀한다.
        expect(nooriBulletLines) == [
            "- “세상”의 옛말로, 우주까지 확장된 새로운 세상을 연다는 의미 -",
            "- 명칭공모전에 1만건 이상 응모, 뜨거운 관심 보여 -",
        ]
        if !failures.isEmpty {
            fail("HWP↔HWPX bullet heading mismatches (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    /// 글머리표 라벨(`문자 + 공백`)이 앞에 붙은 줄만 문서 순서로 모은다.
    ///
    /// 라벨 문자는 픽스처 10종의 유일한 실물인 `-`로 한정한다. `□`·`o` 같은
    /// 다른 기호는 noori 본문 문단이 **글자 그대로** 쓰고 있어(문단 머리가
    /// 아니다) 넓히면 본문이 딸려 들어온다.
    ///
    /// 줄 나누기는 `components(separatedBy: .newlines)`여야 한다 — 문단 끝은
    /// CRLF이고 Swift에서 `"\r\n"`은 **문자 하나**(확장 grapheme cluster)라
    /// `split(separator: "\n")`은 아무것도 쪼개지 못한다.
    private static func bulletHeadingLines(of document: HwpDocument) -> [String] {
        FixtureText.extractFromPaintList(document)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
    }

    /// 문서 전체의 `.chart` payload 블록 수.
    private static func chartBlockCount(of document: HwpDocument) -> Int {
        document.pages.flatMap(\.blocks).filter { block in
            if case .chart = block.payload {
                return true
            }
            return false
        }.count
    }

    /// 페이지별 쪽 크롬 텍스트 블록 문자열 (문서 순서).
    private static func pageChromeTexts(of document: HwpDocument) -> [[String]] {
        document.pages.map { page in
            page.blocks
                .filter { $0.role == .pageChrome && $0.kind == .text }
                .compactMap { $0.attributedString?.string }
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
