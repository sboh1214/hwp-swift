import Foundation

public struct HwpForbiddenChar {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public let data: Data
    public let unknownChildren: [HwpUnknownRecord]

    public init(
        data: Data,
        rawPayload: Data? = nil,
        unknownChildren: [HwpUnknownRecord] = []
    ) {
        self.rawPayload = rawPayload ?? data
        self.data = data
        self.unknownChildren = unknownChildren
    }
}

extension HwpForbiddenChar: HwpFromData {
    // MARK: loader contract exemption - forbidden-char payload is stored as opaque raw data

    init(_ reader: inout DataReader) throws {
        // data는 typed 값이라 양 모드 동일해야 한다 — off면 분리 복사만.
        data = reader.options.decoupledPayload(try reader.readToEnd())
        rawPayload = reader.options.preservedPayload(data)
        unknownChildren = []
    }
}

extension HwpForbiddenChar: HwpTagValidatedRecord {
    static let expectedTag: HwpDocInfoTag = .forbiddenChar

    // MARK: loader contract exemption - forbidden-char record payload is opaque raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // data는 typed 값이라 양 모드 동일해야 한다 — off면 분리 복사만.
        data = reader.options.decoupledPayload(try reader.readToEnd())
        rawPayload = reader.options.preservedPayload(data)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
