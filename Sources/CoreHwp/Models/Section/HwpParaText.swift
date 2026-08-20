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
    public var charArray: [HwpChar] {
        didSet { wcharCount = Self.wcharCount(of: charArray) }
    }

    /// 원본 payload의 WCHAR 수 — 컨트롤 문자는 wchar 1 + payload 14바이트
    /// (= wchar 7)로 총 8 wchar를 차지한다. rawPayload 없이도 계산되므로
    /// PARA_HEADER charCount 검증에 양 모드 공통으로 쓴다. 파스 루프에서
    /// 누적하고 charArray 변경 시 didSet으로 재동기화하는 파생 저장값이라
    /// 아카이브에는 싣지 않는다 (아래 custom Codable).
    public private(set) var wcharCount: Int

    init() {
        rawPayload = Data()
        let char0 = HwpChar(type: .extended, value: 2)
        let char1 = HwpChar(type: .extended, value: 2)
        let char2 = HwpChar(type: .char, value: 13)
        charArray = [char0, char1, char2]
        wcharCount = Self.wcharCount(of: charArray)
    }

    init(rawPayload: Data, charArray: [HwpChar]) {
        self.rawPayload = rawPayload
        self.charArray = charArray
        wcharCount = Self.wcharCount(of: charArray)
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        var array = [HwpChar]()
        var accumulatedWcharCount = 0
        while !reader.isEOF {
            let char = try reader.read(WCHAR.self)
            switch char {
            case 0, 1, 13:
                array.append(HwpChar(type: .char, value: char))
                accumulatedWcharCount += 1
            case 4 ... 9, 19 ... 20:
                let payload = try reader.readBytes(14)
                array.append(HwpChar(type: .inline, value: char, payload: payload))
                accumulatedWcharCount += 8
            case 2 ... 3, 11 ... 12, 14 ... 18, 21 ... 23:
                let payload = try reader.readBytes(14)
                array.append(HwpChar(type: .extended, value: char, payload: payload))
                accumulatedWcharCount += 8
            default:
                array.append(HwpChar(type: .char, value: char))
                accumulatedWcharCount += 1
            }
        }
        charArray = array
        wcharCount = accumulatedWcharCount
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        var paraText = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        paraText.rawPayload = options.preservedPayload(data)
        return paraText
    }

    static func wcharCount(of charArray: [HwpChar]) -> Int {
        charArray.reduce(0) { $0 + ($1.payload == nil ? 1 : 8) }
    }
}

// MARK: - Equatable/Hashable — 종전 synthesized 시맨틱 유지 (charArray만)

// rawPayload는 @ExcludeEquatable였고, wcharCount는 payload **유무**에서
// 파생되어 HwpChar 동등성(type/value만 비교)과 어긋날 수 있는 파생값이라
// 비교에서 제외한다 — 빈 문서 템플릿(payload 없는 extended char)과 파싱본
// (payload 14 byte)의 round-trip 동등성이 이 시맨틱에 기댄다.

public extension HwpParaText {
    static func == (lhs: HwpParaText, rhs: HwpParaText) -> Bool {
        lhs.charArray == rhs.charArray
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(charArray)
    }
}

// MARK: - Codable — 종전 synthesized 형상 보존 (wcharCount 파생값 제외)

// (rawPayload 키는 ExcludeEquatable 래퍼 {"wrappedValue": …}로 인코딩)

public extension HwpParaText {
    private enum CodingKeys: String, CodingKey {
        case rawPayload, charArray
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rawPayload: try container.decode(
                ExcludeEquatable<Data>.self, forKey: .rawPayload
            ).wrappedValue,
            charArray: try container.decode([HwpChar].self, forKey: .charArray)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ExcludeEquatable(wrappedValue: rawPayload), forKey: .rawPayload)
        try container.encode(charArray, forKey: .charArray)
    }
}
