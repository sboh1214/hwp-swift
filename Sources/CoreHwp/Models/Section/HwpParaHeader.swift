import Foundation

/**
 문단 헤더

 Tag ID : HWPTAG_PARA_HEADER
 텍스트의 수가 1 이상이면 문자 수만큼 텍스트를 로드하고 그렇지 않을 경우 PARA_BREAK로 문단을 생성한다.
 */
public struct HwpParaHeader: HwpFromDataWithVersion {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** if (nchars & 0x80000000) { nchars &= 0x7fffffff;} */
    public let isLastInList: Bool
    /**text(=chars) */
    public let charCount: UInt32
    /**
     control mask

     (UINT32)(1<<ctrlch) 조합
     ctrlch는 HwpCtrlAPI.Hwp 2.1 CtrlCh 참고
     */
    public let controlMask: UInt32
    /** 문단 모양 아이디 참조값 */
    public let paraShapeId: UInt16
    /** 문단 스타일 아이디 참조값 */
    public let paraStyleId: UInt8
    /** 단 나누기 종류 */
    public let columnType: UInt8
    /** 글자 모양 정보 수 */
    public let charShapeInfoCount: UInt16
    /** range tag 정보 수 */
    public let rangeTagInfoCount: UInt16
    /** 각 줄에 대한 align에 대한 정보 수 */
    public let alignInfoCount: UInt16
    /** 문단 Instance ID (unique ID) */
    @ExcludeEquatable
    public var paraId: UInt32
    /** 변경추적 병합 문단여부. (5.0.3.2 버전 이상) */
    public var isTraceChange: UInt16?

    init() {
        rawPayload = Data()
        isLastInList = true
        charCount = 17
        controlMask = 4
        paraShapeId = 0
        paraStyleId = 0
        columnType = 3
        charShapeInfoCount = 1
        rangeTagInfoCount = 0
        alignInfoCount = 1
        paraId = 0
        isTraceChange = 0
    }

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        let value = try reader.read(UInt32.self)
        if (value & 0x8000_0000) == 0x8000_0000 {
            isLastInList = true
            charCount = (value & 0x7FFF_FFFF)
        } else {
            isLastInList = false
            charCount = value
        }
        controlMask = try reader.read(UInt32.self)
        paraShapeId = try reader.read(UInt16.self)
        paraStyleId = try reader.read(UInt8.self)
        columnType = try reader.read(UInt8.self)
        charShapeInfoCount = try reader.read(UInt16.self)
        rangeTagInfoCount = try reader.read(UInt16.self)
        alignInfoCount = try reader.read(UInt16.self)
        paraId = try reader.read(UInt32.self)
        if version >= HwpVersion(5, 0, 3, 2) {
            isTraceChange = try reader.read(UInt16.self)
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public static func load(_ data: Data, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(data)
        var paraHeader = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        paraHeader.rawPayload = data
        return paraHeader
    }
}
