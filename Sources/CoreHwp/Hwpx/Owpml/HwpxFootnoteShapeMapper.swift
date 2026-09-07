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
        payload.appendHwpxLittleEndian(numbering?.uint16Attribute("newNum", default: 1) ?? 1)
        // 구분선 길이는 **4바이트**다 (표 133의 2바이트는 오기). 2바이트로 쓰면
        // `HwpFootnoteDividerInfo.decode`의 wide 우선 경로가 무효가 돼 narrow로
        // 폴백하고 여백·종류·굵기·색이 통째로 어긋난다.
        payload.appendHwpxLittleEndian(
            UInt32(bitPattern: line?.int32Attribute("length", default: -1) ?? -1)
        )
        payload.appendHwpxLittleEndian(hwpUnit16(spacing?.intAttribute("aboveLine")))
        payload.appendHwpxLittleEndian(hwpUnit16(spacing?.intAttribute("belowLine")))
        payload.appendHwpxLittleEndian(hwpUnit16(spacing?.intAttribute("betweenNotes")))
        payload += dividerLineBytes(line)

        return try HwpFootnoteShape.load(payload, options: options)
    }

    /// 표 134 속성 — 소비자가 있는 네 자리만 세운다.
    /// bits 0-7 번호 모양 · bits 8-9 배치 · bits 10-11 번호 매김 · bit 12 위 첨자.
    private static func property(
        of node: HwpxXMLNode,
        format: HwpxXMLNode?,
        numbering: HwpxXMLNode?
    ) -> UInt32 {
        var property = UInt32(HwpxNumberFormatMapper.code(for: format?.attribute("type")) & 0xFF)
        let place = node.paragraphFirstChild(named: "placement")?.attribute("place")
        property |= UInt32(placements[place ?? ""] ?? 0) << 8
        property |= UInt32(numberingModes[numbering?.attribute("type") ?? "CONTINUOUS"] ?? 0) << 10
        if format?.boolAttribute("supscript") == true {
            property |= 1 << 12
        }
        return property
    }

    /// 종류·굵기·색 6바이트. 종류 > 17이나 굵기 > 15는 `dividerInfo`의 wide
    /// 유효성 게이트를 깨뜨려 narrow 폴백을 부르므로 두 변환기의 상한을 믿는다
    /// (`lineShapeIndex`는 표 27 이름표라 0-17, `thicknessIndex`는 표 26 index).
    private static func dividerLineBytes(_ line: HwpxXMLNode?) -> Data {
        var bytes = Data(capacity: 6)
        bytes.append(UInt8(clamping: HwpxCharShapeMapper.lineShapeIndex(
            line?.attribute("type"), default: 0
        )))
        bytes.append(HwpxParaShapeMapper.thicknessIndex(of: line?.attribute("width")))
        bytes += HwpxParaShapeMapper.colorrefBytes(line?.colorAttribute("color") ?? HwpColor())
        return bytes
    }

    /// HWPUNIT 여백을 표 133의 HWPUNIT16 자리에 싣는다.
    private static func hwpUnit16(_ value: Int?) -> UInt16 {
        UInt16(bitPattern: Int16(clamping: value ?? 0))
    }

    /// `hp:placement@place` → 표 134 bits 8-9.
    ///
    /// 미주는 배치(`END_OF_SECTION`↔1 실측), 각주는 같은 비트가 다단 배열이다.
    /// 각주 쪽 실측은 `EACH_COLUMN`↔0 하나이고 나머지 둘은 스키마 나열 순서를
    /// 따랐다 — 조판이 각주 다단 배열을 아직 쓰지 않아 렌더 격차는 없다.
    /// 미지 이름은 0(문서의 끝·각 단마다)으로 접는다.
    static let placements: [String: Int] = [
        "EACH_COLUMN": 0, "MERGED_COLUMN": 1, "RIGHT_COLUMN": 2,
        "END_OF_DOCUMENT": 0, "END_OF_SECTION": 1,
    ]

    /// `hp:numbering@type` → 표 134 bits 10-11. `CONTINUOUS`↔0·`ON_SECTION`↔1은
    /// 실측이고 `ON_PAGE`↔2(쪽마다 새로)는 표 134 나열 순서다 — 미주 모양
    /// 대화상자에 그 항목이 없어 실물을 만들지 못했다.
    static let numberingModes: [String: Int] = [
        "CONTINUOUS": 0, "ON_SECTION": 1, "ON_PAGE": 2,
    ]
}
