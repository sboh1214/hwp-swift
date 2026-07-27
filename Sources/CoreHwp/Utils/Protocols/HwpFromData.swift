import Foundation

protocol HwpFromData: HwpPrimitive {
    init(_ reader: inout DataReader) throws
    static func load(_ data: Data, options: HwpLoadOptions) throws -> Self
}

extension HwpFromData {
    static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        let hwpFromData = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return hwpFromData
    }
}
