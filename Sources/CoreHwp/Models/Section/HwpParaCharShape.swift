import Foundation

/**
 문단의 글자 모양

 Tag ID : HWPTAG_PARA_CHAR_SHAPE
 */
public struct HwpParaCharShape: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 글자 모양이 바뀌는 시작 위치 */
    public var startingIndex: [UInt32]
    /** 글자 모양 ID */
    public var shapeId: [UInt32]

    init() {
        rawPayload = Data()
        startingIndex = [0]
        shapeId = [0]
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        var startingIndex = [UInt32]()
        var shapeId = [UInt32]()
        while !reader.isEOF {
            startingIndex.append(try reader.read(UInt32.self))
            shapeId.append(try reader.read(UInt32.self))
        }
        if let firstStartingIndex = startingIndex.first, firstStartingIndex != 0 {
            throw HwpError.invalidRecordTree(
                reason:
                "paragraph char shape first starting index must be 0, got \(firstStartingIndex)"
            )
        }
        self.startingIndex = startingIndex
        self.shapeId = shapeId
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var paraCharShape = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        paraCharShape.rawPayload = data
        return paraCharShape
    }
}
