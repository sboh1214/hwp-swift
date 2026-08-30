@testable import CoreHwp
import Foundation

/// 구역 매퍼 스위트가 공유하는 합성 픽스처 — id 테이블·구역 래퍼·최소 구역.
enum HwpxSectionFixture {
    static func makeContext(options: HwpLoadOptions = .default) -> HwpxMappingContext {
        var tables = HwpxIdTables()
        tables.charShape.register(id: "7", offset: 0)
        tables.charShape.register(id: "12", offset: 1)
        tables.paraShape.register(id: "4", offset: 0)
        tables.paraShape.register(id: "9", offset: 1)
        tables.style.register(id: "0", offset: 0)
        tables.style.register(id: "2", offset: 1)
        return HwpxMappingContext(
            idTables: tables,
            binItemIdByManifestId: [:],
            options: options,
            entry: "Contents/section0.xml"
        )
    }

    static func mapSection(
        _ body: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSection {
        let xml = """
        <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" \
        xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\(body)</hs:sec>
        """
        return try HwpxSectionMapper.map(Data(xml.utf8), context: makeContext(options: options))
    }

    /// 번들 Normal.hwtx의 section0.xml을 본뜬 최소 구역.
    static let blankBody = """
    <hp:p id="3121190098" paraPrIDRef="4" styleIDRef="0" pageBreak="0" \
    columnBreak="0" merged="0">\
    <hp:run charPrIDRef="7">\
    <hp:secPr id="" textDirection="HORIZONTAL" spaceColumns="1134" tabStop="8000">\
    <hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>\
    <hp:pagePr landscape="WIDELY" width="59528" height="84186" gutterType="LEFT_ONLY">\
    <hp:margin header="4252" footer="4252" gutter="0" left="8504" right="8504" \
    top="5668" bottom="4252"/></hp:pagePr>\
    </hp:secPr>\
    <hp:ctrl><hp:colPr id="" type="NEWSPAPER" layout="LEFT" colCount="1" \
    sameSz="1" sameGap="0"/></hp:ctrl>\
    </hp:run>\
    <hp:run charPrIDRef="7"><hp:t/></hp:run>\
    <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
    textheight="1000" baseline="850" spacing="600" horzpos="0" horzsize="42520" \
    flags="393216"/></hp:linesegarray></hp:p>
    """
}
