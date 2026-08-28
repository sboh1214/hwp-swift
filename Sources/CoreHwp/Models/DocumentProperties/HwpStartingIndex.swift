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

    /// HWPX(`hh:beginNum`) 합성 전용 — 시작 번호 6종.
    init(
        hwpxPage page: UInt16,
        footnote: UInt16,
        endnote: UInt16,
        picture: UInt16,
        table: UInt16,
        equation: UInt16
    ) {
        rawPayload = Data()
        self.page = page
        self.footnote = footnote
        self.endnote = endnote
        self.picture = picture
        self.table = table
        self.equation = equation
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

    static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        var startingIndex = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        startingIndex.rawPayload = options.preservedPayload(data)
        return startingIndex
    }
}
