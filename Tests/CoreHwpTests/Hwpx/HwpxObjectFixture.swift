@testable import CoreHwp
import Foundation

/// 표·그림 매퍼 스위트가 공유하는 합성 픽스처 — id 테이블·파서 래퍼·실물 구조 XML.
enum HwpxObjectFixture {
    static func makeContext(
        options: HwpLoadOptions = .default,
        binItemIds: [String: UInt16] = [:]
    ) -> HwpxMappingContext {
        var tables = HwpxIdTables()
        tables.charShape.register(id: "0", offset: 0)
        tables.borderFill.register(id: "1", offset: 0)
        tables.borderFill.register(id: "3", offset: 1)
        return HwpxMappingContext(
            idTables: tables,
            binItemIdByManifestId: binItemIds,
            options: options,
            entry: "Contents/section0.xml"
        )
    }

    static func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/section0.xml")
    }

    static let tableXML = """
    <hp:tbl xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
    xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" id="123" zOrder="2" \
    numberingType="TABLE" textWrap="TOP_AND_BOTTOM" textFlow="BOTH_SIDES" \
    pageBreak="CELL" repeatHeader="1" rowCnt="2" colCnt="2" cellSpacing="0" \
    borderFillIDRef="3" noAdjust="0">\
    <hp:sz width="41954" height="8000" widthRelTo="ABSOLUTE" heightRelTo="ABSOLUTE" \
    protect="0"/>\
    <hp:pos treatAsChar="1" affectLSpacing="0" flowWithText="1" allowOverlap="0" \
    vertRelTo="PARA" horzRelTo="PARA" vertAlign="TOP" horzAlign="LEFT" \
    vertOffset="0" horzOffset="0"/>\
    <hp:outMargin left="283" right="283" top="283" bottom="283"/>\
    <hp:inMargin left="510" right="510" top="141" bottom="141"/>\
    <hp:tr>\
    <hp:tc name="" header="1" borderFillIDRef="1">\
    <hp:subList vertAlign="CENTER">\
    <hp:p paraPrIDRef="0"><hp:run charPrIDRef="0"><hp:t>머리</hp:t></hp:run></hp:p>\
    </hp:subList>\
    <hp:cellAddr colAddr="0" rowAddr="0"/><hp:cellSpan colSpan="2" rowSpan="1"/>\
    <hp:cellSz width="41954" height="4000"/>\
    <hp:cellMargin left="510" right="510" top="141" bottom="141"/>\
    </hp:tc>\
    </hp:tr>\
    <hp:tr>\
    <hp:tc name="" header="0" borderFillIDRef="3">\
    <hp:subList vertAlign="TOP">\
    <hp:p paraPrIDRef="0"><hp:run charPrIDRef="0"><hp:t>본1</hp:t></hp:run></hp:p>\
    <hp:p paraPrIDRef="0"><hp:run charPrIDRef="0"><hp:t>본2</hp:t></hp:run></hp:p>\
    </hp:subList>\
    <hp:cellAddr colAddr="0" rowAddr="1"/><hp:cellSpan colSpan="1" rowSpan="1"/>\
    <hp:cellSz width="20977" height="4000"/>\
    </hp:tc>\
    <hp:tc name="" header="0">\
    <hp:subList vertAlign="TOP">\
    <hp:p paraPrIDRef="0"><hp:run charPrIDRef="0"><hp:t/></hp:run></hp:p>\
    </hp:subList>\
    <hp:cellAddr colAddr="1" rowAddr="1"/><hp:cellSpan colSpan="1" rowSpan="1"/>\
    <hp:cellSz width="20977" height="4000"/>\
    </hp:tc>\
    </hp:tr>\
    </hp:tbl>
    """

    static let pictureXML = """
    <hp:pic xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
    xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" id="77" zOrder="0" \
    numberingType="FIGURE" textWrap="BEHIND_TEXT" reverse="0">\
    <hp:sz width="21000" height="14000" widthRelTo="ABSOLUTE" \
    heightRelTo="ABSOLUTE" protect="0"/>\
    <hp:pos treatAsChar="0" affectLSpacing="0" flowWithText="1" allowOverlap="1" \
    vertRelTo="PARA" horzRelTo="COLUMN" vertAlign="TOP" horzAlign="LEFT" \
    vertOffset="500" horzOffset="700"/>\
    <hp:outMargin left="0" right="0" top="0" bottom="0"/>\
    <hp:imgRect><hc:pt0 x="0" y="0"/><hc:pt1 x="21000" y="0"/>\
    <hc:pt2 x="21000" y="14000"/><hc:pt3 x="0" y="14000"/></hp:imgRect>\
    <hp:imgClip left="10" top="20" right="30" bottom="40"/>\
    <hp:inMargin left="1" right="2" top="3" bottom="4"/>\
    <hc:img binaryItemIDRef="image1" bright="5" contrast="-3" effect="GRAY_SCALE" \
    alpha="0"/>\
    </hp:pic>
    """
}
