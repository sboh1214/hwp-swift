import Foundation

/**
 테두리/배경

 Tag ID : HWPTAG_BORDER_FILL
 */
public struct HwpBorderFill {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 속성 */
    public let property: UInt16
    /** 4방향 테두리선 종류 */
    public let borderType: [UInt8]
    /** 4방향 테두리선 굵기 */
    public let borderThickness: [UInt8]
    /** 4방향 테두리선 색상 */
    public let borderColor: [HwpColor]
    /** 대각선 종류 */
    public let diagonalType: UInt8
    /** 대각선 굵기 */
    public let diagonalThickness: UInt8
    /** 대각선 색깔 */
    public let diagonalColor: HwpColor
    /** 채우기 정보 */
    public let fillInfo: [BYTE]
}

extension HwpBorderFill: HwpFromData {
    init() {
        rawPayload = Data()
        property = 0
        borderType = [0, 0, 0, 0]
        borderThickness = [0, 0, 0, 0]
        borderColor = Array(repeating: HwpColor(), count: 4)
        diagonalType = 0
        diagonalThickness = 0
        diagonalColor = HwpColor()
        fillInfo = [BYTE]()
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt16.self)
        borderType = try reader.readBytes(4).bytes
        borderThickness = try reader.readBytes(4).bytes
        borderColor = try reader.read(UInt32.self, 4).map { HwpColor($0) }
        diagonalType = try reader.read(UInt8.self)
        diagonalThickness = try reader.read(UInt8.self)
        diagonalColor = HwpColor(try reader.read(UInt32.self))
        fillInfo = try reader.readToEnd().bytes
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var borderFill = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        borderFill.rawPayload = data
        return borderFill
    }
}

extension HwpBorderFill {
    init(fillInfo: [BYTE]) {
        rawPayload = Data()
        property = 0
        borderType = [0, 0, 0, 0]
        borderThickness = [0, 0, 0, 0]
        borderColor = Array(repeating: HwpColor(), count: 4)
        diagonalType = 1
        diagonalThickness = 0
        diagonalColor = HwpColor()
        self.fillInfo = fillInfo
    }
}
