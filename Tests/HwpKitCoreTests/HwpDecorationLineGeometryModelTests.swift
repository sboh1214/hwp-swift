import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 장식선 기하의 산식 핀 (#187·#210·#226) — 렌더러 없이 `HwpDecorationLineGeometry`만 잰다.
/// 한글 문서는 밑줄이 줄 상자 가장자리·두께가 줄 글자 크기 비례, 한글 2007 호환 문서는
/// 같은 가장자리에 고정 두께, MS 워드 호환 문서는 줄 상자(밑줄)·run 상자(취소선)에서
/// 나온다. 수치는 한글 12.30.0 실측(`HwpRenderTuning.Text`의 doc-comment).
final class HwpDecorationLineGeometryModelTests: XCTestCase {
    /// 한글 PDF가 찍은 실제 글자 크기와 세 선의 중심 (pt, 베이스라인 기준).
    private struct Hwp200XSample {
        let size: CGFloat
        let below: CGFloat
        let above: CGFloat
        let strike: CGFloat
    }

    func testNativeLinesScaleWithFontSize() {
        let below = HwpDecorationLineGeometry.underlineBelow(fontSize: 10)
        expect(below.center).to(beCloseTo(-1.7, within: 0.0001))
        expect(below.thickness).to(beCloseTo(0.4, within: 0.0001))
        let above = HwpDecorationLineGeometry.underlineAbove(fontSize: 10)
        expect(above.center).to(beCloseTo(8.7, within: 0.0001))
        expect(above.thickness).to(beCloseTo(0.4, within: 0.0001))
        // 취소선 중심은 (첨자로 줄어든) 글꼴 크기, 두께는 축소 전 크기 기준.
        let script = HwpDecorationLineGeometry.strikethrough(fontSize: 6.4, thicknessFontSize: 10)
        expect(script.center).to(beCloseTo(2.24, within: 0.0001))
        expect(script.thickness).to(beCloseTo(0.4, within: 0.0001))
    }

    /// 한글 PDF가 찍은 줄 단위 밑줄 (#226) — 줄 상자 높이(L)·줄 글자 기본 크기(T)와 중심
    /// (pt, 베이스라인 기준; 위 밑줄은 nil이면 표본 없음)·두께.
    private struct LineWideSample {
        let lineBox: CGFloat
        let text: CGFloat
        let below: CGFloat?
        let above: CGFloat?
        let thickness: CGFloat
    }

    /// 한글 문서의 밑줄은 **줄 단위**다 (#226) — 아래 밑줄은 위 가장자리가 줄 상자 바닥
    /// (0.15L)에, 위 밑줄은 아래 가장자리가 줄 상자 상단(0.85L)에 붙고 두께는 0.04T다.
    /// 한글 12.30 PDF 실측(2026-09-22·25, 함초롬바탕, 10pt 밑줄 run과 한 줄에 놓인 것):
    /// 40pt 무장식 글자·40pt 공백(L 40·T 40) −6.84·1.56, 위 밑줄은 기본 40pt·상대 크기
    /// 50% run +34.80·1.56; 40pt 문단 끝 글자·한 줄 끝·책갈피·그림·표(L 40·T 10) −6.12~
    /// −6.24·+34.20·0.36; 20pt 무장식 글자 + 40pt 문단 끝 글자(L 40·T 20) −6.36·0.84;
    /// 40pt 마커의 8pt 그림 + 20pt 글자(L 20·T 20) −3.36·0.84; 바깥 여백 위 7·아래 3pt인
    /// 20pt 그림(L 30·T 10) −4.68·+25.68·0.36; 10pt만(L·T 10) −1.68·+8.76·0.36. 한글은
    /// 좌표·두께를 600dpi 장치 단위(0.12pt)로 떨어뜨리므로 한 단위 안에서 본다.
    func testNativeUnderlinesSitOnTheLineBoxEdges() {
        let quantum = 0.12
        let samples = [
            LineWideSample(lineBox: 40, text: 40, below: -6.84, above: 34.80, thickness: 1.56),
            LineWideSample(lineBox: 40, text: 10, below: -6.24, above: 34.20, thickness: 0.36),
            LineWideSample(lineBox: 40, text: 20, below: -6.36, above: nil, thickness: 0.84),
            LineWideSample(lineBox: 20, text: 20, below: -3.36, above: nil, thickness: 0.84),
            LineWideSample(lineBox: 30, text: 10, below: -4.68, above: 25.68, thickness: 0.36),
            LineWideSample(lineBox: 10, text: 10, below: -1.68, above: 8.76, thickness: 0.36),
        ]
        for sample in samples {
            let label = "L \(sample.lineBox) · T \(sample.text)"
            let below = HwpDecorationLineGeometry.underlineBelow(
                lineBoxHeight: sample.lineBox, thicknessFontSize: sample.text
            )
            let above = HwpDecorationLineGeometry.underlineAbove(
                lineBoxHeight: sample.lineBox, thicknessFontSize: sample.text
            )
            if let expected = sample.below {
                expect(below.center).to(beCloseTo(expected, within: quantum), description: label)
            }
            if let expected = sample.above {
                expect(above.center).to(beCloseTo(expected, within: quantum), description: label)
            }
            for line in [below, above] {
                expect(line.thickness)
                    .to(beCloseTo(sample.thickness, within: quantum), description: label)
            }
            // 가장자리는 두께와 무관하게 줄 상자 바닥·상단이다.
            expect(below.center + below.thickness / 2)
                .to(beCloseTo(-0.15 * sample.lineBox, within: 0.0001), description: label)
            expect(above.center - above.thickness / 2)
                .to(beCloseTo(0.85 * sample.lineBox, within: 0.0001), description: label)
        }
        // 한 크기만 있는 줄의 편의 산식은 L = T = 글자 크기다.
        expect(HwpDecorationLineGeometry.underlineBelow(fontSize: 40)) == HwpDecorationLineGeometry
            .underlineBelow(lineBoxHeight: 40, thicknessFontSize: 40)
        expect(HwpDecorationLineGeometry.underlineAbove(fontSize: 40)) == HwpDecorationLineGeometry
            .underlineAbove(lineBoxHeight: 40, thicknessFontSize: 40)
    }

    /// 한글 2007 호환 문서도 같은 줄 상자 가장자리에 고정 0.36pt 선을 얹는다 (#226 실측: 10pt
    /// 밑줄과 한 줄인 40pt 글자·문단 끝 글자·한 줄 끝·책갈피·그림·표 −6.12·+34.08~34.20,
    /// 상자 30pt 그림 줄 −4.68·+25.68, 상자 20pt 줄 −3.12).
    func testHwp200XUnderlinesSitOnTheLineBoxEdges() {
        let quantum = 0.12
        expect(HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: 40).center)
            .to(beCloseTo(-6.12, within: quantum))
        expect(HwpDecorationLineGeometry.hwp200XUnderlineAbove(lineBoxHeight: 40).center)
            .to(beCloseTo(34.20, within: quantum))
        expect(HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: 30).center)
            .to(beCloseTo(-4.68, within: quantum))
        expect(HwpDecorationLineGeometry.hwp200XUnderlineAbove(lineBoxHeight: 30).center)
            .to(beCloseTo(25.68, within: quantum))
        expect(HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: 20).center)
            .to(beCloseTo(-3.12, within: quantum))
    }

    /// 한글 2007 호환 문서의 세 선을 한글 PDF 좌표에 맞춘다 — 한글은 좌표를 600dpi
    /// 장치 단위(0.12pt)로 떨어뜨리므로 한 단위 안에서 본다. 실측(2026-09-22, 함초롬바탕,
    /// 괄호는 PDF가 찍은 실제 글자 크기): 10pt(9.96) 밑줄 −1.56·위 밑줄 +8.64·취소선
    /// +3.48pt, 20pt(20.04) −3.12·+17.16·+6.96, 40pt(39.96) −6.12·+34.20·+14.04,
    /// 100pt(99.96) −15.12·+85.08·+34.92.
    func testHwp200XLinesMatchHangulPdfCoordinates() {
        let quantum = 0.12
        let samples = [
            Hwp200XSample(size: 9.96, below: -1.56, above: 8.64, strike: 3.48),
            Hwp200XSample(size: 20.04, below: -3.12, above: 17.16, strike: 6.96),
            Hwp200XSample(size: 39.96, below: -6.12, above: 34.20, strike: 14.04),
            Hwp200XSample(size: 99.96, below: -15.12, above: 85.08, strike: 34.92),
        ]
        for sample in samples {
            expect(HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: sample.size)
                .center)
                .to(beCloseTo(sample.below, within: quantum), description: "\(sample.size)pt 밑줄")
            expect(HwpDecorationLineGeometry.hwp200XUnderlineAbove(lineBoxHeight: sample.size)
                .center)
                .to(beCloseTo(sample.above, within: quantum), description: "\(sample.size)pt 위 밑줄")
            expect(HwpDecorationLineGeometry.hwp200XStrikethrough(fontSize: sample.size).center)
                .to(beCloseTo(sample.strike, within: quantum), description: "\(sample.size)pt 취소선")
        }
    }

    /// 두께는 크기와 무관한 0.36pt 고정이고 (한글 문서는 0.04em) 밑줄 **가장자리**는 두
    /// 갈래가 같다 — 중심 차이가 두께 절반의 차이다.
    func testHwp200XLinesUseAFixedThicknessOnTheNativeEdge() {
        for size in [CGFloat(5), 10, 40, 100] {
            let below = HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: size)
            let above = HwpDecorationLineGeometry.hwp200XUnderlineAbove(lineBoxHeight: size)
            let strike = HwpDecorationLineGeometry.hwp200XStrikethrough(fontSize: size)
            for line in [below, above, strike] {
                expect(line.thickness).to(beCloseTo(0.36, within: 0.0001), description: "\(size)pt")
            }
            let nativeBelow = HwpDecorationLineGeometry.underlineBelow(fontSize: size)
            let nativeAbove = HwpDecorationLineGeometry.underlineAbove(fontSize: size)
            expect(below.center + below.thickness / 2)
                .to(beCloseTo(nativeBelow.center + nativeBelow.thickness / 2, within: 0.0001))
            expect(above.center - above.thickness / 2)
                .to(beCloseTo(nativeAbove.center - nativeAbove.thickness / 2, within: 0.0001))
            expect(strike.center).to(beCloseTo(
                HwpDecorationLineGeometry.strikethrough(
                    fontSize: size, thicknessFontSize: size
                ).center, within: 0.0001
            ))
        }
    }

    /// 함초롬돋움 40pt (win 1.07/0.23, CJK): 밑줄 −(0.23 + 0.021 × 1.3) × 40 = −10.29pt,
    /// 두께 0.05 × 1.3 × 40 = 2.6pt (한글 PDF −0.2576em·0.0663em); 위 밑줄 +(1.07 +
    /// 0.0273) × 40 = 43.89pt (한글 +1.0985em); 취소선 0.273 × 1.07 × 40 = 11.68pt
    /// (한글 +0.2917em).
    func testMsWordLinesFollowTheLineBox() {
        let box = HwpMsWordLineBox(winAscent: 1.07, winDescent: 0.23, lineGap: 0, isCJK: true)
            .scaled(by: 40)
        let below = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
        expect(below.center).to(beCloseTo(-10.292, within: 0.001))
        expect(below.thickness).to(beCloseTo(2.6, within: 0.001))
        let above = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box)
        expect(above.center).to(beCloseTo(43.892, within: 0.001))
        expect(above.thickness).to(beCloseTo(2.6, within: 0.001))
        let strike = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: box, thicknessFontSize: 40
        )
        expect(strike.center).to(beCloseTo(11.684, within: 0.001))
        expect(strike.thickness).to(beCloseTo(1.6, within: 0.001))
    }

    /// Helvetica 80pt (그 밖 갈래, 기준 상자 0.8146/0.0895·cell 0.9041): 한글 PDF
    /// −0.1080em·+0.8333em·+0.2197em·두께 0.0455em.
    func testMsWordLinesForANonCJKFont() {
        let box = HwpMsWordLineBox(
            winAscent: 0.9502, winDescent: 0.2251, lineGap: 0, isCJK: false
        ).scaled(by: 80)
        let below = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
        expect(below.center / 80).to(beCloseTo(-0.1085, within: 0.002))
        expect(below.thickness / 80).to(beCloseTo(0.0452, within: 0.001))
        let above = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box)
        expect(above.center / 80).to(beCloseTo(0.8336, within: 0.002))
        let strike = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: box, thicknessFontSize: 80
        )
        expect(strike.center / 80).to(beCloseTo(0.2224, within: 0.003))
    }

    /// 줄 상자를 합치면 밑줄은 합친 상자를 따른다 — Apple SD 10pt 글자 줄에 Menlo 10pt
    /// 문단 끝 글자가 들면 −(0.2772 + 0.0252) × 10 = −3.02pt (한글 PDF −0.3012em; Apple
    /// SD 혼자면 −3.25pt).
    func testUnionMovesTheUnderline() throws {
        let appleSD = HwpMsWordLineBox(winAscent: 0.9, winDescent: 0.3, lineGap: 0, isCJK: true)
            .scaled(by: 10)
        let menlo = HwpMsWordLineBox(
            winAscent: 0.9282, winDescent: 0.2358, lineGap: 0, isCJK: true
        ).scaled(by: 10)
        let alone = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: appleSD)
        expect(alone.center).to(beCloseTo(-3.252, within: 0.001))
        let line = try XCTUnwrap(HwpMsWordLineBox.union([appleSD, menlo]))
        let joined = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: line)
        expect(joined.center).to(beCloseTo(-3.024, within: 0.002))
        expect(joined.thickness).to(beCloseTo(0.6, within: 0.001))
    }
}
