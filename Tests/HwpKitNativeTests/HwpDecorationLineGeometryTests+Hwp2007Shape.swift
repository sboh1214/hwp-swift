import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 한글 2007 호환 문서의 글자선 모양 (#227) — 렌더러가 이 갈래의 밑줄·취소선에 크기와 무관한
/// 고정 축척(`HwpLineShapeGeometry.Scale.hwp200XCharacterLine`)을 고르고, 그 결과 무늬가 run·줄
/// 크기와 상관없이 같은 pt로 그려지는지 래스터로 잡는다. 고정값 자체는
/// `HwpLineShapeGeometryTests+Hwp2007`(HwpKitCore)가, 실물 좌표는
/// `FixtureDecorationLineRenderTests+Hwp2007Shapes`(HwpKit)가 고정한다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-26): 5~100pt 전부 긴 점선
/// 2.40/1.44pt(주기 3.84pt), 2중선 0.36pt 두 줄·중심 간격 1.08pt, 물결 진폭 2.88pt·획 0.72pt.
/// 같은 표본을 한글 문서로 내보내면 40pt 긴 점선 주기가 18.24pt(= 8 × 0.057 × 40)다.
extension HwpDecorationLineGeometryTests {
    private static let hwp2007Target = NSNumber(
        value: HwpCompatibleDocumentTarget.hwp200X.rawValue
    )
    private static let shapeCyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)

    private static func isShapeCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    /// 한글 2007 호환(`target` 기본) 또는 한글 문서(`target: nil`) run — `shape`의 밑줄이나 취소선
    private func hwp2007ShapeRun(
        size: CGFloat, shape: HwpBorderType, strikethrough: Bool = false,
        target: NSNumber? = HwpDecorationLineGeometryTests.hwp2007Target
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.charShapeId: NSNumber(value: 3),
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = target
        }
        if strikethrough {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = Self.shapeCyan
            attributes[HwpAttributedStringKey.strikethroughShape] = NSNumber(value: shape.rawValue)
        } else {
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = Self.shapeCyan
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(value: shape.rawValue)
        }
        return attributes
    }

    /// 잉크가 가장 많은 행에서 청록 조각의 (시작, 길이) 목록 (pt) — 대시의 선·주기를 잰다.
    private static func dashes(_ raster: Raster) -> [(start: CGFloat, length: CGFloat)] {
        var bestRow = 0
        var bestCount = 0
        for y in 0 ..< raster.pixelHeight {
            var count = 0
            for x in 0 ..< raster.pixelWidth {
                let offset = y * raster.bytesPerRow + x * 4
                let pixel = (raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
                if isShapeCyan(pixel.0, pixel.1, pixel.2) {
                    count += 1
                }
            }
            if count > bestCount {
                bestCount = count
                bestRow = y
            }
        }
        var runs: [(start: CGFloat, length: CGFloat)] = []
        var start: Int?
        for x in 0 ... raster.pixelWidth {
            let offset = bestRow * raster.bytesPerRow + x * 4
            let ink = x < raster.pixelWidth && isShapeCyan(
                raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
            )
            if ink, start == nil {
                start = x
            } else if !ink, let first = start {
                runs.append((CGFloat(first) / scale, CGFloat(x - first) / scale))
                start = nil
            }
        }
        return runs
    }

    /// 청록 잉크가 있는 행의 위·아래 끝 (pt, 위에서부터)
    private static func inkRowSpan(_ raster: Raster) -> ClosedRange<CGFloat>? {
        var rows: [Int] = []
        for y in 0 ..< raster.pixelHeight {
            for x in 0 ..< raster.pixelWidth {
                let offset = y * raster.bytesPerRow + x * 4
                let pixel = (raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
                if isShapeCyan(pixel.0, pixel.1, pixel.2) {
                    rows.append(y)
                    break
                }
            }
        }
        guard let top = rows.min(), let bottom = rows.max() else { return nil }
        return CGFloat(top) / scale ... CGFloat(bottom + 1) / scale
    }

    /// 한글 2007 호환 문서의 밑줄·취소선 축척은 run·줄 크기와 무관한 고정 갈래다. 한글 문서는
    /// 밑줄이 줄 글자 크기(`textFontSize`), 취소선이 run 기본 크기이고(#226), MS 워드 호환
    /// 문서는 종전대로 첨자 축소 전 run 크기다 (미실측).
    func testHwp2007ShapeScaleIsFixedWhateverTheSizes() {
        let layer = HwpPageLayer()
        for size in [CGFloat(5), 10, 40, 100] {
            let run = hwp2007ShapeRun(size: size, shape: .longDotLine)
            for lineSize in [size, 60] {
                let reference = HwpDecorationLineGeometry.UnderlineReference(
                    lineBoxHeight: lineSize, textFontSize: lineSize
                )
                expect(layer.underlineShapeScale(run, reference: reference))
                    == .hwp200XCharacterLine
            }
            expect(layer.strikethroughShapeScale(run)) == .hwp200XCharacterLine
            let native = hwp2007ShapeRun(size: size, shape: .longDotLine, target: nil)
            let reference = HwpDecorationLineGeometry.UnderlineReference(
                lineBoxHeight: 60, textFontSize: 60
            )
            expect(layer.underlineShapeScale(native, reference: reference))
                == .characterLine(fontSize: 60)
            expect(layer.strikethroughShapeScale(native)) == .characterLine(fontSize: size)
        }
        var msWord = hwp2007ShapeRun(
            size: 20, shape: .longDotLine,
            target: NSNumber(value: HwpCompatibleDocumentTarget.msWord.rawValue)
        )
        msWord[HwpAttributedStringKey.spaceTargetSize] = NSNumber(value: 16)
        expect(layer.strikethroughShapeScale(msWord)) == .characterLine(fontSize: 16)
        // MS 워드 호환 줄(줄 상자가 있는 줄)의 밑줄도 종전대로 첨자 축소 전 run 크기다 —
        // 줄 글자 크기(60)도, 한글 2007 호환의 고정 축척도 아니다
        let msWordLine = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 60, textFontSize: 60,
            msWordLineBox: HwpMsWordLineBox(lineHeight: 1.3, baseline: 1.0, cellHeight: 1.0)
        )
        expect(layer.underlineShapeScale(msWord, reference: msWordLine))
            == .characterLine(fontSize: 16)
    }

    /// 긴 점선 밑줄의 무늬가 10pt와 40pt에서 같다 — 2.40pt 선·주기 3.84pt (한글 실측, 모든 크기).
    /// 한글 문서라면 40pt 주기 18.24pt·선 11.4pt다.
    func testHwp2007LongDotPatternIsTheSameAtEverySize() throws {
        for size in [CGFloat(10), 40] {
            let raster = try render(text: NSAttributedString(
                string: "AAAAAAAA", attributes: hwp2007ShapeRun(size: size, shape: .longDotLine)
            ))
            let runs = Self.dashes(raster)
            expect(runs.count).to(beGreaterThan(8), description: "\(size)pt 조각 수")
            guard runs.count > 4 else { continue }
            // 첫 선은 run 시작 x 10에서
            expect(runs[0].start).to(beCloseTo(10, within: 0.2), description: "\(size)pt 시작")
            for index in 0 ..< 4 {
                expect(runs[index].length)
                    .to(beCloseTo(2.40, within: 0.2), description: "\(size)pt 선 \(index)")
                expect(runs[index + 1].start - runs[index].start)
                    .to(beCloseTo(3.84, within: 0.2), description: "\(size)pt 주기 \(index)")
            }
        }
        let native = Self.dashes(try render(text: NSAttributedString(
            string: "AAAAAAAA",
            attributes: hwp2007ShapeRun(size: 40, shape: .longDotLine, target: nil)
        )))
        expect(native.first?.length ?? 0).to(beCloseTo(40 * 0.057 * 5, within: 0.2))
    }

    /// 2중선 밑줄은 0.36pt 두 줄·중심 간격 1.08pt, 물결 밑줄은 진폭 2.88pt + 꼭짓점 평탄의 획
    /// 0.72pt — 40pt에서도 고정값이다 (한글 문서 40pt: 1.2pt 두 줄·간격 3.6pt, 물결 4.48 + 1.2).
    func testHwp2007MultiLineAndWaveBandsAreFixedAtFortyPoints() throws {
        let double = try render(text: NSAttributedString(
            string: "AAAAAAAA", attributes: hwp2007ShapeRun(size: 40, shape: .doubleLine)
        ))
        let bands = Self.rowBands(double, where: Self.isShapeCyan)
        expect(bands.count) == 2
        if bands.count == 2 {
            expect(bands[1] - bands[0]).to(beCloseTo(1.08, within: 0.15))
        }
        let wave = try XCTUnwrap(Self.inkRowSpan(try render(text: NSAttributedString(
            string: "AAAAAAAA", attributes: hwp2007ShapeRun(size: 40, shape: .wave)
        ))))
        expect(wave.upperBound - wave.lowerBound).to(beCloseTo(2.88 + 0.72, within: 0.25))
        let nativeWave = try XCTUnwrap(Self.inkRowSpan(try render(text: NSAttributedString(
            string: "AAAAAAAA", attributes: hwp2007ShapeRun(size: 40, shape: .wave, target: nil)
        ))))
        expect(nativeWave.upperBound - nativeWave.lowerBound)
            .to(beCloseTo(40 * 0.112 + 40 * 0.03, within: 0.25))
    }

    /// 취소선도 같은 고정 축척이다 — 원형 점선 취소선은 지름 1.32pt 원이 3.0pt 간격으로 취소선
    /// 중심에 놓인다 (한글 실측: 모든 크기, 취소선은 원을 옮기지 않는다). 글리프 잉크가 선을
    /// 가리지 않게 빈칸 run으로 잰다.
    func testHwp2007CircleStrikethroughIsFixedAndCentered() throws {
        let circles = try render(text: NSAttributedString(
            string: "        ",
            attributes: hwp2007ShapeRun(size: 40, shape: .circle, strikethrough: true)
        ))
        let runs = Self.dashes(circles)
        expect(runs.count).to(beGreaterThan(20))
        guard runs.count > 3 else { return }
        expect(runs[1].start - runs[0].start).to(beCloseTo(3.0, within: 0.2))
        expect(runs[1].length).to(beCloseTo(1.32, within: 0.25))
        let solid = try render(text: NSAttributedString(
            string: "        ",
            attributes: hwp2007ShapeRun(size: 40, shape: .line, strikethrough: true)
        ))
        let span = try XCTUnwrap(Self.inkRowSpan(circles))
        let solidCenter = try XCTUnwrap(Self.rowCenter(solid, where: Self.isShapeCyan))
        expect((span.lowerBound + span.upperBound) / 2).to(beCloseTo(solidCenter, within: 0.15))
    }
}
