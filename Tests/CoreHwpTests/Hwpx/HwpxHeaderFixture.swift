@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// header.xml 매퍼 스위트 2종이 공유하는 합성 픽스처.
///
/// 매핑 결과 검증(`HwpxHeaderMapperTests`)과 미해석 강등·namespace
/// 좁히기 검증(`HwpxHeaderDiagnosticsTests`)이 같은 실물 구조를 본다.
enum HwpxHeaderFixture {
    static func mapHeader(
        _ xml: String,
        catalog: HwpxBinDataCatalog = HwpxBinDataCatalog(),
        sectionCount: Int? = nil
    ) throws -> (docInfo: HwpDocInfo, idTables: HwpxIdTables) {
        try HwpxHeaderMapper.map(
            Data(xml.utf8),
            binDataCatalog: catalog,
            options: .default,
            sectionCount: sectionCount
        )
    }

    /// 실물 구조를 본뜬 최소 헤더 — id가 dense가 아니고(charPr 7부터,
    /// borderFill 1부터) 가족 간 참조가 얽혀 있다.
    static let headerXML = """
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
}
