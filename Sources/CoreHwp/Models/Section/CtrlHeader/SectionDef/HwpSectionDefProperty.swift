/**
 4.3.10.1. 구역 정의

 구역 정의 속성은 첫 쪽의 머리말/꼬리말/바탕쪽 감춤 여부와 텍스트 방향 등을
 나타내는 bit field이다.
 */
public struct HwpSectionDefProperty {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 머리말을 감출지 여부 */
    public var hideHeader: Bool
    /** 꼬리말을 감출지 여부 */
    public var hideFooter: Bool
    // swiftlint:disable inclusive_language
    /** 바탕쪽을 감출지 여부 */
    public var hideMasterPage: Bool
    // swiftlint:enable inclusive_language
    /** 테두리를 감출지 여부 */
    public var hideBorder: Bool
    /** 배경을 감출지 여부 */
    public var hideFill: Bool
    /** 쪽 번호 위치를 감출지 여부 */
    public var hidePageNumberPosition: Bool
    /** 구역의 첫 쪽에만 테두리 표시 여부 */
    public var showFirstPageBorderOnly: Bool
    /** 구역의 첫 쪽에만 배경 표시 여부 */
    public var showFirstPageFillOnly: Bool
    /** 텍스트 방향 raw 값 */
    public var textDirectionRawValue: Int
    /** 빈 줄 감춤 여부 */
    public var hideEmptyLine: Bool
    /** 구역 나눔으로 새 페이지가 생길 때의 페이지 번호 적용 raw 값 */
    public var newPageNumberApplyRawValue: Int
    /** 원고지 정서법 적용 여부 */
    public var applyManuscriptPaper: Bool
}

extension HwpSectionDefProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        hideHeader = try reader.readBit()
        hideFooter = try reader.readBit()
        hideMasterPage = try reader.readBit()
        hideBorder = try reader.readBit()
        hideFill = try reader.readBit()
        hidePageNumberPosition = try reader.readBit()
        try reader.readBits(2)
        showFirstPageBorderOnly = try reader.readBit()
        showFirstPageFillOnly = try reader.readBit()
        try reader.readBits(6)
        textDirectionRawValue = try reader.readInt(3)
        hideEmptyLine = try reader.readBit()
        newPageNumberApplyRawValue = try reader.readInt(2)
        applyManuscriptPaper = try reader.readBit()
        try reader.readBits(9)
    }

    static func load(_ uint: UInt32) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

extension HwpSectionDefProperty {
    init() {
        rawValue = 0
        hideHeader = false
        hideFooter = false
        hideMasterPage = false
        hideBorder = false
        hideFill = false
        hidePageNumberPosition = false
        showFirstPageBorderOnly = false
        showFirstPageFillOnly = false
        textDirectionRawValue = 0
        hideEmptyLine = false
        newPageNumberApplyRawValue = 0
        applyManuscriptPaper = false
    }
}
