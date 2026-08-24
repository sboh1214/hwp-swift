import Foundation

public struct HwpCtrlHeader {
    public var ctrlId: UInt32
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    public init(ctrlId: UInt32, rawPayload: Data) {
        self.ctrlId = ctrlId
        self.rawPayload = rawPayload
        unknownChildren = []
    }

    public init(ctrlId: UInt32, rawPayload: Data, unknownChildren: [HwpUnknownRecord]) {
        self.ctrlId = ctrlId
        self.rawPayload = rawPayload
        self.unknownChildren = unknownChildren
    }
}

extension HwpCtrlHeader: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .ctrlHeader
    /// 커스텀 load 시절 EOF를 검사하지 않던 현행 동작 보존 (#83) —
    /// init이 payload를 전부 소비하므로 강제 전환은 후속 이슈에서 켠다.
    static let enforcesEOF = false

    // MARK: loader contract exemption - malformed ctrl header still preserves raw payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        do {
            ctrlId = try reader.read(UInt32.self)
        } catch HwpError.truncatedData {
            ctrlId = 0
        }
        _ = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
