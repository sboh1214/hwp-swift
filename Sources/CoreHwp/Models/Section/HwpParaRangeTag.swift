import Foundation

/**
 문단의 영역 태그

 range tag 정보를 정보 수만큼 읽어 온다. range tag는 텍스트의 일정 영역을 마킹하는 용도로 사용되며,
 글자 모양과는 달리 각 영역은 서로 겹칠 수 있다.(형광펜, 교정 부호 등)
 Tag ID : HWPTAG_PARA_RANGE_TAG
 */
public struct HwpParaRangeTag: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 영역 시작 */
    public let start: UInt32
    /** 영역 끝 */
    public let end: UInt32
    /**
     태그(종류 + 데이터)

     상위 8비트가 종류를 하위 24비트가 종류별로 다른 설명을 부여할 수 있는 임의의 데이터를 나타낸다.
     */
    public let tag: UInt32

    init() {
        rawPayload = Data()
        start = 0
        end = 0
        tag = 0
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        start = try reader.read(UInt32.self)
        end = try reader.read(UInt32.self)
        tag = try reader.read(UInt32.self)
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        var paraRangeTag = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        paraRangeTag.rawPayload = options.preservedPayload(data)
        return paraRangeTag
    }

    /// PARA_RANGE_TAG 레코드 하나에는 태그가 정보 수만큼 (12바이트씩) 담긴다
    /// (ViewText 변경 추적 저장본 실측 — 한 레코드에 2개 이상).
    public static func loadArray(
        _ data: Data,
        options: HwpLoadOptions = .default
    ) throws -> [Self] {
        guard data.count.isMultiple(of: 12) else {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: data.count % 12)
        }
        var reader = DataReader(data, options: options)
        var tags: [Self] = []
        while !reader.isEOF {
            tags.append(try self.init(&reader))
        }
        return tags
    }
}
