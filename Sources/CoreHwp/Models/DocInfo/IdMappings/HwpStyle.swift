import Foundation

/**
 스타일(문단 스타일)

 Tag ID : HWPTAG_STYLE

 끝에 문서화되지 않은 2바이트가 붙어 있음
 */
public struct HwpStyle {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 길이 (len1) */
    public let length1: WORD
    /** 로컬 스타일 이름. 한글 윈도우에서는 한글 스타일 이름 */
    public let styleLocalName: String
    /** 로컬 스타일 이름 원문 WCHAR payload */
    @ExcludeEquatable
    public var styleLocalNameRawPayload: Data
    /** 길이 (len2) */
    public let length2: WORD
    /** 영문 스타일 이름 */
    public let styelEnglishName: String
    /** 영문 스타일 이름 원문 WCHAR payload */
    @ExcludeEquatable
    public var styleEnglishNameRawPayload: Data
    /** 속성 */
    public let property: BYTE
    /** 다음 스타일 아이디 참조값 */
    public let nextId: BYTE
    /** 언어 아이디 */
    public let languageId: Int16
    /**
     문단 모양 아이디 참조값(문단 모양의 아이디 속성)

     스타일의 종류가 문단인 경우 반드시 지정해야 한다.
     */
    public let paraShapeId: UInt16
    /**
     글자 모양 아이디(글자 모양의 아이디 속성)

     스타일의 종류가 글자인 경우 반드시 지정해야 한다.
     */
    public let charShapeId: UInt16
    /** 문서화되어있지 않음 */
    public let unknown: [BYTE]
    /** 문서화되지 않은 trailing bytes */
    public var undocumentedTrailing: [BYTE] {
        unknown
    }
}

extension HwpStyle: HwpFromData {
    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        length1 = try reader.read(WORD.self)
        let localNameStartOffset = reader.byteOffset
        let localNameCharacters = try reader.read(WCHAR.self, Int(length1))
        styleLocalNameRawPayload = try reader.consumedData(from: localNameStartOffset)
        styleLocalName = try localNameCharacters.string
        length2 = try reader.read(WORD.self)
        let englishNameStartOffset = reader.byteOffset
        let englishNameCharacters = try reader.read(WCHAR.self, Int(length2))
        styleEnglishNameRawPayload = try reader.consumedData(from: englishNameStartOffset)
        styelEnglishName = try englishNameCharacters.string
        property = try reader.read(BYTE.self)
        nextId = try reader.read(BYTE.self)
        languageId = try reader.read(Int16.self)
        paraShapeId = try reader.read(UInt16.self)
        charShapeId = try reader.read(UInt16.self)
        unknown = try reader.readBytes(2).bytes
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var style = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        style.rawPayload = data
        return style
    }
}

extension HwpStyle {
    init(_ styleLocalName: String, _ styelEnglishName: String, property: BYTE = 0,
         nextId: BYTE, paraShapeId: UInt16, charShapeId: UInt16)
    {
        rawPayload = Data()
        length1 = WORD(styleLocalName.utf16.count)
        self.styleLocalName = styleLocalName
        styleLocalNameRawPayload = styleNameRawPayload(styleLocalName)
        length2 = WORD(styelEnglishName.utf16.count)
        self.styelEnglishName = styelEnglishName
        styleEnglishNameRawPayload = styleNameRawPayload(styelEnglishName)
        self.property = property
        self.nextId = nextId
        languageId = 1042
        self.paraShapeId = paraShapeId
        self.charShapeId = charShapeId
        unknown = [0, 0]
    }
}

private func styleNameRawPayload(_ name: String) -> Data {
    var data = Data()
    for codeUnit in name.utf16 {
        var littleEndian = codeUnit.littleEndian
        data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
    }
    return data
}
