import Foundation

protocol HwpFromDataWithVersion: HwpPrimitive {
    init(_ reader: inout DataReader, _ version: HwpVersion) throws
    static func load(_ data: Data, _ version: HwpVersion, options: HwpLoadOptions) throws -> Self
}

extension HwpFromDataWithVersion {
    static func load(
        _ data: Data,
        _ version: HwpVersion,
        options: HwpLoadOptions = .default
    ) throws -> Self {
        var reader = DataReader(data, options: options)
        let hwpFromDataWithVersion = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return hwpFromDataWithVersion
    }
}
