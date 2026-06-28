import Foundation

/**
 글머리표

 Tag ID : HWPTAG_BULLET

 문서화되지 않은 trailing bytes는 `undocumentedTrailing`에 보존한다.
 */
public struct HwpBullet {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 문단 머리의 정보 8바이트 */
    public let info: [BYTE]
    /** 글머리표 문자 */
    public let char: String
    /** 글머리표 문자 원문 WCHAR payload */
    @ExcludeEquatable
    public var charRawPayload: Data
    /** 이미지 글머리표 여부 (글머리표 :0, 이미지글머리표 : ID) */
    public let imageId: Int32
    /** 이미지 글머리 (대비, 밝기 ,효과, ID) 4바이트 */
    public let imageProperty: [BYTE]
    /** 체크 글머리표 문자 */
    public let checkChar: String
    /** 체크 글머리표 문자 원문 WCHAR payload */
    @ExcludeEquatable
    public var checkCharRawPayload: Data
    /** 문서화되어 있지 않은 trailing bytes */
    public let undocumentedTrailing: [BYTE]
}

extension HwpBullet: HwpFromData {
    // MARK: loader contract exemption - preserves undocumented trailing bytes after known fields

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        info = try reader.readBytes(8).bytes
        let charStartOffset = reader.byteOffset
        let charValue = try reader.read(WCHAR.self)
        charRawPayload = try reader.consumedData(from: charStartOffset)
        char = try [charValue].string
        imageId = try reader.read(Int32.self)
        imageProperty = try reader.readBytes(4).bytes
        let checkCharStartOffset = reader.byteOffset
        let checkCharValue = try reader.read(WCHAR.self)
        checkCharRawPayload = try reader.consumedData(from: checkCharStartOffset)
        checkChar = try [checkCharValue].string
        undocumentedTrailing = try reader.readToEnd().bytes
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - restores complete rawPayload after trailing preservation

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var bullet = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        bullet.rawPayload = data
        return bullet
    }
}
