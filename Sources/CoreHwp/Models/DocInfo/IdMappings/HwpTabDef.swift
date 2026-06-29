import Foundation

/**
 탭 정의

 Tag ID : HWPTAG_TAB_DEF
 */
public struct HwpTabDef {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 속성 */
    public let property: UInt32
    /** count */
    public let count: Int32
    public var tabInfoArray: [HwpTabInfo]
}

extension HwpTabDef {
    init(property: UInt32) {
        rawPayload = Data()
        self.property = property
        count = 0
        tabInfoArray = [HwpTabInfo]()
    }
}

extension HwpTabDef: HwpFromData {
    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt32.self)
        count = try reader.read(Int32.self)
        guard let tabInfoCount = Int(exactly: count), tabInfoCount >= 0 else {
            throw HwpError.invalidDataLength(length: String(count))
        }
        tabInfoArray = [HwpTabInfo]()
        let tabInfoByteCount = tabInfoCount * 8
        var tabInfoReader = DataReader(try reader.readBytes(tabInfoByteCount))
        for _ in 0 ..< tabInfoCount {
            tabInfoArray.append(try HwpTabInfo(&tabInfoReader))
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var tabDef = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        tabDef.rawPayload = data
        return tabDef
    }
}
