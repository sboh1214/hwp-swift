import Foundation

/// `hp:footNotePr`·`hp:endNotePr`(구역의 각주·미주 모양)를
/// `HwpSectionDef.footNoteShape`·`endNoteShape`로 옮긴다 (표 133·134, #168).
///
/// **payload를 합성해 바이너리 로더에 태운다.** typed 필드를 직접 세우면 안 되는
/// 이유가 둘이다.
///
/// 1. 조판이 보는 구분선 값은 typed 필드가 아니라 `HwpFootnoteShape.dividerInfo`,
///    즉 **`rawPayload`의 재디코드**다. `Data()`로 두면 `dividerInfo`가 nil이라
///    길이·굵기·색·주석 간격이 전부 튜닝 폴백으로 떨어진다 — HWP 쌍이 0.34pt
///    구분선을 그리는 자리에서 HWPX만 1.0pt를 그린다.
/// 2. `HwpFootnoteShape.init(_:)`은 구분선 길이를 스펙 표 133 그대로
///    **HWPUNIT16(2바이트)** 로 읽지만 실저장본은 4바이트다. 그래서 실물에서는
///    typed 저장 필드 일곱(`dividerLength`·`dividerMarginTop`·`dividerMarginBottom`·
///    `marginComment`·`dividerType`·`dividerThickness`·`dividerColor`)이 통째로
///    오정렬돼 있고, `dividerInfo`만 4바이트 우선으로 다시 읽어 바로잡는다.
///    같은 payload를 같은 로더에 태워야 그 오정렬까지 HWP 쌍과 똑같아진다.
///
/// (`HwpSectionDef()`의 각주·미주 기본값 `dividerLength: -1, dividerMarginTop: -1` ·
/// `12280, 224`는 그 2바이트 오독의 화석이다 — 4바이트로 이어 붙이면 각각
/// -1과 14,692,344로, 실물 payload의 오프셋 12-15와 정확히 같다.)
///
/// ## 실측 (2026-09-07, 한컴오피스 한글 12.30.0 macOS)
///
/// `footnote-endnote` 변환 쌍의 `hp:footNotePr` 다섯 자식이 HWP 쌍 FOOTNOTE_SHAPE
/// 28바이트와 한 자리도 남기지 않고 맞는다.
///
/// ```xml
/// <hp:footNotePr>
///   <hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>
///   <hp:noteLine length="-1" type="SOLID" width="0.12 mm" color="#000000"/>
///   <hp:noteSpacing betweenNotes="283" belowLine="567" aboveLine="850"/>
///   <hp:numbering type="CONTINUOUS" newNum="1"/>
///   <hp:placement place="EACH_COLUMN" beneathText="0"/>
/// </hp:footNotePr>
/// ```
///
/// ↔ `00 00 00 00 | 00 00 | 00 00 | 29 00 | 01 00 | FF FF FF FF | 52 03 | 37 02 |
/// 1B 01 | 01 | 01 | 00 00 00 00` (미주는 길이만 `F8 2F E0 00` = 14,692,344이고
/// `betweenNotes="0"`).
///
/// 기본값이 아닌 두 번째 표본(미주 모양을 `㉠,㉡,㉢` + 앞 `[` · 뒤 `]` +
/// 시작 번호 3 + 구역의 끝 + 작게로 바꿔 저장)이 속성 비트를 확정했다 —
/// `type="CIRCLED_HANGUL_JAMO" prefixChar="[" suffixChar="]" supscript="1"` ·
/// `numbering type="ON_SECTION" newNum="3"` · `placement place="END_OF_SECTION"`
/// ↔ property **0x150B** · 시작 번호 3 · 앞 0x5B · 뒤 0x5D. 즉
/// bits 0-7 = 11(표 134 번호 모양) · bit 8 = 미주 배치 · bit 10 = 번호 매김 ·
/// bit 12 = 위 첨자다.
enum HwpxFootnoteShapeMapper {
    /// 각주·미주 모양 하나. 요소가 없으면 nil을 돌려 호출부가 빈 문서 기본값을
    /// 그대로 두게 한다 — 값을 지어내면 없던 구분선 설정이 생긴다.
    static func map(
        _ node: HwpxXMLNode?,
        options: HwpLoadOptions
    ) throws -> HwpFootnoteShape? {
        guard let node else {
            return nil
        }
        let format = node.paragraphFirstChild(named: "autoNumFormat")
        let line = node.paragraphFirstChild(named: "noteLine")
        let spacing = node.paragraphFirstChild(named: "noteSpacing")
        let numbering = node.paragraphFirstChild(named: "numbering")

        var payload = Data(capacity: 28)
        payload.appendHwpxLittleEndian(property(of: node, format: format, numbering: numbering))
        payload.appendHwpxLittleEndian(
            HwpxFootnoteMapper.literalWchar(format?.attribute("userChar"))
        )
        payload.appendHwpxLittleEndian(
            HwpxFootnoteMapper.literalWchar(format?.attribute("prefixChar"))
        )
        payload.appendHwpxLittleEndian(
            HwpxFootnoteMapper.literalWchar(format?.attribute("suffixChar"))
        )
        payload.appendHwpxLittleEndian(
            numbering?.uint16Attribute("newNum", default: newNumDefault) ?? newNumDefault
        )
        // 구분선 길이는 **4바이트**다 (표 133의 2바이트는 오기). 2바이트로 쓰면
        // `HwpFootnoteDividerInfo.decode`의 wide 우선 경로가 무효가 돼 narrow로
        // 폴백하고 여백·종류·굵기·색이 통째로 어긋난다.
        payload.appendHwpxLittleEndian(UInt32(bitPattern: line?.int32Attribute(
            "length", default: lengthDefault
        ) ?? lengthDefault))
        payload.appendHwpxLittleEndian(hwpUnit16(spacing, "aboveLine", default: aboveLineDefault))
        payload.appendHwpxLittleEndian(hwpUnit16(spacing, "belowLine", default: belowLineDefault))
        payload.appendHwpxLittleEndian(
            hwpUnit16(spacing, "betweenNotes", default: betweenNotesDefault)
        )
        payload += dividerLineBytes(line)

        return try HwpFootnoteShape.load(payload, options: options)
    }

    /// 생략 속성·생략 요소의 기본값은 **한컴 참조 모델의 생성자**에서 온다 —
    /// `Util.cpp`의 `GetAttribute`가 속성 부재(그리고 열거 이름이 표에 없을 때)에
    /// 값을 건드리지 않고 false만 돌려주므로, 생성자가 세운 값이 그대로 남는다
    /// (`hh:paraHead`의 `useInstWidth`·`autoIndent`와 같은 규약).
    /// `CNoteSpacing()`은 `m_uBetweenNotes(850), m_uBelowLine(567), m_uAboveLine(567)`,
    /// `CNoteLine()`은 `m_nLength(0), m_uType(LT2_SOLID), m_uWidth(LWT_0_12),
    /// m_cColor(0x000000)`, `CFNNumbering()`/`CENNumbering()`은 `m_uNewNum(1)`이다.
    ///
    /// 0으로 접으면 `HwpFootnoteLayout.dividerMetrics`가 그 값을 그대로 써서
    /// **구분선 위·아래 여백과 주석 사이 간격이 0이 된다**(값이 있으면 폴백을 타지
    /// 않는다). 종류·굵기는 그렇지 않다 — `DividerMetrics`에 종류 필드가 없고
    /// 굵기도 `max(0.5, …)`에 흡수돼 렌더가 같으므로, 그 둘을 참조값으로 맞추는
    /// 실익은 HWP 쌍과의 payload 동등성과 `dividerInfo`의 wide 유효성 게이트다.
    ///
    /// **명시된 0은 보존한다** — 기본값은 속성이 아예 없을 때(그리고 형식이 틀렸을
    /// 때)만 쓴다. 참조 생성자의 값이 한글이 **저장하는** 값(각주 aboveLine 850 ·
    /// belowLine 567 · betweenNotes 283)과 다른 것은 그대로 둔다: 생략된 문서를
    /// 한글이 읽을 때 쓰는 값이 생성자 쪽이고, 우리가 맞춰야 하는 것도 그쪽이다.
    /// (payload가 아예 없어 `dividerInfo`가 nil인 경로의 폴백은 `HwpRenderTuning`이
    /// 따로 갖고 있고 그쪽은 저장값 850/567/283에 맞춰져 있다 — 다른 상황이다.)
    static let aboveLineDefault = 567
    static let belowLineDefault = 567
    static let betweenNotesDefault = 850
    static let lengthDefault: Int32 = 0
    static let newNumDefault: UInt16 = 1
    static let lineTypeDefault = 1 // LT2_SOLID
    static let lineWidthDefault: UInt8 = 1 // LWT_0_12 = 0.12 mm

    /// 표 134 속성 — bits 0-7 번호 모양 · bits 8-9 배치 · bits 10-11 번호 매김 ·
    /// bit 12 위 첨자 · bit 13 텍스트에 이어 바로 출력.
    ///
    /// bit 12까지는 실측(미주 모양 대화상자 표본 0x150B)이고, bit 13은 표 134가
    /// 위 첨자 **바로 다음 줄**에 적은 항목이다 — 실물은 `beneathText="0"`뿐이라
    /// 자리는 미실측이다. 소비자가 없는데도 싣는 이유는 컨트롤 헤더의 `flag`·
    /// `instId`와 같다: 실물이 담은 값을 합성에서 잃지 않아야 왕복이 성립한다.
    private static func property(
        of node: HwpxXMLNode,
        format: HwpxXMLNode?,
        numbering: HwpxXMLNode?
    ) -> UInt32 {
        var property = UInt32(HwpxNumberFormatMapper.code(for: format?.attribute("type")) & 0xFF)
        let placement = node.paragraphFirstChild(named: "placement")
        property |= UInt32(placements[placement?.attribute("place") ?? ""] ?? 0) << 8
        property |= UInt32(numberingModes[numbering?.attribute("type") ?? "CONTINUOUS"] ?? 0) << 10
        if format?.boolAttribute("supscript") == true {
            property |= 1 << 12
        }
        if placement?.boolAttribute("beneathText") == true {
            property |= 1 << 13
        }
        return property
    }

    /// 종류·굵기·색 6바이트. 종류 > 17이나 굵기 > 15는 `dividerInfo`의 wide
    /// 유효성 게이트를 깨뜨려 narrow 폴백을 부르므로 두 변환기의 상한을 믿는다
    /// (`lineShapeIndex`는 OWPML `LINETYPE2` 이름표라 0-17, `thicknessIndex`는
    /// `LINEWIDTHTYPE`과 같은 표 26 index).
    ///
    /// 생략·읽을 수 없는 값은 참조 모델 생성자 값(SOLID·0.12 mm)으로 접어 한컴
    /// `GetAttribute`와 같은 동작을 만든다 — 두 변환기 모두 `default:`를 받으므로
    /// 호출부가 그 값을 넘긴다. 기본 `default:` 0에 맡기면 `width="0.12mm"`(공백
    /// 없음) 같은 값이 조용히 0.1 mm가 된다.
    private static func dividerLineBytes(_ line: HwpxXMLNode?) -> Data {
        var bytes = Data(capacity: 6)
        bytes.append(UInt8(clamping: HwpxCharShapeMapper.lineShapeIndex(
            line?.attribute("type"), default: lineTypeDefault
        )))
        bytes.append(HwpxParaShapeMapper.thicknessIndex(
            of: line?.attribute("width"), default: lineWidthDefault
        ))
        // `color="none"`은 한컴 `GetAttribute`가 **흰색**(0xFFFFFFFF)으로 읽는다 —
        // `colorAttribute`는 `#` 접두가 없으면 nil이라 그대로 두면 흰 구분선이
        // 검정으로 뒤집힌다. 속성 자체의 생략은 생성자 값 `m_cColor(0x000000)`이다.
        let color = line?.colorAttribute("color")
            ?? (line?.attribute("color")?.lowercased() == "none" ? HwpColor(255, 255, 255) : nil)
        bytes += HwpxParaShapeMapper.colorrefBytes(color ?? HwpColor())
        return bytes
    }

    /// HWPUNIT 여백을 표 133의 HWPUNIT16 자리에 싣는다. 속성이 없으면 참조 모델
    /// 생성자 값을 쓰고 명시된 0은 그대로 보존한다.
    private static func hwpUnit16(
        _ node: HwpxXMLNode?, _ name: String, default defaultValue: Int
    ) -> UInt16 {
        UInt16(bitPattern: Int16(clamping: node?.intAttribute(
            name, default: defaultValue
        ) ?? defaultValue))
    }

    /// `hp:placement@place` → 표 134 bits 8-9. 이름과 값은 한컴 공개 OWPML 모델의
    /// 직렬화 표(`enumdef.h`의 `g_FNPlacementList`·`g_ENPlacementList`)다 — 각주는
    /// 다단 배열(`EACH_COLUMN`·`MERGED_COLUMN`·**`RIGHT_MOST_COLUMN`**), 미주는
    /// 배치(`END_OF_DOCUMENT`·`END_OF_SECTION`)이고 두 열거가 같은 비트를 쓴다.
    /// `EACH_COLUMN`↔0·`END_OF_SECTION`↔1은 실측이기도 하다. 미지 이름은 참조
    /// 모델 생성자 값(`FNPT_EACH_COLUMN`·`ENPT_END_OF_DOCUMENT` = 0)으로 접는다.
    /// 조판은 각주 다단 배열을 아직 쓰지 않아 그쪽 렌더 격차는 없다.
    static let placements: [String: Int] = [
        "EACH_COLUMN": 0, "MERGED_COLUMN": 1, "RIGHT_MOST_COLUMN": 2,
        "END_OF_DOCUMENT": 0, "END_OF_SECTION": 1,
    ]

    /// `hp:numbering@type` → 표 134 bits 10-11. `CONTINUOUS`↔0·`ON_SECTION`↔1은
    /// 실측이고 `ON_PAGE`↔2(쪽마다 새로, 각주 전용)는 한컴 모델의
    /// `g_FNNumberingTypeList`가 정본이다 — 미주 모양 대화상자에 그 항목이 없어
    /// 실물은 만들지 못했다. 미지 이름은 생성자 값 `FNNT_CONTINUOUS`(0)다.
    static let numberingModes: [String: Int] = [
        "CONTINUOUS": 0, "ON_SECTION": 1, "ON_PAGE": 2,
    ]
}
