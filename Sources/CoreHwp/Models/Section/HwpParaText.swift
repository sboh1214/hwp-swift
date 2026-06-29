import Foundation

/**
 문단의 텍스트

 Tag ID : HWPTAG_PARA_TEXT
 문단은 최소 하나의 문자 Shape buffer가 존재하며, 첫 번째 pos가 반드시 0이어야 한다.
 텍스트 문자 Shape 레코드를 글자 모양 정보 수(Character Shapes)만큼 읽는다.
 */
public struct HwpParaText: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 문자수만큼의 텍스트 */
    public var charArray: [HwpChar]

    init() {
        rawPayload = Data()
        let char0 = HwpChar(type: .extended, value: 2)
        let char1 = HwpChar(type: .extended, value: 2)
        let char2 = HwpChar(type: .char, value: 13)
        charArray = [char0, char1, char2]
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        var array = [HwpChar]()
        while !reader.isEOF {
            let char = try reader.read(WCHAR.self)
            switch char {
            case 0, 1, 13:
                array.append(HwpChar(type: .char, value: char))
            case 4 ... 9, 19 ... 20:
                let payload = try reader.readBytes(14)
                array.append(HwpChar(type: .inline, value: char, payload: payload))
            case 2 ... 3, 11 ... 12, 14 ... 18, 21 ... 23:
                let payload = try reader.readBytes(14)
                array.append(HwpChar(type: .extended, value: char, payload: payload))
            default:
                array.append(HwpChar(type: .char, value: char))
            }
        }
        charArray = array
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var paraText = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        paraText.rawPayload = data
        return paraText
    }
}
