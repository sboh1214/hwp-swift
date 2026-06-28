import Foundation

/**
 4.3.10.1.2. 각주/미주 모양

 Tag ID : HWPTAG_FOOTNOTE_SHAPE
 */
public struct HwpFootnoteShape {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 속성 */
    public var property: UInt32
    /** 사용자 기호 */
    public var userSymbol: Character
    /** 사용자 기호 원문 WCHAR 값 */
    public var userSymbolRawValue: WCHAR
    /** 사용자 기호 원문 WCHAR payload */
    @ExcludeEquatable
    public var userSymbolRawPayload: Data
    /** 앞 장식 문자 */
    public var decorationHead: Character
    /** 앞 장식 문자 원문 WCHAR 값 */
    public var decorationHeadRawValue: WCHAR
    /** 앞 장식 문자 원문 WCHAR payload */
    @ExcludeEquatable
    public var decorationHeadRawPayload: Data
    /** 뒤 장식 문자 */
    public var decorationTail: Character
    /** 뒤 장식 문자 원문 WCHAR 값 */
    public var decorationTailRawValue: WCHAR
    /** 뒤 장식 문자 원문 WCHAR payload */
    @ExcludeEquatable
    public var decorationTailRawPayload: Data
    /** 시작 번호 */
    public var startingNumber: UInt16
    /** 구분선 길이 */
    public var dividerLength: HWPUNIT16
    /** 구분선 위 여백 */
    public var dividerMarginTop: HWPUNIT16
    /** 구분선 아래 여백 */
    public var dividerMarginBottom: HWPUNIT16
    /** 주석 사이 여백 */
    public var marginComment: HWPUNIT16
    /**
     구분선 종류

     (테두리/배경의 테두리 선 종류 참조)
     */
    public var dividerType: UInt8
    /**
     구분선 굵기

     (테두리/배경의 테두리 선 굵기 참조)
     */
    public var dividerThickness: UInt8
    /**
     구분선 색상

     (테두리/배경의 테두리 선 색상 참조)
     */
    public var dividerColor: HwpColor
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
    /** unknown 2bytes and later trailing payload */
    public var unknown: Data
}

extension HwpFootnoteShape: HwpFromData {
    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt32.self)
        let userSymbolStartOffset = reader.byteOffset
        userSymbolRawValue = try reader.read(WCHAR.self)
        userSymbolRawPayload = try reader.consumedData(from: userSymbolStartOffset)
        userSymbol = try userSymbolRawValue.character
        let decorationHeadStartOffset = reader.byteOffset
        decorationHeadRawValue = try reader.read(WCHAR.self)
        decorationHeadRawPayload = try reader.consumedData(from: decorationHeadStartOffset)
        decorationHead = try decorationHeadRawValue.character
        let decorationTailStartOffset = reader.byteOffset
        decorationTailRawValue = try reader.read(WCHAR.self)
        decorationTailRawPayload = try reader.consumedData(from: decorationTailStartOffset)
        decorationTail = try decorationTailRawValue.character
        startingNumber = try reader.read(UInt16.self)
        dividerLength = try reader.read(HWPUNIT16.self)
        dividerMarginTop = try reader.read(HWPUNIT16.self)
        dividerMarginBottom = try reader.read(HWPUNIT16.self)
        marginComment = try reader.read(HWPUNIT16.self)
        dividerType = try reader.read(UInt8.self)
        dividerThickness = try reader.read(UInt8.self)
        dividerColor = HwpColor(try reader.read(COLORREF.self))
        guard reader.remainBytes >= 2 else {
            throw HwpError.truncatedData(expected: 2, actual: reader.remainBytes)
        }
        rawTrailing = try reader.readToEnd()
        unknown = rawTrailing
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var footnoteShape = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        footnoteShape.rawPayload = data
        return footnoteShape
    }
}

extension HwpFootnoteShape {
    init(dividerLength: HWPUNIT16, dividerMarginTop: HWPUNIT16,
         dividerType: UInt8, dividerThickness: UInt8)
    {
        rawPayload = Data()
        property = 0
        userSymbolRawValue = 0
        userSymbolRawPayload = footnoteShapeWcharPayload(userSymbolRawValue)
        userSymbol = "\0"
        decorationHeadRawValue = 0
        decorationHeadRawPayload = footnoteShapeWcharPayload(decorationHeadRawValue)
        decorationHead = "\0"
        decorationTailRawValue = WCHAR(0x0029)
        decorationTailRawPayload = footnoteShapeWcharPayload(decorationTailRawValue)
        decorationTail = ")"
        startingNumber = 1
        self.dividerLength = dividerLength
        self.dividerMarginTop = dividerMarginTop
        dividerMarginBottom = 850
        marginComment = 567
        self.dividerType = dividerType
        self.dividerThickness = dividerThickness
        dividerColor = HwpColor(red: 1, green: 1, blue: 1)
        rawTrailing = Data(Array(repeating: 0, count: 2))
        unknown = rawTrailing
    }
}

private func footnoteShapeWcharPayload(_ value: WCHAR) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
