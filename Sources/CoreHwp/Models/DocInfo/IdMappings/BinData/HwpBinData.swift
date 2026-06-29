import Foundation

/**
 그림, OLE 등의 바이너리 데이터 아이템에 대한 정보

 Tag ID : HWPTAG_BIN_DATA
 */
public struct HwpBinData: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public var property: HwpBinDataProperty

    /** Type이 "LINK"일 때, 연결 파일의 절대 경로 */
    public var absolutePath: String?
    /** Type이 "LINK"일 때, 연결 파일의 절대 경로 원문 WCHAR payload */
    @ExcludeEquatable
    public var absolutePathRawPayload: Data?
    /** Type이 "LINK"일 때, 연결 파일의 상대 경로 */
    public var relativePath: String?
    /** Type이 "LINK"일 때, 연결 파일의 상대 경로 원문 WCHAR payload */
    @ExcludeEquatable
    public var relativePathRawPayload: Data?

    /** Type이 "EMBEDDING"이거나 "STORAGE"일 때, BINDATASTORAGE에 저장된 바이너리 데이터의 아이디 */
    public var streamId: UInt16?
    /**
     Type이 "EMBEDDING"일 때 extension("." 제외)

     그림의 경우 jpg, bmp, gif
     OLE의 경우 ole
     */
    public var extensionName: String?
    /** Type이 "EMBEDDING"이거나 "STORAGE"일 때 extension 원문 WCHAR payload */
    @ExcludeEquatable
    public var extensionNameRawPayload: Data?

    init() {
        rawPayload = Data()
        property = HwpBinDataProperty()
        absolutePath = nil
        absolutePathRawPayload = nil
        relativePath = nil
        relativePathRawPayload = nil
        streamId = nil
        extensionName = nil
        extensionNameRawPayload = nil
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        property = try HwpBinDataProperty.load(try reader.read(UInt16.self))

        if property.type == .link {
            let absolutePathLength = try reader.read(WORD.self)
            let absolutePathStartOffset = reader.byteOffset
            let absolutePathCharacters = try reader.read(WCHAR.self, absolutePathLength)
            absolutePathRawPayload = try reader.consumedData(from: absolutePathStartOffset)
            absolutePath = try absolutePathCharacters.string
            let relativePathLength = try reader.read(WORD.self)
            let relativePathStartOffset = reader.byteOffset
            let relativePathCharacters = try reader.read(WCHAR.self, relativePathLength)
            relativePathRawPayload = try reader.consumedData(from: relativePathStartOffset)
            relativePath = try relativePathCharacters.string
            extensionNameRawPayload = nil
        } else {
            absolutePathRawPayload = nil
            relativePathRawPayload = nil
            streamId = try reader.read(UInt16.self)
            let extensionLength = try reader.read(WORD.self)
            let extensionNameStartOffset = reader.byteOffset
            let extensionNameCharacters = try reader.read(WCHAR.self, extensionLength)
            extensionNameRawPayload = try reader.consumedData(from: extensionNameStartOffset)
            extensionName = try extensionNameCharacters.string
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var binData = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        binData.rawPayload = data
        return binData
    }
}
