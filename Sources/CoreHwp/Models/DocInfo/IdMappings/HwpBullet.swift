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
    /// HWPX(`hh:bullet`) 합성 전용 — 표 39 문단 머리 정보 12바이트를
    /// `info`(앞 8바이트)와 `headCharShapeId`(뒤 `INT32`)로 쪼개 든다.
    /// 레코드 payload는 합성하지 않는다 (`HwpBorderFill(hwpxBorders:fillInfo:)`·
    /// `HwpFaceName(hwpxFace:substituteFace:)`와 같은 DocInfo 가족 관행 —
    /// HWPX 매니페스트에 payload 핀이 없고 등가 투영도 제외한다).
    init(hwpxInfo info: [BYTE], headCharShapeId: Int32, char: String) {
        rawPayload = Data()
        self.info = info
        self.headCharShapeId = headCharShapeId
        self.char = char
        charRawPayload = Data()
        // `imageId`는 여부가 아니라 "글머리표 0, 이미지 글머리표 ID"인 값이라
        // 0이 곧 "이미지 아님"이다. 이미지 글머리표(`useImage="1"`)는 HWPX
        // 픽스처 10종에 사례가 없어 실파일 검증 대기 항목이다.
        imageId = 0
        imageProperty = [0, 0, 0, 0]
        // 체크 글머리표 문자는 대응 OWPML 속성의 실물이 없어 비운다 — 체크
        // 여부 자체는 표 39에 자리가 없는 `hh:paraHead@checkable`에 있다.
        checkChar = ""
        checkCharRawPayload = Data()
        undocumentedTrailing = []
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
