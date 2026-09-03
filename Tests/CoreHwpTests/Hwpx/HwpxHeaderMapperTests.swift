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
        // 개요(머리 종류 1)는 numbering 참조를 싣지 않아 0이다.
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

    func testSectionCountBeyondModelFieldIsRejected() throws {
        // 조립기는 spine 목록 전체로 구역을 만드는데(중복 itemref도 각각)
        // sectionSize는 UInt16이라, 클램프하면 sectionArray.count ==
        // sectionSize 불변식이 깨진 모델이 나간다.
        expect {
            _ = try HwpxHeaderFixture.mapHeader(
                HwpxHeaderFixture.headerXML, sectionCount: 65536
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("65,535"))
        })

        // 경계 대조군 — 65,535개는 수용되고 그대로 실린다.
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(
            HwpxHeaderFixture.headerXML, sectionCount: 65535
        )
        expect(docInfo.documentProperties.sectionSize) == 65535
    }

    func testTabDefinitionsBeyondReferenceSpaceAreRejected() {
        // 문단 tabDefId는 0-based UInt16 — 65,537번째부터 오프셋이 65,535로
        // 별칭화된다.
        let tabPrs = (0 ..< 65537).map { "<hh:tabPr id=\"t\($0)\"/>" }.joined()
        let withMany = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:tabProperties itemCnt="2">.*</hh:tabProperties>"#,
            with: "<hh:tabProperties itemCnt=\"65537\">\(tabPrs)</hh:tabProperties>",
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(withMany)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("tabPr"))
        })
    }

    func testFontDefinitionsBeyondReferenceSpaceAreRejected() {
        // fontRef의 언어별 faceId는 0-based WORD — 같은 별칭화가 언어별
        // 글꼴 테이블에도 성립한다.
        let fonts = (0 ..< 65537).map { "<hh:font id=\"f\($0)\" face=\"F\"/>" }.joined()
        let withMany = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:fontface lang="LATIN" fontCnt="1">.*?</hh:fontface>"#,
            with: "<hh:fontface lang=\"LATIN\" fontCnt=\"65537\">\(fonts)</hh:fontface>",
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(withMany)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("font"))
        })
    }

    func testFontDefinitionsAreCountedAcrossSameLanguageBlocks() {
        /// 오프셋은 같은 lang의 여러 fontface 블록에 걸쳐 누적되므로 블록
        /// 단위로 세면 두 블록이 각각 가드를 통과한 뒤 별칭화된다.
        func block(_ range: Range<Int>) -> String {
            let fonts = range.map { "<hh:font id=\"f\($0)\" face=\"F\"/>" }.joined()
            return "<hh:fontface lang=\"LATIN\" fontCnt=\"\(range.count)\">"
                + fonts + "</hh:fontface>"
        }
        let split = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:fontface lang="LATIN" fontCnt="1">.*?</hh:fontface>"#,
            with: block(0 ..< 32769) + block(32769 ..< 65538),
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(split)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("font"))
        })
    }

    func testCharShapesBeyondReferenceSpaceAreRejected() {
        // 스타일의 charShapeId는 0-based UInt16 — run 참조(UInt32)만 온전해
        // 같은 문서 안에서 두 참조가 어긋난다.
        let charPrs = (0 ..< 65537).map { "<hh:charPr id=\"c\($0)\" height=\"1000\"/>" }
            .joined()
        let withMany = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:charProperties itemCnt="2">.*</hh:charProperties>"#,
            with: "<hh:charProperties itemCnt=\"65537\">\(charPrs)</hh:charProperties>",
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(withMany)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("charPr"))
        })
    }

    func testBorderFillsBeyondOneBasedReferenceSpaceAreRejected() {
        // borderFill 참조는 1-based UInt16 (0 = 없음) — 65,536번째 정의부터
        // `borderFillId`의 offset + 1 클램프가 직전 정의로 별칭화된다.
        let fills = (0 ..< 65536).map { "<hh:borderFill id=\"b\($0)\"/>" }.joined()
        let withMany = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:borderFills itemCnt="2">.*</hh:borderFills>"#,
            with: "<hh:borderFills itemCnt=\"65536\">\(fills)</hh:borderFills>",
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(withMany)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("65,535"))
        })
    }

    func testBorderFillsAtTheOneBasedReferenceSpaceBoundaryAreAccepted() throws {
        // 경계 대조군 — 65,535개는 수용되고 마지막 정의가 별칭 없이 참조
        // 공간의 끝(65,535)으로 리맵된다.
        let fills = (0 ..< 65535).map { "<hh:borderFill id=\"b\($0)\"/>" }.joined()
        let atBoundary = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:borderFills itemCnt="2">.*</hh:borderFills>"#,
            with: "<hh:borderFills itemCnt=\"65535\">\(fills)</hh:borderFills>",
            options: .regularExpression
        )

        let (docInfo, idTables) = try HwpxHeaderFixture.mapHeader(atBoundary)
        expect(docInfo.idMappings.borderFillArray.count) == 65535
        expect(idTables.borderFillId(of: "b65534")) == 65535
    }

    func testParaShapesBeyondReferenceSpaceAreRejected() {
        // 문단 paraShapeId는 UInt16 — 65,537번째부터 참조가 65,535로
        // 별칭화되므로 정의 수를 참조 공간으로 제한한다.
        let paraPrs = (0 ..< 65537).map { "<hh:paraPr id=\"p\($0)\"/>" }.joined()
        let withMany = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: #"<hh:paraProperties itemCnt="2">.*</hh:paraProperties>"#,
            with: "<hh:paraProperties itemCnt=\"65537\">\(paraPrs)</hh:paraProperties>",
            options: .regularExpression
        )

        expect {
            _ = try HwpxHeaderFixture.mapHeader(withMany)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("65,536"))
        })
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
        // `numberings`는 #133에서 승격돼 더는 강등되지 않는다 — 이 픽스처에서
        // 매핑 밖에 남은 가족은 금칙어 목록뿐이다.
        expect(names).to(contain("forbiddenWordList"))
        expect(names).toNot(contain("numberings"))
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

    func testCharShapePropertyRawValueMatchesTypedFields() throws {
        // typed 필드만 채우면 rawValue가 0으로 남아 같은 모델이 "보통 글자"
        // 라는 어긋난 값을 함께 주장한다.
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(HwpxHeaderFixture.headerXML)
        let property = docInfo.idMappings.charShapeArray[0].property

        // 비공허: 픽스처 charPr[0]은 진하게·밑줄·취소선을 함께 쓴다.
        expect(property.isBold) == true
        expect(property.rawValue) != 0

        let decoded = try HwpCharShapeProperty.load(property.rawValue)
        expect(decoded.isBold) == property.isBold
        expect(decoded.underlineType) == property.underlineType
        expect(decoded.underlineShape) == property.underlineShape
        expect(decoded.strikethrough) == property.strikethrough
        expect(decoded.strikethroughShape) == property.strikethroughShape
        expect(decoded.emphasisType) == property.emphasisType
    }
}
