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
    /** 문단 머리 글자 모양 ID (표 40 — −1이면 바탕글 모양) */
    public let headCharShapeId: Int32
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

extension HwpBullet {
    private enum CodingKeys: String, CodingKey {
        case rawPayload, info, headCharShapeId, char, charRawPayload,
             imageId, imageProperty, checkChar, checkCharRawPayload, undocumentedTrailing
    }

    /// main 아카이브에는 headCharShapeId 키가 없고, 그 필드 이후가 전부 4바이트씩
    /// 밀려 저장돼 있다 (main 파서는 표 40의 글자 모양 ID를 읽지 않고 info 직후
    /// 바로 char를 읽었다) — 아카이브 값 대신 rawPayload를 파서로 전량 재수화한다.
    /// rawPayload가 비었거나(뷰어 모드 인코딩) 잘렸으면 표 40 기본값 −1로만
    /// 폴백해 keyNotFound 실패를 막는다 (R61 #1, R66 #2).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decode(
            ExcludeEquatable<Data>.self, forKey: .rawPayload
        ).wrappedValue
        if !container.contains(.headCharShapeId), let legacy = Self.reparsed(from: payload) {
            self = legacy
            return
        }
        rawPayload = payload
        info = try container.decode([BYTE].self, forKey: .info)
        headCharShapeId = try container.decodeIfPresent(
            Int32.self, forKey: .headCharShapeId
        ) ?? -1
        char = try container.decode(String.self, forKey: .char)
        charRawPayload = try container.decode(
            ExcludeEquatable<Data>.self, forKey: .charRawPayload
        ).wrappedValue
        imageId = try container.decode(Int32.self, forKey: .imageId)
        imageProperty = try container.decode([BYTE].self, forKey: .imageProperty)
        checkChar = try container.decode(String.self, forKey: .checkChar)
        checkCharRawPayload = try container.decode(
            ExcludeEquatable<Data>.self, forKey: .checkCharRawPayload
        ).wrappedValue
        undocumentedTrailing = try container.decode([BYTE].self, forKey: .undocumentedTrailing)
    }

    /// 원본 payload를 파서로 다시 읽어 legacy 아카이브의 밀린 필드를 복원한다.
    /// 파스 실패(빈/잘린 payload)는 nil — 호출부가 키별 폴백으로 내려간다.
    private static func reparsed(from payload: Data) -> HwpBullet? {
        guard !payload.isEmpty else { return nil }
        do {
            return try load(payload)
        } catch {
            return nil
        }
    }
}

extension HwpBullet: HwpFromData {
    // MARK: loader contract exemption - preserves undocumented trailing bytes after known fields

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        info = try reader.readBytes(8).bytes
        // 표 40 문단 머리 정보는 글자 모양 ID(INT32)까지 12바이트다 — 8바이트로
        // 읽으면 글머리표 문자가 4바이트 밀려 U+FFFF가 된다 (noori '-' 실측)
        headCharShapeId = try reader.read(Int32.self)
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

    static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        var bullet = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        bullet.rawPayload = options.preservedPayload(data)
        return bullet
    }
}
