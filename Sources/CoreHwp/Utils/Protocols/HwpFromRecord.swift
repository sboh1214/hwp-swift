import Foundation

protocol HwpFromRecord: HwpPrimitive {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws
    static func load(_ record: HwpRecord) throws -> Self
}

extension HwpFromRecord {
    static func load(_ record: HwpRecord) throws -> Self {
        var reader = DataReader(record.payload, options: record.options)
        let hwpFromRecord = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return hwpFromRecord
    }
}
