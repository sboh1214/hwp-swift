@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 섹션/문단 매핑 크럭스 — WCHAR 스트림 합성 불변식을 합성 XML로 고정한다.
final class HwpxSectionMapperTests: XCTestCase {
    private func mapSection(
        _ body: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSection {
        try HwpxSectionFixture.mapSection(body, options: options)
    }

    private var blankBody: String {
        HwpxSectionFixture.blankBody
    }

    func testGutterTypeMapsIntoPageDefinitionProperty() throws {
        // 조판 gutterInsets는 property bits 1-2로 제본 방향을 정한다 —
        // 양만 옮기면 위 제본(TOP_BOTTOM) 문서가 왼쪽에 제본 여백을 얻는다.
        let topBottom = try mapSection(blankBody.replacingOccurrences(
            of: "gutterType=\"LEFT_ONLY\"", with: "gutterType=\"TOP_BOTTOM\""
        ))
        let leftRight = try mapSection(blankBody.replacingOccurrences(
            of: "gutterType=\"LEFT_ONLY\"", with: "gutterType=\"LEFT_RIGHT\""
        ))
        let leftOnly = try mapSection(blankBody)

        expect(try self.firstSectionDef(of: topBottom).pageDef.property) == 0b100
        expect(try self.firstSectionDef(of: leftRight).pageDef.property) == 0b010
        expect(try self.firstSectionDef(of: leftOnly).pageDef.property) == 0
    }

    private func firstSectionDef(of section: HwpSection) throws -> HwpSectionDef {
        let ctrls = try XCTUnwrap(section.paragraph[0].ctrlHeaderArray)
        guard case let .section(sectionDef) = ctrls[0] else {
            struct UnexpectedControl: Error {}
            throw UnexpectedControl()
        }
        return sectionDef
    }

    func testParagraphMetadataBeyondUInt16IsRejected() throws {
        // 65,536개 글자 모양 변경 — 헤더 count(UInt16)가 담지 못하는 배열은
        // 클램프가 아니라 typed error로 거부된다.
        let runs = (0 ..< 65536).map {
            "<hp:run charPrIDRef=\"\($0 % 2)\"><hp:t>a</hp:t></hp:run>"
        }.joined()
        let xml = """
        <hp:p xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        id="1" paraPrIDRef="0" styleIDRef="0">\(runs)</hp:p>
        """
        var tables = HwpxIdTables()
        tables.charShape.register(id: "0", offset: 0)
        tables.charShape.register(id: "1", offset: 1)
        let context = HwpxMappingContext(
            idTables: tables,
            binItemIdByManifestId: [:],
            options: .default,
            entry: "Contents/section0.xml"
        )
        let node = try HwpxXMLTreeParser.parse(
            Data(xml.utf8), entry: "Contents/section0.xml"
        )

        expect {
            _ = try HwpxParagraphMapper.map(node, context: context, isLastInList: true)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("exceed"))
        })
    }

    func testLineCacheWithUnknownChildIsRejectedAndDemoted() throws {
        // 안전밸브의 "미지 요소" 축 — lineseg만 골라 채택하면 불확실한
        // 캐시가 절대 조판의 신뢰 입력이 된다. 대조군: 깨끗한 캐시는 채택.
        let clean = try mapSection(blankBody)
        expect(clean.paragraph[0].paraLineSeg.paraLineSegInternalArray.count) == 1

        let withUnknown = try mapSection(blankBody.replacingOccurrences(
            of: "<hp:linesegarray>",
            with: "<hp:linesegarray><hp:future/>"
        ))
        let paragraph = withUnknown.paragraph[0]
        expect(paragraph.paraLineSeg.paraLineSegInternalArray).to(beEmpty())
        let names = paragraph.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names).to(contain("future"))
    }

    func testUnknownColumnChildrenDegradeIntoDiagnostics() throws {
        // colPr의 미소비 자식은 column.unknownChildren으로 남아야
        // parseDiagnostics()가 완전한 파스로 오보하지 않는다.
        let body = blankBody.replacingOccurrences(
            of: "sameSz=\"1\" sameGap=\"0\"/>",
            with: "sameSz=\"1\" sameGap=\"0\"><hp:colBreak/></hp:colPr>"
        )
        let section = try mapSection(body)

        let ctrls = try XCTUnwrap(section.paragraph[0].ctrlHeaderArray)
        guard case let .column(column) = ctrls[1] else {
            return fail("Expected .column, got \(ctrls[1])")
        }
        let names = column.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["colBreak"]
    }

    func testLineSegmentsWithoutTextposDegradeToReflow() throws {
        // textpos는 sanity 판정의 기준이라 기본값 0으로 합성하면 안 된다 —
        // 누락·비숫자 캐시는 빈 배열로 강등해 reflow로 넘긴다.
        for broken in ["", " textpos=\"abc\""] {
            let body = blankBody.replacingOccurrences(
                of: "<hp:lineseg textpos=\"0\"",
                with: "<hp:lineseg\(broken)"
            )
            let section = try mapSection(body)
            expect(section.paragraph[0].paraLineSeg.paraLineSegInternalArray)
                .to(beEmpty(), description: "broken=\(broken.isEmpty ? "missing" : broken)")
        }

        // 정상 캐시는 그대로 신뢰한다 (음성 대조).
        let intact = try mapSection(blankBody)
        expect(intact.paragraph[0].paraLineSeg.paraLineSegInternalArray.count) == 1
    }

    func testForeignSameNameChildIsPreservedInDiagnostics() throws {
        // <ext:pagePr>는 조회에서 거부되므로 소비된 적이 없다 — 소비 판정이
        // local name만 보면 진단에서도 사라진다.
        let body = blankBody.replacingOccurrences(
            of: "</hp:secPr>",
            with: "<ext:pagePr xmlns:ext=\"urn:example:ext\"/></hp:secPr>"
        )
        let section = try mapSection(body)

        guard case let .section(sectionDef)? = section.paragraph[0].ctrlHeaderArray?.first
        else {
            return fail("first control must be .section")
        }
        let names = sectionDef.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["pagePr"]
        // 진짜 hp:pagePr은 소비되므로 강등되지 않는다 (음성 대조).
        expect(sectionDef.pageDef.width) == 59528
    }

    func testParagraphFromOtherKnownVocabularyIsNotABodyParagraph() throws {
        // local name "p"라도 head vocabulary(hh:p)면 본문 문단이 아니다 —
        // 문단으로 오인하지 않고 unknown으로 보고한다 ((namespace, local name)).
        let section = try mapSection(
            blankBody + "<hh:p xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\"/>"
        )

        expect(section.paragraph.count) == 1
        let names = section.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["p"]
    }

    func testUnconsumedSecPrChildrenDegradeIntoSectionDefDiagnostics() throws {
        // footNotePr 등 1차 범위 밖 자식은 조용히 사라지지 않고 합성
        // unknownChildren으로 남아야 한다 — 소비되는 pagePr·startNum은 제외.
        let body = blankBody.replacingOccurrences(
            of: "</hp:secPr>",
            with: "<hp:footNotePr/><hp:endNotePr/><hp:pageBorderFill type=\"BOTH\"/></hp:secPr>"
        )
        let section = try mapSection(body)

        guard case let .section(sectionDef)? = section.paragraph[0].ctrlHeaderArray?.first else {
            return fail("first control must be .section")
        }
        let names = sectionDef.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["footNotePr", "endNotePr", "pageBorderFill"]
        expect(sectionDef.unknownChildren.map(\.tagId)) == [
            hwpxSyntheticTagId, hwpxSyntheticTagId, hwpxSyntheticTagId,
        ]
    }

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
            HwpxSectionFixture.blankBody + """
            <hp:p paraPrIDRef="9" styleIDRef="2">\
            <hp:run charPrIDRef="7"><hp:t>ab<hp:tab/>cd</hp:t></hp:run>\
            <hp:run charPrIDRef="12"><hp:t>한𐐷</hp:t></hp:run>\
            </hp:p>
            """
        )
        let paragraph = section.paragraph[1]
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
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:ctrl><hp:fieldBegin id="1" type="HYPERLINK"/></hp:ctrl>\
            <hp:t>링크</hp:t>\
            <hp:ctrl><hp:fieldEnd beginIDRef="1"/></hp:ctrl>\
            </hp:run></hp:p>
            """
        )
        let paragraph = section.paragraph[1]
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

    func testObjectElementsPromoteOleAndKeepChartAndHeaderDegraded() throws {
        let section = try mapSection(
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:ole id="1"/>\
            <hp:chart id="3"/>\
            <hp:ctrl><hp:header id="2"/></hp:ctrl>\
            </hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[1]
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)

        expect(chars.map(\.value)) == [11, 11, 16, 13]
        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        // 개수를 guard로 본다 — expect만 두면 슬롯이 빌 때 뒤 인덱스 접근이
        // 트랩해 실패 사유가 출력에 남지 않는다.
        guard ctrls.count == 3 else {
            return fail("Expected three controls, got \(ctrls)")
        }
        guard case let .ole(ole) = ctrls[0],
              case let .notImplemented(chart) = ctrls[1],
              case let .notImplemented(header) = ctrls[2]
        else {
            return fail("Expected .ole + two .notImplemented, got \(ctrls)")
        }
        // <hp:ole>은 typed 승격됐다 (#134) — manifest 참조가 없는 합성 문서라
        // BinData id는 0으로 접힌다.
        expect(ole.ctrlId) == HwpCommonCtrlId.ole
        expect(ole.shapeComponentArray.first?.oleArray.first?.binaryDataId) == 0
        // fallback 없는 <hp:chart>는 쌍둥이 <hp:ole>과 같은 4CC의 강등 앵커여야
        // 한다 — 분류표에 없으면 앵커도 ctrl 슬롯도 없이 사라진다.
        expect(chart.ctrlId) == HwpCommonCtrlId.ole.rawValue
        // 4CC는 같아도 요소 이름은 payload에 남아 진단에서 갈린다.
        expect(String(bytes: chart.rawPayload, encoding: .utf8)) == "chart"
        expect(header.ctrlId) == HwpOtherCtrlId.header.rawValue
        // 분류 가능한 요소는 위치가 확실하므로 lineseg가 유지된다.
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.count) == 1
    }

    func testUnknownElementDropsLineSegCacheAndRecordsDiagnostic() throws {
        let section = try mapSection(
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7"><hp:t>가</hp:t>\
            <hp:mysteryObject/></hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[1]

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
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7">\
            <hp:t>가<hp:markpenBegin color="#FFFF00"/>나<hp:markpenEnd/></hp:t>\
            </hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[1]

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
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7"><hp:t>가나</hp:t></hp:run>\
            <hp:linesegarray>\
            <hp:lineseg textpos="5" vertpos="0" vertsize="1000" textheight="1000" \
            baseline="850" spacing="600" horzpos="0" horzsize="42520" flags="0"/>\
            </hp:linesegarray></hp:p>
            """
        )

        // 첫 textpos ≠ 0 — 신뢰할 수 없는 캐시는 폐기한다.
        expect(section.paragraph[1].paraLineSeg.paraLineSegInternalArray).to(beEmpty())
    }

    func testPageBreakAttributeSetsColumnTypeBit() throws {
        let section = try mapSection(
            HwpxSectionFixture.blankBody + """
            <hp:p pageBreak="1"><hp:run charPrIDRef="7"><hp:t>가</hp:t></hp:run></hp:p>\
            <hp:p><hp:run charPrIDRef="7"><hp:t>나</hp:t></hp:run></hp:p>
            """
        )

        // paginator가 읽는 쪽 나누기 bit 2.
        expect(section.paragraph[1].paraHeader.columnType & 0b100) == 0b100
        expect(section.paragraph[2].paraHeader.columnType) == 0
        expect(section.paragraph[1].paraHeader.isLastInList) == false
        expect(section.paragraph[2].paraHeader.isLastInList) == true
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
                context: HwpxSectionFixture.makeContext()
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
                context: HwpxSectionFixture.makeContext()
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("root element"))
        })
    }

    func testForeignPrefixedAttributesDoNotDriveLayout() throws {
        // 요소는 (namespace, local name)으로 엄격히 매칭하면서 속성만 접두사를
        // 무시하면 조작 속성이 진짜 조판을 바꾼다 — ext:pageBreak가 쪽 나누기로
        // 읽히면 안 된다. 대조군은 무접두사 pageBreak다 (bit 2).
        let section = try mapSection(
            HwpxSectionFixture.blankBody + """
            <hp:p xmlns:ext="urn:x" ext:pageBreak="1">\
            <hp:run charPrIDRef="7"><hp:t>가</hp:t></hp:run></hp:p>\
            <hp:p pageBreak="1"><hp:run charPrIDRef="7"><hp:t>나</hp:t></hp:run></hp:p>
            """
        )

        expect(section.paragraph[1].paraHeader.columnType & 0b100) == 0
        expect(section.paragraph[2].paraHeader.columnType & 0b100) == 0b100
    }
}
