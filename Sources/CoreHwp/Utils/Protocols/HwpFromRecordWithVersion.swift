import Foundation

protocol HwpFromRecordWithVersion: HwpPrimitive {
    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws
    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self
}

extension HwpFromRecordWithVersion {
    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(record.payload, options: record.options)
        let hwpFromRecordWithVersion = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return hwpFromRecordWithVersion
    }
}
