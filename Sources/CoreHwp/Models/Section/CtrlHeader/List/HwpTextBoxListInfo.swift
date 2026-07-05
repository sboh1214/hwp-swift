import Foundation

/**
 글상자 텍스트 속성 (표 90)

 글상자 리스트 헤더의 공통 필드 뒤에 이어지는 12 byte 속성이다.
 여백 순서는 왼쪽/오른쪽/위쪽/아래쪽 (HWPUNIT16), 마지막은 텍스트 최대 폭 (HWPUNIT).
 */
public struct HwpTextBoxListInfo: HwpPrimitive {
    /** 글상자 텍스트 왼쪽 여백 (HWPUNIT16) */
    public var leftMargin: HWPUNIT16
    /** 글상자 텍스트 오른쪽 여백 (HWPUNIT16) */
    public var rightMargin: HWPUNIT16
    /** 글상자 텍스트 위쪽 여백 (HWPUNIT16) */
    public var topMargin: HWPUNIT16
    /** 글상자 텍스트 아래쪽 여백 (HWPUNIT16) */
    public var bottomMargin: HWPUNIT16
    /** 텍스트 문자열의 최대 폭 (HWPUNIT, 일반적으로 개체의 폭과 같다) */
    public var maxTextWidth: HWPUNIT

    public init(
        leftMargin: HWPUNIT16 = 0,
        rightMargin: HWPUNIT16 = 0,
        topMargin: HWPUNIT16 = 0,
        bottomMargin: HWPUNIT16 = 0,
        maxTextWidth: HWPUNIT = 0
    ) {
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.maxTextWidth = maxTextWidth
    }

    static let byteCount = 12

    /// 리스트 헤더 trailing payload에서 글상자 텍스트 속성을 best-effort로 디코딩한다.
    static func decode(from data: Data) -> HwpTextBoxListInfo? {
        guard data.count >= byteCount else { return nil }
        do {
            return HwpTextBoxListInfo(
                leftMargin: try data.readLittleEndianInt16(at: 0),
                rightMargin: try data.readLittleEndianInt16(at: 2),
                topMargin: try data.readLittleEndianInt16(at: 4),
                bottomMargin: try data.readLittleEndianInt16(at: 6),
                maxTextWidth: try data.readLittleEndianUInt32(at: 8)
            )
        } catch {
            return nil
        }
    }
}
