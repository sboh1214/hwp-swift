@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// OWPML `LINETYPE2` 이름 → HWP5 값 (#177). 실물 근거는 한글 12.30.0이 같은 편집
/// 세션에서 저장한 `line-shapes` 쌍이다 — 글자선은 `LINETYPE2 - 1`(실선 0), 테두리·
/// 대각선·각주/미주 구분선·단 구분선은 `LINETYPE2` 그대로(실선 1)로 저장된다.
final class HwpxLineTypeMapperTests: XCTestCase {
    /// 한컴 `g_LineTypeList2`의 나열 순서 = 값. `DOT`(2)가 `DASH`(3)보다 앞이다 —
    /// 이름의 뜻(점선·긴 점선)으로 표를 만들면 두 값이 뒤바뀐다.
    func testBorderLineTypesFollowTheOwpmlEnumerationOrder() {
        let names = [
            "NONE", "SOLID", "DOT", "DASH", "DASH_DOT", "DASH_DOT_DOT", "LONG_DASH",
            "CIRCLE", "DOUBLE_SLIM", "SLIM_THICK", "THICK_SLIM", "SLIM_THICK_SLIM",
            "WAVE", "DOUBLEWAVE", "THICK3D", "THICKREV3D", "3D", "REV3D",
        ]
        expect(HwpxLineTypeMapper.borderLineTypes.count) == names.count
        for (value, name) in names.enumerated() {
            expect(HwpxLineTypeMapper.borderLineTypes[name]).to(
                equal(value), description: name
            )
        }
        expect(HwpxLineTypeMapper.borderLineTypes["REV3D"])
            == HwpBorderType.single3DReverse.rawValue
    }

    /// 글자선 값은 테두리 값에서 1을 뺀 것이다. `NONE`은 자리가 없고 `REV3D`(16)는
    /// 4비트 필드를 넘쳐 한글이 실선으로 접는다 — 표에 없는 이름은 기본값 0이다.
    func testCharacterLineShapesAreBorderLineTypesShiftedByOne() {
        expect(HwpxLineTypeMapper.characterLineShapes.count) == 16
        for (name, value) in HwpxLineTypeMapper.characterLineShapes {
            expect(HwpxLineTypeMapper.borderLineTypes[name]).to(
                equal(value + 1), description: name
            )
            expect(value).to(beLessThan(16), description: "\(name)은 4비트 안에 있어야 한다")
        }
        expect(HwpxLineTypeMapper.characterLineShapes["NONE"]).to(beNil())
        expect(HwpxLineTypeMapper.characterLineShapes["REV3D"]).to(beNil())
        expect(HwpxLineTypeMapper.characterLineShape("REV3D")) == 0
        expect(HwpxLineTypeMapper.characterLineShape("NONE")) == 0
        expect(HwpxLineTypeMapper.characterLineShape(nil)) == 0
        expect(HwpxLineTypeMapper.characterLineShape("NOT_A_LINE")) == 0
    }

    /// `line-shapes` 쌍이 확정한 값 — 이슈가 남긴 세 물음(실선의 값, DOT/DASH의 순서,
    /// 글자선과 구분선의 분리)의 답을 표 단위로 핀한다.
    func testMeasuredValuesFromTheLineShapesPair() {
        expect(HwpxLineTypeMapper.characterLineShape("SOLID")) == 0
        expect(HwpxLineTypeMapper.characterLineShape("DOT")) == 1
        expect(HwpxLineTypeMapper.characterLineShape("DASH")) == 2
        expect(HwpxLineTypeMapper.characterLineShape("3D")) == 15
        expect(HwpxLineTypeMapper.borderLineType("SOLID", default: 0)) == 1
        expect(HwpxLineTypeMapper.borderLineType("DOT", default: 0)) == 2
        expect(HwpxLineTypeMapper.borderLineType("DASH", default: 0)) == 3
        expect(HwpxLineTypeMapper.borderLineType("DASH_DOT", default: 0)) == 4
        expect(HwpxLineTypeMapper.borderLineType(nil, default: 1)) == 1
        expect(HwpxLineTypeMapper.borderLineType("NOT_A_LINE", default: 1)) == 1
    }

    func testCharShapeMapperReadsCharacterLineShapesFromTheCharacterTable() throws {
        let xml = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:underline type=\"BOTTOM\" shape=\"DASH\" color=\"#FF00FF\"/>",
                with: "<hh:underline type=\"BOTTOM\" shape=\"DOT\" color=\"#FF00FF\"/>"
            )
            .replacingOccurrences(
                of: "<hh:strikeout shape=\"SOLID\" color=\"#111111\"/>",
                with: "<hh:strikeout shape=\"DASH\" color=\"#111111\"/>"
            )
            .replacingOccurrences(
                of: "<hh:italic/>",
                with: "<hh:italic/>"
                    + "<hh:underline type=\"BOTTOM\" shape=\"REV3D\" color=\"#000000\"/>"
                    + "<hh:strikeout shape=\"3D\" color=\"#000000\"/>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(xml)
        let shapes = docInfo.idMappings.charShapeArray

        expect(shapes[0].property.underlineShape) == 1
        expect(shapes[0].property.strikethroughShape) == 2
        // REV3D는 한글처럼 실선으로 접고 3D는 4비트의 마지막 값 15다 — 합성 rawValue와
        // typed 필드가 같은 값을 말해야 한다.
        expect(shapes[1].property.underlineShape) == 0
        expect(shapes[1].property.strikethroughShape) == 15
        let decoded = try HwpCharShapeProperty.load(shapes[1].property.rawValue)
        expect(decoded.underlineShape) == 0
        expect(decoded.strikethroughShape) == 15
    }

    /// 대각선도 같은 표다 — 한글은 대각선을 긋지 않는 기본 테두리/배경에도
    /// `hh:diagonal type="SOLID"`를 적고 바이너리에 1을 저장한다.
    func testBorderFillMapperReadsTheDiagonalLine() throws {
        let xml = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:bottomBorder type=\"SOLID\" width=\"0.1 mm\" color=\"#000000\"/>",
            with: "<hh:bottomBorder type=\"SOLID\" width=\"0.1 mm\" color=\"#000000\"/>"
                + "<hh:diagonal type=\"DASH_DOT\" width=\"0.4 mm\" color=\"#0000FF\">"
                + "<ext:future xmlns:ext=\"urn:x\"/></hh:diagonal>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(xml)
        let fills = docInfo.idMappings.borderFillArray

        // 픽스처의 첫 borderFill은 hh:diagonal이 없다 — 0으로 남는다.
        expect(fills[0].diagonalType) == 0
        expect(fills[1].diagonalType) == 4
        expect(fills[1].diagonalThickness) == 6
        expect(fills[1].diagonalColor) == HwpColor(0, 0, 0xFF)
        // 소비한 자식은 미해석으로 오보되지 않는다 — 소비 표(`borderFillChildNamespaces`)에
        // 없으면 한글 저장본 전부의 borderFill마다 진단이 하나씩 생긴다.
        let names = docInfo.unknownRecords.compactMap { String(bytes: $0.payload, encoding: .utf8) }
        expect(names).toNot(contain("diagonal"))
        // 소비한 요소 **안의** 미지 자식은 여전히 진단에 남는다 — 요소 단위 소비가 자손을
        // 함께 삼키면 승격이 정보를 잃는 방향이 된다 (`hp:indexmark`와 같은 규약).
        expect(names).to(contain("future"))
    }

    func testColumnMapperReadsTheDividerLineFromTheBorderTable() throws {
        let xml = """
        <hp:colPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        id="" type="NEWSPAPER" layout="LEFT" colCount="2" sameSz="1" sameGap="1134">\
        <hp:colLine type="DASH_DOT" width="0.12 mm" color="#000000"/>\
        </hp:colPr>
        """
        let node = try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/section0.xml")
        let column = HwpxSecPrMapper.mapColumn(
            node, maxDepth: HwpReadLimits.default.maxNestingDepth
        )

        expect(column.dividerType) == 4
        expect(column.dividerThickness) == 1
        expect(column.dividerColor) == HwpColor(0, 0, 0)
    }
}
