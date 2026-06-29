import Foundation

/**
 미리보기 이미지

 PrvImage 스트림에는 미리보기 이미지가 BMP, GIF, PNG, JPEG 형식으로 저장된다.
 */
public struct HwpPreviewImage: HwpFromData {
    public let rawPayload: Data
    public let image: Data
    public let format: HwpPreviewImageFormat

    public init(rawPayload: Data = Data()) {
        self.rawPayload = rawPayload
        image = rawPayload
        format = HwpPreviewImageFormat(data: rawPayload)
    }

    // MARK: loader contract exemption - PrvImage stream is preserved as raw image payload

    init(_ reader: inout DataReader) throws {
        self.init(rawPayload: try reader.readToEnd())
    }
}

public enum HwpPreviewImageFormat: String, HwpPrimitive {
    case none
    case bmp
    case gif
    case png
    case jpeg
    case unknown
}

private extension HwpPreviewImageFormat {
    init(data: Data) {
        if data.isEmpty {
            self = .none
        } else if data.starts(with: [0x42, 0x4D]) {
            self = .bmp
        } else if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            self = .gif
        } else if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else {
            self = .unknown
        }
    }
}
