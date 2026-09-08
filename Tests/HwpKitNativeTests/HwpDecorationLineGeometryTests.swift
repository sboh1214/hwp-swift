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
        let bytesPerRow = pixelWidth * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        let context = try XCTUnwrap(data.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })
        context.scaleBy(x: Self.scale, y: Self.scale)
        layer.draw(in: context)
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
        let data = raster.data
        let pixelWidth = raster.pixelWidth
        let pixelHeight = raster.pixelHeight
        let bytesPerRow = raster.bytesPerRow

        func center(where match: (UInt8, UInt8, UInt8) -> Bool) throws -> CGFloat {
            var weighted = 0.0
            var total = 0.0
            for y in 0 ..< pixelHeight {
                var count = 0
                for x in 0 ..< pixelWidth {
                    let offset = y * bytesPerRow + x * 4
                    if match(data[offset], data[offset + 1], data[offset + 2]) {
                        count += 1
                    }
                }
                guard count > 2 else { continue }
                weighted += Double(y) * Double(count)
                total += Double(count)
            }
            let found = try XCTUnwrap(total > 0 ? weighted / total : nil)
            // 픽셀 중심 보정: 행 y가 덮는 구간은 [y, y+1)이다.
            return (CGFloat(found) + 0.5) / Self.scale
        }

        return Probe(
            small: try center { $0 < 100 && $1 > 150 && $2 > 150 },
            large: try center { $0 > 150 && $1 < 100 && $2 > 150 }
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
