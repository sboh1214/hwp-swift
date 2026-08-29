@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 섹션/문단 매핑 크럭스 — WCHAR 스트림 합성 불변식을 합성 XML로 고정한다.
final class HwpxSectionMapperTests: XCTestCase {
    private func makeContext(options: HwpLoadOptions = .default) -> HwpxMappingContext {
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

    private func mapSection(
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
    private let blankBody = """
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

    func testBlankSectionMatchesBinaryBlankDocumentShape() throws {
        let section = try mapSection(blankBody)

        expect(section.paragraph.count) == 1
        let paragraph = section.paragraph[0]

        // WCHAR 스트림: [ext2(secPr), ext2(colPr), char13] — 빈 문서 문단과
        // 같은 모양이고, payload가 실려 있으므로 8+8+1 = 17 WCHAR다.
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)
        expect(chars.count) == 3
        expect(chars[0].type) == HwpCharType.extended
        expect(chars[0].value) == 2
        expect(chars[1].type) == HwpCharType.extended
        expect(chars[1].value) == 2
        expect(chars[2].type) == HwpCharType.char
        expect(chars[2].value) == 13
        expect(paragraph.paraText?.wcharCount) == 17
        expect(paragraph.paraHeader.charCount) == 17
        expect(paragraph.paraHeader.controlMask) == 4
        expect(paragraph.paraHeader.isLastInList) == true
        expect(paragraph.paraHeader.paraId) == 3_121_190_098

        // ctrl 슬롯은 extended 문자와 1:1 — [.section, .column].
        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        expect(ctrls.count) == 2
        guard case let .section(sectionDef) = ctrls[0] else {
            return fail("Expected .section, got \(ctrls[0])")
        }
        guard case let .column(column) = ctrls[1] else {
            return fail("Expected .column, got \(ctrls[1])")
        }
        expect(sectionDef.pageDef.width) == 59528
        expect(sectionDef.pageDef.height) == 84186
        expect(sectionDef.pageDef.marginLeft) == 8504
        expect(sectionDef.pageDef.marginHeader) == 4252
        expect(sectionDef.pageDef.marginFootnote) == 4252
        expect(sectionDef.columnSpacing) == 1134
        expect(sectionDef.defaultTabSpacing) == 8000
        expect(column.property.count) == 1
        expect(column.property.isSameWidth) == true

        // charPr id "7" → 리맵 오프셋 0. 같은 위치의 두 run은 마지막이 이긴다.
        expect(paragraph.paraCharShape.startingIndex) == [0]
        expect(paragraph.paraCharShape.shapeId) == [0]
        expect(paragraph.paraHeader.charShapeInfoCount) == 1

        // lineseg 9속성 1:1 — 절대 캐시 조판 유지의 전제.
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.count) == 1
        let seg = paragraph.paraLineSeg.paraLineSegInternalArray[0]
        expect(seg.textStartingIndex) == 0
        expect(seg.lineHeight) == 1000
        expect(seg.baselineDistance) == 850
        expect(seg.width) == 42520
        expect(seg.property) == 393_216
        expect(paragraph.paraHeader.alignInfoCount) == 1
    }

    func testTextRunsPreserveInterleavingAndWcharArithmetic() throws {
        let section = try mapSection(
            """
            <hp:p paraPrIDRef="9" styleIDRef="2">\
            <hp:run charPrIDRef="7"><hp:t>ab<hp:tab/>cd</hp:t></hp:run>\
            <hp:run charPrIDRef="12"><hp:t>한𐐷</hp:t></hp:run>\
            </hp:p>
            """
        )
        let paragraph = section.paragraph[0]
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)

        // a, b, tab(inline 9), c, d, 한, 𐐷(서로게이트 2), 문단 끝 13.
        expect(chars.map(\.type)) == [
            .char, .char, .inline, .char, .char, .char, .char, .char, .char,
        ]
        expect(chars[2].value) == 9
        // WCHAR 산술: 2 + 8(tab) + 2 + 1(한) + 2(𐐷) + 1(13) = 16.
        expect(paragraph.paraText?.wcharCount) == 16
        expect(paragraph.paraHeader.charCount) == 16
        // 둘째 run은 tab 포함 12 WCHAR 뒤에서 시작한다.
        expect(paragraph.paraCharShape.startingIndex) == [0, 12]
        expect(paragraph.paraCharShape.shapeId) == [0, 1]
        // 문단 모양·스타일 리맵.
        expect(paragraph.paraHeader.paraShapeId) == 1
        expect(paragraph.paraHeader.paraStyleId) == 1
        // tab은 inline이라 ctrl 슬롯이 없다.
        expect(paragraph.ctrlHeaderArray) == []
        expect(paragraph.paraHeader.controlMask) == 1 << 9
    }

    func testFieldBeginEndKeepOrdinalAlignment() throws {
        let section = try mapSection(
            """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:ctrl><hp:fieldBegin id="1" type="HYPERLINK"/></hp:ctrl>\
            <hp:t>링크</hp:t>\
            <hp:ctrl><hp:fieldEnd beginIDRef="1"/></hp:ctrl>\
            </hp:run></hp:p>
            """
        )
        let paragraph = section.paragraph[0]
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)

        // ext3(필드 시작) → 텍스트 → inline4(필드 끝, ctrl 슬롯 없음) → 13.
        expect(chars.map(\.value)) == [3, 0xB9C1, 0xD06C, 4, 13]
        expect(chars[0].type) == HwpCharType.extended
        expect(chars[3].type) == HwpCharType.inline

        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        expect(ctrls.count) == 1
        guard case let .notImplemented(header) = ctrls[0] else {
            return fail("Expected .notImplemented, got \(ctrls[0])")
        }
        expect(header.ctrlId) == HwpFieldCtrlId.hyperLink.rawValue
        // 합성 payload 선두 4바이트가 ctrl id다 (HwpInlineControl 계약).
        expect(chars[0].inlineControl?.rawControlId) == HwpFieldCtrlId.hyperLink.rawValue
    }

    func testObjectElementsDegradeToNotImplementedAnchors() throws {
        let section = try mapSection(
            """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:ole id="1"/>\
            <hp:ctrl><hp:header id="2"/></hp:ctrl>\
            </hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[0]
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)

        expect(chars.map(\.value)) == [11, 16, 13]
        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        expect(ctrls.count) == 2
        guard case let .notImplemented(ole) = ctrls[0],
              case let .notImplemented(header) = ctrls[1]
        else {
            return fail("Expected two .notImplemented, got \(ctrls)")
        }
        expect(ole.ctrlId) == HwpCommonCtrlId.ole.rawValue
        expect(header.ctrlId) == HwpOtherCtrlId.header.rawValue
        // 분류 가능한 요소는 위치가 확실하므로 lineseg가 유지된다.
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.count) == 1
    }

    func testUnknownElementDropsLineSegCacheAndRecordsDiagnostic() throws {
        let section = try mapSection(
            """
            <hp:p><hp:run charPrIDRef="7"><hp:t>가</hp:t>\
            <hp:mysteryObject/></hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[0]

        // 미지 요소는 앵커를 추측하지 않는다 — WCHAR 위치가 불확실해지므로
        // 절대 캐시를 폐기하고 reflow로 강등한다.
        expect(paragraph.paraLineSeg.paraLineSegInternalArray).to(beEmpty())
        expect(paragraph.paraHeader.alignInfoCount) == 0
        let names = paragraph.unknownChildren.map {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["mysteryObject"]
        // 텍스트 자체는 살아 있다.
        expect(paragraph.paraText?.wcharCount) == 2
    }

    func testZeroWidthMarksKeepLineSegAndLeaveDiagnostic() throws {
        let section = try mapSection(
            """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:t>가<hp:markpenBegin color="#FFFF00"/>나<hp:markpenEnd/></hp:t>\
            </hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[0]

        // 형광펜 표식은 HWP5에서 WCHAR를 차지하지 않는다 — 위치 확실.
        expect(paragraph.paraText?.wcharCount) == 3
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.count) == 1
        let names = paragraph.unknownChildren.map {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["markpenBegin", "markpenEnd"]
    }

    func testInvalidLineSegCacheIsDropped() throws {
        let section = try mapSection(
            """
            <hp:p><hp:run charPrIDRef="7"><hp:t>가나</hp:t></hp:run>\
            <hp:linesegarray>\
            <hp:lineseg textpos="5" vertpos="0" vertsize="1000" textheight="1000" \
            baseline="850" spacing="600" horzpos="0" horzsize="42520" flags="0"/>\
            </hp:linesegarray></hp:p>
            """
        )

        // 첫 textpos ≠ 0 — 신뢰할 수 없는 캐시는 폐기한다.
        expect(section.paragraph[0].paraLineSeg.paraLineSegInternalArray).to(beEmpty())
    }

    func testPageBreakAttributeSetsColumnTypeBit() throws {
        let section = try mapSection(
            """
            <hp:p pageBreak="1"><hp:run charPrIDRef="7"><hp:t>가</hp:t></hp:run></hp:p>\
            <hp:p><hp:run charPrIDRef="7"><hp:t>나</hp:t></hp:run></hp:p>
            """
        )

        // paginator가 읽는 쪽 나누기 bit 2.
        expect(section.paragraph[0].paraHeader.columnType & 0b100) == 0b100
        expect(section.paragraph[1].paraHeader.columnType) == 0
        expect(section.paragraph[0].paraHeader.isLastInList) == false
        expect(section.paragraph[1].paraHeader.isLastInList) == true
    }

    func testNonParagraphChildrenLandInUnknownRecords() throws {
        let section = try mapSection(
            blankBody + "<hp:someSectionExtra/>"
        )

        let names = section.unknownRecords.map {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["someSectionExtra"]
    }

    func testUnexpectedRootElementThrowsInvalidXML() {
        expect {
            _ = try HwpxSectionMapper.map(
                Data("<hh:head xmlns:hh=\"urn:x\"/>".utf8),
                context: self.makeContext()
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("root element"))
        })
    }

    func testSectionWithoutParagraphsThrowsInvalidXML() {
        expect {
            _ = try self.mapSection("")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("no paragraphs"))
        })
    }

    func testRootInWrongKnownVocabularyIsRejected() {
        // local name "sec"가 맞아도 namespace가 다른 known vocabulary(head)면
        // 거부한다 — 전역 known 집합만 보던 이전 가드는 이를 통과시켰다.
        expect {
            _ = try HwpxSectionMapper.map(
                Data(
                    """
                    <x:sec xmlns:x="http://www.hancom.co.kr/hwpml/2011/head"/>
                    """.utf8
                ),
                context: self.makeContext()
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("root element"))
        })
    }
}
