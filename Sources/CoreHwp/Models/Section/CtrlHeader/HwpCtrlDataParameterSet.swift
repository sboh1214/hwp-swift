import Foundation

/** 컨트롤 데이터 ParameterSet */
public struct HwpCtrlDataParameterSet: HwpPrimitive {
    /** ParameterSet ID */
    public var parameterSetId: UInt16
    /** ParameterSet ID 원문 payload */
    public var parameterSetIdRawPayload: Data
    /** item 개수 */
    public var itemCount: UInt16
    /** item 개수 원문 payload */
    public var itemCountRawPayload: Data
    /** 알려진 문자열 item */
    public var stringItem: HwpCtrlDataParameterStringItem

    init?(_ payload: Data) {
        do {
            guard payload.count >= Self.stringItemOffset else {
                return nil
            }

            let parameterSetId = try payload.readLittleEndianUInt16(at: 0)
            let itemCount = try payload.readLittleEndianUInt16(at: 2)
            guard parameterSetId == Self.fieldNameParameterSetId,
                  itemCount == 1,
                  let stringItem = HwpCtrlDataParameterStringItem(
                      payload,
                      offset: Self.stringItemOffset
                  )
            else {
                return nil
            }

            self.parameterSetId = parameterSetId
            parameterSetIdRawPayload = Data(payload.prefix(MemoryLayout<UInt16>.size))
            self.itemCount = itemCount
            itemCountRawPayload = Data(
                payload
                    .dropFirst(MemoryLayout<UInt16>.size)
                    .prefix(MemoryLayout<UInt16>.size)
            )
            self.stringItem = stringItem
        } catch {
            return nil
        }
    }

    private static let fieldNameParameterSetId: UInt16 = 0x021B
    private static let stringItemOffset = 4
}

/** 컨트롤 데이터 ParameterSet의 문자열 item */
public struct HwpCtrlDataParameterStringItem: HwpPrimitive {
    /** item ID 원문 UInt32 값 */
    public var itemId: UInt32
    /** item ID 원문 payload */
    public var itemIdRawPayload: Data
    /** value type */
    public var valueType: UInt16
    /** value type 원문 payload */
    public var valueTypeRawPayload: Data
    /** 문자열 길이 */
    public var valueCharacterCount: Int
    /** 문자열 길이 WORD 원문 payload */
    public var valueLengthRawPayload: Data
    /** 문자열 값 */
    public var value: String
    /** 문자열 WCHAR 원문 payload */
    public var valueRawPayload: Data
    /** 문자열 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data

    init?(_ payload: Data, offset: Int) {
        do {
            let itemIdOffset = offset
            let valueTypeOffset = itemIdOffset + MemoryLayout<UInt32>.size
            let lengthOffset = valueTypeOffset + MemoryLayout<UInt16>.size
            let valueOffset = lengthOffset + MemoryLayout<WORD>.size
            guard payload.count >= valueOffset else {
                return nil
            }

            let itemId = try payload.readLittleEndianUInt32(at: itemIdOffset)
            let valueType = try payload.readLittleEndianUInt16(at: valueTypeOffset)
            guard itemId == Self.fieldNameStringItemId,
                  valueType == Self.stringValueType
            else {
                return nil
            }

            let valueCharacterCount = Int(try payload.readLittleEndianUInt16(at: lengthOffset))
            let valueByteCount = valueCharacterCount * MemoryLayout<WCHAR>.size
            let valueEndOffset = valueOffset + valueByteCount
            guard payload.count >= valueEndOffset else {
                return nil
            }

            let valueChars = try (0 ..< valueCharacterCount).map { index in
                try payload.readLittleEndianUInt16(
                    at: valueOffset + index * MemoryLayout<WCHAR>.size
                )
            }

            self.itemId = itemId
            itemIdRawPayload = Data(
                payload.dropFirst(itemIdOffset).prefix(MemoryLayout<UInt32>.size)
            )
            self.valueType = valueType
            valueTypeRawPayload = Data(
                payload.dropFirst(valueTypeOffset).prefix(MemoryLayout<UInt16>.size)
            )
            self.valueCharacterCount = valueCharacterCount
            valueLengthRawPayload = Data(
                payload.dropFirst(lengthOffset).prefix(MemoryLayout<WORD>.size)
            )
            value = try valueChars.string
            valueRawPayload = Data(payload.dropFirst(valueOffset).prefix(valueByteCount))
            rawTrailing = Data(payload.dropFirst(valueEndOffset))
        } catch {
            return nil
        }
    }

    private static let fieldNameStringItemId: UInt32 = 0x4000_0000
    private static let stringValueType: UInt16 = 1
}
