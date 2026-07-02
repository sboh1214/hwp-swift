import Foundation

/**
 4.3.10.1.1. 용지 설정

 Tag ID : HWPTAG_PAGE_DEF
 */
public struct HwpPageDef {
    /** 용지 가로 크기 */
    public var width: HWPUNIT
    /** 용지 세로 크기 */
    public var height: HWPUNIT
    /** 왼쪽 여백 */
    public var marginLeft: HWPUNIT
    /** 오른쪽 여백 */
    public var marginRight: HWPUNIT
    /** 위 여백 */
    public var marginTop: HWPUNIT
    /** 아래 여백 */
    public var marginBottom: HWPUNIT
    /** 머리말 여백 */
    public var marginHeader: HWPUNIT
    /** 꼬리말 여백 */
    public var marginFootnote: HWPUNIT
    /** 제본 여백 */
    public var marginGutter: HWPUNIT
    /** 속성 */
    public var property: UInt32
    /** raw payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
}

extension HwpPageDef: HwpFromData {
    // MARK: loader contract exemption - preserves PAGE_DEF trailing payload

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        width = try reader.read(HWPUNIT.self)
        height = try reader.read(HWPUNIT.self)
        marginLeft = try reader.read(HWPUNIT.self)
        marginRight = try reader.read(HWPUNIT.self)
        marginTop = try reader.read(HWPUNIT.self)
        marginBottom = try reader.read(HWPUNIT.self)
        marginHeader = try reader.read(HWPUNIT.self)
        marginFootnote = try reader.read(HWPUNIT.self)
        marginGutter = try reader.read(HWPUNIT.self)
        property = try reader.read(UInt32.self)
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - restores complete PAGE_DEF rawPayload

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var pageDef = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        pageDef.rawPayload = data
        return pageDef
    }
}

public extension HwpPageDef {
    init() {
        width = 59528
        height = 84186
        marginLeft = 8504
        marginRight = 8504
        marginTop = 5668
        marginBottom = 4252
        marginHeader = 4252
        marginFootnote = 4252
        marginGutter = 0
        property = 0
        rawPayload = Data()
        rawTrailing = Data()
    }
}
