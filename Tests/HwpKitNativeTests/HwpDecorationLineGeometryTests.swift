import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 글자 장식 선(취소선·글자 위 밑줄·글자 아래 밑줄·변경 추적 삭제선)의 세로
/// 위치가 **글자 크기에 비례**한다는 것과 그 비율을 고정한다 (#136).
///
/// 한 줄에 크기가 다른 두 run을 놓으면 베이스라인이 하나로 공유되므로, 두 선의
/// 행 간격이 곧 `비율 × 크기 차`다 — 폰트·조판 구현과 무관하게 비율만 잰다.
/// 절대 위치(실물 문서에서 어느 행에 떨어지는지)는
/// `FixtureDecorationLineRenderTests`가 픽스처로 잡는다.
///
/// 실측 근거는 `HwpRenderTuning.Text`의 각 상수 doc-comment에 있다
/// (한글.app 12.30.0 PDF 내보내기, 2026-09-08).
final class HwpDecorationLineGeometryTests: XCTestCase {
    private static let scale: CGFloat = 8
    private static let smallSize: CGFloat = 20
    private static let largeSize: CGFloat = 40

    private struct Probe {
        let small: CGFloat
        let large: CGFloat
        /// 위 방향(작은 크기 → 큰 크기) 이동량. 베이스라인 **위** 장식이면 양수.
        var rise: CGFloat {
            small - large
        }
    }

    private struct Raster {
        let data: [UInt8]
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int
    }

    /// 조건에 맞는 픽셀이 3개를 넘는 행들의 잉크 가중 중심 (pt, 위에서부터).
    private static func rowCenter(
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

    /// 크기만 다른 두 run("AA " 작게 + "BB" 크게)을 한 줄에 그린 래스터.
    private func render(
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

    private func render(text: NSAttributedString) throws -> Raster {
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
    private func probe(
        attributes: (CGFloat, CGColor) -> [NSAttributedString.Key: Any]
    ) throws -> Probe {
        let raster = try render(attributes: attributes)
        return try Probe(
            small: XCTUnwrap(Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }),
            large: XCTUnwrap(Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 })
        )
    }

    private func strikethroughAttributes(
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

    /// 취소선은 베이스라인 **위** 0.35em이다 — 크기가 2배가 되면 선도 그만큼
    /// 위로 간다. 종전 산식(폰트 x-height의 절반)은 한글 실물보다 낮았다.
    func testStrikethroughRisesWithFontSize() throws {
        let probe = try probe { size, color in
            strikethroughAttributes(size: size, color: color)
        }
        let expected = HwpRenderTuning.Text.strikethroughCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(7.0, within: 0.001))
    }

    /// 변경 추적 삭제선은 같은 취소선 경로를 쓰되 한글이 조금 낮게 그린다
    /// (0.29em) — 일반 취소선과 다른 비율임을 고정한다.
    func testTrackChangeStrikethroughUsesItsOwnRatio() throws {
        let probe = try probe { size, color in
            strikethroughAttributes(size: size, color: color, trackChange: true)
        }
        let expected = HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio)
            < HwpRenderTuning.Text.strikethroughCenterRatio
    }

    /// 밑줄 '글자 위'(표 33 밑줄 종류 3)는 베이스라인 위 0.87em이다.
    func testAboveUnderlineRisesWithFontSize() throws {
        let probe = try probe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        let expected = HwpRenderTuning.Text.underlineAboveCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(17.4, within: 0.001))
    }

    /// 키 큰 인라인 개체가 섞인 줄에서도 '글자 위' 밑줄은 취소선과 같은
    /// 베이스라인을 기준으로 놓인다 — 둘의 간격은 항상 `(0.87 − 0.35) × 크기`다.
    ///
    /// 밑줄 '글자 아래'만 `underlineReturnDrop`으로 되돌린 원점을 쓴다 (실물은
    /// 밑줄을 개체 하단에 남긴다). 그 되돌림을 위쪽 밑줄에도 적용하면 선이
    /// 개체 ascent의 15%만큼 내려가 글자 **아래**로 떨어진다 (100pt 개체 + 10pt
    /// 글자에서 베이스라인 위 8.7pt 대신 아래 6.3pt).
    func testAboveUnderlineIgnoresInlineObjectReturnDrop() throws {
        let size: CGFloat = 10
        let text = NSMutableAttributedString(string: "AA ", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: CGColor(red: 0, green: 1, blue: 1, alpha: 1),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: CGColor(
                red: 1, green: 0, blue: 1, alpha: 1
            ),
        ])
        // 높이 100pt 인라인 개체 — 줄 베이스라인을 끌어올려 되돌림을 켠다.
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { _ in },
            getAscent: { _ in 100 },
            getDescent: { _ in 0 },
            getWidth: { _ in 40 }
        )
        let delegate = try XCTUnwrap(CTRunDelegateCreate(&callbacks, nil))
        text.append(NSAttributedString(string: "\u{FFFC}", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
        ]))

        let raster = try render(text: text)
        let above = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "위쪽 밑줄"
        )
        let strike = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "취소선"
        )
        let expected = (HwpRenderTuning.Text.underlineAboveCenterRatio
            - HwpRenderTuning.Text.strikethroughCenterRatio) * size
        expect(strike - above).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(5.2, within: 0.001))
    }

    /// 밑줄 '글자 아래'는 이번 수정의 대상이 아니다 — 베이스라인 아래 0.20em이
    /// 그대로인지 확인한다 (큰 글자일수록 **아래로** 간다).
    func testBelowUnderlineKeepsItsRatio() throws {
        let probe = try probe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        expect(probe.rise).to(beCloseTo(-0.20 * (Self.largeSize - Self.smallSize), within: 0.2))
    }
}
