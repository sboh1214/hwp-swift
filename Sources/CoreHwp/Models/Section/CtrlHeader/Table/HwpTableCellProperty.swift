import Foundation

/**
 표 셀 속성 (표 80)

 LIST_HEADER 공통 필드 뒤에 이어지는 셀 전용 속성이다.
 셀 주소는 0부터 시작하며, 폭/높이는 HWPUNIT, 여백은 HWPUNIT16 (왼쪽/오른쪽/위쪽/아래쪽) 순서이다.
 */
public struct HwpTableCellProperty: HwpPrimitive {
    /** 셀 주소 열 (맨 왼쪽 = 0) */
    public var columnAddress: UInt16
    /** 셀 주소 행 (맨 위 = 0) */
    public var rowAddress: UInt16
    /** 열의 병합 개수 */
    public var columnSpan: UInt16
    /** 행의 병합 개수 */
    public var rowSpan: UInt16
    /** 셀의 폭 (HWPUNIT) */
    public var width: HWPUNIT
    /** 셀의 높이 (HWPUNIT) */
    public var height: HWPUNIT
    /** 셀 4방향 여백 (왼쪽/오른쪽/위쪽/아래쪽, HWPUNIT16) */
    public var marginArray: [HWPUNIT16]
    /** 테두리/배경 아이디 (HWPTAG_BORDER_FILL 참조, 1-based) */
    public var borderFillId: UInt16

    public init(
        columnAddress: UInt16 = 0,
        rowAddress: UInt16 = 0,
        columnSpan: UInt16 = 1,
        rowSpan: UInt16 = 1,
        width: HWPUNIT = 0,
        height: HWPUNIT = 0,
        marginArray: [HWPUNIT16] = [0, 0, 0, 0],
        borderFillId: UInt16 = 0
    ) {
        self.columnAddress = columnAddress
        self.rowAddress = rowAddress
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.width = width
        self.height = height
        self.marginArray = marginArray
        self.borderFillId = borderFillId
    }

    static let byteCount = 26

    /// LIST_HEADER 공통 필드 뒤의 trailing payload에서 셀 속성을 best-effort로 디코딩한다.
    /// payload가 26 byte보다 짧으면 nil을 반환한다.
    static func decode(from data: Data) -> HwpTableCellProperty? {
        guard data.count >= byteCount else { return nil }
        do {
            return HwpTableCellProperty(
                columnAddress: try data.readLittleEndianUInt16(at: 0),
                rowAddress: try data.readLittleEndianUInt16(at: 2),
                columnSpan: max(1, try data.readLittleEndianUInt16(at: 4)),
                rowSpan: max(1, try data.readLittleEndianUInt16(at: 6)),
                width: try data.readLittleEndianUInt32(at: 8),
                height: try data.readLittleEndianUInt32(at: 12),
                marginArray: try (0 ..< 4).map {
                    try data.readLittleEndianInt16(at: 16 + $0 * 2)
                },
                borderFillId: try data.readLittleEndianUInt16(at: 24)
            )
        } catch {
            return nil
        }
    }
}
