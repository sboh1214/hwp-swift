import Foundation

/**
 미리보기 텍스트

 PrvText 스트림에는 미리보기 텍스트가 유니코드 문자열로 저장된다.
 */
public struct HwpPreviewText: HwpFromData {
    public let text: String
    public let rawPayload: Data

    public init() {
        text = "\r\n"
        rawPayload = Data([0x0D, 0x00, 0x0A, 0x00])
    }

    public init(rawPayload: Data) throws {
        guard rawPayload.count.isMultiple(of: MemoryLayout<WCHAR>.size) else {
            throw HwpError.invalidDataForString(data: rawPayload, name: "PreviewText")
        }

        let characters: [WCHAR]
        do {
            characters = try rawPayload.littleEndianWCHARArray
        } catch {
            throw HwpError.invalidDataForString(data: rawPayload, name: "PreviewText")
        }
        do {
            text = try characters.string
        } catch {
            throw HwpError.invalidDataForString(data: rawPayload, name: "PreviewText")
        }
        self.rawPayload = rawPayload
    }

    init(_ reader: inout DataReader) throws {
        try self.init(rawPayload: reader.readToEnd())
    }
}

private extension Data {
    var littleEndianWCHARArray: [WCHAR] {
        get throws {
            try stride(from: 0, to: count, by: MemoryLayout<WCHAR>.size).map { offset in
                try readLittleEndianUInt16(at: offset)
            }
        }
    }
}
