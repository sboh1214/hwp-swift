import Foundation

/**
 문단 머리 정보 (표 39) — 문단 번호(`HwpNumberingFormat.property`)와
 글머리표(`HwpBullet.info` + `headCharShapeId`)가 공유하는 12바이트의 해석.

 스펙은 항목 4개(속성 `UINT32` · 너비 보정값 `HWPUNIT16` · 본문과의 거리
 `HWPUNIT16` · 글자 모양 아이디 참조 `INT32`)를 적고 "전체 길이 8"로 합계를
 틀리게 적었다 — 실물은 12바이트다 (`HwpBullet` 파싱 주석의 noori `-` 실측).
 `HwpNumberingFormat.property`는 12바이트를 통째로 들고, `HwpBullet`은 같은
 12바이트를 `info`(앞 8바이트)와 `headCharShapeId`로 쪼개 든다. 두 모델의
 `paraHeadInfo` 접근자가 이 타입으로 모이고, `bytes`·`infoBytes`가 그 거울상
 인코더다 (HWPX 매퍼가 같은 배치로 합성한다).

 속성(표 40)은 bit 0-4(정렬·번호 너비·자동 내어 쓰기·거리 종류)만 적고
 **번호 모양은 적지 않는데, 실측이 bit 5-8**이다 — 빈 문서 기본
 `numberingArray`(`HwpIdMappings`)의 수준별 선두 UINT32가 `^1.` 0x0C ·
 `^2.` 0x10C · `^7` 0x2C이고 noori HWPX의 같은 수준이 `DIGIT`(표 41 값 0)·
 `HANGUL_SYLLABLE`(8)·`CIRCLED_DIGIT`(1)이다 (#133). 헌법주석
 (`legacy-common-control-property`)의 개요 번호 정의 1수준 0x4C는 로마 숫자
 대문자(2)다 (#152). 표 41 코드는 표 134 번호 모양의 0-14 구간과 항목이
 같아 `HwpNumberFormat.string(for:shape:)`(HwpKitCore)이 그대로 소비한다.

 정렬(bit 0-1)과 본문과의 거리 종류(bit 4)의 **비기본값은 실문서 대조 전**이다
 — 저장소 픽스처는 전부 왼쪽 정렬·비율 거리라 값 배치는 OWPML 스키마 나열
 순서(한컴 참조 모델 `g_ParaHeadAlignList`·`g_TextOffsetTypeList`)를 따른다
 (`Sources/CoreHwp/Hwpx/AGENTS.md` "실파일 검증 대기 항목").
 */
public struct HwpParaHeadInfo: HwpPrimitive {
    /// 표 39 실물 길이 — 스펙의 "전체 길이 8"은 오기다.
    public static let byteCount = 12

    /// 속성 (표 40) raw `UINT32`.
    public var property: UInt32
    /// 너비 보정값 `HWPUNIT16`.
    public var widthAdjust: HWPUNIT16
    /// 본문과의 거리 `HWPUNIT16` — 단위는 `textOffsetType`이 정한다
    /// (비율이면 글자 크기에 대한 %, 실측 기본값 50).
    public var textOffset: HWPUNIT16
    /// 글자 모양 아이디 참조 `INT32` — -1이면 바탕글 모양이다.
    public var charShapeId: Int32

    public init(
        property: UInt32 = 0,
        widthAdjust: HWPUNIT16 = 0,
        textOffset: HWPUNIT16 = 0,
        charShapeId: Int32 = -1
    ) {
        self.property = property
        self.widthAdjust = widthAdjust
        self.textOffset = textOffset
        self.charShapeId = charShapeId
    }

    /// 표 40 필드로 속성을 합성하는 init.
    ///
    /// `numberFormat`은 bit 5-8 네 비트에 담기므로 표 41의 0-14만 보존되고
    /// 그 밖의 코드(`SYMBOL` 0x80 등)는 접힌다 — HWPX 매퍼의 규약과 같다.
    public init(
        alignment: HwpParaHeadAlignment,
        useInstWidth: Bool,
        autoIndent: Bool,
        textOffsetType: HwpParaHeadTextOffsetType,
        numberFormat: Int,
        widthAdjust: HWPUNIT16 = 0,
        textOffset: HWPUNIT16,
        charShapeId: Int32 = -1
    ) {
        var property = alignment.rawValue & 0b11
        if useInstWidth {
            property |= 1 << 2
        }
        if autoIndent {
            property |= 1 << 3
        }
        property |= (textOffsetType.rawValue & 0b1) << 4
        property |= (UInt32(clamping: max(0, numberFormat)) & 0b1111) << 5
        self.init(
            property: property,
            widthAdjust: widthAdjust,
            textOffset: textOffset,
            charShapeId: charShapeId
        )
    }

    /// 12바이트(`HwpNumberingFormat.property`) 디코더 — `bytes`의 거울상.
    ///
    /// 파서는 언제나 12바이트를 읽으므로 짧은 배열은 합성 값에서만 생긴다 —
    /// 12바이트 미만이면 nil이고, 넘치는 꼬리는 무시한다 (0으로 메우면
    /// 글자 모양 ID 0이 실재하는 참조가 되어 바탕글(-1)과 구별되지 않는다).
    public init?(bytes: [BYTE]) {
        guard bytes.count >= Self.byteCount else {
            return nil
        }
        self.init(
            property: Self.uint32(bytes, at: 0),
            widthAdjust: HWPUNIT16(bitPattern: Self.uint16(bytes, at: 4)),
            textOffset: HWPUNIT16(bitPattern: Self.uint16(bytes, at: 6)),
            charShapeId: Int32(bitPattern: Self.uint32(bytes, at: 8))
        )
    }

    /// 앞 8바이트(`HwpBullet.info`)와 글자 모양 ID(`headCharShapeId`)에서 만든다.
    /// 8바이트 미만이면 nil.
    public init?(infoBytes: [BYTE], charShapeId: Int32) {
        guard infoBytes.count >= 8 else {
            return nil
        }
        self.init(
            property: Self.uint32(infoBytes, at: 0),
            widthAdjust: HWPUNIT16(bitPattern: Self.uint16(infoBytes, at: 4)),
            textOffset: HWPUNIT16(bitPattern: Self.uint16(infoBytes, at: 6)),
            charShapeId: charShapeId
        )
    }

    // MARK: - 표 40 속성

    /// 문단의 정렬 종류 raw (bit 0-1) — 0 왼쪽, 1 가운데, 2 오른쪽.
    public var alignmentRawValue: UInt32 {
        property & 0b11
    }

    /// 문단의 정렬 종류 — 스펙에 정의가 없는 raw 3이면 nil.
    public var alignment: HwpParaHeadAlignment? {
        HwpParaHeadAlignment(rawValue: alignmentRawValue)
    }

    /// 번호 너비를 실제 인스턴스 문자열의 너비에 따를지 여부 (bit 2).
    public var useInstWidth: Bool {
        property & (1 << 2) != 0
    }

    /// 자동 내어 쓰기 여부 (bit 3).
    public var autoIndent: Bool {
        property & (1 << 3) != 0
    }

    /// 수준별 본문과의 거리 종류 (bit 4) — `textOffset`의 단위.
    public var textOffsetType: HwpParaHeadTextOffsetType {
        property & (1 << 4) != 0 ? .hwpUnit : .percent
    }

    /// 번호 모양 (표 41 코드, bit 5-8) — 표 134의 0-14 구간과 같은 값이라
    /// `HwpNumberFormat.string(for:shape:)`에 그대로 넘긴다.
    public var numberFormat: Int {
        Int((property >> 5) & 0b1111)
    }

    // MARK: - 인코더 (거울상)

    /// `HwpBullet.info`가 드는 앞 8바이트 — 속성 · 너비 보정값 · 본문과의 거리.
    public var infoBytes: [BYTE] {
        var bytes: [BYTE] = []
        bytes.reserveCapacity(8)
        Self.append(property, to: &bytes)
        Self.append(UInt16(bitPattern: widthAdjust), to: &bytes)
        Self.append(UInt16(bitPattern: textOffset), to: &bytes)
        return bytes
    }

    /// `HwpNumberingFormat.property`가 드는 12바이트 전체.
    public var bytes: [BYTE] {
        var bytes = infoBytes
        Self.append(UInt32(bitPattern: charShapeId), to: &bytes)
        return bytes
    }

    // MARK: - LE 산술

    private static func uint16(_ bytes: [BYTE], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [BYTE], at offset: Int) -> UInt32 {
        UInt32(uint16(bytes, at: offset)) | UInt32(uint16(bytes, at: offset + 2)) << 16
    }

    private static func append(_ value: UInt16, to bytes: inout [BYTE]) {
        bytes.append(BYTE(value & 0xFF))
        bytes.append(BYTE(value >> 8))
    }

    private static func append(_ value: UInt32, to bytes: inout [BYTE]) {
        append(UInt16(value & 0xFFFF), to: &bytes)
        append(UInt16(value >> 16), to: &bytes)
    }
}

/// 표 40 bit 0-1 문단의 정렬 종류.
///
/// 값 배치는 OWPML `align` 열거(`LEFT`·`CENTER`·`RIGHT`)의 나열 순서다 —
/// 왼쪽 정렬만 실문서(전 픽스처)로 확인됐고 가운데·오른쪽은 실파일 검증
/// 대기 항목이다. raw 3은 정의가 없어 케이스로 두지 않는다.
public enum HwpParaHeadAlignment: UInt32, HwpPrimitive {
    /// 왼쪽
    case left = 0
    /// 가운데
    case center = 1
    /// 오른쪽
    case right = 2
}

/// 표 40 bit 4 수준별 본문과의 거리 종류 — `HwpParaHeadInfo.textOffset`의 단위.
///
/// 비율만 실문서(전 픽스처의 50%)로 확인됐고 HWPUNIT 값은 OWPML
/// `textOffsetType` 열거(`PERCENT`·`HWPUNIT`)의 나열 순서를 따른 실파일 검증
/// 대기 항목이다.
public enum HwpParaHeadTextOffsetType: UInt32, HwpPrimitive {
    /// 글자 크기에 대한 상대 비율(%)
    case percent = 0
    /// 값 (HWPUNIT)
    case hwpUnit = 1
}

public extension HwpNumberingFormat {
    /// 표 39 문단 머리 정보 — `property` 12바이트의 해석. 12바이트 미만이면 nil.
    var paraHeadInfo: HwpParaHeadInfo? {
        HwpParaHeadInfo(bytes: property)
    }
}

public extension HwpBullet {
    /// 표 39 문단 머리 정보 — `info` 8바이트와 `headCharShapeId`의 해석.
    /// `info`가 8바이트 미만이면 nil.
    var paraHeadInfo: HwpParaHeadInfo? {
        HwpParaHeadInfo(infoBytes: info, charShapeId: headCharShapeId)
    }
}
