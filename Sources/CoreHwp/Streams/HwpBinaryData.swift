import Foundation

/**
 바이너리 데이터

 BinData 스토리지에는 그림이나 OLE 개체와 같이 문서에 첨부된 바이너리 데이터가 각각의 스트림으로 저장된다.
 */
public struct HwpBinaryData: HwpPrimitive {
    /** BinData 스토리지 안의 원본 stream 이름 */
    public let name: String
    /** BinData stream 이름에서 추출한 stream id */
    public let streamId: UInt16?
    /** BinData stream 이름에서 추출한 확장자 */
    public let extensionName: String?
    /** BinData stream의 payload. 압축된 BinData는 압축 해제된 payload를 저장한다. */
    public let data: Data

    public init() {
        name = ""
        streamId = nil
        extensionName = nil
        data = Data()
    }

    public init(name: String, data: Data) {
        self.name = name
        let metadata = Self.metadata(from: name)
        streamId = metadata.streamId
        extensionName = metadata.extensionName
        self.data = data
    }
}

extension HwpBinaryData {
    static func metadata(from name: String) -> (streamId: UInt16?, extensionName: String?) {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let streamName = parts.first,
              let extensionPart = parts.last
        else {
            return (nil, nil)
        }

        guard streamName.hasPrefix("BIN") else {
            return (nil, nil)
        }

        // Stream 이름의 id는 16진수 4자리이다 (BIN%04X.ext).
        let digits = streamName.dropFirst(3)
        guard digits.count == 4,
              digits.allSatisfy(\.isASCIIHexDigit),
              let streamId = UInt16(digits, radix: 16)
        else {
            return (nil, nil)
        }

        let extensionName = String(extensionPart)
        guard !extensionName.isEmpty else {
            return (nil, nil)
        }

        return (streamId, extensionName)
    }
}

private extension Character {
    var isASCIIHexDigit: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return false }
        return (0x30 ... 0x39).contains(scalar.value)
            || (0x41 ... 0x46).contains(scalar.value)
            || (0x61 ... 0x66).contains(scalar.value)
    }
}
