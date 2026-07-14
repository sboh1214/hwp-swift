import CoreGraphics
import CoreImage
import Foundation
import HwpKitCore

/// 표 107 그림 스타일 (crop/밝기/명암/효과)을 디코딩된 CGImage에 적용한다.
///
/// crop은 `HwpImageRenderStyle.pixelCropRect` (원본 크기 HWPUNIT → 픽셀,
/// 96 DPI 고정)로 `CGImage.cropping`을 수행하고, 밝기/명암/GRAY_SCALE/
/// BLACK_WHITE는 CoreImage 필터로 적용한다. 결과는 호출자
/// (`HwpPageImageProvider`)가 캐시한다.
enum HwpImageStyleRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 스타일을 적용한 이미지를 반환한다. 적용할 것이 없으면 원본 그대로.
    /// originalSize를 주면 (다운샘플된 경우) 원본 좌표계 crop을 스케일한다 (#5).
    static func apply(
        _ style: HwpImageRenderStyle?,
        to image: CGImage,
        originalSize: CGSize? = nil
    ) -> CGImage {
        guard let style else { return image }

        var result = image
        if let cropRect = style.pixelCropRect(
            imageWidth: image.width,
            imageHeight: image.height,
            originalWidth: originalSize.map { Int($0.width.rounded()) },
            originalHeight: originalSize.map { Int($0.height.rounded()) }
        ), let cropped = result.cropping(to: cropRect) {
            result = cropped
        }
        guard style.hasColorAdjustments else { return result }
        return adjusted(result, style: style)
    }

    /// 밝기/명암/효과를 CoreImage로 적용한다. 실패하면 crop까지만 적용된 이미지.
    private static func adjusted(_ image: CGImage, style: HwpImageRenderStyle) -> CGImage {
        var ciImage = CIImage(cgImage: image)

        let colorControls = CIFilter(name: "CIColorControls")
        colorControls?.setValue(ciImage, forKey: kCIInputImageKey)
        // HWP 밝기/명암 -100...100 → CI 밝기 -1...1, 명암 0...2 근사 매핑
        colorControls?.setValue(
            NSNumber(value: Double(style.brightness) / 100),
            forKey: kCIInputBrightnessKey
        )
        colorControls?.setValue(
            NSNumber(value: max(0, 1 + Double(style.contrast) / 100)),
            forKey: kCIInputContrastKey
        )
        colorControls?.setValue(
            NSNumber(value: style.effect == .none ? 1 : 0),
            forKey: kCIInputSaturationKey
        )
        if let output = colorControls?.outputImage {
            ciImage = output
        }

        if style.effect == .blackWhite {
            let threshold = CIFilter(name: "CIColorThreshold")
            threshold?.setValue(ciImage, forKey: kCIInputImageKey)
            threshold?.setValue(NSNumber(value: 0.5), forKey: "inputThreshold")
            if let output = threshold?.outputImage {
                ciImage = output
            }
        }

        guard let rendered = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }
        return rendered
    }
}
