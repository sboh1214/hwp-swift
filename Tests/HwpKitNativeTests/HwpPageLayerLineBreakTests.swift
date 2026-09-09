import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 한 줄 끝(10) 표식 run은 글리프를 그리지 않는다 (#146).
///
/// 표식이 글리프를 실제로 가리는지는 폰트와 무관하게 재야 한다 — U+000A에 잉크
/// 있는 글리프를 가진 HY 계열 폰트는 한컴오피스 번들에만 있어 CI에는 없다. 그래서
/// 잉크가 확실한 글자에 표식을 붙여 그 자리가 비는지 보고, 실물 폰트 시나리오는
/// 한컴 폰트 opt-in(`HWP_HANCOM_FONTS=1`)에서만 한 번 더 잠근다.
final class HwpPageLayerLineBreakTests: XCTestCase {
    private static let scale: CGFloat = 4

    private struct Raster {
        let data: [UInt8]
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int

        /// 어두운(r·g·b 모두 128 미만) 픽셀 수.
        var darkPixels: Int {
            var count = 0
            for y in 0 ..< pixelHeight {
                for x in 0 ..< pixelWidth {
                    let offset = y * bytesPerRow + x * 4
                    if data[offset] < 128, data[offset + 1] < 128, data[offset + 2] < 128 {
                        count += 1
                    }
                }
            }
            return count
        }
    }

    private static func attributes(
        font: CTFont, lineBreak: Bool = false, underline: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1),
        ]
        if lineBreak {
            attributes[HwpAttributedStringKey.lineBreak] = NSNumber(value: true)
        }
        if underline {
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
        }
        return attributes
    }

    private func render(_ text: NSAttributedString) throws -> Raster {
        let width = 240.0
        let height = 80.0
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.pageHeight = height
        layer.paintList = HwpPaintList(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ),
            .drawText(attributedString: text, origin: CGPoint(x: 10, y: 10), lineWidth: 220),
        ])

        let pixelWidth = Int(width * Self.scale)
        let pixelHeight = Int(height * Self.scale)
        // 픽셀 버퍼는 CGContext가 소유하게 둔다 (`data: nil`) — Array의
        // `withUnsafeMutableBytes` 포인터는 클로저 안에서만 유효해서, 그 포인터로
        // 만든 컨텍스트에 밖에서 그리면 미정의 동작이다.
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: Self.scale, y: Self.scale)
        layer.draw(in: context)
        let bytesPerRow = context.bytesPerRow
        let pixels = try XCTUnwrap(context.data)
        let data = [UInt8](UnsafeRawBufferPointer(
            start: pixels, count: bytesPerRow * pixelHeight
        ))
        return Raster(
            data: data, pixelWidth: pixelWidth, pixelHeight: pixelHeight, bytesPerRow: bytesPerRow
        )
    }

    /// 장평 매트릭스를 실은 글꼴 — 조판은 장평(`faceScaleX`)과 기울임 근사를 CTFont
    /// 매트릭스로 싣는다. run 단위 그리기 경로가 이 매트릭스를 잃으면 글리프가
    /// 장평 없이 넓게 그려지므로, 두 경로의 픽셀 동치는 이 글꼴로 잰다.
    private static func condensedMenlo(size: CGFloat) -> CTFont {
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        var matrix = CGAffineTransform(scaleX: 0.8, y: 1)
        return CTFontCreateCopyWithAttributes(font, 0, &matrix, nil)
    }

    /// 표식 run은 글리프를 그리지 않되 같은 줄의 다른 run(글리프·밑줄)은 그대로다.
    /// 잉크가 확실한 'X'에 표식을 붙여 폰트와 무관하게 잰다.
    func testMarkedRunDrawsNoGlyphWhileNeighborsStillDraw() throws {
        let font = Self.condensedMenlo(size: 20)
        let plain = NSAttributedString(
            string: "A", attributes: Self.attributes(font: font, underline: true)
        )
        let marked = NSMutableAttributedString(attributedString: plain)
        marked.append(NSAttributedString(
            string: "X", attributes: Self.attributes(font: font, lineBreak: true)
        ))
        let unmarked = NSMutableAttributedString(attributedString: plain)
        unmarked.append(NSAttributedString(string: "X", attributes: Self.attributes(font: font)))

        let plainInk = try render(plain).darkPixels
        expect(plainInk).to(beGreaterThan(0))
        // 표식 없는 'X'는 잉크를 더한다 — 표식이 그 잉크를 없앤다는 대조군.
        expect(try self.render(unmarked).darkPixels).to(beGreaterThan(plainInk))
        // 표식 run이 있으면 줄이 run 단위 경로로 바뀌는데, 'A'의 글리프와 밑줄은
        // CTLineDraw 경로와 같은 픽셀로 남아야 한다.
        expect(try self.render(marked).darkPixels) == plainInk
    }

    /// run 단위 경로(`drawRun`)는 CTLineDraw와 픽셀이 같아야 한다 — CTRunDraw는 run의
    /// 텍스트 매트릭스(장평·기울임 근사)를 자동으로 적용하지 않으므로 렌더러가 직접
    /// 맞춘다. 빠지면 장평 80% 글꼴이 이 경로에서만 본래 폭으로 그려져 잉크가 는다
    /// (legacy 각주 실측: 장평 95%에서 +8.5%). 표식 줄뿐 아니라 그림자·양각·글자
    /// 위치 줄도 같은 경로라 같은 계약이다.
    func testPerRunDrawingKeepsTheRunTextMatrix() throws {
        let font = Self.condensedMenlo(size: 20)
        let plain = NSAttributedString(string: "MMMM", attributes: Self.attributes(font: font))
        // 글자 위치 0은 배치를 바꾸지 않으면서 run 단위 경로만 켠다.
        let perRun = NSMutableAttributedString(attributedString: plain)
        perRun.addAttribute(
            HwpAttributedStringKey.glyphBaselineOffset, value: NSNumber(value: 0.0),
            range: NSRange(location: 0, length: 1)
        )
        let wide = NSAttributedString(
            string: "MMMM",
            attributes: Self.attributes(font: CTFontCreateWithName("Menlo" as CFString, 20, nil))
        )

        let plainInk = try render(plain).darkPixels
        expect(plainInk).to(beGreaterThan(0))
        expect(try self.render(perRun).darkPixels) == plainInk
        // 장평이 실제로 걸렸는지 — 매트릭스 없는 같은 글꼴은 더 넓어 잉크가 다르다.
        expect(try self.render(wide).darkPixels) != plainInk
    }

    /// 실물 시나리오 — 라틴 슬롯 HY울릉도M은 U+000A에 잉크 있는 글리프를 갖는다
    /// (이슈 #146 재현). 표식 run으로 낸 한 줄 끝은 그 잉크를 남기지 않는다.
    /// 한컴오피스 번들 폰트라 `HWP_HANCOM_FONTS=1` opt-in 기기에서만 돈다.
    func testHancomLatinFontLineBreakGlyphIsSuppressed() throws {
        try XCTSkipUnless(
            HwpInstalledHancomFonts.isEnabled,
            "HWP_HANCOM_FONTS=1 opt-in 전용 — HY울릉도M은 한컴오피스 번들 폰트다"
        )
        let resolver = HwpFontResolver(usesInstalledHancomFonts: true)
        let font = resolver.resolve(faceName: "HY울릉도M", script: .english, size: 15)
        try XCTSkipUnless(
            CTFontCopyPostScriptName(font) as String == "HYwulM",
            "한컴 번들에서 HY울릉도M을 찾지 못함"
        )
        let body = NSAttributedString(string: "구 분", attributes: Self.attributes(font: font))
        let drawnBreak = NSMutableAttributedString(attributedString: body)
        drawnBreak.append(NSAttributedString(
            string: "\u{000A}", attributes: Self.attributes(font: font)
        ))
        let markedBreak = NSMutableAttributedString(attributedString: body)
        markedBreak.append(NSAttributedString(
            string: "\u{000A}", attributes: Self.attributes(font: font, lineBreak: true)
        ))

        let bodyInk = try render(body).darkPixels
        expect(bodyInk).to(beGreaterThan(0))
        // 전제 확인: 이 폰트로 개행 글리프를 그리면 조판 부호 잉크가 실제로 더해진다.
        expect(try self.render(drawnBreak).darkPixels).to(beGreaterThan(bodyInk))
        expect(try self.render(markedBreak).darkPixels) == bodyInk
    }
}
