import Foundation

public struct HwpBinDataProperty {
    /** 원본 bit field */
    @ExcludeEquatable
    public var rawValue: UInt16
    /** Type */
    public var type: HwpBinDataType
    /** 압축 */
    public var compressType: HwpBinDataCompressType
    /** 상태 */
    public var state: HwpBinDataState
}

extension HwpBinDataProperty: HwpFromUInt {
    typealias UIntType = UInt16

    init(_ reader: inout BitsReader<UIntType>) throws {
        rawValue = 0
        let typeRawValue = try reader.readInt(4)
        guard let type = HwpBinDataType(rawValue: typeRawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpBinDataType.self,
                rawValue: typeRawValue
            )
        }
        self.type = type

        let compressTypeRawValue = try reader.readInt(2)
        guard let compressType = HwpBinDataCompressType(rawValue: compressTypeRawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpBinDataCompressType.self,
                rawValue: compressTypeRawValue
            )
        }
        self.compressType = compressType

        let stateRawValue = try reader.readInt(2)
        switch stateRawValue {
        case HwpBinDataState.never.rawValue:
            state = .never
        case HwpBinDataState.successed.rawValue:
            state = .successed
        case HwpBinDataState.failed.rawValue:
            state = .failed
        case HwpBinDataState.ignored.rawValue:
            state = .ignored
        default:
            throw HwpError.invalidRawValueForEnum(
                model: HwpBinDataState.self,
                rawValue: stateRawValue
            )
        }

        try reader.readBits(8)
    }

    static func load(_ uint: UIntType) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

extension HwpBinDataProperty {
    init() {
        rawValue = 0
        type = .link
        compressType = .followStorage
        state = .never
    }
}

public enum HwpBinDataType: Int, HwpPrimitive {
    /** LINK. 그림 외부 파일 참조 */
    case link = 0x0
    /** EMBEDDING. 그림 파일 포함 */
    case embedding = 0x1
    /** STORAGE. OLE 포함 */
    case storage = 0x2
}

public enum HwpBinDataCompressType: Int, HwpPrimitive {
    /** 스토리지의 디폴트 모드 따라감 */
    case followStorage = 0x0
    /** 무조건 압축 */
    case always = 0x1
    /** 무조건 압축하지 않음 */
    case never = 0x2
}

public enum HwpBinDataState: Int, HwpPrimitive {
    /** 아직 access 된 적이 없는 상태 */
    case never = 0x0
    /** access에 성공하여 파일을 찾은 상태 */
    case successed = 0x1
    /** access가 실패한 에러 상태 */
    case failed = 0x2
    /** 링크 access가 실패했으나 무시된 상태 */
    case ignored = 0x3
}
