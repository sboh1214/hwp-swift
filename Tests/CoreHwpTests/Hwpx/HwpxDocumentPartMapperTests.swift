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

    func testVersionInWrongKnownVocabularyIsRejected() {
        // known 집합의 다른 vocabulary(head)도 거부한다 — urn:x 테스트와 짝.
        expect {
            _ = try HwpxVersionMapper.version(fromVersionXML: Data(
                """
                <x:HCFVersion xmlns:x="http://www.hancom.co.kr/hwpml/2011/head"/>
                """.utf8
            ))
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
        let manifest = try parseManifest(manifestXML)

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
            _ = try parseManifest("<html/>")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/content.hpf"
            expect(reason).to(contain("root element"))
        })
    }

    func testManifestRootInWrongKnownVocabularyIsRejected() {
        // OPF package 루트가 한컴 head namespace로 위장해도 거부한다.
        expect {
            _ = try parseManifest(
                """
                <x:package xmlns:x="http://www.hancom.co.kr/hwpml/2011/head"/>
                """
            )
        }.to(throwError { error in
            guard case HwpError.invalidXML = error else {
                return fail("Expected invalidXML, got \(error)")
            }
        })
    }

    func testManifestChildrenIgnoreDecoysFromOtherKnownVocabularies() throws {
        // manifest/spine 자식은 정의상 OPF다 — 앞에 선 known vocabulary의
        // 동명 요소(hh:manifest·hh:spine)에 가로채이면 안 된다.
        let manifest = try parseManifest(
            """
            <opf:package xmlns:opf="http://www.idpf.org/2007/opf/" \
            xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head">\
            <hh:manifest><hh:item id="fake" href="Contents/section9.xml" \
            media-type="application/xml"/></hh:manifest>\
            <opf:manifest><opf:item id="s0" href="Contents/section0.xml" \
            media-type="application/xml"/></opf:manifest>\
            <hh:spine><hh:itemref idref="fake"/></hh:spine>\
            <opf:spine><opf:itemref idref="s0"/></opf:spine>\
            </opf:package>
            """
        )

        expect(manifest.items.map(\.href)) == ["Contents/section0.xml"]
        expect(manifest.sectionHrefs) == ["Contents/section0.xml"]
    }

    func testManifestWithoutSpineHasNoSectionHrefs() throws {
        let manifest = try parseManifest("<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf/\"/>")

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

    func testBinDataItemsBeyondTheIdSpaceAreRejected() throws {
        /// BinItem id는 1-based 16비트다 — 종전에는 65,536번째부터 조용히
        /// 잘려 그 항목을 참조하는 그림이 id 0으로 떨어졌는데 문서는 성공한
        /// 파스로 보고됐다. manifest XML을 짓지 않고 항목만 합성한다.
        func manifest(itemCount: Int) -> HwpxManifest {
            HwpxManifest(
                items: (0 ..< itemCount).map {
                    HwpxManifest.Item(
                        id: "b\($0)", href: "BinData/f\($0).png", mediaType: "image/png"
                    )
                },
                sectionHrefs: [],
                entry: "Package/main.hpf"
            )
        }
        var container = try makeContainer(entries: [])

        // 대조군: 경계값 65,535개는 그대로 실린다.
        let catalog = try HwpxBinDataMapper.map(
            manifest: manifest(itemCount: 65535), container: &container
        )
        expect(catalog.binDataArray.count) == 65535
        expect(catalog.binDataArray.last?.streamId) == 65535

        expect {
            _ = try HwpxBinDataMapper.map(
                manifest: manifest(itemCount: 65536), container: &container
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            // 진단은 해석된 패키지 경로를 가리킨다.
            expect(entry) == "Package/main.hpf"
            expect(reason).to(contain("65,535"))
        })
    }

    private func makeContainer(entries: [ZipBuilder.Entry]) throws -> HwpxContainer {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
        ] + entries
        return try HwpxContainer(data: builder.build(), limits: .default)
    }

    func testBinDataCatalogAssignsSequentialStreamIds() throws {
        let manifest = try parseManifest(manifestXML)
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
        let manifest = try parseManifest(manifestXML)
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

/// 진단 엔트리 이름은 이 스위트의 관심사가 아니다 — 관례 경로로 고정한다
/// (해석된 경로를 싣는지는 HwpxFileTests가 본다).
private func parseManifest(_ xml: String) throws -> HwpxManifest {
    try HwpxManifest.parse(Data(xml.utf8), entry: HwpxContainer.EntryName.manifest)
}
