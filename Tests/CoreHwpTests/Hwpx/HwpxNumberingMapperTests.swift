@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hh:numbering`·`hh:bullet` → 문단 번호·글머리표 정의 매핑 — 표 39/40 속성
/// 비트, 표 41 번호 형식 코드, 수준 슬롯 배치, `charPrIDRef` 센티널,
/// 참조 공간 상한, 미소비 자식 강등을 합성 XML로 고정한다 (#133).
final class HwpxNumberingMapperTests: XCTestCase {
    /// `hh:refList` 안에 가족 하나만 담은 최소 헤더.
    private func mapFamilies(_ families: String) throws -> HwpDocInfo {
        try HwpxHeaderFixture.mapHeader("""
        <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" secCnt="1">\
        <hh:refList>\(families)</hh:refList></hh:head>
        """).docInfo
    }

    private func mapNumbering(_ paraHeads: String) throws -> HwpNumbering {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
        \(paraHeads)</hh:numbering></hh:numberings>
        """)
        return try XCTUnwrap(docInfo.idMappings.numberingArray.first)
    }

    private func mapBullet(_ element: String) throws -> HwpBullet {
        let docInfo = try mapFamilies(
            "<hh:bullets itemCnt=\"1\">\(element)</hh:bullets>"
        )
        return try XCTUnwrap(docInfo.idMappings.bulletArray.first)
    }

    /// 수준 하나짜리 `hh:paraHead` — 속성만 바꿔 가며 12바이트를 확인한다.
    private func paraHead(_ attributes: String, level: Int = 1, text: String = "") -> String {
        "<hh:paraHead level=\"\(level)\" \(attributes)>\(text)</hh:paraHead>"
    }

    // MARK: - 표 39 문단 머리 정보 12바이트

    func testNooriLevelOneParaHeadMatchesHwpPairBytes() throws {
        // noori 실저장본 수준 1 그대로 — HWP 쌍의 HWPTAG_NUMBERING 앞 12바이트가
        // `0C 00 00 00 | 00 00 | 32 00 | FF FF FF FF`다
        // (Fixtures/noori/manifest.json `docInfoNumberings`).
        let numbering = try mapNumbering(paraHead(
            """
            start="1" align="LEFT" useInstWidth="1" autoIndent="1" widthAdjust="0" \
            textOffsetType="PERCENT" textOffset="50" numFormat="DIGIT" \
            charPrIDRef="4294967295" checkable="0"
            """,
            text: "^1."
        ))
        expect(numbering.formatArray[0].property) == [
            0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x32, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        ]
        expect(numbering.formatArray[0].format) == "^1."
        expect(numbering.formatArray[0].formatLength) == 3
    }

    func testNooriBulletMatchesHwpPairBytes() throws {
        // HWP 쌍의 HWPTAG_BULLET 앞 14바이트는 `08 00 00 00 | 00 00 | 32 00 |
        // FF FF FF FF | 2D 00` — 앞 8바이트가 `info`, 다음 INT32가 글자 모양
        // ID, 그다음 WCHAR가 글머리표 문자다.
        let bullet = try mapBullet("""
        <hh:bullet id="1" char="-" useImage="0">\
        <hh:paraHead level="0" align="LEFT" useInstWidth="0" autoIndent="1" \
        widthAdjust="0" textOffsetType="PERCENT" textOffset="50" numFormat="DIGIT" \
        charPrIDRef="4294967295" checkable="0"/></hh:bullet>
        """)
        expect(bullet.info) == [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x32, 0x00]
        expect(bullet.headCharShapeId) == -1
        expect(bullet.char) == "-"
        expect(bullet.imageId) == 0
    }

    // MARK: - 표 40 속성 비트

    func testAlignmentOccupiesBitsZeroAndOne() throws {
        for (name, code) in [("LEFT", 0), ("CENTER", 1), ("RIGHT", 2)] {
            let numbering = try mapNumbering(paraHead(
                "align=\"\(name)\" numFormat=\"DIGIT\" textOffset=\"0\" charPrIDRef=\"-1\""
            ))
            expect(numbering.formatArray[0].property[0] & 0b11) == BYTE(code)
        }
    }

    func testWidthAndIndentFlagsOccupyBitsTwoAndThree() throws {
        let both = try mapNumbering(paraHead(
            "useInstWidth=\"1\" autoIndent=\"1\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        expect(both.formatArray[0].property[0] & 0b1100) == 0b1100

        let neither = try mapNumbering(paraHead(
            "useInstWidth=\"0\" autoIndent=\"0\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        expect(neither.formatArray[0].property[0] & 0b1100) == 0
    }

    /// 생략은 거짓이 아니라 **참**이다 — 한컴 모델이 두 속성을
    /// `m_bUseInstWidth(true)`·`m_bAutoIndent(true)`로 초기화해 직렬화한다.
    func testOmittedWidthAndIndentFlagsDefaultToTrue() throws {
        let omitted = try mapNumbering(paraHead("textOffset=\"0\" charPrIDRef=\"-1\""))
        expect(omitted.formatArray[0].property[0] & 0b1100) == 0b1100
    }

    func testTextOffsetTypeOccupiesBitFour() throws {
        let percent = try mapNumbering(paraHead(
            "textOffsetType=\"PERCENT\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        expect(percent.formatArray[0].property[0] & 0b10000) == 0

        let value = try mapNumbering(paraHead(
            "textOffsetType=\"HWPUNIT\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        expect(value.formatArray[0].property[0] & 0b10000) == 0b10000
    }

    /// 표 41 번호 형식은 표 40에 자리가 없다 — 빈 문서 기본값(`HwpIdMappings`)의
    /// `^1.` 0x0C · `^2.` 0x10C · `^7` 0x2C가 noori HWPX의 `DIGIT`(0)·
    /// `HANGUL_SYLLABLE`(8)·`CIRCLED_DIGIT`(1)과 맞아 bit 5-8이다.
    func testNumberFormatOccupiesBitsFiveToEight() throws {
        // 두 불리언을 생략했으므로 bit 2·3(0x0C)이 기본으로 선다.
        let defaultFlags: UInt32 = 0x0000_000C
        let expected: [(String, UInt32)] = [
            ("DIGIT", 0x0000_0000), ("CIRCLED_DIGIT", 0x0000_0020),
            ("HANGUL_SYLLABLE", 0x0000_0100), ("CIRCLED_IDEOGRAPH", 0x0000_01C0),
        ]
        for (name, bits) in expected {
            let numbering = try mapNumbering(paraHead(
                "numFormat=\"\(name)\" textOffset=\"0\" charPrIDRef=\"-1\""
            ))
            expect(Self.property(numbering.formatArray[0])) == bits | defaultFlags
        }
    }

    /// bit 5-8은 4비트라 표 41 밖 코드(`SYMBOL` 0x80)는 담기지 않는다 —
    /// 미지 이름은 `HwpxNumberFormatMapper`의 0(숫자) 폴백을 탄다.
    func testNumberFormatOutsideTableFortyOneFoldsIntoFourBits() throws {
        let symbol = try mapNumbering(paraHead(
            "numFormat=\"SYMBOL\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        expect(Self.property(symbol.formatArray[0]) & 0x0000_01E0) == 0

        let unknown = try mapNumbering(paraHead(
            "numFormat=\"NOT_A_FORMAT\" textOffset=\"0\" charPrIDRef=\"-1\""
        ))
        // 번호 모양 비트만 0이고, 생략한 두 불리언의 기본 bit 2·3은 선다.
        expect(Self.property(unknown.formatArray[0])) == 0x0000_000C
    }

    /// 매퍼가 합성한 12바이트는 바이너리 파서와 같은 `HwpParaHeadInfo`로 읽힌다 (#152).
    /// 합성 입력이다 — 실물 대조는 `outline-numbering` 쌍(`ParaHeadInfoTests`·등가 축).
    func testMappedParaHeadInfoDecodesThroughTheSharedModel() throws {
        let numbering = try mapNumbering(paraHead(
            """
            align="CENTER" useInstWidth="0" autoIndent="1" widthAdjust="-3" \
            textOffsetType="HWPUNIT" textOffset="300" numFormat="ROMAN_CAPITAL" \
            charPrIDRef="-1"
            """,
            text: "^1."
        ))
        let info = try XCTUnwrap(numbering.formatArray[0].paraHeadInfo)

        expect(info) == HwpParaHeadInfo(
            alignment: .center, useInstWidth: false, autoIndent: true,
            textOffsetType: .hwpUnit, numberFormat: 2,
            widthAdjust: -3, textOffset: 300, charShapeId: -1
        )
        expect(info.bytes) == numbering.formatArray[0].property
        // 슬롯이 빈 수준은 기본 init 그대로다 — 속성 0 · 거리 0 · 바탕글.
        expect(numbering.formatArray[1].paraHeadInfo) == HwpParaHeadInfo()
    }

    func testWidthAdjustAndTextOffsetAreSignedSixteenBitFields() throws {
        let numbering = try mapNumbering(paraHead(
            "widthAdjust=\"-3\" textOffset=\"50\" charPrIDRef=\"-1\""
        ))
        let property = numbering.formatArray[0].property
        expect([property[4], property[5]]) == [0xFD, 0xFF]
        expect([property[6], property[7]]) == [0x32, 0x00]
    }

    // MARK: - `charPrIDRef` 센티널과 리맵

    func testCharPrIdRefSentinelStaysMinusOneInsteadOfDanglingToZero() throws {
        for sentinel in ["4294967295", "-1"] {
            let numbering = try mapNumbering(paraHead(
                "numFormat=\"DIGIT\" textOffset=\"0\" charPrIDRef=\"\(sentinel)\""
            ))
            let property = numbering.formatArray[0].property
            expect(Array(property[8 ... 11])) == [0xFF, 0xFF, 0xFF, 0xFF]
        }
    }

    func testCharPrIdRefIsRemappedThroughTheCharShapeTable() throws {
        // charPr id "7"·"12" → 오프셋 0·1 (id는 dense가 아니다).
        let docInfo = try mapFamilies("""
        <hh:charProperties itemCnt="2">\
        <hh:charPr id="7" height="1000"/><hh:charPr id="12" height="1200"/>\
        </hh:charProperties>\
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
        <hh:paraHead level="1" charPrIDRef="12" textOffset="0"/>\
        </hh:numbering></hh:numberings>
        """)
        let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
        expect(Array(numbering.formatArray[0].property[8 ... 11])) == [0x01, 0x00, 0x00, 0x00]
    }

    // MARK: - 수준 슬롯

    func testLevelsFillDocumentedAndExtendedSlotsByLevelAttribute() throws {
        let heads = (1 ... 10)
            .map { paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", level: $0, text: "^\($0)") }
            .joined()
        let numbering = try mapNumbering(heads)
        expect(numbering.formatArray.count) == 7
        expect(numbering.formatArray.map(\.format)) == ["^1", "^2", "^3", "^4", "^5", "^6", "^7"]
        expect(numbering.extendedFormatArray?.map(\.format)) == ["^8", "^9", "^10"]
    }

    /// 문서 순서가 아니라 `level` 속성이 슬롯을 정한다.
    func testLevelSlotsFollowTheLevelAttributeNotDocumentOrder() throws {
        let numbering = try mapNumbering(
            paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", level: 3, text: "third")
                + paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", level: 1, text: "first")
        )
        expect(numbering.formatArray[0].format) == "first"
        expect(numbering.formatArray[2].format) == "third"
    }

    /// 배열 길이는 바이너리와 같게 고정하고 빈 수준은 형식 길이 0이다.
    func testMissingLevelsBecomeEmptySlotsOfTheDocumentedLength() throws {
        let numbering = try mapNumbering(
            paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", level: 2, text: "^2")
        )
        expect(numbering.formatArray.count) == 7
        expect(numbering.extendedFormatArray?.count) == 3
        expect(numbering.formatArray[0].format) == ""
        expect(numbering.formatArray[0].formatLength) == 0
        expect(numbering.formatArray[1].format) == "^2"
        // 빈 슬롯의 글자 모양 ID는 바탕글(-1)이다 — 0은 실재하는 참조다.
        expect(Array(numbering.formatArray[0].property[8 ... 11])) == [0xFF, 0xFF, 0xFF, 0xFF]
    }

    func testDuplicateLevelKeepsFirstAndDemotesTheRest() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
        <hh:paraHead level="1" textOffset="0" charPrIDRef="-1">first</hh:paraHead>\
        <hh:paraHead level="1" textOffset="0" charPrIDRef="-1">second</hh:paraHead>\
        </hh:numbering></hh:numberings>
        """)
        let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
        expect(numbering.formatArray[0].format) == "first"
        expect(Self.demotedNames(docInfo)) == ["paraHead"]
    }

    func testLevelOutsideOneToTenIsDemotedWithoutASlot() throws {
        for level in [0, 11] {
            let docInfo = try mapFamilies("""
            <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
            <hh:paraHead level="\(level)" textOffset="0" charPrIDRef="-1">x</hh:paraHead>\
            </hh:numbering></hh:numberings>
            """)
            let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
            expect(numbering.formatArray.allSatisfy(\.format.isEmpty)) == true
            expect(Self.demotedNames(docInfo)) == ["paraHead"]
        }
    }

    // MARK: - 시작 번호

    func testStartingIndexesComeFromNumberingAndParaHeadStart() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="0">\
        <hh:paraHead level="1" start="5" textOffset="0" charPrIDRef="-1"/>\
        </hh:numbering></hh:numberings>
        """)
        let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
        expect(numbering.startingIndex) == 0
        expect(numbering.startingIndexArray?.first) == 5
        // 선언 없는 수준은 스키마 기본값 1이다.
        expect(numbering.startingIndexArray?.dropFirst()) == [1, 1, 1, 1, 1, 1]
        expect(numbering.extendedStartingIndexArray) == [1, 1, 1]
    }

    /// 수준별 시작 번호는 표 38이 `UINT`로 적는다 — 16비트로 먼저 읽으면
    /// 65,535를 넘는 값이 파싱 실패로 기본값 1이 되어 조용히 뭉개진다.
    func testLevelStartingIndexKeepsValuesBeyondSixteenBits() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
        <hh:paraHead level="1" start="65535" textOffset="0" charPrIDRef="-1"/>\
        <hh:paraHead level="2" start="65536" textOffset="0" charPrIDRef="-1"/>\
        <hh:paraHead level="3" start="70000" textOffset="0" charPrIDRef="-1"/>\
        </hh:numbering></hh:numberings>
        """)
        let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
        expect(numbering.startingIndexArray?.prefix(3)) == [65535, 65536, 70000]
    }

    // MARK: - 글머리표 문자

    func testBulletCharTakesTheFirstUtf16UnitAndEmptyStaysEmpty() throws {
        let geometric = try mapBullet("<hh:bullet id=\"1\" char=\"□\"/>")
        expect(geometric.char) == "□"
        // 두 글자 이상은 첫 unit — 필드가 WCHAR 하나다.
        let twoChars = try mapBullet("<hh:bullet id=\"1\" char=\"ab\"/>")
        expect(twoChars.char) == "a"
        // 빈 문자열·생략은 빈 문자열이다 — U+0000 한 자로 접으면 조판의
        // `char.isEmpty` 게이트를 지나 NUL 글리프를 그린다.
        let empty = try mapBullet("<hh:bullet id=\"1\" char=\"\"/>")
        expect(empty.char) == ""
        let omitted = try mapBullet("<hh:bullet id=\"1\"/>")
        expect(omitted.char) == ""
    }

    /// 표 42의 필드가 WCHAR 하나라 비BMP 문자는 담기지 않는다 — 첫 unit만 떼면
    /// 반쪽 서러게이트가 U+FFFD로 복구돼 문서에 없던 대체 글리프를 그리므로,
    /// U+0000과 같이 빈 문자열로 접는다.
    func testNonBmpBulletCharFoldsToEmptyInsteadOfReplacementCharacter() throws {
        let emoji = try mapBullet("<hh:bullet id=\"1\" char=\"😀\" checkedChar=\"😀\"/>")
        expect(emoji.char) == ""
        expect(emoji.checkChar) == ""
        // 조판은 `char.isEmpty` 게이트로 건너뛴다 — U+FFFD였다면 통과해 대체
        // 글리프를 그렸을 것이다.
        expect(emoji.char.unicodeScalars.contains("\u{FFFD}")) == false

        // 비BMP 뒤에 BMP 문자가 와도 첫 문자가 기준이라 접힌다.
        let leading = try mapBullet("<hh:bullet id=\"1\" char=\"😀x\"/>")
        expect(leading.char) == ""
    }

    /// 레코드 payload는 합성하지 않는다 — 바이너리는 `consumedData`(뷰어 게이트
    /// 부류)라 `.viewer`에서 비우므로, HWPX만 양 모드에서 들고 있으면 패리티가
    /// 깨진다. `HwpBullet`의 `charRawPayload`와 같은 DocInfo 가족 관행이다.
    func testNumberingFormatDoesNotSynthesizeRawPayload() throws {
        let numbering = try mapNumbering(
            paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", text: "^1.")
        )
        expect(numbering.formatArray[0].format) == "^1."
        expect(numbering.formatArray[0].formatRawPayload).to(beEmpty())
        expect(numbering.formatArray.allSatisfy(\.formatRawPayload.isEmpty)) == true
        expect(numbering.extendedFormatArray?.allSatisfy(\.formatRawPayload.isEmpty)) == true

        let bullet = try mapBullet("<hh:bullet id=\"1\" char=\"-\"/>")
        expect(bullet.charRawPayload).to(beEmpty())
        expect(bullet.checkCharRawPayload).to(beEmpty())
    }

    /// `hh:bullet@checkedChar`는 체크 글머리표 문자다 — 한컴 모델이 값이 있을
    /// 때만 쓰므로(`BulletType.cpp`) 생략은 "없음"이다.
    func testBulletCheckedCharIsCarriedIntoCheckChar() throws {
        let checked = try mapBullet("<hh:bullet id=\"1\" char=\"□\" checkedChar=\"■\"/>")
        expect(checked.char) == "□"
        expect(checked.checkChar) == "■"

        let omitted = try mapBullet("<hh:bullet id=\"1\" char=\"□\"/>")
        expect(omitted.checkChar) == ""
    }

    func testBulletKeepsFirstParaHeadAndDemotesTheRest() throws {
        let docInfo = try mapFamilies("""
        <hh:bullets itemCnt="1"><hh:bullet id="1" char="-">\
        <hh:paraHead level="0" useInstWidth="1" textOffset="0" charPrIDRef="-1"/>\
        <hh:paraHead level="0" useInstWidth="0" textOffset="0" charPrIDRef="-1"/>\
        </hh:bullet></hh:bullets>
        """)
        let bullet = try XCTUnwrap(docInfo.idMappings.bulletArray.first)
        expect(bullet.info[0] & 0b100) == 0b100
        expect(Self.demotedNames(docInfo)) == ["paraHead"]
    }

    // MARK: - 빈 정의와 미소비 자식

    func testDefinitionWithoutParaHeadIsMappedInsteadOfDemoted() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1"/></hh:numberings>\
        <hh:bullets itemCnt="1"><hh:bullet id="1"/></hh:bullets>
        """)
        expect(docInfo.idMappings.numberingArray.count) == 1
        expect(docInfo.idMappings.bulletArray.count) == 1
        expect(docInfo.idMappings.numberingArray[0].formatArray.count) == 7
        expect(docInfo.idMappings.bulletArray[0].char) == ""
        expect(Self.demotedNames(docInfo)).to(beEmpty())
    }

    func testUnknownChildrenOfDefinitionsAndParaHeadsAreDemoted() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
        <hh:paraHead level="1" textOffset="0" charPrIDRef="-1">\
        <hh:futureLeaf/></hh:paraHead>\
        <hh:futureChild/></hh:numbering></hh:numberings>
        """)
        expect(Self.demotedNames(docInfo).sorted()) == ["futureChild", "futureLeaf"]
    }

    /// 이름이 같은 타 vocabulary 디코이는 정의로 오인하지 않는다.
    func testForeignNamespaceDefinitionIsDemotedNotMapped() throws {
        let docInfo = try mapFamilies("""
        <hh:numberings xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        itemCnt="1"><hp:numbering id="1"/></hh:numberings>
        """)
        expect(docInfo.idMappings.numberingArray).to(beEmpty())
        expect(Self.demotedNames(docInfo)) == ["numbering"]
    }

    // MARK: - 참조 공간 상한

    func testDefinitionsBeyondTheOneBasedReferenceSpaceAreRejected() {
        let numberings = (0 ..< 65536).map { "<hh:numbering id=\"\($0)\"/>" }.joined()
        expect {
            try self.mapFamilies(
                "<hh:numberings itemCnt=\"65536\">\(numberings)</hh:numberings>"
            )
        }.to(throwError())

        let bullets = (0 ..< 65536).map { "<hh:bullet id=\"\($0)\"/>" }.joined()
        expect {
            try self.mapFamilies("<hh:bullets itemCnt=\"65536\">\(bullets)</hh:bullets>")
        }.to(throwError())
    }

    /// 번호 형식 길이는 표 38의 WORD다 — 넘치면 길이만 접혀
    /// `formatLength == format.utf16.count` 불변식이 깨진 모델이 나가므로
    /// 절단하지 않고 거부한다 (절단은 서러게이트 쌍을 가른다).
    func testFormatTextBeyondTheWordLengthFieldIsRejected() throws {
        let atLimit = String(repeating: "^", count: Int(WORD.max))
        let overLimit = String(repeating: "^", count: Int(WORD.max) + 1)

        let accepted = try mapNumbering(
            paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", text: atLimit)
        )
        expect(accepted.formatArray[0].formatLength) == WORD.max
        expect(accepted.formatArray[0].format.utf16.count) == Int(WORD.max)

        expect {
            try self.mapNumbering(
                self.paraHead("textOffset=\"0\" charPrIDRef=\"-1\"", text: overLimit)
            )
        }.to(throwError())
    }

    /// 슬롯을 얻지 못한 `hh:paraHead`는 형식이 되지 않으므로 길이 가드의
    /// 대상이 아니다 — 중복 수준·범위 밖 수준은 문서를 거부하지 않고 진단으로
    /// 강등해야 한다 (`Sources/CoreHwp/Hwpx/AGENTS.md` 문단 머리 규약).
    func testOverlongTextOnRejectedParaHeadIsDemotedNotRejected() throws {
        let overLimit = String(repeating: "^", count: Int(WORD.max) + 1)
        for rejected in [
            "<hh:paraHead level=\"1\" textOffset=\"0\" charPrIDRef=\"-1\">\(overLimit)</hh:paraHead>",
            "<hh:paraHead level=\"0\" textOffset=\"0\" charPrIDRef=\"-1\">\(overLimit)</hh:paraHead>",
            "<hh:paraHead level=\"11\" textOffset=\"0\" charPrIDRef=\"-1\">\(overLimit)</hh:paraHead>",
        ] {
            let docInfo = try mapFamilies("""
            <hh:numberings itemCnt="1"><hh:numbering id="1" start="1">\
            <hh:paraHead level="1" textOffset="0" charPrIDRef="-1">^1.</hh:paraHead>\
            \(rejected)</hh:numbering></hh:numberings>
            """)
            let numbering = try XCTUnwrap(docInfo.idMappings.numberingArray.first)
            expect(numbering.formatArray[0].format) == "^1."
            expect(Self.demotedNames(docInfo)) == ["paraHead"]
        }
    }

    // MARK: - Helpers

    /// 속성 12바이트의 선두 `UINT32`.
    private static func property(_ format: HwpNumberingFormat) -> UInt32 {
        format.property.prefix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func demotedNames(_ docInfo: HwpDocInfo) -> [String] {
        docInfo.unknownRecords.compactMap { String(bytes: $0.payload, encoding: .utf8) }
    }
}
