@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// version.xml·content.hpf·Preview·BinData 매퍼 — 합성 입력은 리포 정책대로
/// malformed/경계 경로 위주고, 정상 경로는 실픽스처 스위트가 이어받는다.
final class HwpxDocumentPartMapperTests: XCTestCase {
    // MARK: - version.xml

    func testVersionMapsFourComponents() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\
        <hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" \
        tagetApplication="WORDPROCESSOR" major="5" minor="1" micro="1" \
        buildNumber="0" os="10" xmlVersion="1.5" application="Hancom Office Hangul"/>
        """

        let version = try HwpxVersionMapper.version(fromVersionXML: Data(xml.utf8))

        expect(version) == HwpVersion(5, 1, 1, 0)
    }

    func testVersionDefaultsWhenEntryIsAbsent() throws {
        expect(try HwpxVersionMapper.version(fromVersionXML: nil))
            == HwpxVersionMapper.defaultVersion
    }

    func testVersionDefaultsMissingAttributes() throws {
        let version = try HwpxVersionMapper.version(
            fromVersionXML: Data(
                """
                <hv:HCFVersion \
                xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version"/>
                """.utf8
            )
        )

        expect(version) == HwpVersion(5, 1, 1, 0)
    }

    func testVersionInForeignNamespaceIsRejected() {
        // 동명 요소라도 낯선 namespace면 OWPML로 오인하지 않는다.
        expect {
            _ = try HwpxVersionMapper.version(
                fromVersionXML: Data("<hv:HCFVersion xmlns:hv=\"urn:x\"/>".utf8)
            )
        }.to(throwError { error in
            guard case HwpError.invalidXML = error else {
                return fail("Expected invalidXML, got \(error)")
            }
        })
    }

    func testVersionThrowsOnUnexpectedRootElement() {
        expect {
            _ = try HwpxVersionMapper.version(fromVersionXML: Data("<other/>".utf8))
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "version.xml"
            expect(reason).to(contain("root element"))
        })
    }

    func testVersionThrowsOnMalformedXML() {
        expect {
            _ = try HwpxVersionMapper.version(fromVersionXML: Data("<broken".utf8))
        }.to(throwError { error in
            guard case HwpError.invalidXML = error else {
                return fail("Expected invalidXML, got \(error)")
            }
        })
    }

    func testFileHeaderSynthesisCarriesVersionAndNoUnsupportedBits() {
        let header = HwpxVersionMapper.fileHeader(version: HwpVersion(5, 1, 1, 0))

        expect(header.version) == HwpVersion(5, 1, 1, 0)
        expect(header.encryptVersion) == 0
        expect(header.fileProperty.unsupportedFeature).to(beNil())
    }

    // MARK: - content.hpf

    private let manifestXML = """
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf/">\
    <opf:metadata><opf:title/></opf:metadata>\
    <opf:manifest>\
    <opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>\
    <opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>\
    <opf:item id="section1" href="Contents/section1.xml" media-type="application/xml"/>\
    <opf:item id="image1" href="BinData/image1.png" media-type="image/png"/>\
    <opf:item id="image2" href="BinData/image2.jpg" media-type="image/jpeg"/>\
    <opf:item id="settings" href="settings.xml" media-type="application/xml"/>\
    </opf:manifest>\
    <opf:spine>\
    <opf:itemref idref="header" linear="yes"/>\
    <opf:itemref idref="section1" linear="yes"/>\
    <opf:itemref idref="section0" linear="yes"/>\
    <opf:itemref idref="missing" linear="yes"/>\
    </opf:spine></opf:package>
    """

    func testManifestParsesItemsSpineOrderAndBinData() throws {
        let manifest = try HwpxManifest.parse(Data(manifestXML.utf8))

        expect(manifest.items.count) == 6
        // spine 순서가 정본이다 — 숫자 순서가 아니라 나열 순서를 따르고,
        // 구역이 아닌 항목(header)과 미등재 idref는 걸러진다.
        expect(manifest.sectionHrefs) == [
            "Contents/section1.xml", "Contents/section0.xml",
        ]
        expect(manifest.binDataItems.map(\.id)) == ["image1", "image2"]
    }

    func testManifestThrowsOnUnexpectedRootElement() {
        expect {
            _ = try HwpxManifest.parse(Data("<html/>".utf8))
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/content.hpf"
            expect(reason).to(contain("root element"))
        })
    }

    func testManifestWithoutSpineHasNoSectionHrefs() throws {
        let manifest = try HwpxManifest.parse(
            Data("<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf/\"/>".utf8)
        )

        expect(manifest.sectionHrefs).to(beEmpty())
        expect(manifest.binDataItems).to(beEmpty())
    }

    // MARK: - Preview

    func testPreviewTextReencodesUTF8ToUTF16LE() {
        let preview = HwpxPreviewMapper.previewText(from: Data("보\r\n".utf8))

        expect(preview.text) == "보\r\n"
        expect(preview.rawPayload) == Data([0xF4, 0xBC, 0x0D, 0x00, 0x0A, 0x00])
    }

    func testPreviewTextHandlesUTF8BOM() {
        let preview = HwpxPreviewMapper.previewText(
            from: Data([0xEF, 0xBB, 0xBF]) + Data("한".utf8)
        )

        expect(preview.text) == "한"
    }

    func testPreviewTextHandlesUTF16BOM() {
        // UTF-16LE BOM + "한"(D55C)
        let preview = HwpxPreviewMapper.previewText(
            from: Data([0xFF, 0xFE, 0x5C, 0xD5])
        )

        expect(preview.text) == "한"
    }

    func testPreviewTextFallsBackOnAbsenceAndGarbage() {
        expect(HwpxPreviewMapper.previewText(from: nil)) == HwpPreviewText()
        expect(HwpxPreviewMapper.previewText(from: Data())) == HwpPreviewText()
        // 유효 UTF-8도 UTF-16도 아닌 바이트열.
        expect(HwpxPreviewMapper.previewText(from: Data([0xFF, 0x00, 0xFE])))
            == HwpPreviewText()
    }

    func testPreviewImageDetectsFormatAndDefaultsOnAbsence() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

        expect(HwpxPreviewMapper.previewImage(from: png).format) == .png
        expect(HwpxPreviewMapper.previewImage(from: png).image) == png
        expect(HwpxPreviewMapper.previewImage(from: nil).format)
            == HwpPreviewImageFormat.none
    }

    // MARK: - BinData

    private func makeContainer(entries: [ZipBuilder.Entry]) throws -> HwpxContainer {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
        ] + entries
        return try HwpxContainer(data: builder.build(), limits: .default)
    }

    func testBinDataCatalogAssignsSequentialStreamIds() throws {
        let manifest = try HwpxManifest.parse(Data(manifestXML.utf8))
        var container = try makeContainer(entries: [
            .init(name: "BinData/image1.png", content: Data("png-bytes".utf8), method: 8),
            .init(name: "BinData/image2.jpg", content: Data("jpg-bytes".utf8), method: 0),
        ])

        let catalog = try HwpxBinDataMapper.map(manifest: manifest, container: &container)

        expect(catalog.binDataArray.count) == 2
        expect(catalog.binDataArray[0].streamId) == 1
        expect(catalog.binDataArray[0].extensionName) == "png"
        expect(catalog.binDataArray[0].property.type) == HwpBinDataType.embedding
        expect(catalog.binDataArray[1].streamId) == 2
        expect(catalog.binaryDataArray.map(\.name)) == ["BIN0001.png", "BIN0002.jpg"]
        // HwpImageStore 조인의 전제 — 이름에서 파생한 streamId가 부여값과 같다.
        expect(catalog.binaryDataArray.map(\.streamId)) == [1, 2]
        expect(catalog.binaryDataArray[0].data) == Data("png-bytes".utf8)
        expect(catalog.binItemIdByManifestId) == ["image1": 1, "image2": 2]
    }

    func testBinDataCatalogKeepsIdSpaceWhenEntryIsMissing() throws {
        // image1 엔트리가 아카이브에 없다 — 메타는 남아 id 공간이 밀리지 않고
        // 스트림만 비어 그 그림이 placeholder로 강등된다.
        let manifest = try HwpxManifest.parse(Data(manifestXML.utf8))
        var container = try makeContainer(entries: [
            .init(name: "BinData/image2.jpg", content: Data("jpg-bytes".utf8), method: 0),
        ])

        let catalog = try HwpxBinDataMapper.map(manifest: manifest, container: &container)

        expect(catalog.binDataArray.count) == 2
        expect(catalog.binDataArray[0].streamId) == 1
        expect(catalog.binDataArray[1].streamId) == 2
        expect(catalog.binaryDataArray.map(\.name)) == ["BIN0002.jpg"]
        expect(catalog.binItemIdByManifestId["image2"]) == 2
    }

    func testExtensionNameFallsBackToBin() {
        expect(HwpxBinDataMapper.extensionName(of: "BinData/image1.png")) == "png"
        expect(HwpxBinDataMapper.extensionName(of: "BinData/noext")) == "bin"
        expect(HwpxBinDataMapper.extensionName(of: "BinData/trailingdot.")) == "bin"
    }
}
