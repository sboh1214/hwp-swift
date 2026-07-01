import Foundation

struct HwpFieldParameterParseResult {
    let value: String
    let characterCount: Int
    let isByteSwapped: Bool
    let rawPayload: Data
    let rawTrailing: Data
}

struct HwpFieldParameterLengthCandidate {
    let characterCount: Int
    let isByteSwapped: Bool
}

struct HwpFieldParameterLengthInfo {
    let characterCount: Int?
    let rawPayload: Data
}

struct HwpFieldControlPayloadParseResult {
    let properties: UInt32
    let propertiesRawPayload: Data
    let extraProperties: UInt8
    let extraPropertiesRawPayload: Data
    let commandLengthRawPayload: Data
    let command: HwpFieldParameterParseResult
    let fieldId: UInt32
    let fieldIdRawPayload: Data
    let memoIndex: Int32
    let memoIndexRawPayload: Data
}

struct HwpFieldControlPayloadOffsets {
    let properties: Int
    let extraProperties: Int
    let commandLength: Int
    let fieldId: Int
    let memoIndex: Int
}

extension HwpMemoFieldParameter {
    init?(_ rawValue: String, rawPayload: Data, rawTrailing: Data) {
        let components = rawValue
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let marker = components.first, marker == "MEMO" else {
            return nil
        }
        self.init(
            rawValue: rawValue,
            rawPayload: rawPayload,
            components: components,
            marker: marker,
            fields: Array(components.dropFirst()),
            author: components.indices.contains(5) ? components[5] : nil,
            rawTrailing: rawTrailing
        )
    }
}
