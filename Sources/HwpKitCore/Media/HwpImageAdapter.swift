import CoreGraphics
import CoreHwp
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
    /// 디코드 허용 최대 픽셀 수 (폭×높이). 실제 문서 이미지는 이 한도 아래다 —
    /// 작은 압축본이 거대 차원을 선언하는 디코드 폭탄을 디코드 전에 거른다.
    static let maximumPixelCount = 50_000_000

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

        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else {
            return .failure(.decodeFailed(underlying: "CGImageSource failed"))
        }
        // 디코드 폭탄 방어: 선언된 픽셀 차원을 디코드 전에 검사한다. 전체
        // CGImage 생성은 압축 크기와 무관하게 폭×높이×4 만큼 할당하므로,
        // 스트림 크기 한도나 캐시 한도로는 이 과대 할당을 막을 수 없다.
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width * height > Self.maximumPixelCount
        {
            return .failure(.decodeFailed(
                underlying: "image dimensions \(width)x\(height) exceed limit"
            ))
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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
        if header.count >= 4,
           header[0] == 0x89, header[1] == 0x50, header[2] == 0x4E, header[3] == 0x47
        {
            return .success(.png)
        }
        if header.count >= 2, header[0] == 0x42, header[1] == 0x4D {
            return .success(.bmp)
        }
        if header.count >= 4,
           header[0] == 0x47, header[1] == 0x49, header[2] == 0x46, header[3] == 0x38
        {
            return .success(.gif)
        }

        let hex = header.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        return .failure(.unsupportedFormat(hex: hex))
    }
}
