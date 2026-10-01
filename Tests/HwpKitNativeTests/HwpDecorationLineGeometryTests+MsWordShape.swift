import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// MS 워드 호환 문서의 글자선 모양 (#244) — 렌더러가 그 문서의 밑줄 무늬에 **줄 글자 상자의 높이**
/// 축척(`HwpMsWordLineBox.cellHeight` × 1.3)과 **취소선 자리**(단선 중심에 가운데)를 고르고,
/// 취소선 무늬에 **글자 모양 기본 크기**를 고르는지 잡는다. 기하 값은
/// `HwpLineShapeGeometryTests+MsWord`(HwpKitCore)가, 실물 좌표는
/// `FixtureDecorationLineRenderTests+MsWordShapes`(HwpKit)가 고정한다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-30). 한글은 이 문서의 밑줄
/// 무늬를 글자 크기가 아니라 줄 글자 상자의 높이(글자 run 상자들의 합 — 문단 끝 글자·개체가 쌓이지
/// 않은 줄에서는 줄 캐시 `vertsize`)로
/// 잰다 — 글꼴 10종 × 8~100pt 원형 점선 밑줄 732표본이 그 크기의 #239 장치 단위 규칙과 같다.
/// Menlo 20pt: 밑줄 원 간격 35u(4.2pt)·칠 지름 15u(1.8pt), 취소선 25u(3.0pt) — 한글 문서라면
/// 밑줄도 25u다.
extension HwpDecorationLineGeometryTests {
    private static let msWordTarget = NSNumber(value: HwpCompatibleDocumentTarget.msWord.rawValue)
    private static let msWordCyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)

    private static func isMsWordCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    /// MS 워드 호환 Menlo run — `size`는 run 글꼴 크기(슬롯 상대 크기 반영), `baseSize`는 글자
    /// 모양 기본 크기(기본은 `size`). `shape`가 있으면 그 모양의 밑줄(`strikethrough`면 취소선).
    private func msWordShapeRun(
        size: CGFloat, baseSize: CGFloat? = nil, shape: HwpBorderType? = nil,
        strikethrough: Bool = false, charShape: Int = 3
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(baseSize ?? size)),
            HwpAttributedStringKey.charShapeId: NSNumber(value: charShape),
            HwpAttributedStringKey.compatibleDocumentTarget: Self.msWordTarget,
        ]
        guard let shape else { return attributes }
        if strikethrough {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = Self.msWordCyan
            attributes[HwpAttributedStringKey.strikethroughShape] = NSNumber(value: shape.rawValue)
        } else {
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = Self.msWordCyan
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(value: shape.rawValue)
        }
        return attributes
    }

    private static func menloBox(_ size: CGFloat) -> HwpMsWordLineBox {
        HwpMsWordLineBox.metrics(of: CTFontCreateWithName("Menlo" as CFString, size, nil))
            .scaled(by: size)
    }

    /// 청록 잉크가 가장 많은 행의 조각 (시작, 길이) 목록 (pt) — 원·대시를 가로로 잰다
    private static func cyanRuns(_ raster: Raster) -> [(start: CGFloat, length: CGFloat)] {
        var bestRow = 0
        var bestCount = 0
        for y in 0 ..< raster.pixelHeight {
            let count = (0 ..< raster.pixelWidth).filter { x in
                let offset = y * raster.bytesPerRow + x * 4
                return isMsWordCyan(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }.count
            if count > bestCount {
                bestCount = count
                bestRow = y
            }
        }
        var runs: [(start: CGFloat, length: CGFloat)] = []
        var start: Int?
        for x in 0 ... raster.pixelWidth {
            let offset = bestRow * raster.bytesPerRow + x * 4
            let ink = x < raster.pixelWidth && isMsWordCyan(
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
    private static func cyanRowSpan(_ raster: Raster) -> ClosedRange<CGFloat>? {
        let rows = (0 ..< raster.pixelHeight).filter { y in
            (0 ..< raster.pixelWidth).contains { x in
                let offset = y * raster.bytesPerRow + x * 4
                return isMsWordCyan(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }
        }
        guard let top = rows.min(), let bottom = rows.max() else { return nil }
        return CGFloat(top) / scale ... CGFloat(bottom + 1) / scale
    }

    /// 밑줄 축척은 줄 기준의 **글자 상자 높이**(cell × 1.3)다 — run 글꼴 크기·기본 크기와도, 문단
    /// 끝 글자·개체가 쌓아 키운 줄 상자와도 무관하다 (한글: 40pt 문단 끝 글자와 한 줄인 10pt 밑줄의
    /// 원 간격은 10pt 상자 몫 20u). 한글 문서 줄은 종전대로 줄 글자 기본 크기다.
    func testMsWordUnderlineShapeScaleIsTheLineTextBox() {
        let layer = HwpPageLayer()
        let run = msWordShapeRun(size: 10, baseSize: 20, shape: .circle)
        let box = Self.menloBox(20)
        let line = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 99, textFontSize: 99, msWordLineBox: box
        )
        expect(layer.underlineShapeScale(run, reference: line))
            == .characterLine(fontSize: box.cellHeight * 1.3)
        expect(box.cellHeight * 1.3).to(beCloseTo(box.lineHeight, within: 0.000_1))
        expect(box.lineHeight).to(beCloseTo(30.29, within: 0.05))
        // 문단 끝 글자가 쌓인 줄 — 줄 상자 60pt, 글자 상자 cell 10pt → 축척 13pt
        let stacked = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 60, textFontSize: 20,
            msWordLineBox: HwpMsWordLineBox(lineHeight: 60, baseline: 45, cellHeight: 10)
        )
        expect(layer.underlineShapeScale(run, reference: stacked)) == .characterLine(fontSize: 13)
        // 한글 문서 줄(줄 상자 없음)은 줄 글자 기본 크기
        let native = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 60, textFontSize: 40
        )
        expect(layer.underlineShapeScale(run, reference: native)) == .characterLine(fontSize: 40)
    }

    /// 밑줄 무늬의 여러 줄 띠·물결 자리 — MS 워드 호환 줄은 아래·위 밑줄 모두 취소선 자리, 한글
    /// 문서 줄은 밑줄 종류 그대로
    func testMsWordUnderlineShapesTakeTheStrikethroughPlacement() {
        let layer = HwpPageLayer()
        let msWord = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 30, textFontSize: 20, msWordLineBox: Self.menloBox(20)
        )
        let native = HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: 20, textFontSize: 20
        )
        for placement in [HwpLineShapeGeometry.Placement.underlineBelow, .underlineAbove] {
            expect(layer.underlineShapePlacement(placement, reference: msWord)) == .strikethrough
            expect(layer.underlineShapePlacement(placement, reference: native)) == placement
        }
    }

    /// 취소선 축척은 글자 모양 기본 크기다 — 슬롯 상대 크기로 줄어든 run(기본 20pt·50%)도
    /// 20pt 몫이다 (한글: 원 간격 25u·긴 점선 47/28u; 종전의 run 크기 10pt라면 13u)
    func testMsWordStrikethroughShapeScaleIsTheCharShapeBaseSize() {
        let layer = HwpPageLayer()
        let relative = msWordShapeRun(size: 10, baseSize: 20, shape: .circle, strikethrough: true)
        expect(layer.strikethroughShapeScale(relative)) == .characterLine(fontSize: 20)
        let enlarged = msWordShapeRun(size: 20, baseSize: 10, shape: .circle, strikethrough: true)
        expect(layer.strikethroughShapeScale(enlarged)) == .characterLine(fontSize: 10)
    }

    /// Menlo 20pt 원형 점선 밑줄은 줄 글자 상자(30.27pt) 몫 — 간격 4.2pt·칠 지름 1.8pt(한글
    /// 35u·경로 14u + 윤곽 1u). 같은 run의 원형 점선 취소선은 글자 크기 몫 3.0pt(25u)다 — 상대 크기가
    /// 없는 run이라 수정 전에도 같은 값인 **대조군**이다 (취소선 축척의 판별은
    /// `testMsWordStrikethroughShapeScaleIsTheCharShapeBaseSize`와 픽스처 9·11번).
    func testMsWordCircleUnderlineUsesTheLineBoxAndStrikethroughTheSize() throws {
        let underline = Self.cyanRuns(try render(text: NSAttributedString(
            string: "          ", attributes: msWordShapeRun(size: 20, shape: .circle)
        )))
        expect(underline.count).to(beGreaterThan(20))
        if underline.count > 11 {
            expect(underline[10].start - underline[0].start).to(beCloseTo(42, within: 0.25))
            expect(underline[1].length).to(beCloseTo(1.8, within: 0.3))
        }
        let strike = Self.cyanRuns(try render(text: NSAttributedString(
            string: "          ",
            attributes: msWordShapeRun(size: 20, shape: .circle, strikethrough: true)
        )))
        expect(strike.count).to(beGreaterThan(20))
        if strike.count > 11 {
            expect(strike[10].start - strike[0].start).to(beCloseTo(30, within: 0.25))
        }
    }

    /// 크기가 섞인 줄은 가장 큰 글자 run의 상자 몫이다 — 10pt 원형 점선 밑줄 run 앞에 40pt
    /// 무장식 글자가 있으면 그 줄의 원은 Menlo 40pt 상자(60.53pt) 몫 간격 8.76pt(73u)다 (한글
    /// 실측 Menlo 40pt 73u; 10pt 상자 몫이면 2.16pt).
    func testMsWordUnderlinePatternFollowsTheTallestTextRun() throws {
        let text = NSMutableAttributedString(
            string: "A", attributes: msWordShapeRun(size: 40, charShape: 4)
        )
        text.append(NSAttributedString(
            string: "                ", attributes: msWordShapeRun(size: 10, shape: .circle)
        ))
        let runs = Self.cyanRuns(try render(text: text))
        expect(runs.count).to(beGreaterThan(8))
        guard runs.count > 6 else { return }
        expect(runs[5].start - runs[0].start).to(beCloseTo(5 * 8.76, within: 0.3))
    }

    /// 2중선 밑줄의 두 줄은 실선 밑줄 중심을 가운데로 두고(한글 ±1.26pt), 물결 밑줄의 위 꼭짓점은
    /// 그 중심 위 2.5 × 0.04 × 30.27 = 3.03pt다(한글 3.04pt) — 한글 문서 규칙(띠가 단선 위
    /// 가장자리에서 아래로)이었다면 두 줄이 중심 아래로 몰리고 꼭짓점은 1.75pt 위다.
    func testMsWordMultiLineAndWaveUnderlinesCenterOnTheSingleLine() throws {
        let solid = try render(text: NSAttributedString(
            string: "          ", attributes: msWordShapeRun(size: 20, shape: .line)
        ))
        let center = try XCTUnwrap(Self.rowCenter(solid, where: Self.isMsWordCyan))
        let double = try render(text: NSAttributedString(
            string: "          ", attributes: msWordShapeRun(size: 20, shape: .doubleLine)
        ))
        let bands = Self.rowBands(double, where: Self.isMsWordCyan)
        expect(bands.count) == 2
        if bands.count == 2 {
            expect((bands[0] + bands[1]) / 2).to(beCloseTo(center, within: 0.15))
            expect(bands[1] - bands[0]).to(beCloseTo(2 * 1.36, within: 0.2))
        }
        let wave = try XCTUnwrap(Self.cyanRowSpan(try render(text: NSAttributedString(
            string: "          ", attributes: msWordShapeRun(size: 20, shape: .wave)
        ))))
        let box = Self.menloBox(20).lineHeight
        let stroke = box * HwpRenderTuning.LineShape.characterWaveStrokeEmRatio
        let amplitude = box * HwpRenderTuning.LineShape.characterWaveAmplitudeEmRatio
        // 대각 획의 잉크는 꼭짓점 밖으로 획 반폭만큼 나간다 (45°라 반폭 × √2 안쪽)
        expect(wave.lowerBound).to(beCloseTo(center - 3.03 - stroke / 2, within: 0.3))
        expect(wave.upperBound).to(beCloseTo(center - 3.03 + amplitude + stroke / 2, within: 0.3))
    }
}
