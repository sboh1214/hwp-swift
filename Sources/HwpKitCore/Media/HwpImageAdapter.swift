import CoreGraphics
@preconcurrency import CoreHwp
import Foundation
import ImageIO

public enum HwpImageFormat: String, Sendable, Hashable {
    case jpeg
    case png
    case bmp
    case gif
}

public enum HwpImageError: Error, Sendable {
    case unsupportedFormat(hex: String)
    case decodeFailed(underlying: String)
    case emptyPayload
}

public struct HwpDecodedImage: Sendable {
    public let image: CGImage
    public let format: HwpImageFormat
    public let pixelSize: CGSize

    public init(image: CGImage, format: HwpImageFormat, pixelSize: CGSize) {
        self.image = image
        self.format = format
        self.pixelSize = pixelSize
    }
}

public struct HwpImageAdapter {
    public init() {}

    public func decode(
        binaryData: CoreHwp.HwpBinaryData,
        hint _: CoreHwp.HwpBinData? = nil
    ) -> Result<HwpDecodedImage, HwpImageError> {
        let bytes = binaryData.data
        return decodeData(bytes)
    }

    func decodeData(_ bytes: Data) -> Result<HwpDecodedImage, HwpImageError> {
        guard !bytes.isEmpty else {
            return .failure(.emptyPayload)
        }

        let formatResult = detectFormat(bytes)
        let format: HwpImageFormat
        switch formatResult {
        case let .success(imageFormat):
            format = imageFormat
        case let .failure(imageError):
            return .failure(imageError)
        }

        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .failure(.decodeFailed(underlying: "CGImageSource failed"))
        }

        let pixelSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return .success(HwpDecodedImage(image: cgImage, format: format, pixelSize: pixelSize))
    }

    private func detectFormat(_ bytes: Data) -> Result<HwpImageFormat, HwpImageError> {
        let header = Array(bytes.prefix(8))

        if header.count >= 3, header[0] == 0xFF, header[1] == 0xD8, header[2] == 0xFF {
            return .success(.jpeg)
        }
        if header.count >= 4, header[0] == 0x89, header[1] == 0x50, header[2] == 0x4E, header[3] == 0x47 {
            return .success(.png)
        }
        if header.count >= 2, header[0] == 0x42, header[1] == 0x4D {
            return .success(.bmp)
        }
        if header.count >= 4, header[0] == 0x47, header[1] == 0x49, header[2] == 0x46, header[3] == 0x38 {
            return .success(.gif)
        }

        let hex = header.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        return .failure(.unsupportedFormat(hex: hex))
    }
}
