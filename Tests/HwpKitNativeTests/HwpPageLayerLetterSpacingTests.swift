import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 글자마다 run으로 갈리는 자간 글자열(#260)의 렌더 — 자간이 글자 전진량의 %라 라틴 글자열은 글자마다
/// kern·tracking 값이 달라 CoreText run이 글자 하나씩이다. run마다 칠하던 음영·실선과 run마다 세우던 메모
/// 앵커 괄호, 장평 run의 위치(행렬 적용 전 좌표)가 그때 드러난다.
final class HwpPageLayerLetterSpacingTests: XCTestCase {
    private static let scale: CGFloat = 4
    private static let font = kCTFontAttributeName as NSAttributedString.Key

    /// 글자마다 다른 tracking을 실은 `aaaa` — 자간 있는 라틴 글자열처럼 글자마다 run이 된다.
    private static func perGlyphRuns(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(string: "aaaa", attributes: attributes)
        for index in 0 ..< 4 {
            string.addAttribute(
                kCTTrackingAttributeName as NSAttributedString.Key,
                value: NSNumber(value: 0.37 + Double(index) * 0.11),
                range: NSRange(location: index, length: 1)
            )
        }
        return string
    }

    private func render(_ text: NSAttributedString) throws -> (data: [UInt8], width: Int, bytesPerRow: Int) {
        let width = 120.0
        let height = 40.0
        let layer = HwpPageLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.pageHeight = height
        layer.paintList = HwpPaintList(commands: [
            .fillRect(
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ),
            .drawText(attributedString: text, origin: CGPoint(x: 10.3, y: 10), lineWidth: 100),
        ])
        let pixelWidth = Int(width * Self.scale)
        let pixelHeight = Int(height * Self.scale)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: Self.scale, y: Self.scale)
        layer.draw(in: context)
        let pixels = try XCTUnwrap(context.data)
        let data = [UInt8](UnsafeRawBufferPointer(
            start: pixels, count: context.bytesPerRow * pixelHeight
        ))
        return (data, pixelWidth, context.bytesPerRow)
    }

    func testShadeAcrossPerGlyphRunsHasNoSeams() throws {
        // 파랑 음영 — run마다 칠하면 소수 좌표의 run 경계 열이 옅게 남는다. 한 경로로 칠하면 음영
        // 띠 안 행의 파랑 채널 외 값이 모두 0이다.
        let menlo = CTFontCreateWithName("Menlo-Regular" as CFString, 20, nil)
        let raster = try render(Self.perGlyphRuns([
            Self.font: menlo,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(value: 0),
            HwpAttributedStringKey.shadeColor: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        ]))
        // 음영 상자 안쪽 행 — 완전히 파랑인 픽셀이 가장 많은 행(위·아래 가장자리 행은 부분 덮임이라
        // 빠진다)에서 첫·끝 파랑 사이에 옅은 픽셀이 있으면 이음매다. 파랑은 색 공간 변환으로
        // (4, 51, 255)라 빨강 채널 10 이하를 완전 덮임으로 본다 (run마다 칠하면 경계 열이 64쯤 옅다).
        var best: (y: Int, columns: [Int]) = (0, [])
        for y in 0 ..< raster.data.count / raster.bytesPerRow {
            let columns = (0 ..< raster.width).filter { x in
                let offset = y * raster.bytesPerRow + x * 4
                return raster.data[offset] <= 10 && raster.data[offset + 2] > 200
            }
            if columns.count > best.columns.count {
                best = (y, columns)
            }
        }
        let first = try XCTUnwrap(best.columns.first)
        let last = try XCTUnwrap(best.columns.last)
        let seams = (first ... last).filter { x in
            raster.data[best.y * raster.bytesPerRow + x * 4] > 10
        }
        expect(best.columns.count) > 100
        expect(seams) == []
    }

    func testMemoAnchorBracketsStandOnlyAtTheRangeEnds() throws {
        // 앵커 범위 양 끝에만 괄호가 선다 — 글자마다 run이어도 괄호는 둘이다.
        let menlo = CTFontCreateWithName("Menlo-Regular" as CFString, 20, nil)
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let raster = try render(Self.perGlyphRuns([
            Self.font: menlo,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(value: 0),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            HwpAttributedStringKey.shadeColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            HwpAttributedStringKey.memoAnchorStroke: green,
        ]))
        // 괄호 세로획이 지나는 열 묶음의 수 — 한 행(상자 가운데)에서 초록 픽셀이 이어진 덩어리.
        let rows = raster.data.count / raster.bytesPerRow
        var maxClusters = 0
        for y in 0 ..< rows {
            var clusters = 0
            var inside = false
            for x in 0 ..< raster.width {
                let offset = y * raster.bytesPerRow + x * 4
                let isGreen = raster.data[offset + 1] > 120 && raster.data[offset] < 200
                    && raster.data[offset + 2] < 200
                if isGreen, !inside {
                    clusters += 1
                }
                inside = isGreen
            }
            maxClusters = max(maxClusters, clusters)
        }
        expect(maxClusters) == 2
    }

    func testLineEndTrackingIsNotDecorated() throws {
        // 줄 끝 글자의 양수 자간은 CoreText가 매달아 둔 몫이라 한글처럼 장식하지 않는다 — 음영이 마지막
        // 글자의 자간 없는 전진량에서 끝난다 (빈칸이 뒤따르는 줄은 그대로 둔다).
        let menlo = CTFontCreateWithName("Menlo-Regular" as CFString, 20, nil)
        let tracking = kCTTrackingAttributeName as NSAttributedString.Key
        func line(_ text: String) -> NSAttributedString {
            let string = NSMutableAttributedString(string: text, attributes: [
                Self.font: menlo, kCTKernAttributeName as NSAttributedString.Key: NSNumber(value: 0),
            ])
            string.addAttribute(
                tracking, value: NSNumber(value: 2.4), range: NSRange(location: 0, length: 4)
            )
            return string
        }
        let layer = HwpPageLayer()
        func clip(_ text: String) -> CGFloat? {
            let ctLine = CTLineCreateWithAttributedString(line(text))
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            return layer.lineEndTrackingClip(of: ctLine, runs: runs, lineOrigin: .zero)
        }
        let typographic = CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(line("abcd")), nil, nil, nil
        ))
        expect(clip("abcd")).to(beCloseTo(typographic - 2.4, within: 1e-9))
        expect(clip("abcd\n")).to(beCloseTo(typographic - 2.4, within: 1e-9))
        expect(clip("abcd ")).to(beNil())

        var shaded = [NSAttributedString.Key: Any]()
        line("abcd").enumerateAttributes(in: NSRange(location: 0, length: 4)) { attributes, _, _ in
            shaded = attributes
        }
        shaded[HwpAttributedStringKey.shadeColor] = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        shaded[kCTForegroundColorAttributeName as NSAttributedString.Key] = CGColor(
            red: 0, green: 0, blue: 1, alpha: 1
        )
        let raster = try render(NSAttributedString(string: "abcd", attributes: shaded))
        let blueColumns = (0 ..< raster.width).filter { x in
            (0 ..< raster.data.count / raster.bytesPerRow).contains { y in
                let offset = y * raster.bytesPerRow + x * 4
                return raster.data[offset] <= 10 && raster.data[offset + 2] > 200
            }
        }
        // 그리는 원점 x 10.3 — 음영 오른쪽 끝은 10.3 + 폭 − 2.4pt (자르지 않으면 10.3 + 폭).
        let right = CGFloat(try XCTUnwrap(blueColumns.last) + 1) / Self.scale
        expect(right).to(beCloseTo(10.3 + typographic - 2.4, within: 0.3))
    }

    func testRunBoundsApplyTheTextMatrix() {
        // 장평 50% run이 줄 중간에서 시작하면 CTRunGetPositions는 행렬 적용 전 좌표(두 배)를 준다 —
        // 장식 경계는 그려지는 자리(캐럿 오프셋)와 같아야 한다.
        let full = CTFontCreateWithName("Menlo-Regular" as CFString, 20, nil)
        var matrix = CGAffineTransform(scaleX: 0.5, y: 1)
        let half = CTFontCreateWithName("Menlo-Regular" as CFString, 20, &matrix)
        let string = NSMutableAttributedString(string: "ab", attributes: [Self.font: full])
        string.append(NSAttributedString(string: "cd", attributes: [Self.font: half]))
        let line = CTLineCreateWithAttributedString(string)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        expect(runs.count) == 2
        let bounds = HwpPageLayer().runBounds(of: runs[1], lineOrigin: .zero)
        expect(bounds.minX).to(beCloseTo(CTLineGetOffsetForStringIndex(line, 2, nil), within: 0.001))
    }
}
