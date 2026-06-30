/**
 4.3.9.1. 표 개체

 표 셀의 LIST_HEADER 확장 속성을 나타내는 bit field이다.
 */
public struct HwpTableCellHeaderProperty: HwpPrimitive {
    /** 원본 bit field */
    public var rawValue: UInt16
    /** 셀 안 여백을 셀 고유 값으로 적용할지 여부 */
    public var appliesInnerMargin: Bool
    /** 셀 보호 여부 */
    public var isCellProtected: Bool
    /** 제목 셀 여부 */
    public var isHeader: Bool
    /** 양식 모드에서 편집 가능 여부 */
    public var isEditableInFormMode: Bool
}

public extension HwpTableCellHeaderProperty {
    init(rawValue: UInt16) {
        self.rawValue = rawValue
        appliesInnerMargin = rawValue & (1 << 0) != 0
        isCellProtected = rawValue & (1 << 1) != 0
        isHeader = rawValue & (1 << 2) != 0
        isEditableInFormMode = rawValue & (1 << 3) != 0
    }

    init() {
        self.init(rawValue: 0)
    }
}
