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

    func testChildrenOfRecognizedInlineElementsAreDemoted() throws {
        // <hp:tab> 같은 인식 인라인 요소는 잎이다 — 하위를 삼키면 진단에서
        // 빠지고 positionCertain이 참으로 남아 잘못된 lineseg 캐시를 쓴다.
        // 대조군: 빈 인라인 요소는 위치 확실로 남아 캐시가 채택된다.
        let clean = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody.replacingOccurrences(
                of: "<hp:t/>", with: "<hp:t>가<hp:tab/></hp:t>"
            )
        )
        expect(clean.paragraph[0].paraLineSeg.paraLineSegInternalArray.count) == 1

        let section = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody.replacingOccurrences(
                of: "<hp:t/>",
                with: "<hp:t>가<hp:tab><ext:metadata xmlns:ext=\"urn:x\"/></hp:tab></hp:t>"
            )
        )

        let paragraph = section.paragraph[0]
        let names = paragraph.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("metadata"))
        expect(paragraph.paraLineSeg.paraLineSegInternalArray).to(beEmpty())
        // 인식된 tab 컨트롤 자체는 종전대로 방출된다.
        expect(paragraph.paraText?.charArray.contains {
            $0.type == .inline && $0.value == 9
        }) == true
    }

    func testLineCacheWithNestedUnknownInsideSegmentIsRejected() throws {
        // lineseg는 속성 전용 — 유효 lineseg 안의 미지 자식은 직계 수
        // 대조를 통과하므로 세그먼트 층에서 따로 거부해야 한다.
        let section = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody.replacingOccurrences(
                of: "flags=\"393216\"/>",
                with: "flags=\"393216\"><hp:cacheExtra/></hp:lineseg>"
            )
        )

        let paragraph = section.paragraph[0]
        expect(paragraph.paraLineSeg.paraLineSegInternalArray).to(beEmpty())
        let names = paragraph.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("cacheExtra"))
    }

    func testSecPrWrapperDescendantsDegradeIntoDiagnostics() throws {
        // pagePr는 margin만, margin·startNum은 속성만 읽는다 — 래퍼 안
        // 확장 요소가 진단에 남아야 한다.
        let xml = """
        <hp:secPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" id="">\
        <hp:pagePr width="59528" height="84186"><hp:pagePrExtra/>\
        <hp:margin left="8504"><hp:marginExtra/></hp:margin></hp:pagePr>\
        <hp:startNum page="0"><hp:startNumExtra/></hp:startNum>\
        </hp:secPr>
        """
        let sectionDef = HwpxSecPrMapper.mapSectionDef(try parse(xml))

        let names = sectionDef.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("pagePrExtra"))
        expect(names).to(contain("marginExtra"))
        expect(names).to(contain("startNumExtra"))
        // 소비되는 래퍼 자체는 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("margin"))
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

    func testVariableColumnCountFollowsParsedSizes() throws {
        // 선언 colCount=3에 colSz 2개 — 파싱 구조가 정본이다. 선언을 믿으면
        // columnFrames의 count 대조(widths.count == count)가 widthArray를
        // 버리고 등폭으로 그린다.
        let xml = """
        <hp:colPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" id="" \
        type="NEWSPAPER" layout="LEFT" colCount="3" sameSz="0" sameGap="0">\
        <hp:colSz width="100" gap="1"/><hp:colSz width="200" gap="2"/>\
        </hp:colPr>
        """
        let column = HwpxSecPrMapper.mapColumn(try parse(xml))

        expect(column.property.count) == 2
        expect(column.widthArray) == [100, 200]
    }

    func testOversizedVariableColumnListFallsBackToEqualWidth() throws {
        // 8비트 count가 못 담는 폭 목록은 채택 불능 — 등폭 폴백으로 그리되
        // 버려진 colSz가 진단에 남아야 조용히 지나가지 않는다.
        let sizes = String(repeating: "<hp:colSz width=\"10\" gap=\"1\"/>", count: 256)
        let xml = """
        <hp:colPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" id="" \
        type="NEWSPAPER" layout="LEFT" colCount="256" sameSz="0" \
        sameGap="0">\(sizes)</hp:colPr>
        """
        let column = HwpxSecPrMapper.mapColumn(try parse(xml))

        expect(column.widthArray).to(beNil())
        let names = column.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names.filter { $0 == "colSz" }.count) == 256
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
