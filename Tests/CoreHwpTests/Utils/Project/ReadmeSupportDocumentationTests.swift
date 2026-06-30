import Foundation
import Nimble
import XCTest

final class ReadmeSupportDocumentationTests: XCTestCase {
    func testProjectReadmeStaysConciseAndLinksDetailedDocs() throws {
        let readme = try String(
            contentsOf: projectRootURL().appendingPathComponent("README.md"),
            encoding: .utf8
        )

        expect(readme).to(contain("[Sources/CoreHwp/AGENTS.md]"))
        expect(readme).to(contain("[Tests/CoreHwpTests/Fixtures/README.md]"))
        expect(readme).to(contain("[edwardkim/rhwp](https://github.com/edwardkim/rhwp)"))
        expect(readme).to(contain("hwp_spec_errata.md"))
        expect(readme).to(contain("[Documentation/ErrataAudit.md](Documentation/ErrataAudit.md)"))
        expect(readme).notTo(contain("codecov"))
        expect(readme).notTo(contain("coverage"))
        expect(readme).notTo(contain("커버리지"))
        expect(readme).notTo(contain("### Fixture coverage"))
        expect(readme).notTo(contain("2026-06-25 현재 Downloads HWP 5개"))
        expect(readme).notTo(contain("readable external 후보 384개"))
    }

    func testLowerDocumentationDocumentsReaderCompletionEvidence() throws {
        let readme = try lowerReaderDocumentation()

        expect(readme).to(contain("`HwpError`"))
        expect(readme).to(contain("`unknownRecords`에 raw payload 보존"))
        expect(readme).to(contain("`.notImplemented` 또는 `.unknown`으로 raw payload 보존"))
        expect(readme).to(contain("summary length/prefix/suffix bytes"))
        expect(readme).to(contain("`Section0`, `Section1` 숫자 순 정렬"))
        expect(readme).to(contain("암호 문서"))
        expect(readme).to(contain("배포용 문서"))
        expect(readme).to(contain("DRM 문서"))
        expect(readme).to(contain("쓰기/저장 | 미지원"))
        expect(readme).to(contain("Tests/CoreHwpTests/Fixtures/<fixture-id>/"))
        expect(readme).to(contain("저수준 corrupt/malformed 입력만 synthetic data 테스트를 허용"))
        expect(readme).to(contain("`HwpFile(fromPath:)`, `HwpFile(fromData:)`"))
        expect(readme).to(contain("같은 `HwpError.unsupportedFeature`"))
        expect(readme).to(contain("`DOC_DATA`는 실제 fixture 기반으로 32-bit word 배열"))
        expect(readme).to(contain("`DISTRIBUTE_DOC_DATA`도 32-bit word 배열과 trailing bytes"))
        expect(readme).to(contain("`TRACK_CHANGE`는 선행 32-bit header 값을 typed model로 노출"))
        expect(readme).to(contain("2026-06-25 현재 Downloads HWP 5개"))
        expect(readme).to(contain("한컴오피스 앱 번들 HWP/HWT 후보 317개"))
        expect(readme).to(contain("tree 기준 `COMPATIBLE_DOCUMENT` child `TRACK_CHANGE = 32`"))
        expect(readme).to(contain("top-level record도 아니고 로컬 앱 resource"))
        expect(readme).to(contain("readable external 후보 384개"))
        expect(readme).to(contain("`PrvImage`와 `PrvText`가 모두 없는 compressed HWP"))
        expect(readme).to(contain("동시에 없는 reader 경로"))
        expect(readme).to(contain("별도 승인 없이 repository fixture로 편입하지 않음"))
        expect(readme).to(contain("DRM/certDRM bit가 없어 실제 DRM fixture는 별도 확보 필요"))
        expect(readme).to(contain("2026-06-27"))
        assertPublicRepositoryScanEvidence(in: readme)

        guard let lineCoverage = documentedPercentage(after: "line coverage는", in: readme),
              let regionCoverage = documentedPercentage(after: "region coverage는", in: readme)
        else {
            return fail("Expected README to document numeric CoreHwp coverage")
        }

        expect(lineCoverage >= 95.0) == true
        expect(regionCoverage >= 95.0) == true
    }
}

private func lowerReaderDocumentation() throws -> String {
    let root = projectRootURL()
    let readerSupport = try String(
        contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("CoreHwp")
            .appendingPathComponent("AGENTS.md"),
        encoding: .utf8
    )
    let fixtureGuide = try String(
        contentsOf: FixtureLoader.root.appendingPathComponent("README.md"),
        encoding: .utf8
    )
    return readerSupport + "\n" + fixtureGuide
}

private func assertPublicRepositoryScanEvidence(in readme: String) {
    expect(readme).to(contain("edwardkim/rhwp"))
    expect(readme).to(contain("123jimin/node-hwp"))
    expect(readme).to(contain("postmelee/alhangeul-macos"))
    expect(readme).to(contain("disjukr/hwpkit"))
    expect(readme).to(contain("dgahn/hwplib-dsl"))
    expect(readme).to(contain("markers={missing-preview-image:2, missing-preview-text:2}"))
    expect(readme).to(contain("markers={deployment:3}"))
    expect(readme).to(contain(
        "markers={deployment:6, missing-preview-image:19, missing-preview-text:19}"
    ))
    expect(readme).to(contain("scanned=151"))
    expect(readme).to(contain("scanned=84"))
    expect(readme).to(contain("nested_track_change=26"))
    expect(readme).to(contain("nested_track_change=73"))
    expect(readme).to(contain("HwpOtherCtrlId.form"))
    expect(readme).to(contain("HwpCtrlId.form"))
    expect(readme).to(contain("hwplib"))
    expect(readme).to(contain("provenance"))
}

private func projectRootURL() -> URL {
    FixtureLoader.root
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
