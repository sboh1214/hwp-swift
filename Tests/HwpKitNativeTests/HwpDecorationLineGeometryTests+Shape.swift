import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 글자선의 선 모양 (#191) — 조판이 실은 `underlineShape`·`strikethroughShape`
/// (`HwpBorderType.rawValue`)를 렌더러가 `HwpLineShapeGeometry`로 그리는 것과, 패턴을
/// **글자 모양 run**(같은 `charShapeId`의 잇닿은 CoreText run) 단위로 새로 시작하는 것을
/// 래스터로 잡는다. 기하 값 자체는 `HwpLineShapeGeometryTests`(HwpKitCore)가 고정한다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-17): 20pt 긴 점선 밑줄 선 5.64pt ·
/// 공백 3.36pt, "가나다 abc 라마" 한 글자 모양의 패턴은 한 위상으로 이어지고 색만 다른 이웃
/// 글자 모양은 다시 시작한다.
///
/// `extension`에 두는 이유는 `+Script`와 같다 (`type_body_length`). 래스터 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let shapeFontSize: CGFloat = 20
    /// 20pt 긴 점선: 단위 1.14pt → 선 5.7 · 공백 3.42 · 주기 9.12
    private static let longDotPeriod: CGFloat = 20 * 0.057 * 8

    private static func isCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    private func shapedUnderline(
        _ shape: HwpBorderType, font: String = "Menlo", charShape: Int? = nil,
        color: CGColor = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                font as CFString, Self.shapeFontSize, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(Self.shapeFontSize)),
            HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: color,
        ]
        if shape != .line {
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(value: shape.rawValue)
        }
        if let charShape {
            attributes[HwpAttributedStringKey.charShapeId] = NSNumber(value: charShape)
        }
        return attributes
    }

    /// 실선 밑줄의 행 중심(pt, 위에서부터) — 같은 조판의 베이스라인 아래 0.17em 자리라 다른
    /// 모양의 띠를 이 값 기준으로 잡는다
    private func solidUnderlineCenter() throws -> CGFloat {
        let solid = try render(text: NSAttributedString(
            string: "AAAAAAAAAA", attributes: shapedUnderline(.line)
        ))
        return try XCTUnwrap(Self.rowCenter(solid, where: Self.isCyan))
    }

    /// 띠 안에서 열마다 청록 잉크가 있는지 — x 순 (픽셀)
    private func underlineColumns(_ raster: Raster, band: ClosedRange<CGFloat>) -> [Bool] {
        let rows = Int(band.lowerBound * Self.scale) ... Int(band.upperBound * Self.scale)
        return (0 ..< raster.pixelWidth).map { x in
            rows.contains { y in
                let offset = y * raster.bytesPerRow + x * 4
                return Self.isCyan(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }
        }
    }

    /// 잉크 열의 시작 x (pt) 목록
    private static func inkStarts(_ columns: [Bool]) -> [CGFloat] {
        var starts: [CGFloat] = []
        for (index, ink) in columns.enumerated() where ink && (index == 0 || !columns[index - 1]) {
            starts.append(CGFloat(index) / scale)
        }
        return starts
    }

    /// 긴 점선 밑줄은 run 시작에서 선으로 시작해 5.7pt 선·3.42pt 공백을 되풀이한다
    func testLongDotUnderlineRepeatsTheMeasuredPattern() throws {
        let text = NSAttributedString(
            string: "AAAAAAAAAA", attributes: shapedUnderline(.longDotLine)
        )
        let raster = try render(text: text)
        let center = try solidUnderlineCenter()
        let columns = underlineColumns(raster, band: (center - 0.6) ... (center + 0.6))
        let starts = Self.inkStarts(columns)
        expect(starts.count) >= 8
        // 첫 선은 run 시작(x 10)에서, 이후 9.12pt 주기
        expect(starts.first).to(beCloseTo(10, within: 0.2))
        for (index, start) in starts.prefix(8).enumerated() {
            expect(start).to(beCloseTo(10 + Self.longDotPeriod * CGFloat(index), within: 0.2))
        }
        // 실선은 한 덩어리
        let solid = try render(text: NSAttributedString(
            string: "AAAAAAAAAA", attributes: shapedUnderline(.line)
        ))
        let solidStarts = Self.inkStarts(
            underlineColumns(solid, band: (center - 0.6) ... (center + 0.6))
        )
        expect(solidStarts.count) == 1
    }

    /// 같은 글자 모양 id의 잇닿은 run은 패턴이 이어지고, 다른 id는 run 시작에서 다시
    /// 시작한다 — 글꼴이 달라 CoreText가 run을 가르는 자리에서 잰다
    func testPatternContinuesAcrossRunsOfOneCharShapeAndRestartsOtherwise() throws {
        func raster(sameShape: Bool) throws -> (Raster, CGFloat) {
            let first = NSAttributedString(
                string: "AAAA", attributes: shapedUnderline(.longDotLine, charShape: 7)
            )
            let second = NSAttributedString(
                string: "BBBB",
                attributes: shapedUnderline(
                    .longDotLine, font: "Menlo-Bold", charShape: sameShape ? 7 : 8
                )
            )
            let text = NSMutableAttributedString(attributedString: first)
            text.append(second)
            let boundary = 10 + CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(first), nil, nil, nil
            )
            return (try render(text: text), boundary)
        }
        let (grouped, boundary) = try raster(sameShape: true)
        let (split, _) = try raster(sameShape: false)
        // 경계 48.16pt: 이어지는 패턴은 45.6~51.3 선 뒤 51.3~54.7 공백이라 52.5는 비고,
        // 다시 시작하는 패턴은 경계에서 5.7pt 선이 시작해 52.5에 잉크가 있다
        expect(boundary).to(beCloseTo(10 + 48.16, within: 0.3))
        let probe = Int((boundary + 4.3) * Self.scale)
        let center = try solidUnderlineCenter()
        let band = (center - 0.6) ... (center + 0.6)
        let groupedColumns = underlineColumns(grouped, band: band)
        let splitColumns = underlineColumns(split, band: band)
        expect(groupedColumns[probe]) == false
        expect(splitColumns[probe]) == true
        // 다시 시작하는 쪽은 경계 바로 뒤가 선이다
        let boundaryColumn = Int((boundary + 0.3) * Self.scale)
        expect(splitColumns[boundaryColumn]) == true
    }

    /// 2중선 밑줄은 두 띠, 물결은 진폭 0.112em의 띠 하나 (20pt: 2.24pt + 획 0.6)
    func testMultiLineAndWaveUnderlinesSpanTheMeasuredBands() throws {
        let double = try render(text: NSAttributedString(
            string: "AAAAAAAA", attributes: shapedUnderline(.doubleLine)
        ))
        let bands = Self.rowBands(double, where: Self.isCyan)
        expect(bands.count) == 2
        // 0.12em 띠: 0.6pt 두 줄, 중심 간격 1.8pt (한글 20pt 실측 0.6/1.8)
        if bands.count == 2 {
            expect(bands[1] - bands[0]).to(beCloseTo(1.8, within: 0.15))
        }
        let wave = try render(text: NSAttributedString(
            string: "AAAAAAAA", attributes: shapedUnderline(.wave)
        ))
        var inkRows: [Int] = []
        for y in 0 ..< wave.pixelHeight {
            for x in 0 ..< wave.pixelWidth {
                let offset = y * wave.bytesPerRow + x * 4
                if Self.isCyan(wave.data[offset], wave.data[offset + 1], wave.data[offset + 2]) {
                    inkRows.append(y)
                    break
                }
            }
        }
        let span = CGFloat((inkRows.max() ?? 0) - (inkRows.min() ?? 0) + 1) / Self.scale
        // 진폭 2.24 + 꼭짓점 평탄의 획 0.6 (한글 20pt 실측 꼭짓점 2.28pt·획 0.6pt)
        expect(span).to(beCloseTo(2.24 + 0.6, within: 0.25))
        // 꼭짓점 띠 위쪽 = 단선 위 가장자리(중심 − 0.4) − 두께 0.8 = 중심 − 1.2, 그 위로 획
        // 반폭 0.3
        let center = try solidUnderlineCenter()
        expect(CGFloat(inkRows.min() ?? 0) / Self.scale).to(beCloseTo(center - 1.5, within: 0.3))
    }
}
