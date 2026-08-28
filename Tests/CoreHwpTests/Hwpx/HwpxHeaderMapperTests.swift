@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// header.xml → HwpDocInfo 매핑 — id 리맵·bit 재합성·미해석 진단을 합성
/// XML로 고정한다 (구조는 한글.app 번들 Normal.hwtx 실측을 따른다).
final class HwpxHeaderMapperTests: XCTestCase {
    private func mapHeader(
        _ xml: String,
        catalog: HwpxBinDataCatalog = HwpxBinDataCatalog()
    ) throws -> (docInfo: HwpDocInfo, idTables: HwpxIdTables) {
        try HwpxHeaderMapper.map(
            Data(xml.utf8), binDataCatalog: catalog, options: .default
        )
    }

    /// 실물 구조를 본뜬 최소 헤더 — id가 dense가 아니고(charPr 7부터,
    /// borderFill 1부터) 가족 간 참조가 얽혀 있다.
    private let headerXML = """
    <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" \
    xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
    xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" version="1.5" secCnt="2">\
    <hh:beginNum page="3" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>\
    <hh:refList>\
    <hh:fontfaces itemCnt="2">\
    <hh:fontface lang="HANGUL" fontCnt="2">\
    <hh:font id="0" face="함초롬돋움" type="TTF" isEmbedded="0"/>\
    <hh:font id="1" face="함초롬바탕" type="TTF" isEmbedded="0">\
    <hh:substFont face="바탕" type="TTF"/></hh:font>\
    </hh:fontface>\
    <hh:fontface lang="LATIN" fontCnt="1">\
    <hh:font id="5" face="Arial" type="TTF" isEmbedded="0"/>\
    </hh:fontface>\
    </hh:fontfaces>\
    <hh:borderFills itemCnt="2">\
    <hh:borderFill id="1" threeD="0" shadow="0" centerLine="NONE">\
    <hh:leftBorder type="NONE" width="0.1 mm" color="#000000"/>\
    <hh:rightBorder type="NONE" width="0.1 mm" color="#000000"/>\
    <hh:topBorder type="NONE" width="0.1 mm" color="#000000"/>\
    <hh:bottomBorder type="NONE" width="0.1 mm" color="#000000"/>\
    </hh:borderFill>\
    <hh:borderFill id="7">\
    <hh:leftBorder type="SOLID" width="0.4 mm" color="#FF0000"/>\
    <hh:rightBorder type="DASH" width="0.12 mm" color="#00FF00"/>\
    <hh:topBorder type="DOT" width="1.0 mm" color="#0000FF"/>\
    <hh:bottomBorder type="SOLID" width="0.1 mm" color="#000000"/>\
    <hc:fillBrush><hc:winBrush faceColor="#DDEEFF" hatchColor="#999999" alpha="0"/>\
    </hc:fillBrush>\
    </hh:borderFill>\
    </hh:borderFills>\
    <hh:charProperties itemCnt="2">\
    <hh:charPr id="7" height="1000" textColor="#112233" shadeColor="none" \
    useKerning="0" symMark="NONE" borderFillIDRef="1">\
    <hh:fontRef hangul="1" latin="5" hanja="0" japanese="0" other="0" \
    symbol="0" user="0"/>\
    <hh:ratio hangul="90" latin="100" hanja="100" japanese="100" other="100" \
    symbol="100" user="100"/>\
    <hh:spacing hangul="-5" latin="0" hanja="0" japanese="0" other="0" \
    symbol="0" user="0"/>\
    <hh:bold/>\
    <hh:underline type="BOTTOM" shape="DASH" color="#FF00FF"/>\
    <hh:strikeout shape="SOLID" color="#111111"/>\
    </hh:charPr>\
    <hh:charPr id="12" height="1600" textColor="#000000" \
    borderFillIDRef="404"><hh:italic/></hh:charPr>\
    </hh:charProperties>\
    <hh:tabProperties itemCnt="2">\
    <hh:tabPr id="0" autoTabLeft="0" autoTabRight="0"/>\
    <hh:tabPr id="3" autoTabLeft="1" autoTabRight="1"/>\
    </hh:tabProperties>\
    <hh:paraProperties itemCnt="2">\
    <hh:paraPr id="4" tabPrIDRef="3" condense="0">\
    <hh:align horizontal="CENTER" vertical="BASELINE"/>\
    <hh:heading type="OUTLINE" idRef="0" level="2"/>\
    <hp:switch>\
    <hp:case hp:required-namespace="http://www.hancom.co.kr/hwpml/2016/HwpUnitChar">\
    <hh:margin><hc:intent value="-2620" unit="HWPUNIT"/>\
    <hc:left value="3000" unit="HWPUNIT"/><hc:right value="100" unit="HWPUNIT"/>\
    <hc:prev value="2400" unit="HWPUNIT"/><hc:next value="600" unit="HWPUNIT"/>\
    </hh:margin>\
    <hh:lineSpacing type="FIXED" value="1600" unit="HWPUNIT"/>\
    </hp:case>\
    <hp:default>\
    <hh:margin><hc:intent value="0" unit="CHAR"/><hc:left value="0" unit="CHAR"/>\
    <hc:right value="0" unit="CHAR"/><hc:prev value="0" unit="CHAR"/>\
    <hc:next value="0" unit="CHAR"/></hh:margin>\
    <hh:lineSpacing type="PERCENT" value="160" unit="HWPUNIT"/>\
    </hp:default>\
    </hp:switch>\
    <hh:border borderFillIDRef="7" offsetLeft="10" offsetRight="20" \
    offsetTop="30" offsetBottom="40" connect="1" ignoreMargin="1"/>\
    </hh:paraPr>\
    <hh:paraPr id="9"><hh:align horizontal="JUSTIFY"/></hh:paraPr>\
    </hh:paraProperties>\
    <hh:styles itemCnt="2">\
    <hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="9" \
    charPrIDRef="7" nextStyleIDRef="0" langID="1042" lockForm="0"/>\
    <hh:style id="2" type="CHAR" name="강조" engName="Emphasis" paraPrIDRef="4" \
    charPrIDRef="12" nextStyleIDRef="2" langID="1042" lockForm="0"/>\
    </hh:styles>\
    <hh:numberings itemCnt="1"><hh:numbering id="1"/></hh:numberings>\
    </hh:refList>\
    <hh:forbiddenWordList itemCnt="0"/>\
    </hh:head>
    """

    func testMapsDocumentPropertiesFromSecCntAndBeginNum() throws {
        let (docInfo, _) = try mapHeader(headerXML)

        expect(docInfo.documentProperties.sectionSize) == 2
        expect(docInfo.documentProperties.startingIndex.page) == 3
        expect(docInfo.documentProperties.startingIndex.footnote) == 1
    }

    func testMapsFontFacesPerLanguageWithSubstitute() throws {
        let (docInfo, _) = try mapHeader(headerXML)
        let idMappings = docInfo.idMappings

        expect(idMappings.faceNameKoreanArray.map(\.faceName)) == ["함초롬돋움", "함초롬바탕"]
        expect(idMappings.faceNameKoreanArray[1].alternativeFaceName) == "바탕"
        expect(idMappings.faceNameEnglishArray.map(\.faceName)) == ["Arial"]
        expect(idMappings.faceNameChineseArray).to(beEmpty())
    }

    func testRemapsCharShapeReferencesFromSparseIds() throws {
        let (docInfo, tables) = try mapHeader(headerXML)
        let charShapes = docInfo.idMappings.charShapeArray

        expect(charShapes.count) == 2
        expect(tables.charShape.offset(of: "7")) == 0
        expect(tables.charShape.offset(of: "12")) == 1

        let first = charShapes[0]
        expect(first.baseSize) == 1000
        expect(first.faceColor) == HwpColor(0x11, 0x22, 0x33)
        expect(first.property.isBold) == true
        expect(first.property.isItalic) == false
        // fontRef: hangul="1" → 한글 배열 오프셋 1, latin="5" → 영어 배열
        // 오프셋 0 (id 5가 유일 항목).
        expect(first.faceId[0]) == 1
        expect(first.faceId[1]) == 0
        expect(first.faceScaleX[0]) == 90
        expect(first.faceSpacing[0]) == -5
        // borderFillIDRef="1" → 배열 오프셋 0 → 1-based 1.
        expect(first.borderFillId) == 1
        expect(first.property.underlineType) == HwpUnderlineType.under
        expect(first.property.underlineShape) == 2
        expect(first.underlineColor) == HwpColor(0xFF, 0x00, 0xFF)
        expect(first.property.strikethrough) == 1
        expect(first.property.strikethroughShape) == 1

        let second = charShapes[1]
        expect(second.property.isItalic) == true
        // 댕글링 borderFillIDRef="404" → 0 (없음).
        expect(second.borderFillId) == 0
    }

    func testMapsBorderFillTypesThicknessAndSolidFill() throws {
        let (docInfo, _) = try mapHeader(headerXML)
        let borderFills = docInfo.idMappings.borderFillArray

        expect(borderFills.count) == 2
        let fancy = borderFills[1]
        // 순서: 왼쪽/오른쪽/위쪽/아래쪽 (표 25).
        expect(fancy.borderType) == [1, 2, 3, 1]
        // 0.4mm → index 6, 0.12mm → index 1, 1.0mm → index 10, 0.1mm → 0.
        expect(fancy.borderThickness) == [6, 1, 10, 0]
        expect(fancy.borderColor[0]) == HwpColor(0xFF, 0, 0)
        let fill = try XCTUnwrap(fancy.fill)
        expect(fill.hasSolidFill) == true
        expect(fill.solidBackgroundColor) == HwpColor(0xDD, 0xEE, 0xFF)
        expect(fill.solidPatternType) == -1
        // 채우기 없는 항목은 fillInfo가 비어 fill 해석이 nil이다.
        expect(borderFills[0].fill).to(beNil())
    }

    func testMapsParaShapeBitsMarginsAndLineSpacing() throws {
        let (docInfo, _) = try mapHeader(headerXML)
        let paraShape = docInfo.idMappings.paraShapeArray[0]

        expect(paraShape.property1Info.alignmentRawValue) == 3 // CENTER
        expect(paraShape.property1Info.headingTypeRawValue) == 1 // OUTLINE
        expect(paraShape.property1Info.headingLevelRawValue) == 2
        expect(paraShape.property1Info.borderConnect) == true
        expect(paraShape.property1Info.borderIgnoreMargin) == true
        // HwpUnitChar case가 default를 이긴다 (switch 해소).
        expect(paraShape.marginLeft) == 3000
        expect(paraShape.marginRight) == 100
        expect(paraShape.indent) == -2620
        expect(paraShape.paragraphSpacingTop) == 2400
        expect(paraShape.paragraphSpacingBottom) == 600
        expect(paraShape.resolvedLineSpacingKind) == HwpLineSpacingKind.fixed
        expect(paraShape.resolvedLineSpacingValue) == 1600
        expect(paraShape.tabDefId) == 1 // id "3" → 오프셋 1
        expect(paraShape.borderFillId) == 2 // id "7" → 오프셋 1 → 1-based 2
        expect(paraShape.borderSpacingLeft) == 10
        expect(paraShape.borderSpacingBottom) == 40
        // 개요 머리인데 numbering 배열은 1차 범위 밖 — id 테이블 리맵만 남는다.
        expect(paraShape.numberingOrBulletId) == 0

        let plain = docInfo.idMappings.paraShapeArray[1]
        expect(plain.property1Info.alignmentRawValue) == 0
        expect(plain.resolvedLineSpacingKind) == HwpLineSpacingKind.percent
        expect(plain.resolvedLineSpacingValue) == 160
    }

    func testMapsTabDefAutoTabBits() throws {
        let (docInfo, _) = try mapHeader(headerXML)
        let tabDefs = docInfo.idMappings.tabDefArray

        expect(tabDefs.map(\.property)) == [0, 0b11]
    }

    func testMapsStylesWithRemappedReferences() throws {
        let (docInfo, _) = try mapHeader(headerXML)
        let styles = docInfo.idMappings.styleArray

        expect(styles.count) == 2
        expect(styles[0].styleLocalName) == "바탕글"
        expect(styles[0].property) == 0
        expect(styles[0].paraShapeId) == 1 // paraPr id "9" → 오프셋 1
        expect(styles[0].charShapeId) == 0 // charPr id "7" → 오프셋 0
        expect(styles[0].nextId) == 0
        expect(styles[1].property) == 1 // type="CHAR"
        expect(styles[1].charShapeId) == 1
        expect(styles[1].nextId) == 1 // nextStyleIDRef "2" → 오프셋 1
    }

    func testUnmappedElementsLandInUnknownRecordsWithSyntheticTag() throws {
        let (docInfo, _) = try mapHeader(headerXML)

        let names = docInfo.unknownRecords.map {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("numberings"))
        expect(names).to(contain("forbiddenWordList"))
        expect(docInfo.unknownRecords.map(\.tagId).allSatisfy { $0 == 0 }) == true
    }

    func testBlankDocumentDefaultsAreFullyOverwritten() throws {
        // 매핑 대상 가족이 빈 문서 기본값과 섞이면 리맵 오프셋이 어긋난다 —
        // 최소 헤더에서 모든 가족이 실제 선언 수만큼만 남는지 확인한다.
        let minimal = """
        <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" secCnt="1">\
        <hh:refList/></hh:head>
        """
        let (docInfo, _) = try mapHeader(minimal)
        let idMappings = docInfo.idMappings

        expect(idMappings.charShapeArray).to(beEmpty())
        expect(idMappings.paraShapeArray).to(beEmpty())
        expect(idMappings.styleArray).to(beEmpty())
        expect(idMappings.borderFillArray).to(beEmpty())
        expect(idMappings.tabDefArray).to(beEmpty())
        expect(idMappings.faceNameKoreanArray).to(beEmpty())
        expect(idMappings.numberingArray).to(beEmpty())
        expect(idMappings.forbiddenCharArray).to(beEmpty())
        expect(docInfo.docData).to(beNil())
        expect(docInfo.compatibleDocument).to(beNil())
    }

    func testBinDataCatalogFlowsIntoIdMappings() throws {
        var catalog = HwpxBinDataCatalog()
        var meta = HwpBinData()
        meta.streamId = 1
        catalog.binDataArray = [meta]

        let minimal = """
        <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" secCnt="1"/>
        """
        let (docInfo, _) = try mapHeader(minimal, catalog: catalog)

        expect(docInfo.idMappings.binDataArray.count) == 1
        expect(docInfo.idMappings.binDataArray[0].streamId) == 1
    }

    func testUnexpectedRootElementThrowsInvalidXML() {
        expect {
            _ = try self.mapHeader("<hs:sec xmlns:hs=\"urn:x\"/>")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/header.xml"
            expect(reason).to(contain("root element"))
        })
    }
}
