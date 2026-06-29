import Foundation
import Nimble
import XCTest

final class FixtureGuideTests: XCTestCase {
    func testCoreHwpTestsGuidanceDocumentsCentralFixtureHarness() throws {
        let guideURL = testsRoot(from: #file).appendingPathComponent("AGENTS.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        expect(guide).to(contain("Tests/CoreHwpTests/Fixtures/<fixture-id>/"))
        expect(guide).to(contain("document.hwp"))
        expect(guide).to(contain("manifest.json"))
        expect(guide).to(contain("README.md"))
        expect(guide).to(contain("FixtureLoader"))
        expect(guide).to(contain("FixtureManifest"))
        expect(guide).to(contain("FixtureAssertions"))
        expect(guide).to(contain("openHwp(#file, \"plain-text-minimal\")"))
        expect(guide).to(contain("새 fixture는 `Fixtures/<fixture-id>/` 구조로 추가한다"))
        expect(guide).notTo(contain("공용 `Fixtures/` 폴더에 픽스처 모으기"))
        expect(guide).notTo(contain("그 파일을 사용하는 테스트 파일과 같은 폴더"))
    }

    func testFixtureRootGuideDocumentsGenerationPolicy() throws {
        let guideURL = FixtureLoader.root.appendingPathComponent("README.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        expect(guide).to(contain("# CoreHwp fixture guide"))
        assertHancomAutomationPolicy(in: guide)
        expect(guide).to(contain("plain-text-minimal"))
        expect(guide).to(contain("chart"))
        expect(guide).to(contain("legacy-common-control-property"))
        expect(guide).to(contain("`HwpFile(fromPath:)`, `HwpFile(fromData:)`"))
        expect(guide).to(contain("`HwpError.unsupportedFeature`를 반환"))
        expect(guide).to(contain("representative truncation/corruption set"))
        expect(guide).to(contain("Track changes fixture 확보 상태"))
        expect(guide).to(contain("track-changes"))
        expect(guide).to(contain("track-changes-flag"))
        expect(guide).to(contain("MEMO_SHAPE fixture 확보 상태"))
        expect(guide).to(contain("memo_preset.hwp"))
        expect(guide).to(contain("drm unsupported"))
        expect(guide).to(contain("DRM fixture 확보 상태"))
        expect(guide).to(contain("isDRMDocument"))
        expect(guide).to(contain("isAccreditedCertificateDRMDocument"))
        expect(guide).to(contain("미리 보기 이미지 저장"))
        expect(guide).to(contain("IDS_SavePreviewImage"))
        expect(guide).to(contain("IDH_OPTIONS_EDIT_PREVIEW"))
        expect(guide).to(contain("previewImageSave"))
        expect(guide).to(contain("Include Preview Image"))
        expect(guide).to(contain("Resources/Help/file/options/options(edit).htm"))
        expect(guide).to(contain("문서에 저장"))
        expect(guide).to(contain("24KB"))
        expect(guide).to(contain("AppState\\Preview"))
        expect(guide).to(contain("defaults read com.hancom.office.hwp12.mac.general"))
        expect(guide).to(contain("Preview = 1"))
        expect(guide).to(contain("AppState\\Preview = 0"))
        expect(guide).to(contain("한글 > 환경 설정... > 편집"))
        expect(guide).to(contain("Value: 1"))
        expect(guide).to(contain("ID: P"))
        expect(guide).to(contain("previewImageBytes=15295"))
        expect(guide).to(contain("한컴오피스 앱 번들 전체의 `.hwp`/`.hwt`"))
        expect(guide).to(contain("332개"))
        expect(guide).to(contain("2026-06-20"))
        expect(guide).to(contain("임시 Swift scanner"))
        expect(guide).to(contain("352개"))
        expect(guide).to(contain("readable인 파일은"))
        expect(guide).to(contain("unreadable 4개"))
        expect(guide).to(contain("previewImage=false`는 암호화 fixture 2개"))
        expect(guide).to(contain("문서 암호 설정"))
        expect(guide).to(contain("문서 암호 변경 및 해제"))
        expect(guide).to(contain("변경/해제"))
        expect(guide).to(contain("DRM 저장 기능이 노출되는 한컴오피스 설치본"))
    }

    func testFixtureRootGuideDocumentsCoverageEvidence() throws {
        let guideURL = FixtureLoader.root.appendingPathComponent("README.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        expect(guide).to(contain("## Coverage 확보 상태"))
        expect(guide).to(contain("swift test --enable-code-coverage"))
        expect(guide).to(contain(".build/out/Products/Debug/codecov/Hwp-Swift.json"))
        expect(guide).to(contain("Sources/CoreHwp"))
        expect(guide).to(contain("95% 이상"))
        expect(guide).notTo(contain("개 XCTest"))
        expect(guide).to(contain("5481/5559"))
        expect(guide).to(contain("2483/2545"))

        guard let lineCoverage = percentage(after: "총 line coverage는", in: guide),
              let regionCoverage = percentage(after: "region coverage는", in: guide)
        else {
            return fail("Expected fixture guide to document numeric CoreHwp coverage")
        }

        expect(lineCoverage >= 95.0) == true
        expect(regionCoverage >= 95.0) == true
    }
}

private func assertHancomAutomationPolicy(in guide: String) {
    expect(guide).to(contain("/Applications/Hancom Office HWP.app"))
    expect(guide).to(contain("com.hancom.office.hwp12.mac.general"))
    expect(guide).to(contain("Contents/MacOS/Hancom Office HWP"))
    expect(guide).to(contain("2026-06-24 재확인"))
    expect(guide).to(contain("12.30.0` / `6382"))
    expect(guide).to(contain("error -10827"))
    expect(guide).to(contain("error -192"))
    expect(guide).to(contain("Hancom Office HWP\"을(를) 가져올 수 없습니다"))
    expect(guide).to(contain("PATH에서 여전히 확인되지"))
    expect(guide).to(contain("독립 실행 파일은 `Hancom Office HWP` 하나"))
    expect(guide).to(contain("hwpctl"))
    expect(guide).to(contain("hwp5proc"))
    expect(guide).to(contain("CFBundleDocumentTypes"))
    expect(guide).to(contain("DocFilters"))
    expect(guide).to(contain("HncLogUploader"))
    expect(guide).to(contain("Computer Use 기반 GUI 조작"))
    expect(guide).to(contain("별도 승인"))
    expect(guide).to(contain("로그인"))
    expect(guide).to(contain("라이선스"))
    expect(guide).to(contain("보안 설정"))
    expect(guide).to(contain("저장 권한 팝업"))
}

private func percentage(after marker: String, in text: String) -> Double? {
    guard let markerRange = text.range(of: marker) else {
        return nil
    }
    let suffix = text[markerRange.upperBound...]
    guard let percentageRange = suffix.range(
        of: #"[0-9]+(\.[0-9]+)?%"#,
        options: .regularExpression
    ) else {
        return nil
    }
    return Double(suffix[percentageRange].dropLast())
}
