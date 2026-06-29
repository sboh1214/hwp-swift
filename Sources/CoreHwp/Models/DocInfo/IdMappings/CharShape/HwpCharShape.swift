import Foundation

/**
 글자 모양

 Tag ID : HWPTAG_CHAR_SHAPE
 */
public struct HwpCharShape {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 언어별 글꼴 ID(FaceID) 참조 값 */
    public let faceId: [WORD]
    /** 언어별 장평, 50%~200%( */
    public let faceScaleX: [UInt8]
    /** 언어별 자간, -50%~50% */
    public let faceSpacing: [Int8]
    /** 언어별 상대 크기, 10%~250% */
    public let faceRelativeSize: [UInt8]
    /** 언어별 글자 위치, -100%~100% */
    public let faceLocation: [Int8]
    /** 기준 크기, 0pt~4096pt */
    public let baseSize: Int32
    /** 속성 */
    public let property: HwpCharShapeProperty
    /** 그림자 간격 X, -100%~100% */
    public let shadowIntervalX: Int8
    /** 그림자 간격 Y, -100%~100% */
    public let shadowIntervalY: Int8
    /** 글자 색 */
    public let faceColor: HwpColor
    /** 밑줄 색 */
    public let underlineColor: HwpColor
    /** 음영 색 */
    public let shadeColor: HwpColor
    /** 그림자 색 */
    public let shadowColor: HwpColor
    /** 글자 테두리/배경 ID(CharShapeBorderFill ID) 참조 값 (5.0.2.1 이상) */
    public var borderFillId: UInt16?
    /** 취소선 색 (5.0.3.0 이상) */
    public var strikethroughColor: HwpColor?
}

extension HwpCharShape: HwpFromDataWithVersion {
    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        faceId = try reader.read(WORD.self, 7)
        faceScaleX = try reader.readBytes(7).bytes
        faceSpacing = try reader.read(Int8.self, 7)
        faceRelativeSize = try reader.readBytes(7).bytes
        faceLocation = try reader.read(Int8.self, 7)
        baseSize = try reader.read(Int32.self)
        property = try HwpCharShapeProperty.load(try reader.read(UInt32.self))
        shadowIntervalX = try reader.read(Int8.self)
        shadowIntervalY = try reader.read(Int8.self)
        faceColor = HwpColor(try reader.read(UInt32.self))
        underlineColor = HwpColor(try reader.read(UInt32.self))
        shadeColor = HwpColor(try reader.read(UInt32.self))
        shadowColor = HwpColor(try reader.read(UInt32.self))
        if version >= HwpVersion(5, 0, 2, 1) {
            borderFillId = try reader.read(UInt16.self)
        }
        if version >= HwpVersion(5, 0, 3, 0) {
            strikethroughColor = HwpColor(try reader.read(UInt32.self))
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(data)
        var charShape = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        charShape.rawPayload = data
        return charShape
    }
}

extension HwpCharShape {
    init(faceId: [WORD], faceSpacing: [Int8], baseSize: Int32, faceColor: HwpColor) {
        rawPayload = Data()
        self.faceId = faceId
        faceScaleX = [100, 100, 100, 100, 100, 100, 100]
        self.faceSpacing = faceSpacing
        faceRelativeSize = [100, 100, 100, 100, 100, 100, 100]
        faceLocation = [0, 0, 0, 0, 0, 0, 0]
        self.baseSize = baseSize
        property = HwpCharShapeProperty()
        shadowIntervalX = 10
        shadowIntervalY = 10
        self.faceColor = faceColor
        underlineColor = HwpColor()
        shadeColor = HwpColor(255, 255, 255)
        shadowColor = HwpColor(192, 192, 192)
        borderFillId = 2
        strikethroughColor = HwpColor()
    }
}
