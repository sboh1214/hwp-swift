import Foundation

/// 문단 텍스트의 문자 하나.
///
/// charArray는 문서 전체 문자 수만큼 이 값을 보유하므로 크기가 곧 상주
/// 메모리다 — 컨트롤 문자 (~수 %)만 갖는 payload를 클래스 박스로 분리해
/// stride를 16바이트로 유지한다 (인라인 임베드 시절 ~80바이트).
/// `inlineControl`은 payload의 순수 파생값이라 저장하지 않고 지연 계산한다.
public struct HwpChar: HwpPrimitive {
    public let type: HwpCharType
    public let value: WCHAR
    /// 컨트롤 문자 payload 박스 — 순수 텍스트 문자는 nil
    private var controlBox: ControlBox?

    /// 컨트롤 문자의 원본 payload (14바이트). 파스 시 섹션 버퍼에서
    /// 분리 복사되므로 charArray가 압축 해제 스트림을 붙잡지 않는다.
    public var payload: Data? {
        get { controlBox?.payload }
        set { controlBox = newValue.map { ControlBox(payload: Data($0)) } }
    }

    /// payload에서 파생한 컨트롤 해석 (controlId·trailing·ctrl enum 조회).
    /// 소비처가 드물어 파스 시 eager 구성 대신 접근 시 계산한다.
    public var inlineControl: HwpInlineControl? {
        controlBox.map { HwpInlineControl(rawPayload: $0.payload) }
    }

    public init(type: HwpCharType, value: WCHAR, payload: Data? = nil) {
        self.type = type
        self.value = value
        controlBox = payload.map { ControlBox(payload: Data($0)) }
    }

    private final class ControlBox: Sendable {
        let payload: Data

        init(payload: Data) {
            self.payload = payload
        }
    }
}

// MARK: - Equatable/Hashable — 종전 @ExcludeEquatable 시맨틱 유지 (type/value만)

public extension HwpChar {
    static func == (lhs: HwpChar, rhs: HwpChar) -> Bool {
        lhs.type == rhs.type && lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(value)
    }
}

// MARK: - Codable — 종전 synthesized 형상 보존

// (payload/inlineControl 키를 ExcludeEquatable 래퍼 {"wrappedValue": …}로 인코딩)

public extension HwpChar {
    private enum CodingKeys: String, CodingKey {
        case type, value, payload, inlineControl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HwpCharType.self, forKey: .type)
        let value = try container.decode(WCHAR.self, forKey: .value)
        let payload = try container.decodeIfPresent(
            ExcludeEquatable<Data?>.self, forKey: .payload
        )?.wrappedValue
        // inlineControl 키는 payload의 파생값이라 읽지 않는다 (재계산 동일)
        self.init(type: type, value: value, payload: payload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(ExcludeEquatable(wrappedValue: payload), forKey: .payload)
        try container.encode(
            ExcludeEquatable(wrappedValue: inlineControl), forKey: .inlineControl
        )
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
