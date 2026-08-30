@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 구역·secPr·lineseg 매핑의 구조 불변식 — 조작·불완전 입력이 조판 전제를
/// 조용히 어기지 않는지 고정한다.
final class HwpxSectionInvariantTests: XCTestCase {
    private func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/section0.xml")
    }

    func testSectionWhoseFirstParagraphLacksSecPrIsRejected() {
        // 문단은 파싱되지만 첫 문단에 secPr가 없다 — 그대로 받으면 paginator가
        // 구역 경계를 인식하지 못해 앞 구역의 기하로 조판된다.
        let body = "<hp:p id=\"1\" paraPrIDRef=\"0\" styleIDRef=\"0\">"
            + "<hp:run charPrIDRef=\"7\"><hp:t>가</hp:t></hp:run></hp:p>"
        expect {
            _ = try HwpxSectionFixture.mapSection(body)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("secPr"))
        })
    }

    func testLineCacheMissingGeometryAttributeDegradesToReflow() throws {
        // vertsize 부재 — 0을 합성하면 높이 0 줄이 절대 조판에 채택된다.
        // 대조군: 속성이 온전한 blankBody 캐시는 채택된다.
        let clean = try HwpxSectionFixture.mapSection(HwpxSectionFixture.blankBody)
        expect(clean.paragraph[0].paraLineSeg.paraLineSegInternalArray.count) == 1

        let degraded = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody.replacingOccurrences(
                of: " vertsize=\"1000\"", with: ""
            )
        )
        expect(degraded.paragraph[0].paraLineSeg.paraLineSegInternalArray).to(beEmpty())
    }

    func testNestedUnknownElementsAreRetainedRecursively() throws {
        // 바이너리 변환(HwpUnknownRecord(HwpRecord))과 같은 재귀 보존 —
        // 평탄 변환이면 진단 walker의 .child[i] 재귀가 안쪽에 닿지 못한다.
        let section = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody
                + "<ext:outer xmlns:ext=\"urn:x\"><ext:inner/></ext:outer>"
        )

        let outer = try XCTUnwrap(section.unknownRecords.first {
            String(bytes: $0.payload, encoding: .utf8) == "outer"
        })
        expect(outer.children.count) == 1
        expect(outer.children.first.flatMap {
            String(bytes: $0.payload, encoding: .utf8)
        }) == "inner"
    }

    func testPagePrLookupIgnoresOtherVocabularyDecoy() throws {
        // firstChild 전역 매칭이면 진짜 앞의 hh:pagePr 디코이가 쪽 기하를 대체한다.
        let xml = """
        <hp:secPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" id="">\
        <hh:pagePr width="11111" height="22222"/>\
        <hp:pagePr width="59528" height="84186"/>\
        </hp:secPr>
        """
        let sectionDef = HwpxSecPrMapper.mapSectionDef(try parse(xml))

        expect(sectionDef.pageDef.width) == 59528
        expect(sectionDef.pageDef.height) == 84186
        // 디코이는 소비되지 않았으므로 진단에 남는다.
        let names = sectionDef.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("pagePr"))
    }

    func testColumnLookupsIgnoreOtherVocabularyDecoys() throws {
        let xml = """
        <hp:colPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" id="" type="NEWSPAPER" \
        layout="LEFT" colCount="2" sameSz="0" sameGap="0">\
        <hh:colSz width="999" gap="9"/>\
        <hp:colSz width="100" gap="1"/><hp:colSz width="200" gap="2"/>\
        <hh:colLine type="SOLID" width="0.4 mm" color="#FF0000"/>\
        </hp:colPr>
        """
        let column = HwpxSecPrMapper.mapColumn(try parse(xml))

        expect(column.widthArray) == [100, 200]
        // hh:colLine 디코이는 구분선을 만들지 않는다.
        expect(column.dividerType) == 0
        let names = column.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("colSz"))
        expect(names).to(contain("colLine"))
    }
}
