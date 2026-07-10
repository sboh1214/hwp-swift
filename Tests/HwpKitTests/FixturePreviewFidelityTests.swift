@preconcurrency import CoreHwp
import Foundation
import HwpKitCore
import Nimble
import XCTest

/// 렌더 결과를 문서 내장 PrvImage(한컴오피스가 직접 렌더한 1페이지
/// 미리보기)와 잉크 밀도 그리드로 대조하는 fidelity 회귀 스위트.
///
/// 임계는 픽스처별 실측 MAE + 소폭 여유로 잡는다 — 폰트 대체 오차는
/// 흡수하고 레이아웃 회귀(문단 위치·간격·단 배분)는 잡을 만큼 타이트하게.
final class FixturePreviewFidelityTests: XCTestCase {
    /// 파싱 자체가 거부되는 픽스처 — 암호 2종·배포용·DRM (HwpError.unsupportedFeature)
    private static let unparseableFixtureIds: Set<String> = [
        "문서암호설정-보안수준높음",
        "문서암호설정-보안수준보통",
        "배포용문서",
        "drm-unsupported-derived",
    ]

    /// PrvImage 스트림이 제거된 파생 픽스처 — 대조 기준이 없다
    private static let missingPreviewFixtureIds: Set<String> = [
        "missing-preview-image-derived",
    ]

    /// 픽스처별 잉크 밀도 MAE 임계 (강도 정합 MAE 기준).
    /// 실측 근거: 2026-07-06 testRenderablePreviewFidelity 리포트 (아래 실측값)
    /// + 30~50% 여유. 폰트 대체 오차는 강도 정합이 흡수하므로 임계는 레이아웃
    /// 회귀 (문단 위치·간격·단 배분·개체 배치)를 잡을 만큼 타이트하게 유지한다.
    /// 새 픽스처는 실측 후 반드시 여기에 추가한다 (엔트리 없으면 테스트 실패).
    private static let maeThresholds: [String: Double] = [
        "2007": 0.002, // 실측 0.0000 (빈 페이지)
        "2014VP": 0.002, // 실측 0.0000 (빈 페이지)
        "BinData": 0.004, // 실측 0.0014 (2× 줌 보정 후)
        "CCL": 0.005, // 실측 0.0023 (저해상 GIF)
        "CharShape": 0.003, // 실측 0.0012 (2026-07-10 상대크기·장평·음영·그림자·취소선 렌더 반영)
        "CharShapeProperty": 0.002, // 실측 0.0005
        "Column": 0.008, // 실측 0.0057 (다단 배분 + 양쪽 정렬 잔차)
        "blank-mac2014vp": 0.002, // 실측 0.0000
        "blank-win2018": 0.002, // 실측 0.0000
        "blank-win2020": 0.002, // 실측 0.0000
        "bookmark": 0.002, // 실측 0.0003
        // OOXML 데이터 기반 차트 근사 렌더 — 한글.app mac 렌더러 실측 기반
        // (닫힌 3D 프레임·굵은 원뿔·실물 계열색·미세 명암). PrvImage는
        // 윈도우 렌더 (강한 그라데이션)라 잉크 차가 남는다.
        "chart": 0.010, // 실측 0.0064 (2026-07-10 실물 픽셀 실측 평행 투영 상자 기하)
        "equation": 0.002, // 실측 0.0003 (EQEDIT 스크립트 근사 텍스트 렌더)
        "footnote-endnote": 0.003, // 실측 0.0011
        "header-footer": 0.003, // 실측 0.0010
        // 저해상 (177×250) GIF + 한자·옛한글 폰트 대체 강도 잔차
        "legacy-common-control-property": 0.024, // 실측 0.0173 (2026-07-10)
        "memo": 0.002, // 실측 0.0003
        "missing-preview-text-derived": 0.002, // 실측 0.0004
        "missing-summary-derived": 0.002, // 실측 0.0004
        "multi-section": 0.002, // 실측 0.0000
        // 저해상 (177×250) GIF 업스케일 잔차. 한컴 번들 폰트 사용 (2026-07-10)
        // 이후 raw 0.0789→0.0714·ink 2.12→1.72로 실물 정합은 개선됐지만
        // 강도 정합 그리드가 재분포되어 MAE 수치는 올랐다 (실측 0.0525).
        "noori": 0.058,
        "plain-text-hancom-mac2026": 0.002, // 실측 0.0005
        "plain-text-minimal": 0.002, // 실측 0.0004
        "text-box": 0.003, // 실측 0.0012
        "track-changes": 0.002, // 실측 0.0002
        "공공누리": 0.006, // 실측 0.0028 (저해상 GIF)
        "문서이력관리": 0.002, // 실측 0.0000
        "변경내용추적": 0.002, // 실측 0.0000
    ]

    /// PrvImage가 전체 페이지 렌더가 아닌 저장본의 렌더 배율 보정.
    /// BinData: PrvImage가 페이지 좌상단 1/4을 2× 배율로 렌더한 저장본
    /// (실측: 미리보기 좌여백 207px = 85.04pt × 2×fit scale, 이미지 폭도 2×).
    private static let previewZoomOverrides: [String: CGFloat] = [
        "BinData": 2,
    ]

    func testExcludedFixturesAreExplicitlyUnrenderable() throws {
        let root = FixtureRoot.url(from: #file)

        for id in Self.unparseableFixtureIds.sorted() {
            let documentPath = root
                .appendingPathComponent(id)
                .appendingPathComponent("document.hwp")
                .path
            expect(try CoreHwp.HwpFile(fromPath: documentPath))
                .to(throwError(errorType: HwpError.self), description: id)
        }

        for id in Self.missingPreviewFixtureIds.sorted() {
            let documentPath = root
                .appendingPathComponent(id)
                .appendingPathComponent("document.hwp")
                .path
            let file = try CoreHwp.HwpFile(fromPath: documentPath)
            expect(file.previewImage.format).to(
                equal(HwpPreviewImageFormat.none),
                description: "\(id) should have no PrvImage"
            )
        }
    }

    func testRenderablePreviewFidelity() async throws {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let excluded = Self.unparseableFixtureIds.union(Self.missingPreviewFixtureIds)
        // 제외 목록이 실제 픽스처와 일치하는지 (오타 가드)
        let fixtureIds = Set(fixtures.map(\.id))
        expect(excluded.subtracting(fixtureIds)).to(beEmpty())

        var reportLines: [String] = []
        var failures: [String] = []
        var measuredCount = 0

        for fixture in fixtures where !excluded.contains(fixture.id) {
            do {
                let measurement = try await Self.measureFixture(fixture)
                measuredCount += 1
                reportLines.append(Self.reportLine(id: fixture.id, measurement: measurement))
                if let failure = Self.thresholdFailure(id: fixture.id, measurement: measurement) {
                    failures.append(failure)
                }
            } catch {
                failures.append("[\(fixture.id)] measurement threw: \(error)")
            }
        }

        print("=== PrvImage fidelity report (\(measuredCount) fixtures) ===")
        for line in reportLines.sorted() {
            print(line)
        }

        // 제외 5종 외 전부가 실제로 측정되어야 한다
        expect(measuredCount) == fixtures.count - excluded.count

        if !failures.isEmpty {
            fail("PrvImage fidelity failures (\(failures.count)):\n" +
                failures.joined(separator: "\n"))
        }
    }

    private static func measureFixture(
        _ fixture: FixtureCase
    ) async throws -> FixturePreview.Measurement {
        let file = try CoreHwp.HwpFile(fromPath: fixture.documentURL.path)
        return try await FixturePreview.measure(
            file: file,
            previewZoom: previewZoomOverrides[fixture.id] ?? 1
        )
    }

    private static func reportLine(
        id: String,
        measurement: FixturePreview.Measurement
    ) -> String {
        String(
            format: "%@ preview %dx%d grid %dx%d MAE %.4f (raw %.4f, ink x%.2f)",
            id.padding(toLength: 34, withPad: " ", startingAt: 0),
            measurement.previewWidth,
            measurement.previewHeight,
            measurement.columns,
            measurement.rows,
            measurement.mae,
            measurement.rawMae,
            measurement.inkScale
        )
    }

    private static func thresholdFailure(
        id: String,
        measurement: FixturePreview.Measurement
    ) -> String? {
        guard let threshold = maeThresholds[id] else {
            return String(
                format: "[%@] no calibrated MAE threshold (measured %.4f)",
                id,
                measurement.mae
            )
        }
        guard measurement.mae > threshold else { return nil }
        return String(
            format: "[%@] MAE %.4f exceeds threshold %.4f",
            id,
            measurement.mae,
            threshold
        )
    }
}
