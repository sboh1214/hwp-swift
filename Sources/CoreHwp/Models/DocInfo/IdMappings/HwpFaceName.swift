import Foundation

public struct HwpFaceName {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public let property: BYTE
    public let faceNameLength: WORD
    public let faceName: String?
    @ExcludeEquatable
    public var faceNameRawPayload: Data
    public var alternativeFaceType: BYTE?
    public var alternativeFaceNameLength: WORD?
    public var alternativeFaceName: String?
    @ExcludeEquatable
    public var alternativeFaceNameRawPayload: Data?
    public var faceTypeInfo: [BYTE]?
    public var defaultFaceNameLength: WORD?
    public var defaultFaceName: String?
    @ExcludeEquatable
    public var defaultFaceNameRawPayload: Data?
}

extension HwpFaceName: HwpFromData {
    init() {
        rawPayload = Data()
        property = 0
        faceNameLength = 0
        faceName = ""
        faceNameRawPayload = Data()
        alternativeFaceType = nil
        alternativeFaceNameLength = nil
        alternativeFaceName = nil
        alternativeFaceNameRawPayload = nil
        faceTypeInfo = nil
        defaultFaceNameLength = nil
        defaultFaceName = nil
        defaultFaceNameRawPayload = nil
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(BYTE.self)
        let hasAlternative = getBitValue(mask: property, start: 7, end: 7) == 1
        let hasInfo = getBitValue(mask: property, start: 6, end: 6) == 1
        let hasDefault = getBitValue(mask: property, start: 5, end: 5) == 1

        faceNameLength = try reader.read(WORD.self)
        let faceNameStartOffset = reader.byteOffset
        let faceNameCharacters = try reader.read(WCHAR.self, faceNameLength)
        faceNameRawPayload = try reader.consumedData(from: faceNameStartOffset)
        faceName = try faceNameCharacters.string

        if hasAlternative {
            alternativeFaceType = try reader.read(BYTE.self)
            let alternativeFaceNameLength = try reader.read(WORD.self)
            self.alternativeFaceNameLength = alternativeFaceNameLength
            let alternativeFaceNameStartOffset = reader.byteOffset
            let alternativeFaceNameCharacters = try reader.read(
                WCHAR.self,
                alternativeFaceNameLength
            )
            alternativeFaceNameRawPayload = try reader.consumedData(
                from: alternativeFaceNameStartOffset
            )
            alternativeFaceName = try alternativeFaceNameCharacters.string
        } else {
            alternativeFaceNameRawPayload = nil
        }
        if hasInfo {
            faceTypeInfo = try reader.readBytes(10).bytes
        }
        if hasDefault {
            let defaultFaceNameLength = try reader.read(WORD.self)
            self.defaultFaceNameLength = defaultFaceNameLength
            let defaultFaceNameStartOffset = reader.byteOffset
            let defaultFaceNameCharacters = try reader.read(WCHAR.self, defaultFaceNameLength)
            defaultFaceNameRawPayload = try reader.consumedData(from: defaultFaceNameStartOffset)
            defaultFaceName = try defaultFaceNameCharacters.string
        } else {
            defaultFaceNameRawPayload = nil
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var faceName = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        faceName.rawPayload = data
        return faceName
    }
}

extension HwpFaceName {
    init(_ faceName: String, _ faceTypeInfo: [BYTE], _ defaultFaceName: String) {
        rawPayload = Data()
        property = 97
        faceNameLength = WORD(faceName.utf16.count)
        self.faceName = faceName
        faceNameRawPayload = faceNamePayload(faceName)
        alternativeFaceType = nil
        alternativeFaceNameLength = nil
        alternativeFaceName = nil
        alternativeFaceNameRawPayload = nil
        self.faceTypeInfo = faceTypeInfo
        defaultFaceNameLength = WORD(defaultFaceName.utf16.count)
        self.defaultFaceName = defaultFaceName
        defaultFaceNameRawPayload = faceNamePayload(defaultFaceName)
    }
}

private func faceNamePayload(_ name: String) -> Data {
    var data = Data()
    for codeUnit in name.utf16 {
        var littleEndian = codeUnit.littleEndian
        data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
    }
    return data
}
