import Foundation

public struct HwpStartingIndex: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public let page: UInt16
    public let footnote: UInt16
    public let endnote: UInt16
    public let picture: UInt16
    public let table: UInt16
    public let equation: UInt16

    init() {
        rawPayload = Data()
        page = 1
        footnote = 1
        endnote = 1
        picture = 1
        table = 1
        equation = 1
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        page = try reader.read(UInt16.self)
        footnote = try reader.read(UInt16.self)
        endnote = try reader.read(UInt16.self)
        picture = try reader.read(UInt16.self)
        table = try reader.read(UInt16.self)
        equation = try reader.read(UInt16.self)
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var startingIndex = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        startingIndex.rawPayload = data
        return startingIndex
    }
}
