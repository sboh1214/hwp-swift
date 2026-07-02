import Foundation

/**
 개체 공통 속성
 */
public struct HwpCommonCtrlProperty: HwpPrimitive {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** ctrl ID */
    public var commonCtrlId: HwpCommonCtrlId
    /** 속성 */
    public var property: UInt32
    /** 속성 bit field */
    public var propertyInfo: HwpCommonCtrlPropertyInfo
    /** 세로 오프셋 값 */
    public var verticalOffset: HWPUNIT
    /** 가로 오프셋 값 */
    public var horizontalOffset: HWPUNIT
    /** width 오브젝트의 폭 */
    public var width: HWPUNIT
    /** height 오브젝트의 높이 */
    public var height: HWPUNIT
    /** z-order */
    public var zOrder: Int32
    /** 오브젝트의 바깥 4방향 여백 */
    public var marginArray: [HWPUNIT16]
    /** 문서 내 각 개체에 대한 고유 아이디(instance ID) */
    public var instanceId: UInt32
    /** 쪽나눔 방지 on(1) / off(0) */
    public var isDividablePage: Bool
    /** 개체 설명문 길이 */
    public var objectDescriptionLength: WORD?
    /** 개체 설명문 글자 */
    public var objectDescription: String
    /** 개체 설명문 원문 WCHAR payload */
    @ExcludeEquatable
    public var objectDescriptionRawPayload: Data

    public init(commonCtrlId: HwpCommonCtrlId = .equation) {
        rawPayload = Data()
        self.commonCtrlId = commonCtrlId
        property = 0
        propertyInfo = HwpCommonCtrlPropertyInfo()
        verticalOffset = 0
        horizontalOffset = 0
        width = 0
        height = 0
        zOrder = 0
        marginArray = [0, 0, 0, 0]
        instanceId = 0
        isDividablePage = false
        objectDescriptionLength = nil
        objectDescription = ""
        objectDescriptionRawPayload = Data()
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let ctrlId = try reader.read(UInt32.self)
        if let commonCtrlId = HwpCommonCtrlId(rawValue: ctrlId) {
            self.commonCtrlId = commonCtrlId
        } else {
            throw HwpError.invalidCtrlId(ctrlId: ctrlId)
        }

        property = try reader.read(UInt32.self)
        propertyInfo = try HwpCommonCtrlPropertyInfo.load(property)
        verticalOffset = try reader.read(HWPUNIT.self)
        horizontalOffset = try reader.read(HWPUNIT.self)
        width = try reader.read(HWPUNIT.self)
        height = try reader.read(HWPUNIT.self)
        zOrder = try reader.read(Int32.self)
        marginArray = try (0 ..< 4).map { _ in try reader.read(HWPUNIT16.self) }
        instanceId = try reader.read(UInt32.self)
        guard reader.remainBytes > 0 else {
            isDividablePage = false
            objectDescriptionLength = nil
            objectDescription = ""
            objectDescriptionRawPayload = Data()
            rawPayload = try reader.consumedData(from: startOffset)
            return
        }
        guard reader.remainBytes >= MemoryLayout<Int32>.size else {
            throw HwpError.truncatedData(
                expected: MemoryLayout<Int32>.size,
                actual: reader.remainBytes
            )
        }
        isDividablePage = try reader.read(Int32.self) == 1 ? true : false

        guard reader.remainBytes > 0 else {
            objectDescriptionLength = nil
            objectDescription = ""
            objectDescriptionRawPayload = Data()
            rawPayload = try reader.consumedData(from: startOffset)
            return
        }
        let objectDescriptionLength = try reader.read(WORD.self)
        self.objectDescriptionLength = objectDescriptionLength
        let objectDescriptionStartOffset = reader.byteOffset
        let objectDescriptionCharacters = try reader.read(WCHAR.self, objectDescriptionLength)
        objectDescriptionRawPayload = try reader.consumedData(from: objectDescriptionStartOffset)
        objectDescription = try objectDescriptionCharacters.string
        rawPayload = try reader.consumedData(from: startOffset)
    }
}
