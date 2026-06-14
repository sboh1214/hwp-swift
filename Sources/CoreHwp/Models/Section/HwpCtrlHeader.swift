import Foundation

public struct HwpCtrlHeader {
    public var ctrlId: UInt32
}

extension HwpCtrlHeader: HwpPrimitive {
    init(_ reader: inout DataReader, _: [HwpRecord]) throws {
        ctrlId = reader.read(UInt32.self)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        var reader = DataReader(record.payload)
        return try self.init(&reader, record.children)
    }
}
