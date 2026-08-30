@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// header.xml의 미해석 강등·namespace 좁히기 계약.
final class HwpxHeaderDiagnosticsTests: XCTestCase {
    func testFontFacesAreResolvedWhenCharPropertiesComeFirst() throws {
        // 1차 등록 패스의 순서 독립 약속은 fontfaces에도 성립해야 한다 —
        // charProperties가 앞에 와도 fontRef가 빈 테이블로 0에 굳지 않는다.
        guard let start = HwpxHeaderFixture.headerXML.range(of: "<hh:fontfaces"),
              let end = HwpxHeaderFixture.headerXML.range(of: "</hh:fontfaces>")
        else {
            return fail("HwpxHeaderFixture.headerXML must contain a fontfaces family")
        }
        let fontfaces = String(HwpxHeaderFixture.headerXML[start.lowerBound ..< end.upperBound])
        let reordered = HwpxHeaderFixture.headerXML
            .replacingOccurrences(of: fontfaces, with: "")
            .replacingOccurrences(
                of: "</hh:charProperties>",
                with: "</hh:charProperties>" + fontfaces
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(reordered)

        let first = docInfo.idMappings.charShapeArray[0]
        expect(first.faceId[0]) == 1
        expect(first.faceId[1]) == 0
        expect(docInfo.idMappings.faceNameKoreanArray.count) == 2
    }

    func testNumberingAndBulletReferencesAreOneBased() throws {
        // 조판이 `> 0` 게이트 뒤에서 -1로 되돌리므로 첫 정의(오프셋 0)도
        // 1로 실려야 사라지지 않는다. 개요·없음은 이 배열을 안 써 0이다.
        let withHeadings = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:heading type=\"OUTLINE\" idRef=\"0\" level=\"2\"/>",
                with: "<hh:heading type=\"NUMBER\" idRef=\"1\" level=\"2\"/>"
            )
            .replacingOccurrences(
                of: "</hh:paraProperties>",
                with: "<hh:paraPr id=\"77\">"
                    + "<hh:heading type=\"BULLET\" idRef=\"1\" level=\"0\"/>"
                    + "</hh:paraPr></hh:paraProperties>"
            )
            .replacingOccurrences(
                of: "<hh:tabProperties",
                with: "<hh:numberings itemCnt=\"1\"><hh:numbering id=\"1\"/></hh:numberings>"
                    + "<hh:bullets itemCnt=\"1\"><hh:bullet id=\"1\"/></hh:bullets>"
                    + "<hh:tabProperties"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withHeadings)
        let paraShapes = docInfo.idMappings.paraShapeArray

        expect(paraShapes[0].property1Info.headingTypeRawValue) == 2
        expect(paraShapes[0].numberingOrBulletId) == 1
        expect(paraShapes[2].property1Info.headingTypeRawValue) == 3
        expect(paraShapes[2].numberingOrBulletId) == 1
        // 머리 없음(0)은 배열을 쓰지 않으므로 0 유지 (음성 대조).
        expect(paraShapes[1].property1Info.headingTypeRawValue) == 0
        expect(paraShapes[1].numberingOrBulletId) == 0
    }

    func testDanglingHeadingReferenceStaysZero() throws {
        // 없는 idRef는 0(없음)으로 남아야 한다 — +1을 무조건 걸면 댕글링이
        // 첫 정의를 가리키게 된다 ("댕글링은 0 폴백" 규약).
        let withDangling = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:heading type=\"OUTLINE\" idRef=\"0\" level=\"2\"/>",
            with: "<hh:heading type=\"NUMBER\" idRef=\"404\" level=\"2\"/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDangling)

        let paraShape = docInfo.idMappings.paraShapeArray[0]
        expect(paraShape.property1Info.headingTypeRawValue) == 2
        expect(paraShape.numberingOrBulletId) == 0
    }

    func testRefListFamilyFromOtherKnownVocabularyIsDemotedNotMapped() throws {
        // hp:charProperties(paragraph vocabulary)는 hh 정의가 아니다 — 등록도
        // 매핑도 하지 않고 unknown으로 강등해야 진짜 배열을 덮지 않는다.
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:tabProperties",
            with: "<hp:charProperties itemCnt=\"1\">"
                + "<hp:charPr id=\"99\" height=\"9999\"/></hp:charProperties>"
                + "<hh:tabProperties"
        )
        let (docInfo, tables) = try HwpxHeaderFixture.mapHeader(withDecoy)

        expect(docInfo.idMappings.charShapeArray.count) == 2
        expect(docInfo.idMappings.charShapeArray[0].baseSize) == 1000
        expect(tables.charShape.offset(of: "99")).to(beNil())
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("charProperties"))
    }

    func testUnconsumedBorderFillDescendantsDegradeIntoDiagnostics() throws {
        let withExtras = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hc:fillBrush>",
                with: "<hh:slash type=\"NONE\" Crooked=\"0\" isCounter=\"0\"/>"
                    + "<hc:fillBrush><hc:gradation angle=\"90\"/>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        expect(docInfo.idMappings.borderFillArray.count) == 2
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("slash"))
        expect(names).to(contain("gradation"))
        // 소비되는 자식은 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("leftBorder"))
        expect(names).toNot(contain("winBrush"))
        expect(names).toNot(contain("fillBrush"))
    }

    func testUnconsumedParaPrChildrenDegradeIntoDiagnostics() throws {
        let withExtras = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:paraPr id=\"4\" tabPrIDRef=\"3\" condense=\"0\">",
            with: "<hh:paraPr id=\"4\" tabPrIDRef=\"3\" condense=\"0\">"
                + "<hh:breakSetting breakLatinWord=\"KEEP_WORD\"/>"
                + "<hh:autoSpacing eAsianEng=\"0\"/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("breakSetting"))
        expect(names).to(contain("autoSpacing"))
        // 소비되는 자식은 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("align"))
        expect(names).toNot(contain("margin"))
        expect(names).toNot(contain("lineSpacing"))
    }

    func testExplicitTabStopsDegradeIntoDiagnostics() throws {
        // hh:tabItem은 1차 범위 밖이라 mapTabDef가 버린다 — 조용히 사라지지
        // 않고 합성 unknownRecord로 진단에 남아야 한다 (noori 픽스처 실측).
        let withTabItems = """
        <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" secCnt="1">\
        <hh:refList><hh:tabProperties itemCnt="1">\
        <hh:tabPr id="0" autoTabLeft="0" autoTabRight="0">\
        <hh:tabItem pos="4000" type="LEFT" leader="NONE"/>\
        </hh:tabPr></hh:tabProperties></hh:refList></hh:head>
        """
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withTabItems)

        expect(docInfo.idMappings.tabDefArray.count) == 1
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("tabItem"))
        expect(docInfo.unknownRecords.map(\.tagId).allSatisfy { $0 == 0 }) == true
    }
}
