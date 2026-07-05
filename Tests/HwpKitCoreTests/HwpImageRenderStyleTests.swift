import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpImageRenderStyleTests: XCTestCase {
    func testFullCropRectFromBinDataConventionIsNoCrop() {
        // BinData 픽스처: 1920×1080 px, crop (0,0,144000,81000) = 픽셀 × 75 정확 일치
        let style = HwpImageRenderStyle(cropRight: 144_000, cropBottom: 81000)
        expect(style.pixelCropRect(imageWidth: 1920, imageHeight: 1080)).to(beNil())
    }

    func testNooriCropValuesRoundToFullImage() {
        // noori 픽스처: 1200×153 px, crop (0,0,90000,11460)
        // 90000/75 = 1200, 11460/75 = 152.8 → 153 반올림 → 전체 (crop 없음)
        let style = HwpImageRenderStyle(cropRight: 90000, cropBottom: 11460)
        expect(style.pixelCropRect(imageWidth: 1200, imageHeight: 153)).to(beNil())
    }

    func testPartialCropProducesPixelRect() {
        // 4×2 이미지에서 왼쪽 2×2 (crop 150×150 HWPUNIT = 2×2 px)
        let style = HwpImageRenderStyle(cropRight: 150, cropBottom: 150)
        let rect = style.pixelCropRect(imageWidth: 4, imageHeight: 2)
        expect(rect) == CGRect(x: 0, y: 0, width: 2, height: 2)
    }

    func testCropOffsetsAndClampingToImageBounds() {
        // (75, 0) ~ (600, 600) → x 1..8 clamp → 1..4, y 0..2
        let style = HwpImageRenderStyle(
            cropLeft: 75,
            cropTop: 0,
            cropRight: 600,
            cropBottom: 600
        )
        let rect = style.pixelCropRect(imageWidth: 4, imageHeight: 2)
        expect(rect) == CGRect(x: 1, y: 0, width: 3, height: 2)
    }

    func testDegenerateCropReturnsNil() {
        expect(
            HwpImageRenderStyle().pixelCropRect(imageWidth: 4, imageHeight: 2)
        ).to(beNil())
        expect(
            HwpImageRenderStyle(cropLeft: 150, cropRight: 75)
                .pixelCropRect(imageWidth: 4, imageHeight: 2)
        ).to(beNil())
        expect(
            HwpImageRenderStyle(cropRight: 150, cropBottom: 150)
                .pixelCropRect(imageWidth: 0, imageHeight: 0)
        ).to(beNil())
    }

    func testColorAdjustmentFlags() {
        expect(HwpImageRenderStyle().hasColorAdjustments) == false
        expect(HwpImageRenderStyle(brightness: 30).hasColorAdjustments) == true
        expect(HwpImageRenderStyle(contrast: -20).hasColorAdjustments) == true
        expect(HwpImageRenderStyle(effect: .grayscale).hasColorAdjustments) == true
        expect(HwpImageEffect(rawEffect: 4)) == HwpImageEffect.none // PATTERN8x8 미지원 → 원본
    }
}
