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
    /// 다운샘플 전 선언 원본 픽셀 크기 — 원본 좌표계인 crop을 다운샘플된
    /// 비트맵에 맞게 스케일하는 데 쓴다 (#5). 다운샘플 안 했으면 pixelSize와 같다.
    public let originalPixelSize: CGSize

    public init(
        image: CGImage,
        format: HwpImageFormat,
        pixelSize: CGSize,
        originalPixelSize: CGSize? = nil
    ) {
        self.image = image
        self.format = format
        self.pixelSize = pixelSize
        self.originalPixelSize = originalPixelSize ?? pixelSize
    }
}

public struct HwpImageAdapter {
    /// 디코드 허용 최대 픽셀 수 (폭×높이). 실제 문서 이미지는 이 한도 아래다 —
    /// 작은 압축본이 거대 차원을 선언하는 디코드 폭탄을 디코드 전에 거른다.
    static let maximumPixelCount = 50_000_000

    /// 다운샘플 축 상한 (px). 이 한도를 넘는 이미지는 줄여, 디코드 결과가
    /// 캐시 예산(4096²·4 = 67MB)에 맞아 즉시 축출→재요청 루프가 안 생기게
    /// 한다 (#2). 이 이하는 원본 그대로 디코드해 렌더가 불변이다.
    static let maximumPixelsPerAxis = 4096

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
        // 선언된 픽셀 차원을 디코드 전에 읽어 (전체 CGImage는 압축 크기와 무관하게
        // 폭×높이×4를 할당) 폭탄은 거부하고 큰 이미지는 다운샘플한다.
        let dimensions = Self.pixelDimensions(of: source)
        if let (width, height) = dimensions, width * height > Self.maximumPixelCount {
            return .failure(.decodeFailed(
                underlying: "image dimensions \(width)x\(height) exceed limit"
            ))
        }
        let overAxisCap = dimensions.map {
            $0.0 > Self.maximumPixelsPerAxis || $0.1 > Self.maximumPixelsPerAxis
        } ?? false
        // EXIF orientation이 기본(1)이 아니면 thumbnail transform 경로로 적용한다 —
        // 풀사이즈 경로가 orientation을 무시해, 같은 회전 JPEG이 4096px 다운샘플
        // 임계를 넘느냐에 따라 정상/회전으로 갈리던 것을 막는다 (R50 #5).
        let orientation = Self.orientation(of: source)
        let needsOrientation = orientation != 1
        let cgImage: CGImage
        if overAxisCap || needsOrientation {
            // 축 상한 초과는 캐시 예산에 맞게 줄이고(#2), 그 이하의 회전 이미지는
            // 원본 크기 그대로 orientation만 적용한다(다운샘플 없음).
            let maxDimension = dimensions.map { Swift.max($0.0, $0.1) } ?? Self.maximumPixelsPerAxis
            let maxPixelSize = overAxisCap ? Self.maximumPixelsPerAxis : maxDimension
            guard let processed = Self.orientedImage(source, maxPixelSize: maxPixelSize)
            else {
                return .failure(.decodeFailed(underlying: "downsample failed"))
            }
            cgImage = processed
        } else {
            // 축 상한 이하 + 기본 orientation은 원본 그대로 디코드 (렌더 불변).
            guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return .failure(.decodeFailed(underlying: "CGImageSource failed"))
            }
            cgImage = full
        }

        let pixelSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        // declared dimensions가 crop 좌표계의 원본 크기다(다운샘플 시 cgImage는 축소본).
        // EXIF orientation 5-8은 축을 스왑하므로 cgImage(회전본)와 좌표계를 맞추려면
        // 원본 크기도 스왑한다 — 안 그러면 crop이 회전 비트맵에 어긋난 비율로
        // 스케일된다 (R51 #3). 스왑 없는 orientation(1-4)은 declared 그대로.
        let swapsAxes = orientation >= 5
        let originalPixelSize = dimensions.map { declared in
            CGSize(
                width: CGFloat(swapsAxes ? declared.1 : declared.0),
                height: CGFloat(swapsAxes ? declared.0 : declared.1)
            )
        } ?? pixelSize
        return .success(HwpDecodedImage(
            image: cgImage, format: format,
            pixelSize: pixelSize, originalPixelSize: originalPixelSize
        ))
    }

    /// 소스의 선언된 픽셀 차원 (디코드 전). 없거나 0이면 nil.
    private static func pixelDimensions(of source: CGImageSource) -> (Int, Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    /// 소스의 EXIF orientation (표 TIFF 1-8). 없으면 기본값 1(정방향).
    private static func orientation(of source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = properties[kCGImagePropertyOrientation] as? Int
        else { return 1 }
        return orientation
    }

    /// `maxPixelSize` 이하로 만든 CGImage — EXIF orientation transform을 적용한다
    /// (`kCGImageSourceCreateThumbnailWithTransform`). ImageIO 썸네일은 전체 디코드
    /// 없이 만든다. maxPixelSize를 원본 최대 축으로 주면 다운샘플 없이 회전만 적용된다.
    private static func orientedImage(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
