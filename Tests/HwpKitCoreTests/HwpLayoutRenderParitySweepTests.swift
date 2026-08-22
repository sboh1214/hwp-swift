@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 측정 (`HwpParagraphLayout.layout`) · 렌더 (`HwpDrawnTextLayout.lines`) 등가의
    /// **픽스처 스케일 잠금** (#80 조각 2).
    ///
    /// 종전 등가 단언은 합성 문자열 단위 테스트 2건뿐이었다
    /// (`HwpParagraphLayoutTests.testCappedMeasurementMatchesRenderRanges` ·
    /// `…testTabParagraphMeasurementMatchesDrawnLayout`). 측정 입력 계약을 바꾸는
    /// 변경(#80 조각 3 — 측정이 부착본을 그대로 framesetting)은 **모든** 문단에
    /// 번지므로, 가드의 규모가 위험에 비해 턱없이 작았다.
    ///
    /// **이 가드는 발견용이 아니라 잠금용이다** — 등가는 이미 성립한다. 세 경로가
    /// 지금은 같은 코어를 쓰므로 대조는 대체로 항등식이고, 그래서 이 스위트가 하는
    /// 일은 "계속 같은 코어를 쓴다"를 못박는 것이다. 빨개지는 날은 넷 중 하나다 —
    /// ① `layout`이 입력을 다시 변형하거나(#80 조각 3 이전으로의 회귀), ② 한쪽만
    /// slight-overflow 술어·폭 클램프를 바꾸거나, ③ 네 번째 줄바꿈 구현이 끼어들거나,
    /// ④ 새 컨테이너가 `childParagraphs`에 추가되며 문단 수 핀이 어긋나거나.
    ///
    /// 대조는 세 갈래다. 같은 attributedString·같은 폭에서
    /// 1. 측정 줄 범위 == 렌더 줄 범위,
    /// 2. 측정 줄 범위·폭·ascent == **공유 코어**(`HwpLineBreaker.nextFrameChunk`)가
    ///    그 문자열에서 직접 낸 프레임 줄,
    /// 3. (1 + 2에서 따라 나오는) 렌더 줄 범위 == 같은 공유 코어 줄.
    ///
    /// 2번이 조각 3의 핵심 가드다: 측정이 입력 사본에 스타일을 재생성해 조판하든
    /// 부착본을 그대로 조판하든, 결과가 **부착본 기준 공유 코어**와 같아야 한다.
    ///
    /// **폭·ascent를 렌더와 직접 비교하지 않는다.** 그 델타는 회귀가 아니라
    /// `HwpWordJustification`의 공백 재배분이다 (`Sources/HwpKitCore/AGENTS.md`
    /// 양쪽 정렬 항목 — 재조판 줄에서만, 최대 10.000pt). 그래서 렌더 쪽은 범위만
    /// 보고, 폭·ascent는 재조판 **전** 프레임 줄인 공유 코어와 맞춘다.
    ///
    /// ## 순회 범위
    ///
    /// `displaySectionArray[].paragraph` 최상위만 훑으면 전체 문단의 상당수를
    /// **구조적으로** 못 본다 — 표 셀·글상자·각주 문단은 `paragraph.ctrlHeaderArray`
    /// 안에 있고, 하필 그 문단들이 조각 3의 위험 구간이다 (#80 실측: legacy
    /// 1,030쪽 페이지네이션 1회의 `layout()` 호출 5,773건 중 3,689건 = 64%가
    /// 컨테이너 문단). 그래서 프로덕션 `HwpPaginator.childParagraphs(of:)`를 **그대로 불러**
    /// 재귀한다 — 분기를 복제하면 새 컨테이너가 추가될 때 이 가드만 조용히 그것을
    /// 못 본다.
    ///
    /// 메모 문단(`memoParagraphArray`)은 뺀다. 메모 본문은 이 두 경로가 아니라
    /// `HwpMemoPanelPainter`가 `CTTypesetterSuggestLineBreak`로 직접 쪼개는
    /// 세 번째 줄바꿈 구현을 타므로, 여기서 대조하면 의미가 없다.
    ///
    /// **알고 있는 범위 한계 둘.** ① `sizeResolver`를 안 실어 글자처럼 취급 개체
    /// 마커가 폭 0으로 예약된다 (프로덕션은 개체 크기). 등가는 두 경로가 **같은**
    /// 문자열을 보는 성질이라 이 축과 무관하지만, 인라인 개체 줄의 실제 줄바꿈
    /// 지점은 여기서 안 태워진다. ② 각주 자동 번호 등
    /// `controlReplacements`도 비어 있어 마커가 번호 텍스트로 치환되지 않는다.
    ///
    /// ## CI 비용
    ///
    /// 상시 스위트다 — opt-in으로 두면 CI에서 한 줄도 안 돌아 #69가 없앤 죽은
    /// 가드가 되살아난다. 대신 legacy를 **표본화**한다: 문단 14,796개 중 14,659개
    /// (99.1%)가 그 픽스처 하나에서 나와, 전수 스윕은 이 스위트만 127초다
    /// (`HwpKitCoreTests` 번들 5.5초의 23배). stride 31 표본이면 4.6초로 떨어지고
    /// 표본은 결정론적이라 실행마다 같은 문단을 본다.
    ///
    /// `HWP_PARITY_SWEEP=1`이면 legacy도 stride 1 (전수) — 측정 입력 계약을 바꾸는
    /// 변경(#80 조각 3 등)을 낼 때 한 번 돌린다. **실측 (2026-08-22, 전수):**
    /// 대조 21,436건 (문단 × 폭 2종, 컨테이너 문단 3,603 포함) 중 등가 위반 0건.
    final class HwpLayoutRenderParitySweepTests: XCTestCase {
        /// legacy 표본 간격. 소수라 표·각주가 규칙적으로 반복되는 구간과
        /// 위상이 맞아떨어지지 않는다.
        private static let legacySampleStride = 31

        private static let legacyFixtureId = "legacy-common-control-property"

        /// 대조 폭. 실제 단 폭 대신 **고정 폭 둘**을 쓴다 — 등가 계약은 폭과
        /// 무관하고, 고정 폭이라야 픽스처의 종이 설정이 바뀌어도 같은 것을 잰다.
        /// 좁은 쪽(120pt)은 wrap 지점을 늘려 청크 경계 계약을 더 많이 태운다.
        private static let sweepWidths: [CGFloat] = [400, 120]

        /// FileHeader 단계에서 거부되는 픽스처 — 암호 2종·배포용·DRM.
        /// **집합을 단언한다**: `try?`로 조용히 넘기면 파서 회귀로 멀쩡한 픽스처가
        /// 스윕에서 빠져도 초록이 된다.
        private static let unreadableFixtureIds: Set<String> = [
            "drm-unsupported-derived",
            "배포용문서",
            "문서암호설정-보안수준높음",
            "문서암호설정-보안수준보통",
        ]

        private static var isExhaustive: Bool {
            ProcessInfo.processInfo.environment["HWP_PARITY_SWEEP"] == "1"
        }

        // MARK: - 스윕

        /// legacy를 뺀 **전 픽스처**. 이슈가 지목한 5종에 국한하지 않는 이유는
        /// 새 픽스처가 들어와도 가드가 자동으로 그것을 덮게 하기 위해서다.
        func testFixturesMeasurementMatchesRender() throws {
            let ids = try Self.fixtureIds().filter { $0 != Self.legacyFixtureId }
            var stats = SweepStats()
            var unreadable: Set<String> = []

            for id in ids {
                guard let file = try? Self.fixture(id) else {
                    unreadable.insert(id)
                    continue
                }
                sweep(file, fixtureId: id, stride: 1, stats: &stats)
            }

            expect(unreadable) == Self.unreadableFixtureIds
            report(stats.failures)
            // 실측 핀 (2026-08-22). 순회·측정 수는 폰트와 무관한 **구조** 값이라
            // 정확히 못박는다 — 컨테이너 종류가 `childParagraphs`에서 빠지거나
            // 픽스처가 늘면 여기서 먼저 빨개진다.
            expect(stats.visited) == Self.expectedFixtureVisited
            expect(stats.measured) == Self.expectedFixtureMeasured
            expect(stats.containerParagraphs) == Self.expectedFixtureContainers
            // 여러 줄 문단 수는 조판 결과라 하한만 둔다 (결정론 resolver로 기기
            // 독립이지만 CT 버전까지 잠그지는 않는다). 공허한 통과 방지가 목적.
            expect(stats.multiLine).to(beGreaterThanOrEqualTo(Self.minimumFixtureMultiLine))
            // 3-way 축이 조용히 비지 않았다 — 공유 코어 대조를 건너뛴 문단은
            // slight-overflow 한 줄뿐이어야 한다 (실측 1 / 260).
            expect(stats.measured - stats.sharedCoreCompared)
                .to(beLessThanOrEqualTo(Self.maximumFixtureSharedCoreSkips))
        }

        /// 문단의 99%가 여기서 나온다 — 표본만 상시로 돈다.
        func testLegacyFixtureMeasurementMatchesRender() throws {
            let file = try Self.fixture(Self.legacyFixtureId)
            let stride = Self.isExhaustive ? 1 : Self.legacySampleStride
            var stats = SweepStats()
            sweep(file, fixtureId: Self.legacyFixtureId, stride: stride, stats: &stats)

            report(stats.failures)
            // 순회 총수는 표본과 무관한 구조 값이다 (stride는 대조 대상만 고른다).
            expect(stats.visited) == Self.expectedLegacyVisited
            let exhaustive = Self.isExhaustive
            expect(stats.measured)
                .to(beGreaterThanOrEqualTo(exhaustive ? 20000 : 600))
            expect(stats.containerParagraphs)
                .to(beGreaterThanOrEqualTo(exhaustive ? 3500 : 100))
            expect(stats.multiLine)
                .to(beGreaterThanOrEqualTo(exhaustive ? 12000 : 360))
            // 위와 같은 이유 (실측: 표본 17 / 652, 전수 320 / 21,436).
            expect(stats.measured - stats.sharedCoreCompared)
                .to(beLessThanOrEqualTo(exhaustive ? 500 : 40))
        }

        // MARK: - 실측 핀

        private static let expectedFixtureVisited = 137
        private static let expectedFixtureMeasured = 260
        private static let expectedFixtureContainers = 50
        private static let minimumFixtureMultiLine = 60
        private static let maximumFixtureSharedCoreSkips = 5
        private static let expectedLegacyVisited = 14659

        // MARK: - 본체

        private struct SweepStats {
            var visited = 0
            var measured = 0
            var multiLine = 0
            var containerParagraphs = 0
            /// 공유 코어 3-way 대조까지 간 문단 수 — 아래 조기 반환 둘이 넓어지면
            /// 그 축이 조용히 비어도 나머지 단언은 초록이다. 세어서 못박는다.
            var sharedCoreCompared = 0
            var failures: [String] = []
        }

        private func report(_ failures: [String]) {
            guard !failures.isEmpty else { return }
            fail(
                "측정·렌더 등가 위반 \(failures.count)건 (앞 20건):\n"
                    + failures.prefix(20).joined(separator: "\n")
            )
        }

        private func sweep(
            _ file: CoreHwp.HwpFile,
            fixtureId: String,
            stride: Int,
            stats: inout SweepStats
        ) {
            let measurer = HwpParagraphMeasurer(
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic,
                attributeCache: HwpTextAttributeCache()
            )
            var localVisited = 0
            for section in file.displaySectionArray {
                for paragraph in section.paragraph {
                    Self.visitParagraphTree(paragraph) { target, depth in
                        localVisited += 1
                        stats.visited += 1
                        guard localVisited % stride == 0 else { return }
                        if depth > 0 {
                            stats.containerParagraphs += 1
                        }
                        for width in Self.sweepWidths {
                            compare(
                                paragraph: target,
                                width: width,
                                measurer: measurer,
                                label: "[\(fixtureId)] #\(localVisited) d\(depth) w\(Int(width))",
                                stats: &stats
                            )
                        }
                    }
                }
            }
        }

        private func compare(
            paragraph: CoreHwp.HwpParagraph,
            width: CGFloat,
            measurer: HwpParagraphMeasurer,
            label: String,
            stats: inout SweepStats
        ) {
            let result = measurer.measure(paragraph, width: width)
            let attributed = result.attributed
            guard attributed.length > 0, !result.frame.lines.isEmpty else { return }
            stats.measured += 1
            if result.frame.lines.count > 1 {
                stats.multiLine += 1
            }

            let drawn = HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: width
            )
            let measuredRanges = result.frame.lines.map(\.attributedRange)
            let drawnRanges = drawn.map(\.stringRange)
            if measuredRanges != drawnRanges {
                stats.failures.append(
                    "\(label) 줄 범위: 측정 \(Self.brief(measuredRanges)) "
                        + "≠ 렌더 \(Self.brief(drawnRanges))"
                )
                return
            }
            compareAgainstSharedCore(
                attributed: attributed, width: width, frame: result.frame,
                label: label, stats: &stats
            )
        }

        /// 측정 프레임을 **부착본 기준 공유 코어**와 맞춘다.
        private func compareAgainstSharedCore(
            attributed: NSAttributedString,
            width: CGFloat,
            frame: HwpParagraphFrame,
            label: String,
            stats: inout SweepStats
        ) {
            // slight-overflow 한 줄은 두 경로가 공유 코어를 아예 타지 않는다
            // (양쪽이 같은 술어로 조기 반환) — 위 범위 대조로 충분하다.
            guard HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: attributed, lineWidth: width
            ) == nil else { return }
            // 공유 코어 호출 **한 번**이 문단 전체를 덮는 조건은
            // `probeLength == fullLength`, 즉 `nextFrameChunk`가 문자 수를 남은 **줄**
            // 예산과 직접 비교하므로 (`min(fullLength - start, remainingLineBudget)`)
            // 문자 수가 maximumLineFrames 이하일 때다. 그보다 길면 다중 청크라
            // 여기서 루프를 재현해야 해 3-way 대조에서 뺀다.
            guard attributed.length <= HwpParagraphLayout.maximumLineFrames else { return }
            guard let chunk = HwpLineBreaker.nextFrameChunk(
                framesetter: CTFramesetterCreateWithAttributedString(attributed),
                typesetter: CTTypesetterCreateWithAttributedString(attributed),
                attributedString: attributed,
                startLocation: 0,
                fullLength: attributed.length,
                remainingLineBudget: HwpParagraphLayout.maximumLineFrames,
                lineWidth: width
            ) else {
                stats.failures.append("\(label) 공유 코어가 청크를 못 냈다")
                return
            }
            stats.sharedCoreCompared += 1
            guard chunk.keepCount == frame.lines.count else {
                stats.failures.append(
                    "\(label) 줄 수: 측정 \(frame.lines.count) ≠ 공유 코어 \(chunk.keepCount)"
                )
                return
            }
            for (line, frameLine) in zip(frame.lines, chunk.lines.prefix(chunk.keepCount)) {
                let range = CTLineGetStringRange(frameLine)
                var ascent: CGFloat = 0
                let coreWidth = CGFloat(CTLineGetTypographicBounds(frameLine, &ascent, nil, nil))
                let coreRange = NSRange(location: range.location, length: range.length)
                if line.attributedRange != coreRange {
                    stats.failures.append(
                        "\(label) 측정 줄 범위가 공유 코어와 다르다: "
                            + "\(line.attributedRange) ≠ \(coreRange)"
                    )
                    break
                }
                if abs(line.width - coreWidth) > 0.0001 || abs(line.baseline - ascent) > 0.0001 {
                    stats.failures.append(
                        "\(label) 측정 줄 메트릭이 공유 코어와 다르다: 폭 \(line.width) vs "
                            + "\(coreWidth), ascent \(line.baseline) vs \(ascent)"
                    )
                    break
                }
            }
        }

        // MARK: - 순회

        /// 문단과 그 아래 **모든** 컨테이너 문단을 방문한다 (depth 0 = 최상위).
        ///
        /// 컨테이너 분기는 프로덕션 `HwpPaginator.childParagraphs(of:)` 하나를
        /// 그대로 쓴다. 깊이 상한은 렌더 상한(`maximumContainerDepth` 3)이 아니라
        /// 넉넉한 값이다 — 여기서는 그려지는 문단이 아니라 **모델의 모든** 문단이
        /// 대상이고, 실제 상한은 파서의 레코드 트리 깊이 가드가 이미 걸었다.
        private static func visitParagraphTree(
            _ paragraph: CoreHwp.HwpParagraph,
            depth: Int = 0,
            visit: (CoreHwp.HwpParagraph, Int) -> Void
        ) {
            guard depth <= 16 else { return }
            visit(paragraph, depth)
            for ctrl in paragraph.ctrlHeaderArray ?? [] {
                for (child, _) in HwpPaginator.childParagraphs(of: ctrl) {
                    visitParagraphTree(child, depth: depth + 1, visit: visit)
                }
            }
        }

        // MARK: - 픽스처

        private static var fixturesRoot: URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures")
        }

        private static func fixtureIds() throws -> [String] {
            try FileManager.default
                .contentsOfDirectory(atPath: fixturesRoot.path)
                .filter {
                    FileManager.default.fileExists(
                        atPath: fixturesRoot.appendingPathComponent("\($0)/document.hwp").path
                    )
                }
                .sorted()
        }

        private static func fixture(_ id: String) throws -> CoreHwp.HwpFile {
            try CoreHwp.HwpFile(
                fromPath: fixturesRoot.appendingPathComponent("\(id)/document.hwp").path
            )
        }

        private static func brief(_ ranges: [NSRange]) -> String {
            let head = ranges.prefix(4).map { "\($0.location)+\($0.length)" }
            return "[\(head.joined(separator: ","))\(ranges.count > 4 ? ",…" : "")]"
                + "(\(ranges.count)줄)"
        }
    }
#endif
