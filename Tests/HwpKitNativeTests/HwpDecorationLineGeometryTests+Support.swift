import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import XCTest

// `HwpDecorationLineGeometryTests`의 래스터·측정 헬퍼 — 테스트 본문과 분리해
// 타입 길이를 지킨다 (SwiftLint type_body_length 300).

extension HwpDecorationLineGeometryTests {
    struct Raster {
        let data: [UInt8]
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int
    }

    /// 조건에 맞는 픽셀이 3개를 넘는 행들의 잉크 가중 중심 (pt, 위에서부터).
    static func rowCenter(
        _ raster: Raster,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> CGFloat? {
        var weighted = 0.0
        var total = 0.0
        for y in 0 ..< raster.pixelHeight {
            var count = 0
            for x in 0 ..< raster.pixelWidth {
                let offset = y * raster.bytesPerRow + x * 4
                if match(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                ) {
                    count += 1
                }
            }
            guard count > 2 else { continue }
            weighted += Double(y) * Double(count)
            total += Double(count)
        }
        guard total > 0 else { return nil }
        // 픽셀 중심 보정: 행 y가 덮는 구간은 [y, y+1)이다.
        return (CGFloat(weighted / total) + 0.5) / scale
    }

    /// 색 선의 두께 (pt) — 세로 한 열의 커버리지 합. 선이 지나는 열(어느 행이든
    /// 채널이 200 아래로 내려간 열)들의 **중앙값**을 돌려주므로 run 양 끝의
    /// 안티앨리어싱은 무시된다. 커버리지는 흰 바탕(255) 대비 `channel`(선 색에서
    /// 가장 낮은 채널)의 감소량을 그 열의 최솟값(선 중심 = 완전 커버)으로 정규화한
    /// 값이다 — 색 공간 변환으로 선 색 채널이 정확히 0이 아니어도 합이 두께가
    /// 된다. 축 정렬 사각형은 CG가 면적 그대로 덮으므로 커버리지 합이 곧 두께다.
    static func lineThickness(
        _ raster: Raster,
        channel: (UInt8, UInt8, UInt8) -> UInt8
    ) -> CGFloat? {
        var sums: [Double] = []
        for x in 0 ..< raster.pixelWidth {
            var values: [Double] = []
            for y in 0 ..< raster.pixelHeight {
                let offset = y * raster.bytesPerRow + x * 4
                values.append(Double(channel(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )))
            }
            guard let full = values.min(), full < 200 else { continue }
            sums.append(values.reduce(0) { $0 + (255 - $1) / (255 - full) })
        }
        guard !sums.isEmpty else { return nil }
        sums.sort()
        return CGFloat(sums[sums.count / 2]) / scale
    }

    /// 빈칸만으로 된 두 run(작게 청록 + 크게 자홍)에 선을 그려 두께를 잰다 — 글리프
    /// 잉크가 없으므로 열의 잉크는 선뿐이다. 청록은 R 채널, 자홍은 G 채널이 0이라
    /// 서로의 열을 오염시키지 않는다 (흰 바탕에서 청록 열의 G·B, 자홍 열의 R·B는
    /// 255 그대로다).
    func thicknessProbe(
        attributes: (CGFloat, CGColor) -> [NSAttributedString.Key: Any]
    ) throws -> Probe {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "    ", attributes: attributes(Self.smallSize, cyan)
        ))
        text.append(NSAttributedString(
            string: "    ", attributes: attributes(Self.largeSize, magenta)
        ))
        let raster = try render(text: text)
        return try Probe(
            small: XCTUnwrap(Self.lineThickness(raster) { red, _, _ in red }, "작은 선"),
            large: XCTUnwrap(Self.lineThickness(raster) { _, green, _ in green }, "큰 선")
        )
    }

    /// 크기만 다른 두 run("AA " 작게 + "BB" 크게)을 한 줄에 그린 래스터.
    func render(
        attributes: (CGFloat, CGColor) -> [NSAttributedString.Key: Any]
    ) throws -> Raster {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "AA ", attributes: attributes(Self.smallSize, cyan)
        ))
        text.append(NSAttributedString(
            string: "BB", attributes: attributes(Self.largeSize, magenta)
        ))
        return try render(text: text)
    }

    func render(text: NSAttributedString) throws -> Raster {
        let width = 240.0
        let height = 120.0
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.pageHeight = height
        layer.paintList = HwpPaintList(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ),
            .drawText(attributedString: text, origin: CGPoint(x: 10, y: 20), lineWidth: 200),
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
        // 행 보폭은 CG가 정렬에 맞춰 정하므로 되읽어 쓴다.
        let bytesPerRow = context.bytesPerRow
        let pixels = try XCTUnwrap(context.data)
        let data = [UInt8](UnsafeRawBufferPointer(
            start: pixels, count: bytesPerRow * pixelHeight
        ))
        return Raster(
            data: data, pixelWidth: pixelWidth,
            pixelHeight: pixelHeight, bytesPerRow: bytesPerRow
        )
    }

    /// 두 색 선의 행 중심(pt, 위에서부터)을 돌려준다.
    func probe(
        attributes: (CGFloat, CGColor) -> [NSAttributedString.Key: Any]
    ) throws -> Probe {
        let raster = try render(attributes: attributes)
        return try Probe(
            small: XCTUnwrap(Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }),
            large: XCTUnwrap(Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 })
        )
    }

    func strikethroughAttributes(
        size: CGFloat, color: CGColor, trackChange: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: color,
        ]
        if trackChange {
            attributes[HwpAttributedStringKey.trackChangeStrikethrough] = NSNumber(value: 1)
        }
        return attributes
    }

    func belowUnderlineAttributes(
        size: CGFloat, color: CGColor
    ) -> [NSAttributedString.Key: Any] {
        [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: color,
        ]
    }

    func trackInsertUnderlineAttributes(
        size: CGFloat, color: CGColor
    ) -> [NSAttributedString.Key: Any] {
        [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.trackInsertUnderline: color,
        ]
    }
}
