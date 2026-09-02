@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 헤더 파트 해석 — manifest 선언·관례 폴백·spine 제외가 **같은 경로**를
/// 봐야 한다. 종단 경로의 나머지는 `HwpxFileTests`가 맡는다.
final class HwpxHeaderResolutionTests: XCTestCase {
    private let versionXML = HwpxArchiveFixture.versionXML
    private let manifestXML = HwpxArchiveFixture.manifestXML
    private let headerXML = HwpxArchiveFixture.headerXML
    private let sectionXML = HwpxArchiveFixture.sectionXML

    private var headerItem: String {
        "<opf:item id=\"header\" href=\"Contents/header.xml\" "
            + "media-type=\"application/xml\"/>"
    }

    private func archiveWithHeader(manifest: String, extra: [ZipBuilder.Entry]) -> Data {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(name: "version.xml", content: Data(versionXML.utf8), method: 8),
            .init(name: "Contents/content.hpf", content: Data(manifest.utf8), method: 8),
            .init(
                name: "Contents/section0.xml", content: Data(sectionXML.utf8), method: 8
            ),
        ] + extra
        return builder.build()
    }

    private var declaredElsewhere: String {
        manifestXML.replacingOccurrences(
            of: headerItem,
            with: "<opf:item id=\"header\" href=\"Package/head.xml\" "
                + "media-type=\"application/xml\"/>"
        )
    }

    func testHeaderIsResolvedThroughTheManifestItem() throws {
        // 헤더도 선언이 정본이다 — 관례 경로만 보면 재포장 후 남은 낡은
        // Contents/header.xml의 스타일·id 테이블을 조용히 쓴다. 두 헤더의
        // baseSize를 갈라 어느 쪽을 읽었는지 관측한다.
        let stale = headerXML.replacingOccurrences(
            of: "height=\"1000\"", with: "height=\"2000\""
        )
        let hwp = try HwpFile(fromData: archiveWithHeader(
            manifest: declaredElsewhere,
            extra: [
                .init(name: "Package/head.xml", content: Data(headerXML.utf8), method: 8),
                .init(name: "Contents/header.xml", content: Data(stale.utf8), method: 8),
            ]
        ))
        expect(hwp.docInfo.idMappings.charShapeArray[0].baseSize) == 1000

        // 대조군: 선언이 없으면 관례 경로로 폴백한다.
        let undeclared = manifestXML.replacingOccurrences(of: headerItem, with: "")
        let fallback = try HwpFile(fromData: archiveWithHeader(
            manifest: undeclared,
            extra: [
                .init(name: "Contents/header.xml", content: Data(stale.utf8), method: 8),
            ]
        ))
        expect(fallback.docInfo.idMappings.charShapeArray[0].baseSize) == 2000
    }

    func testFallbackHeaderWithForeignIdStaysOutOfTheSpine() throws {
        // 폴백이 지원하는 생산자(id≠"header"·관례 href)에서는 spine 제외도
        // 같은 폴백 경로를 봐야 한다 — 선언만 비교하면 헤더 itemref가
        // 구역으로 새어 들어가 기본 로드가 <head> 루트로 무너지고, 복구
        // 모드는 가짜 placeholder 구역을 하나 더 만든다.
        let manifest = manifestXML
            .replacingOccurrences(of: "id=\"header\"", with: "id=\"head-part\"")
            .replacingOccurrences(of: "idref=\"header\"", with: "idref=\"head-part\"")
        let archive = archiveWithHeader(manifest: manifest, extra: [
            .init(name: "Contents/header.xml", content: Data(headerXML.utf8), method: 8),
        ])

        let hwp = try HwpFile(fromData: archive)
        expect(hwp.sectionArray.count) == 1
        expect(hwp.docInfo.documentProperties.sectionSize) == 1

        let recovered = try HwpFile(fromData: archive, options: .viewer)
        expect(recovered.sectionArray.count) == 1
        expect(recovered.sectionArray[0].parseFailure).to(beNil())
    }

    func testMalformedResolvedHeaderReportsItsOwnPath() {
        // 진단도 실제로 읽은 경로를 가리켜야 한다 (패키지 문서와 같은 규약).
        let archive = archiveWithHeader(
            manifest: declaredElsewhere,
            extra: [
                .init(name: "Package/head.xml", content: Data("<html/>".utf8), method: 8),
            ]
        )

        expect {
            _ = try HwpFile(fromData: archive)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, _) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Package/head.xml"
        })
    }
}
