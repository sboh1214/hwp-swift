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

    func testUnconsumedFontChildrenAndUnknownLanguageDegradeIntoDiagnostics() throws {
        let withExtras = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:font id=\"0\" face=\"함초롬돋움\" type=\"TTF\" isEmbedded=\"0\"/>",
                with: "<hh:font id=\"0\" face=\"함초롬돋움\" type=\"TTF\" isEmbedded=\"0\">"
                    + "<hh:typeInfo familyType=\"FCAT_GOTHIC\"/></hh:font>"
            )
            .replacingOccurrences(
                of: "</hh:fontfaces>",
                with: "<hh:fontface lang=\"KLINGON\" fontCnt=\"1\">"
                    + "<hh:font id=\"9\" face=\"nope\"/></hh:fontface></hh:fontfaces>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("typeInfo"))
        expect(names).to(contain("fontface"))
        // 미지 lang 목록은 채택되지 않는다 (한글 2 + 영어 1 그대로).
        expect(docInfo.idMappings.faceNameKoreanArray.count) == 2
        expect(docInfo.idMappings.faceNameEnglishArray.count) == 1
        // 소비되는 substFont는 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("substFont"))
    }

    func testDuplicateCharPropertyLeafIsDemotedIntoDiagnostics() throws {
        // 잎은 단일 조회라 둘째 <hh:italic>은 모델에 안 실린다 — 소비 표시가
        // 이름 단위라 진단에서도 지워지면 부분 해석된 헤더가 완전한 파스로
        // 보고되고, 둘째 래퍼 안의 미지 요소까지 함께 사라진다.
        let withDuplicate = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "borderFillIDRef=\"404\"><hh:italic/>",
            with: "borderFillIDRef=\"404\"><hh:italic/>"
                + "<hh:italic><hh:ghost/></hh:italic>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDuplicate)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("italic"))
        // 첫 등장은 그대로 모델에 실린다 (음성 대조).
        expect(docInfo.idMappings.charShapeArray[1].property.isItalic) == true
    }

    func testCharPropertyLeafDecoysFromOtherVocabularyAreDemotedNotApplied() throws {
        // <hp:bold>는 head vocabulary가 아니다 — 전역 조회면 굵게가 적용되고
        // 전역 소비 필터가 그것을 진단에서도 지운다.
        // 픽스처의 charPr[0]은 진짜 <hh:bold/>를 가지므로 대조가 되지 않는다 —
        // 굵게가 없는 charPr[1]에 디코이만 넣는다.
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "borderFillIDRef=\"404\"><hh:italic/>",
            with: "borderFillIDRef=\"404\"><hh:italic/><hp:bold/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoy)

        expect(docInfo.idMappings.charShapeArray[1].property.isBold) == false
        // 대조군: 진짜 hh:bold는 그대로 적용된다.
        expect(docInfo.idMappings.charShapeArray[0].property.isBold) == true
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("bold"))
    }

    func testBorderDecoysAreDemotedWhileCoreFillIsStillConsumed() throws {
        // 테두리는 head, 채우기는 core다 — 한쪽으로 통일하면 디코이가
        // 적용되거나(전역) 정상 hc:fillBrush가 미지로 오보된다(head 통일).
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:leftBorder type=\"SOLID\"",
            with: "<hp:leftBorder type=\"DOT\" width=\"1.0 mm\" color=\"#00FF00\"/>"
                + "<hh:leftBorder type=\"SOLID\""
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoy)

        // SOLID(1)가 유지되고 디코이의 DOT(3)으로 덮이지 않는다.
        // borderLineArray는 매퍼가 넣은 순서(left·right·top·bottom)다.
        let fill = docInfo.idMappings.borderFillArray[1]
        expect(fill.borderLineArray[0].typeRawValue) == 1
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("leftBorder"))
        // 대조군: 소비되는 hc:fillBrush는 강등되지 않는다.
        expect(names).toNot(contain("fillBrush"))
    }

    func testParagraphShapeLeafDecoysFromOtherVocabularyAreDemotedNotApplied() throws {
        // <hp:align>은 head vocabulary가 아니다 — 전역 조회면 이 디코이가
        // 정렬을 덮고, 전역 소비 필터가 그것을 진단에서도 지운다.
        // 디코이를 진짜 <hh:align> 앞에 둬 먼저 발견되게 한다.
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:align horizontal=\"CENTER\"",
            with: "<hp:align horizontal=\"RIGHT\" vertical=\"BASELINE\"/>"
                + "<hh:align horizontal=\"CENTER\""
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoy)

        // CENTER(3)가 유지되고 디코이의 RIGHT(2)로 덮이지 않는다.
        expect(docInfo.idMappings.paraShapeArray[0].property1Info.alignmentRawValue) == 3
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("align"))
    }

    func testUnconsumedFontfaceChildrenWithOtherNamesAreDemoted() throws {
        // fontface 직속의 다른 이름 자식 — 이름이 "font"인 디코이만 잡는
        // 술어로는 매핑도 강등도 되지 않아 흔적 없이 사라진다.
        let withExtra = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:font id=\"5\" face=\"Arial\" type=\"TTF\" isEmbedded=\"0\"/>",
            with: "<hh:font id=\"5\" face=\"Arial\" type=\"TTF\" isEmbedded=\"0\"/>"
                + "<hh:faceMeta vendor=\"x\"/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtra)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("faceMeta"))
        // 소비되는 font는 강등되지 않는다 (음성 대조).
        expect(docInfo.idMappings.faceNameEnglishArray.count) == 1
        expect(names).toNot(contain("font"))
    }

    func testHeadChildDecoysFromOtherKnownVocabularyAreDemotedNotMapped() throws {
        // 같은 local name의 <hp:*> 디코이 — head vocabulary가 아니므로
        // 시작 번호를 덮지 못하고 진단으로 강등되어야 한다.
        let withDecoys = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:refList>",
            with: "<hp:beginNum page=\"99\" tbl=\"77\"/>"
                + "<hp:refList><hp:borderFills itemCnt=\"1\"/></hp:refList><hh:refList>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoys)

        expect(docInfo.documentProperties.startingIndex.page) == 3
        expect(docInfo.documentProperties.startingIndex.table) == 1
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("beginNum"))
        expect(names).to(contain("refList"))
        // 진짜 <hh:refList>는 계속 소비된다 — borderFill 2종 매핑 유지.
        expect(docInfo.idMappings.borderFillArray.count) == 2
    }

    func testUnconsumedWrapperDescendantsDegradeIntoDiagnostics() throws {
        // 소비된 래퍼(margin·align) 안 미지 자식도 진단에 남아야 한다 —
        // 래퍼를 통째로 소비 처리하면 그 안의 확장 요소가 사라진다.
        let withExtras = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:margin><hc:intent value=\"-2620\" unit=\"HWPUNIT\"/>",
                with: "<hh:margin><hh:marginExtra/><hc:intent value=\"-2620\" unit=\"HWPUNIT\"/>"
            )
            .replacingOccurrences(
                of: "<hh:paraPr id=\"9\"><hh:align horizontal=\"JUSTIFY\"/>",
                with: "<hh:paraPr id=\"9\"><hh:align horizontal=\"JUSTIFY\">"
                    + "<hh:alignExtra/></hh:align>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("marginExtra"))
        expect(names).to(contain("alignExtra"))
        // 소비되는 margin 자식은 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("intent"))
        expect(names).toNot(contain("left"))
    }

    func testUnsupportedBrushIsDemotedExactlyOnce() throws {
        // 강등 경로가 둘이면(레거시 루프 + fillBrush 소비 목록) 같은 레코드가
        // 두 번 실려 공개 진단 카운트가 부풀려진다.
        let withGradation = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hc:winBrush faceColor=\"#DDEEFF\" hatchColor=\"#999999\" alpha=\"0\"/>",
            with: "<hc:winBrush faceColor=\"#DDEEFF\" hatchColor=\"#999999\" alpha=\"0\"/>"
                + "<hc:gradation angle=\"90\"/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withGradation)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names.filter { $0 == "gradation" }.count) == 1
    }

    func testHeaderLeafWrapperDescendantsDegradeIntoDiagnostics() throws {
        // 테두리·winBrush·substFont·margin 값·beginNum·style은 속성만 읽는
        // 잎이다 — 안의 확장 요소가 진단에 남아야 한다.
        let withExtras = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:leftBorder type=\"SOLID\" width=\"0.4 mm\" color=\"#FF0000\"/>",
                with: "<hh:leftBorder type=\"SOLID\" width=\"0.4 mm\" color=\"#FF0000\">"
                    + "<hh:borderExtra/></hh:leftBorder>"
            )
            .replacingOccurrences(
                of: "<hc:winBrush faceColor=\"#DDEEFF\" hatchColor=\"#999999\" alpha=\"0\"/>",
                with: "<hc:winBrush faceColor=\"#DDEEFF\" hatchColor=\"#999999\" alpha=\"0\">"
                    + "<hc:brushExtra/></hc:winBrush>"
            )
            .replacingOccurrences(
                of: "<hh:substFont face=\"바탕\" type=\"TTF\"/>",
                with: "<hh:substFont face=\"바탕\" type=\"TTF\"><hh:substExtra/></hh:substFont>"
            )
            .replacingOccurrences(
                of: "<hc:intent value=\"-2620\" unit=\"HWPUNIT\"/>",
                with: "<hc:intent value=\"-2620\" unit=\"HWPUNIT\"><hc:intentExtra/></hc:intent>"
            )
            .replacingOccurrences(
                of: "equation=\"1\"/>",
                with: "equation=\"1\"><hh:beginNumExtra/></hh:beginNum>"
            )
            .replacingOccurrences(
                of: "nextStyleIDRef=\"0\" langID=\"1042\" lockForm=\"0\"/>",
                with: "nextStyleIDRef=\"0\" langID=\"1042\" lockForm=\"0\">"
                    + "<hh:styleExtra/></hh:style>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        for expected in [
            "borderExtra", "brushExtra", "substExtra",
            "intentExtra", "beginNumExtra", "styleExtra",
        ] {
            expect(names).to(contain(expected))
        }
        // 소비되는 래퍼 자체는 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("winBrush"))
    }

    func testCharPrLeafWrapperDescendantsDegradeIntoDiagnostics() throws {
        // underline 같은 잎 래퍼는 속성만 읽는다 — 안의 확장 요소가 진단에
        // 남아야 한다.
        let withExtras = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:underline type=\"BOTTOM\" shape=\"DASH\" color=\"#FF00FF\"/>",
            with: "<hh:underline type=\"BOTTOM\" shape=\"DASH\" color=\"#FF00FF\">"
                + "<hh:underlineExtra/></hh:underline>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("underlineExtra"))
        expect(names).toNot(contain("underline"))
    }

    func testUnconsumedCharPrChildrenDegradeIntoDiagnostics() throws {
        let withExtras = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:bold/>",
            with: "<hh:bold/><hh:extraDecoration/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("extraDecoration"))
        // 소비되는 자식은 강등되지 않는다 (음성 대조).
        expect(names).toNot(contain("bold"))
        expect(names).toNot(contain("underline"))
    }

    func testUnknownFamilyChildrenDegradeIntoDiagnostics() throws {
        // 정의와 이름이 다른 미래 자식도 진단에 남아야 한다 — 이름이 같은
        // 디코이만 잡는 강등이면 조용히 사라진다.
        let withExtras = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:charPr id=\"7\"",
            with: "<hh:newDefinition/><hh:charPr id=\"7\""
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withExtras)

        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("newDefinition"))
        // 진짜 정의는 강등되지 않고 매핑된다 (음성 대조).
        expect(names).toNot(contain("charPr"))
        expect(docInfo.idMappings.charShapeArray.count) == 2
    }

    func testRefListDefinitionDecoysAreDemotedAndDoNotShiftRegistration() throws {
        // 진짜 hh:charPr(id 7) 앞에 다른 id의 hp:charPr 디코이 — 등록이
        // 디코이를 세면 id 7의 오프셋이 밀려 스타일 참조가 어긋난다.
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:charPr id=\"7\"",
            with: "<hp:charPr id=\"99\" height=\"9999\"/><hh:charPr id=\"7\""
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoy)

        // 매핑은 진짜 2건만 담고 첫째가 실값이다.
        let shapes = docInfo.idMappings.charShapeArray
        expect(shapes.count) == 2
        expect(shapes[0].baseSize) == 1000
        // 등록도 디코이를 세지 않는다 — charPrIDRef="7"이 여전히 오프셋 0.
        expect(docInfo.idMappings.styleArray[0].charShapeId) == 0
        // 디코이는 진단에 남는다.
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("charPr"))
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

    func testMarginValueDecoysFromOtherVocabularyAreDemotedNotApplied() throws {
        // 여백 값 자식은 hc:다 — 전역 조회면 앞에 놓인 hp: 디코이가 여백을
        // 덮고, 전역 소비 필터가 그것을 진단에서도 지운다.
        let withDecoy = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hc:left value=\"3000\" unit=\"HWPUNIT\"/>",
            with: "<hp:left value=\"9999\" unit=\"HWPUNIT\"/>"
                + "<hc:left value=\"3000\" unit=\"HWPUNIT\"/>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDecoy)

        // HWPUNIT 3000이 모델에서 2배로 저장된다 — 디코이의 9999가 아니다.
        expect(docInfo.idMappings.paraShapeArray[0].marginLeft) == 6000
        let names = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("left"))
    }

    func testHeaderUnknownSubtreeDepthHonorsTheCallerLimit() throws {
        // 헤더 강등도 호출자의 maxNestingDepth를 따라야 한다 — 본문 경로만
        // 전파하면 진단이 요청보다 깊은 트리를 받는다.
        let withDeep = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "</hh:head>",
            with: "<ext:deep xmlns:ext=\"urn:x\"><ext:a><ext:b><ext:c/></ext:b></ext:a>"
                + "</ext:deep></hh:head>"
        )
        func depth(of record: HwpUnknownRecord) -> Int {
            1 + (record.children.map(depth(of:)).max() ?? 0)
        }
        func deepRecord(_ docInfo: HwpDocInfo) throws -> HwpUnknownRecord {
            try XCTUnwrap(docInfo.unknownRecords.first {
                String(bytes: $0.payload, encoding: .utf8) == "deep"
            })
        }

        // 대조군: 기본 한도에서는 네 겹이 그대로 남는다.
        let (full, _) = try HwpxHeaderFixture.mapHeader(withDeep)
        expect(depth(of: try deepRecord(full))) == 4

        let (capped, _) = try HwpxHeaderFixture.mapHeader(
            withDeep,
            options: HwpLoadOptions(readLimits: HwpReadLimits(maxNestingDepth: 2))
        )
        expect(depth(of: try deepRecord(capped))) == 2
    }
}
