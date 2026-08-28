@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpFile` 진입점의 HWPX 자동 감지와 문서 조립 종단 경로.
///
/// 실픽스처 기반 기능 검증은 HwpxFixtures 하니스가 맡고, 여기서는 합성
/// 아카이브로 라우팅·조립·복구·오류 표면을 고정한다.
final class HwpxFileTests: XCTestCase {
    private let versionXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\
    <hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" \
    tagetApplication="WORDPROCESSOR" major="5" minor="1" micro="1" buildNumber="0"/>
    """

    private let manifestXML = """
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf/">\
    <opf:manifest>\
    <opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>\
    <opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>\
    <opf:item id="image1" href="BinData/image1.png" media-type="image/png"/>\
    </opf:manifest>\
    <opf:spine><opf:itemref idref="header"/><opf:itemref idref="section0"/>\
    </opf:spine></opf:package>
    """

    private let headerXML = """
    <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" version="1.5" secCnt="1">\
    <hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>\
    <hh:refList>\
    <hh:fontfaces itemCnt="1"><hh:fontface lang="HANGUL" fontCnt="1">\
    <hh:font id="0" face="함초롬바탕" type="TTF" isEmbedded="0"/>\
    </hh:fontface></hh:fontfaces>\
    <hh:charProperties itemCnt="1">\
    <hh:charPr id="0" height="1000" textColor="#000000"/>\
    </hh:charProperties>\
    <hh:paraProperties itemCnt="1"><hh:paraPr id="0">\
    <hh:align horizontal="JUSTIFY"/></hh:paraPr></hh:paraProperties>\
    <hh:styles itemCnt="1">\
    <hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="0" \
    charPrIDRef="0" nextStyleIDRef="0"/></hh:styles>\
    </hh:refList></hh:head>
    """

    private let sectionXML = """
    <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" \
    xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
    <hp:p id="1" paraPrIDRef="0" styleIDRef="0">\
    <hp:run charPrIDRef="0">\
    <hp:secPr id="" spaceColumns="1134" tabStop="8000">\
    <hp:pagePr landscape="WIDELY" width="59528" height="84186">\
    <hp:margin header="4252" footer="4252" gutter="0" left="8504" right="8504" \
    top="5668" bottom="4252"/></hp:pagePr></hp:secPr>\
    <hp:ctrl><hp:colPr id="" type="NEWSPAPER" layout="LEFT" colCount="1" \
    sameSz="1" sameGap="0"/></hp:ctrl>\
    </hp:run>\
    <hp:run charPrIDRef="0"><hp:t>HWPX 본문</hp:t></hp:run>\
    <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
    textheight="1000" baseline="850" spacing="600" horzpos="0" horzsize="42520" \
    flags="393216"/></hp:linesegarray></hp:p></hs:sec>
    """

    private func makeArchive(
        sectionXML: String? = nil,
        includePreview: Bool = true
    ) -> Data {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "mimetype",
                content: Data("application/hwp+zip".utf8),
                method: 0
            ),
            .init(name: "version.xml", content: Data(versionXML.utf8), method: 8),
            .init(
                name: "Contents/content.hpf", content: Data(manifestXML.utf8), method: 8
            ),
            .init(name: "Contents/header.xml", content: Data(headerXML.utf8), method: 8),
            .init(
                name: "Contents/section0.xml",
                content: Data((sectionXML ?? self.sectionXML).utf8),
                method: 8
            ),
            .init(name: "BinData/image1.png", content: Data("png-bytes".utf8), method: 0),
        ]
        if includePreview {
            builder.entries.append(
                .init(name: "Preview/PrvText.txt", content: Data("HWPX 본문".utf8), method: 0)
            )
        }
        return builder.build()
    }

    func testLoadsHwpxFromDataWithAutoDetection() throws {
        let hwp = try HwpFile(fromData: makeArchive())

        expect(hwp.fileHeader.version) == HwpVersion(5, 1, 1, 0)
        expect(hwp.sectionArray.count) == 1
        expect(hwp.viewSectionArray).to(beEmpty())
        expect(hwp.displaySectionArray.count) == 1
        expect(hwp.docInfo.documentProperties.sectionSize) == 1
        expect(hwp.docInfo.idMappings.charShapeArray.count) == 1
        expect(hwp.docInfo.idMappings.binDataArray.count) == 1
        expect(hwp.binaryDataArray.map(\.name)) == ["BIN0001.png"]
        expect(hwp.previewText.text) == "HWPX 본문"

        let paragraph = hwp.sectionArray[0].paragraph[0]
        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        guard case .section = ctrls.first else {
            return fail("Expected leading .section control, got \(ctrls)")
        }
        // 본문 텍스트가 WCHAR 스트림에 실려 있다: ext2 + ext2 + "HWPX 본문" + 13.
        expect(paragraph.paraText?.wcharCount) == 8 + 8 + 7 + 1
    }

    func testLoadsHwpxFromPathAndWrapper() throws {
        let archive = makeArchive()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hwpx-e2e-\(UUID().uuidString).hwpx")
        try archive.write(to: url)
        defer {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // 임시 파일 정리 실패는 테스트 결과와 무관하다.
            }
        }

        let fromPath = try HwpFile(fromPath: url.path)
        expect(fromPath.sectionArray.count) == 1

        let fromWrapper = try HwpFile(
            fromWrapper: FileWrapper(regularFileWithContents: archive)
        )
        expect(fromWrapper.sectionArray.count) == 1
        expect(fromPath) == fromWrapper
    }

    func testNonZipInputKeepsExistingOLEErrorSurface() {
        expect {
            _ = try HwpFile(fromData: Data("definitely not a container".utf8))
        }.to(throwError { error in
            guard case HwpError.invalidOLEFile = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
        })
    }

    func testForeignZipIsRejectedAtContainerGate() {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "mimetype",
                content: Data("application/vnd.oasis.opendocument.text".utf8),
                method: 0
            ),
        ]

        expect {
            _ = try HwpFile(fromData: builder.build())
        }.to(throwError { error in
            guard case let HwpError.invalidArchive(reason) = error else {
                return fail("Expected invalidArchive, got \(error)")
            }
            expect(reason).to(contain("unexpected mimetype"))
        })
    }

    func testBrokenSectionFailsFastByDefaultAndRecoversInViewerMode() throws {
        let archive = makeArchive(sectionXML: "<hs:sec xmlns:hs=\"urn:x\"><broken")

        expect {
            _ = try HwpFile(fromData: archive)
        }.to(throwError { error in
            guard case HwpError.invalidXML = error else {
                return fail("Expected invalidXML, got \(error)")
            }
        })

        // 복구 모드 — 구역 수를 보존한 placeholder로 강등되고 문서는 열린다.
        let recovered = try HwpFile(fromData: archive, options: .viewer)
        expect(recovered.sectionArray.count) == 1
        expect(recovered.sectionArray[0].parseFailure).notTo(beNil())
    }

    func testMissingHeaderEntryThrowsTypedError() {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(
                name: "Contents/content.hpf", content: Data(manifestXML.utf8), method: 8
            ),
        ]

        expect {
            _ = try HwpFile(fromData: builder.build())
        }.to(throwError { error in
            guard case let HwpError.archiveEntryDoesNotExist(name) = error else {
                return fail("Expected archiveEntryDoesNotExist, got \(error)")
            }
            expect(name) == "Contents/header.xml"
        })
    }

    func testParseDiagnosticsReportDegradedHwpxElements() throws {
        let section = """
        <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" \
        xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
        <hp:p id="1" paraPrIDRef="0" styleIDRef="0">\
        <hp:run charPrIDRef="0">\
        <hp:ctrl><hp:header id="9"/></hp:ctrl><hp:t>가</hp:t>\
        </hp:run></hp:p></hs:sec>
        """
        let hwp = try HwpFile(fromData: makeArchive(sectionXML: section))

        let diagnostics = hwp.parseDiagnostics()
        // 머리말 강등: notImplementedControl(실제 4CC)과 합성 tagId(0)의
        // unknownRecord 쌍으로 이중 보고된다.
        expect(diagnostics.contains { diagnostic in
            diagnostic.kind == .notImplementedControl
                && diagnostic.ctrlId == HwpOtherCtrlId.header.rawValue
        }) == true
        expect(diagnostics.contains { diagnostic in
            diagnostic.kind == .unknownRecord && diagnostic.tagId == hwpxSyntheticTagId
        }) == true
    }
}
