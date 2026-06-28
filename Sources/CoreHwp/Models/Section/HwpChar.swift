import Foundation

public struct HwpChar: HwpPrimitive {
    public let type: HwpCharType
    public let value: WCHAR
    @ExcludeEquatable
    public var payload: Data?
    @ExcludeEquatable
    public var inlineControl: HwpInlineControl?

    public init(type: HwpCharType, value: WCHAR, payload: Data? = nil) {
        self.type = type
        self.value = value
        self.payload = payload
        inlineControl = payload.map(HwpInlineControl.init(rawPayload:))
    }
}

public enum HwpCharType: String, Codable {
    case char
    case inline
    case extended
}

public struct HwpInlineControl: HwpPrimitive {
    public let rawPayload: Data
    public let rawControlId: UInt32?
    public let rawTrailing: Data
    public let commonCtrlId: HwpCommonCtrlId?
    public let otherCtrlId: HwpOtherCtrlId?
    public let fieldCtrlId: HwpFieldCtrlId?

    public var ctrlIdName: String {
        if let commonCtrlId {
            return String(describing: commonCtrlId)
        }
        if let otherCtrlId {
            return String(describing: otherCtrlId)
        }
        if let fieldCtrlId {
            return String(describing: fieldCtrlId)
        }
        return "unknown"
    }

    public init(rawPayload: Data) {
        self.rawPayload = rawPayload
        rawControlId = Self.controlId(from: rawPayload)
        if rawPayload.count > MemoryLayout<UInt32>.size {
            rawTrailing = Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        } else {
            rawTrailing = Data()
        }
        commonCtrlId = rawControlId.flatMap(HwpCommonCtrlId.init(rawValue:))
        otherCtrlId = rawControlId.flatMap(HwpOtherCtrlId.init(rawValue:))
        fieldCtrlId = rawControlId.flatMap(HwpFieldCtrlId.init(rawValue:))
    }

    private static func controlId(from payload: Data) -> UInt32? {
        guard payload.count >= MemoryLayout<UInt32>.size else {
            return nil
        }
        do {
            return try payload.readLittleEndianUInt32(at: 0)
        } catch {
            return nil
        }
    }
}
