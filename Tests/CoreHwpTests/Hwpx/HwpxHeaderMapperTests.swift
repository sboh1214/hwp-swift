@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// header.xml → HwpDocInfo 매핑 — id 리맵·bit 재합성·미해석 진단을 합성
/// XML로 고정한다 (구조는 한글.app 번들 Normal.hwtx 실측을 따른다).
final class HwpxHeaderMapperTests: XCTestCase {
    func testMapsDocumentPropertiesFromSecCntAndBeginNum() throws {
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)

        expect(docInfo.documentProperties.sectionSize) == 2
        expect(docInfo.documentProperties.startingIndex.page) == 3
        expect(docInfo.documentProperties.startingIndex.footnote) == 1
    }

    func testMapsFontFacesPerLanguageWithSubstitute() throws {
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
        let idMappings = docInfo.idMappings

        expect(idMappings.faceNameKoreanArray.map(\.faceName)) == ["함초롬돋움", "함초롬바탕"]
        expect(idMappings.faceNameKoreanArray[1].alternativeFaceName) == "바탕"
        expect(idMappings.faceNameEnglishArray.map(\.faceName)) == ["Arial"]
        expect(idMappings.faceNameChineseArray).to(beEmpty())
    }

    func testRemapsCharShapeReferencesFromSparseIds() throws {
        let (docInfo, tables) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
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
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
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
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
        let paraShape = docInfo.idMappings.paraShapeArray[0]

        expect(paraShape.property1Info.alignmentRawValue) == 3 // CENTER
        expect(paraShape.property1Info.headingTypeRawValue) == 1 // OUTLINE
        expect(paraShape.property1Info.headingLevelRawValue) == 2
        expect(paraShape.property1Info.borderConnect) == true
        expect(paraShape.property1Info.borderIgnoreMargin) == true
        // HwpUnitChar case가 default를 이긴다 (switch 해소). 길이는 모델의
        // 2배 저장 규약대로 XML HWPUNIT의 2배다 (noori HWP↔HWPX 실측).
        expect(paraShape.marginLeft) == 6000
        expect(paraShape.marginRight) == 200
        expect(paraShape.indent) == -5240
        expect(paraShape.paragraphSpacingTop) == 4800
        expect(paraShape.paragraphSpacingBottom) == 1200
        expect(paraShape.resolvedLineSpacingKind) == HwpLineSpacingKind.fixed
        expect(paraShape.resolvedLineSpacingValue) == 3200
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
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
        let tabDefs = docInfo.idMappings.tabDefArray

        expect(tabDefs.map(\.property)) == [0, 0b11]
    }

    func testStylesBeyondByteReferenceSpaceAreRejected() throws {
        /// 스타일 참조(paraStyleId·nextId)는 UInt8 — 257번째부터 오프셋이
        /// 255로 별칭화되므로 정의 수를 참조 공간으로 제한한다.
        func headerXML(styleCount: Int) -> String {
            let styles = (0 ..< styleCount).map {
                "<hh:style id=\"\($0)\" type=\"PARA\" name=\"s\($0)\" "
                    + "engName=\"s\($0)\" paraPrIDRef=\"9\" charPrIDRef=\"7\" "
                    + "nextStyleIDRef=\"0\"/>"
            }.joined()
            return HwpxHeaderFixture.headerXML.replacingOccurrences(
                of: #"<hh:styles itemCnt="2">.*</hh:styles>"#,
                with: "<hh:styles itemCnt=\"\(styleCount)\">\(styles)</hh:styles>",
                options: .regularExpression
            )
        }
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(headerXML(styleCount: 256))
        expect(docInfo.idMappings.styleArray.count) == 256

        expect {
            _ = try HwpxHeaderFixture.mapHeader(headerXML(styleCount: 257))
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("256"))
        })
    }

    func testMapsStylesWithRemappedReferences() throws {
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
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

    func testMapsCharacterOutlineThroughDedicatedTable() throws {
        // 외곽선은 표 33 체계다 — 표 27 계열 lineShapes를 공유하면 THICK이
        // .none으로 접혀 외곽선이 사라지고 DASH가 점선으로 그려진다.
        let withOutlines = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:bold/>",
                with: "<hh:bold/><hh:outline type=\"THICK\"/>"
            )
            .replacingOccurrences(
                of: "<hh:italic/>",
                with: "<hh:italic/><hh:outline type=\"DASH\"/>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withOutlines)

        let shapes = docInfo.idMappings.charShapeArray
        expect(shapes[0].property.borderlineType) == HwpBorderLineType.thickLine
        expect(shapes[1].property.borderlineType) == HwpBorderLineType.loneDot
    }

    func testUnmappedElementsLandInUnknownRecordsWithSyntheticTag() throws {
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)

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
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(minimal)
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
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(minimal, catalog: catalog)

        expect(docInfo.idMappings.binDataArray.count) == 1
        expect(docInfo.idMappings.binDataArray[0].streamId) == 1
    }

    func testUnexpectedRootElementThrowsInvalidXML() {
        expect {
            _ = try HwpxHeaderFixture.mapHeader("<hs:sec xmlns:hs=\"urn:x\"/>")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/header.xml"
            expect(reason).to(contain("root element"))
        })
    }

    func testRootElementInWrongKnownVocabularyIsRejected() {
        // local name "head"가 맞아도 namespace가 다른 known vocabulary(section)면
        // 거부한다 — 전역 known 집합만 보던 이전 가드는 이를 통과시켰다.
        let wrongVocabulary = """
        <x:head xmlns:x="http://www.hancom.co.kr/hwpml/2011/section" secCnt="1">\
        <x:refList/></x:head>
        """
        expect {
            _ = try HwpxHeaderFixture.mapHeader(wrongVocabulary)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/header.xml"
            expect(reason).to(contain("root element"))
        })
    }
}
