import Foundation

/**
 각주/미주 모양의 구분선 정보 (표 133 뒷부분)를 재해석한 값

 구분선 길이 필드는 4 byte(UINT32)로 고정이다 — 스펙 표 133은 2 byte로 적었으나
 실제 저장본은 4 byte다 (hwplib·hwp-rs 실측; hwp-rs 주석 "공식 문서와 다르게 실제
 4바이트"). 따라서 4 byte(wide) 해석을 확정 우선하고, wide가 무효인 malformed
 레코드만 2 byte(narrow)로 폴백한다.
 */
public struct HwpFootnoteDividerInfo: HwpPrimitive {
    /** 구분선 길이 (HWPUNIT). nil이면 자동 (관례상 단 폭의 1/3). */
    public var length: Int32?
    /** 구분선 위 여백 (HWPUNIT16) */
    public var marginTop: Int16
    /** 구분선 아래 여백 (HWPUNIT16) */
    public var marginBottom: Int16
    /** 주석 사이 여백 (HWPUNIT16) */
    public var spacingBetweenNotes: Int16
    /** 구분선 종류 (표 25 선 종류 index) */
    public var type: UInt8
    /** 구분선 굵기 (표 26 굵기 index) */
    public var thickness: UInt8
    /** 구분선 색상 */
    public var color: HwpColor

    public init(
        length: Int32?,
        marginTop: Int16,
        marginBottom: Int16,
        spacingBetweenNotes: Int16,
        type: UInt8,
        thickness: UInt8,
        color: HwpColor
    ) {
        self.length = length
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.spacingBetweenNotes = spacingBetweenNotes
        self.type = type
        self.thickness = thickness
        self.color = color
    }

    /// FOOTNOTE_SHAPE record payload 전체에서 구분선 정보를 디코딩한다.
    /// 길이 필드가 4 byte 고정이므로 wide를 확정 우선하고, wide가 무효인 malformed
    /// 레코드(짧거나 종류/굵기 index 범위 밖)만 narrow로 폴백한다 — 임의 trailing이
    /// 허용돼 레코드 크기로는 폭을 구분할 수 없다 (R45 #1).
    static func decode(from payload: Data) -> HwpFootnoteDividerInfo? {
        decode(from: payload, lengthByteCount: 4) ?? decode(from: payload, lengthByteCount: 2)
    }

    private static func decode(
        from payload: Data,
        lengthByteCount: Int
    ) -> HwpFootnoteDividerInfo? {
        let lengthOffset = 12
        let cursor = lengthOffset + lengthByteCount
        guard payload.count >= cursor + 12 else { return nil }
        do {
            let rawLength: Int32 = if lengthByteCount == 4 {
                try payload.readLittleEndianInt32(at: lengthOffset)
            } else {
                Int32(try payload.readLittleEndianInt16(at: lengthOffset))
            }
            let type = try payload.readUInt8(at: cursor + 6)
            let thickness = try payload.readUInt8(at: cursor + 7)
            // 유효 border type은 0~17 (표 25, single3DReverse=17까지). thickness는
            // 표 26 0~15. 유효 style 17을 거부하면 wide 디코드가 무효화돼 narrow로
            // 잘못 폴백, 오프셋이 어긋나 metrics·color가 오염된다 (R53 #3).
            guard type <= HwpBorderType.single3DReverse.rawValue, thickness <= 15 else {
                return nil
            }
            return HwpFootnoteDividerInfo(
                length: rawLength > 0 ? rawLength : nil,
                marginTop: try payload.readLittleEndianInt16(at: cursor),
                marginBottom: try payload.readLittleEndianInt16(at: cursor + 2),
                spacingBetweenNotes: try payload.readLittleEndianInt16(at: cursor + 4),
                type: type,
                thickness: thickness,
                color: HwpColor(try payload.readLittleEndianUInt32(at: cursor + 8))
            )
        } catch {
            return nil
        }
    }
}

public extension HwpFootnoteShape {
    /** 구분선 길이 필드 폭 차이를 흡수한 구분선 정보. 디코딩 실패 시 nil. */
    var dividerInfo: HwpFootnoteDividerInfo? {
        HwpFootnoteDividerInfo.decode(from: rawPayload)
    }

    /** 번호 매김 방식 (표 134 bits 10-11): 0 앞 구역에 이어서, 1 구역마다 새로, 2 쪽마다 새로 */
    var numberingModeRawValue: Int {
        Int((property >> 10) & 0b11)
    }

    /**
     미주 배치 (표 134 bits 8-9, 미주 모양 전용):
     0 문서의 마지막, 1 구역의 마지막.
     (각주 모양에서는 같은 bit가 다단 배열 방식을 뜻한다.)
     */
    var endnotePlacementRawValue: Int {
        Int((property >> 8) & 0b11)
    }

    /** 미주를 구역의 마지막에 배치하는지 여부 (표 134 bits 8-9 == 1) */
    var placesEndnoteAtSectionEnd: Bool {
        endnotePlacementRawValue == 1
    }
}
