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
    /** 4방향 테두리선 정보 */
    public let borderLineArray: [HwpBorderLine]
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
        borderLineArray = Array(repeating: HwpBorderLine(), count: 4)
        borderType = borderLineArray.map(\.typeRawValue)
        borderThickness = borderLineArray.map(\.thickness)
        borderColor = borderLineArray.map(\.color)
        diagonalType = 0
        diagonalThickness = 0
        diagonalColor = HwpColor()
        fillInfo = [BYTE]()
    }

    // MARK: loader contract exemption - fillInfo consumes the remaining raw fill payload

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt16.self)
        borderLineArray = try (0 ..< 4).map { _ in
            let typeRawValue = try reader.read(UInt8.self)
            let thickness = try reader.read(UInt8.self)
            let color = HwpColor(try reader.read(UInt32.self))
            return HwpBorderLine(typeRawValue: typeRawValue, thickness: thickness, color: color)
        }
        borderType = borderLineArray.map(\.typeRawValue)
        borderThickness = borderLineArray.map(\.thickness)
        borderColor = borderLineArray.map(\.color)
        diagonalType = try reader.read(UInt8.self)
        diagonalThickness = try reader.read(UInt8.self)
        diagonalColor = HwpColor(try reader.read(UInt32.self))
        fillInfo = try reader.readToEnd().bytes
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - restores complete rawPayload after fillInfo preservation

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

public extension HwpBorderFill {
    /** 채우기 정보 (표 28)를 해석한 값. 단색 채우기 배경색 접근용. */
    var fill: HwpFillInfo? {
        HwpFillInfo.decode(from: Data(fillInfo), at: 0)
    }

    /** 표 26 테두리선 굵기 index → mm 값 */
    static let borderThicknessMillimeters: [Double] = [
        0.1, 0.12, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5,
        0.6, 0.7, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0,
    ]

    /// 테두리선 굵기 index를 point로 변환한다 (1 mm = 72/25.4 pt).
    static func borderThicknessPoints(at index: UInt8) -> Double {
        let millimeters = Int(index) < borderThicknessMillimeters.count
            ? borderThicknessMillimeters[Int(index)]
            : borderThicknessMillimeters[0]
        return millimeters * 72.0 / 25.4
    }
}

extension HwpBorderFill {
    init(fillInfo: [BYTE]) {
        rawPayload = Data()
        property = 0
        borderLineArray = Array(repeating: HwpBorderLine(), count: 4)
        borderType = borderLineArray.map(\.typeRawValue)
        borderThickness = borderLineArray.map(\.thickness)
        borderColor = borderLineArray.map(\.color)
        diagonalType = 1
        diagonalThickness = 0
        diagonalColor = HwpColor()
        self.fillInfo = fillInfo
    }
}

/**
 테두리/배경의 한 방향 테두리선 정보
 */
public struct HwpBorderLine: HwpPrimitive {
    /** 테두리선 종류 raw 값 */
    public let typeRawValue: UInt8
    /** 테두리선 종류 */
    public let type: HwpBorderType?
    /** 테두리선 굵기 */
    public let thickness: UInt8
    /** 테두리선 색상 */
    public let color: HwpColor
}

public extension HwpBorderLine {
    init(typeRawValue: UInt8 = 0, thickness: UInt8 = 0, color: HwpColor = HwpColor(0, 0, 0)) {
        self.typeRawValue = typeRawValue
        type = HwpBorderType(rawValue: Int(typeRawValue))
        self.thickness = thickness
        self.color = color
    }
}
