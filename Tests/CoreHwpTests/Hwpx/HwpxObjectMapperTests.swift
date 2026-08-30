@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 표·그림 typed 매핑 — 셀 재귀·id 리맵·표 107 payload 합성을 고정한다.
final class HwpxObjectMapperTests: XCTestCase {
    private func makeContext(
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

    private func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/section0.xml")
    }

    private let tableXML = """
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

    func testTableMapsStructureAndProperties() throws {
        let table = try HwpxTableMapper.map(try parse(tableXML), context: makeContext())

        expect(table.tableProperty.rowCount) == 2
        expect(table.tableProperty.columnCount) == 2
        // pageBreak CELL은 바이너리 2(나눔)다 (noori 실측) + repeatHeader bit 2.
        expect(table.tableProperty.property) == 0b110
        expect(table.tableProperty.pageBreakMode) == HwpTableProperty.HwpTablePageBreakMode.split
        expect(table.tableProperty.repeatsHeaderRow) == true
        expect(table.tableProperty.leftInnerMargin) == 510
        expect(table.tableProperty.topInnerMargin) == 141
        // borderFillIDRef "3" → 오프셋 1 → 1-based 2.
        expect(table.tableProperty.borderFillId) == 2
        // rowSize: 행별 셀 개수 [1, 2] LE UInt16.
        expect(table.tableProperty.rowCellCounts) == [1, 2]

        let common = try XCTUnwrap(table.commonCtrlProperty)
        expect(common.width) == 41954
        expect(common.height) == 8000
        expect(common.propertyInfo.treatAsChar) == true
        expect(common.propertyInfo.textWrap) == HwpCommonCtrlTextWrap.topAndBottom
        expect(common.propertyInfo.numberingCategory)
            == HwpCommonCtrlNumberingCategory.table
        expect(common.zOrder) == 2
        expect(common.marginArray) == [283, 283, 283, 283]

        expect(table.cellArray.count) == 3
        let headerCell = table.cellArray[0]
        expect(headerCell.header.isHeader) == true
        expect(headerCell.header.paragraphCount) == 1
        expect(headerCell.header.propertyInfo.verticalAlignment)
            == HwpListHeaderVerticalAlignment.center
        let headerCellProperty = try XCTUnwrap(headerCell.header.cellProperty)
        expect(headerCellProperty.columnSpan) == 2
        expect(headerCellProperty.width) == 41954
        expect(headerCellProperty.borderFillId) == 1

        let bodyCell = table.cellArray[1]
        expect(bodyCell.header.paragraphCount) == 2
        expect(bodyCell.paragraphArray.count) == 2
        expect(bodyCell.paragraphArray[0].paraText?.wcharCount) == 3
        expect(bodyCell.paragraphArray[0].paraHeader.isLastInList) == false
        expect(bodyCell.paragraphArray[1].paraHeader.isLastInList) == true
        let bodyCellProperty = try XCTUnwrap(bodyCell.header.cellProperty)
        expect(bodyCellProperty.rowAddress) == 1
        // 셀의 댕글링 borderFillIDRef 부재 → 0 (없음).
        expect(table.cellArray[2].header.cellProperty?.borderFillId) == 0
    }

    func testCellHasMarginSetsAppliesInnerMarginBit() throws {
        // hasMargin 없는 셀은 hp:cellMargin이 있어도 표 전체 여백을 쓴다
        // (조판 게이트는 appliesInnerMargin — HwpTableLayout.cellMargins).
        let withoutFlag = try HwpxTableMapper.map(try parse(tableXML), context: makeContext())
        expect(withoutFlag.cellArray[0].header.cellPropertyInfo.appliesInnerMargin) == false

        let withFlag = tableXML.replacingOccurrences(
            of: "<hp:tc name=\"\" header=\"1\"",
            with: "<hp:tc name=\"\" header=\"1\" hasMargin=\"1\""
        )
        let mapped = try HwpxTableMapper.map(try parse(withFlag), context: makeContext())
        let headerCell = mapped.cellArray[0].header
        expect(headerCell.cellPropertyInfo.appliesInnerMargin) == true
        expect(headerCell.cellProperty?.marginArray) == [510, 510, 141, 141]
        expect(headerCell.isHeader) == true
        expect(mapped.cellArray[1].header.cellPropertyInfo.appliesInnerMargin) == false
    }

    func testTableDimensionsBeyondUInt16AreRejected() {
        // 행 수·행당 셀 수는 UInt16 필드다 — 접으면 rowSize·셀 배열과
        // 어긋난 모델이 나가므로 typed error로 거부된다.
        let manyRows = String(repeating: "<hp:tr/>", count: 65536)
        let manyCells = "<hp:tr>" + String(repeating: "<hp:tc/>", count: 65536) + "</hp:tr>"
        for body in [manyRows, manyCells] {
            let xml = """
            <hp:tbl xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
            rowCnt="2" colCnt="1">\(body)</hp:tbl>
            """
            expect {
                _ = try HwpxTableMapper.map(try self.parse(xml), context: self.makeContext())
            }.to(throwError { error in
                guard case let HwpError.invalidXML(_, reason) = error else {
                    return fail("Expected invalidXML, got \(error)")
                }
                expect(reason).to(contain("exceed"))
            })
        }
    }

    func testUnknownRowChildrenDegradeIntoDiagnostics() throws {
        // tr 전체를 소비 처리하면 행 안 미지 자식이 사라진다. hh:tc 디코이는
        // 전역 소비 판정이면 "소비됨"으로 오인되는 대조군이다.
        let withRowExtras = tableXML.replacingOccurrences(
            of: "<hp:tc name=\"\" header=\"1\"",
            with: "<hp:rowExtension/>"
                + "<hh:tc xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\"/>"
                + "<hp:tc name=\"\" header=\"1\""
        )
        let table = try HwpxTableMapper.map(try parse(withRowExtras), context: makeContext())

        let names = table.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("rowExtension"))
        expect(names).to(contain("tc"))
        // 채택 행·셀은 그대로다.
        expect(table.cellArray.count) == 3
        expect(table.tableProperty.rowCellCounts) == [1, 2]
    }

    func testCellLookupsIgnoreOtherVocabularyDecoys() throws {
        // 진짜 앞의 hh:subList 디코이가 셀 본문을 대체하면 안 되고, 밀린
        // 디코이는 셀 진단에 남아야 한다.
        let withDecoys = tableXML.replacingOccurrences(
            of: "<hp:subList vertAlign=\"CENTER\">",
            with: "<hh:subList xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\">"
                + "<hh:p/></hh:subList><hp:subList vertAlign=\"CENTER\">"
        )
        let table = try HwpxTableMapper.map(try parse(withDecoys), context: makeContext())

        let headerCell = table.cellArray[0]
        expect(headerCell.header.paragraphCount) == 1
        expect(headerCell.paragraphArray[0].paraText?.wcharCount) == 3
        let names = headerCell.header.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("subList"))
    }

    func testTableDimensionsFollowParsedStructureOverStaleDeclarations() throws {
        // rowCnt="9"·colCnt="0" 선언 — 파싱 구조는 2행, 머리 셀 colSpan=2가
        // 2열을 덮는다. 선언을 믿으면 빈 행 7개 또는 grid nil(표 소실)이다.
        let withStaleDeclarations = tableXML.replacingOccurrences(
            of: "rowCnt=\"2\" colCnt=\"2\"",
            with: "rowCnt=\"9\" colCnt=\"0\""
        )
        let table = try HwpxTableMapper.map(
            try parse(withStaleDeclarations), context: makeContext()
        )

        expect(table.tableProperty.rowCount) == 2
        expect(table.tableProperty.columnCount) == 2
    }

    func testDeclaredColumnCountWiderThanCoveredCellsIsTrusted() throws {
        // 셀이 덮는 폭(2)보다 넓은 colCnt="5"는 그대로 믿는다 — 도출은
        // 하한이지 대체가 아니다 (선언 격자를 존중하는 acceptedCells 정책).
        let withWiderDeclaration = tableXML.replacingOccurrences(
            of: "colCnt=\"2\"", with: "colCnt=\"5\""
        )
        let table = try HwpxTableMapper.map(
            try parse(withWiderDeclaration), context: makeContext()
        )

        expect(table.tableProperty.columnCount) == 5
    }

    func testTableStructureFromOtherKnownVocabularyIsNotAdopted() throws {
        // <hh:tr>은 표 행이 아니다 — 전역 known 매칭이면 진짜 행이 되어
        // 행/셀 수와 rowSize가 오염된다.
        let withDecoyRow = tableXML.replacingOccurrences(
            of: "<hp:tr>",
            with: "<hh:tr xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\">"
                + "<hh:tc><hh:subList><hh:p/></hh:subList></hh:tc></hh:tr><hp:tr>",
            options: [],
            range: tableXML.range(of: "<hp:tr>")
        )
        let table = try HwpxTableMapper.map(try parse(withDecoyRow), context: makeContext())

        // 진짜 hp:tr 2행·셀 3개만 채택된다 (decoy 행은 제외).
        expect(table.cellArray.count) == 3
        expect(table.tableProperty.rowCellCounts) == [1, 2]
    }

    func testUnconsumedTableAndCellChildrenDegradeIntoDiagnostics() throws {
        let withExtras = tableXML
            .replacingOccurrences(
                of: "<hp:inMargin left=\"510\" right=\"510\" top=\"141\" bottom=\"141\"/>",
                with: "<hp:inMargin left=\"510\" right=\"510\" top=\"141\" bottom=\"141\"/>"
                    + "<hp:caption side=\"TOP\"/>"
            )
            .replacingOccurrences(
                of: "<hp:cellMargin left=\"510\" right=\"510\" top=\"141\" bottom=\"141\"/>",
                with: "<hp:cellMargin left=\"510\" right=\"510\" top=\"141\" bottom=\"141\"/>"
                    + "<hp:cellzoneList/>"
            )
        let table = try HwpxTableMapper.map(try parse(withExtras), context: makeContext())

        func names(_ records: [HwpUnknownRecord]) -> [String] {
            records.compactMap { String(bytes: $0.payload, encoding: .utf8) }
        }
        expect(names(table.unknownChildren)) == ["caption"]
        expect(names(table.cellArray[0].header.unknownChildren)) == ["cellzoneList"]

        // 전부 소비되는 기본 표는 강등 0건 (음성 대조).
        let plain = try HwpxTableMapper.map(try parse(tableXML), context: makeContext())
        expect(plain.unknownChildren).to(beEmpty())
        expect(plain.cellArray.flatMap(\.header.unknownChildren)).to(beEmpty())
    }

    func testTableCellRecursionIsBoundedByMaxNestingDepth() throws {
        // 표 안 문단 안 표 … 를 maxNestingDepth보다 깊게 중첩하면 typed
        // error로 끊어야 한다 (스택 오버플로 방지 — parseTreeRecord의 level
        // 가드에 해당하는 XML 쪽 가드).
        var xml = "<hp:t>끝</hp:t>"
        for _ in 0 ..< 8 {
            xml = """
            <hp:tbl rowCnt="1" colCnt="1"><hp:tr><hp:tc><hp:subList>\
            <hp:p><hp:run charPrIDRef="0">\(xml)</hp:run></hp:p>\
            </hp:subList><hp:cellAddr colAddr="0" rowAddr="0"/></hp:tc></hp:tr></hp:tbl>
            """
        }
        let node = try parse(
            "<hp:p xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\">"
                + "<hp:run charPrIDRef=\"0\">\(xml)</hp:run></hp:p>"
        )
        let options = HwpLoadOptions(readLimits: HwpReadLimits(maxNestingDepth: 4))
        var tables = HwpxIdTables()
        tables.charShape.register(id: "0", offset: 0)
        let context = HwpxMappingContext(
            idTables: tables,
            binItemIdByManifestId: [:],
            options: options,
            entry: "Contents/section0.xml"
        )

        expect {
            _ = try HwpxParagraphMapper.map(node, context: context, isLastInList: true)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("maxNestingDepth"))
        })
    }

    private let pictureXML = """
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
    <hp:img binaryItemIDRef="image1" bright="5" contrast="-3" effect="GRAY_SCALE" \
    alpha="0"/>\
    </hp:pic>
    """

    func testPictureSynthesizesTable107PayloadAndBinItemJoin() throws {
        let control = HwpxPictureMapper.map(
            try parse(pictureXML),
            context: makeContext(binItemIds: ["image1": 3])
        )

        expect(control.ctrlId) == HwpCommonCtrlId.picture
        let common = try XCTUnwrap(control.commonCtrlProperty)
        expect(common.width) == 21000
        expect(common.height) == 14000
        expect(common.verticalOffset) == 500
        expect(common.horizontalOffset) == 700
        expect(common.propertyInfo.textWrap) == HwpCommonCtrlTextWrap.behindText
        expect(common.propertyInfo.allowOverlap) == true

        let component = try XCTUnwrap(control.shapeComponentArray.first)
        expect(component.ctrlId) == HwpCommonCtrlId.picture
        let picture = try XCTUnwrap(component.pictureArray.first)
        expect(picture.rawPayload.count) == 73
        expect(picture.binaryDataId) == 3

        // 하류가 실제로 쓰는 경로 — rawPayload에서 표 107을 다시 디코드한다.
        let property = try XCTUnwrap(picture.pictureProperty)
        expect(property.binItemId) == 3
        expect(property.imageCorners.map(\.x)) == [0, 21000, 21000, 0]
        expect(property.imageCorners.map(\.y)) == [0, 0, 14000, 14000]
        expect(property.cropLeft) == 10
        expect(property.cropTop) == 20
        expect(property.cropRight) == 30
        expect(property.cropBottom) == 40
        expect(property.innerMarginArray) == [1, 2, 3, 4]
        expect(property.brightness) == 5
        expect(property.contrast) == -3
        expect(property.effect) == 1
        expect(property.borderThickness) == 0
    }

    func testPictureUnconsumedChildrenDegradeIntoDiagnostics() throws {
        // 회전·반전 등은 렌더에 반영되지 않으므로 조용히 사라지면 안 된다 —
        // 진단 walker가 걷는 shapeControl.unknownChildren에 남는다.
        let withTransforms = pictureXML.replacingOccurrences(
            of: "</hp:pic>",
            with: "<hp:rotationInfo angle=\"90\" centerX=\"0\" centerY=\"0\"/>"
                + "<hp:renderingInfo/><hp:flip horizontal=\"1\" vertical=\"0\"/></hp:pic>"
        )
        let control = HwpxPictureMapper.map(
            try parse(withTransforms),
            context: makeContext(binItemIds: ["image1": 3])
        )
        let names = control.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["rotationInfo", "renderingInfo", "flip"]

        // 전부 소비되는 기본 그림은 강등 0건 (음성 대조).
        let plain = HwpxPictureMapper.map(
            try parse(pictureXML),
            context: makeContext(binItemIds: ["image1": 3])
        )
        expect(plain.unknownChildren).to(beEmpty())
    }

    func testPictureWithoutImgRectFallsBackToObjectSizeCorners() throws {
        let xml = """
        <hp:pic xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
        <hp:sz width="100" height="200"/>\
        <hp:img binaryItemIDRef="missing"/></hp:pic>
        """
        let control = HwpxPictureMapper.map(try parse(xml), context: makeContext())

        let picture = try XCTUnwrap(control.shapeComponentArray.first?.pictureArray.first)
        let property = try XCTUnwrap(picture.pictureProperty)
        // manifest에 없는 참조 → binItemId 0 (스트림 없음 → placeholder 강등).
        expect(property.binItemId) == 0
        expect(property.imageCorners.map(\.x)) == [0, 100, 100, 0]
        expect(property.imageCorners.map(\.y)) == [0, 0, 200, 200]
    }
}
