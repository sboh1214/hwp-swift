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

    /// 10pt 한 크기 줄 — 획 두께 3u(0.36pt, #252: 무늬 두께 39HWPUNIT ÷ 12 = 3.25 → 3)라 밑줄 중심은
    /// 가장자리 −1.5·+8.5에서 획 절반만큼 바깥이다 (한글 12.30 PDF −1.68·+8.76, 두께 0.36).
    func testNativeLinesScaleWithFontSize() {
        let below = HwpDecorationLineGeometry.underlineBelow(fontSize: 10)
        expect(below.center).to(beCloseTo(-1.68, within: 0.0001))
        expect(below.thickness).to(beCloseTo(0.36, within: 0.0001))
        let above = HwpDecorationLineGeometry.underlineAbove(fontSize: 10)
        expect(above.center).to(beCloseTo(8.68, within: 0.0001))
        expect(above.thickness).to(beCloseTo(0.36, within: 0.0001))
        // 첨자 취소선 중심은 기본 크기 × 89/140(#258)의 0.35배, 두께는 축소 전 크기 기준 — 줄어든
        // 6.4pt로 재면 무늬 두께 25HWPUNIT → 2u(0.24pt)라 갈린다.
        let script = HwpDecorationLineGeometry.strikethrough(
            fontSize: 10 * HwpRenderTuning.Text.scriptStrikethroughScale, thicknessFontSize: 10
        )
        expect(script.center).to(beCloseTo(2.225, within: 0.0001))
        expect(script.thickness).to(beCloseTo(0.36, within: 0.0001))
        expect(HwpDecorationLineGeometry.strokeThickness(referenceSize: 6.4))
            .to(beCloseTo(0.24, within: 0.0001))
    }

    /// 한글 문서·한글 2007 호환 문서의 첨자 취소선은 첨자로 옮겨진 베이스라인 위, 보통 글자 취소선
    /// 높이의 89/140배다 (#258) — 렌더러는 기본 크기 × `scriptStrikethroughScale`을 두 산식에 넘긴다.
    /// 기대값은 한글 12.30.0 build 6523이 내보낸 PDF의 실측(2026-10-07, 함초롬바탕, 옮겨진 글리프
    /// 베이스라인 → 선 중심, pt)이다. 글리프와 선이 저마다 장치 단위(0.12pt)로 떨어지므로 한 칸 안에서
    /// 본다. 한글이 다시 저장한 줄 캐시로 푼 이산 규칙(⌊89 × 기본 크기 HWPUNIT ÷ 400⌋ HWPUNIT)과는
    /// 버림 몫(0.01pt) 안이어야 한다. 첨자 글리프 축소 비율 0.64를 곱하면 기본 크기의 0.0015배 높아
    /// 50pt부터 이 두 핀을 넘는다 (250pt 56.00 — 한글 55.56·55.68).
    func testScriptStrikethroughIsAFixedFractionOfThePlainHeight() {
        struct Sample {
            let size: CGFloat
            /// 한글 PDF 실측 — 위 첨자·아래 첨자
            let superscript: CGFloat
            let `subscript`: CGFloat
        }
        let samples = [
            Sample(size: 50, superscript: 11.16, subscript: 11.04),
            Sample(size: 72, superscript: 15.96, subscript: 15.96),
            Sample(size: 100, superscript: 22.32, subscript: 22.20),
            Sample(size: 120, superscript: 26.64, subscript: 26.64),
            Sample(size: 150, superscript: 33.48, subscript: 33.48),
            Sample(size: 200, superscript: 44.40, subscript: 44.52),
            Sample(size: 250, superscript: 55.56, subscript: 55.68),
        ]
        for sample in samples {
            let size = sample.size
            let height = size * HwpRenderTuning.Text.scriptStrikethroughScale
            let native = HwpDecorationLineGeometry.strikethrough(
                fontSize: height, thicknessFontSize: size
            )
            let hwp200X = HwpDecorationLineGeometry.hwp200XStrikethrough(fontSize: height)
            let rule = (89 * size * 100 / 400).rounded(.down) / 100
            for (name, line) in [("한글 문서", native), ("한글 2007 호환", hwp200X)] {
                let label = "\(name) \(size)pt"
                expect(line.center).to(beCloseTo(rule, within: 0.01), description: "\(label) 규칙")
                expect(line.center)
                    .to(beCloseTo(sample.superscript, within: 0.12), description: "\(label) 위 첨자")
                expect(line.center)
                    .to(beCloseTo(sample.subscript, within: 0.12), description: "\(label) 아래 첨자")
            }
            expect(native.thickness).to(beCloseTo(
                HwpDecorationLineGeometry.strokeThickness(referenceSize: size), within: 0.0001
            ))
        }
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
    /// (0.15L)에, 위 밑줄은 아래 가장자리가 줄 상자 상단(0.85L)에 붙고 두께는 T의 획 두께다
    /// (장치 단위 정수, #252 — 아래 표본의 두께는 한글이 그린 값과 정확히 같다).
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
                    .to(beCloseTo(sample.thickness, within: 1e-9), description: label)
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

    /// 두께는 크기와 무관한 0.36pt 고정이고 (한글 문서는 크기에서 푼 장치 단위 획 — 5pt
    /// 0.24·100pt 3.96) 밑줄 **가장자리**는 두 갈래가 같다 — 중심 차이가 두께 절반의 차이다.
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

    /// 함초롬돋움 40pt (win 1.07/0.23, CJK): 밑줄 −(0.23 + 0.021 × 1.3) × 40 = −10.29pt
    /// (한글 PDF −0.2576em), 두께는 줄 글자 상자 높이 1.3 × 1.3 × 40 = 67.6pt의 획 — 무늬 두께
    /// 264HWPUNIT → 22u = 2.64pt (#252, 한글 0.0663em = 2.65pt); 위 밑줄 +(1.07 + 0.0273) × 40 =
    /// 43.89pt (한글 +1.0985em); 취소선은 줄 상자 베이스라인 높이(1.07 + 0.15 × 1.3 = 1.265em)의
    /// 0.23배 × 40 = 11.64pt (#257 — 한글 +0.2917em·#257 실측 11.64pt), 두께는 기본 크기 40pt의
    /// 획 13u = 1.56pt.
    func testMsWordLinesFollowTheLineBox() {
        let box = HwpMsWordLineBox(winAscent: 1.07, winDescent: 0.23, lineGap: 0, isCJK: true)
            .scaled(by: 40)
        let below = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
        expect(below.center).to(beCloseTo(-10.292, within: 0.001))
        expect(below.thickness).to(beCloseTo(2.64, within: 0.0001))
        let above = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box)
        expect(above.center).to(beCloseTo(43.892, within: 0.001))
        expect(above.thickness).to(beCloseTo(2.64, within: 0.0001))
        let strike = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: box, thicknessFontSize: 40
        )
        expect(strike.center).to(beCloseTo(11.638, within: 0.001))
        expect(strike.thickness).to(beCloseTo(1.56, within: 0.0001))
    }

    /// Helvetica 80pt (그 밖 갈래, 기준 상자 0.8146/0.0895·cell 0.9041, 베이스라인 높이 0.9502):
    /// 한글 PDF −0.1080em·+0.8333em·+0.2197em (취소선은 0.23 × 0.9502 = 0.2185em, #257 — 같은 글꼴
    /// 20~100pt 스윕의 한글 비율도 0.2185). 두께는 줄 글자 상자 높이 1.1753 × 80 = 94.02pt의 획 —
    /// 무늬 두께 367HWPUNIT → 31u = 3.72pt (0.0465em, #252: 한글 12.30 build 6523 100% 쪽에서
    /// 아래·위 밑줄 3.72pt, 줄 캐시 `vertsize` 9407; 종전 0.0455em은 변경 추적 문서의 0.8배
    /// 축소 쪽에서 잰 값이라 축소한 크기로 다시 반올림된 획이었다), 취소선은 기본 크기 80pt의
    /// 26u = 3.12pt.
    func testMsWordLinesForANonCJKFont() {
        let box = HwpMsWordLineBox(
            winAscent: 0.9502, winDescent: 0.2251, lineGap: 0, isCJK: false
        ).scaled(by: 80)
        let below = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
        expect(below.center / 80).to(beCloseTo(-0.1085, within: 0.002))
        expect(below.thickness).to(beCloseTo(3.72, within: 0.0001))
        let above = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box)
        expect(above.center / 80).to(beCloseTo(0.8336, within: 0.002))
        expect(above.thickness).to(beCloseTo(3.72, within: 0.0001))
        let strike = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: box, thicknessFontSize: 80
        )
        expect(strike.center / 80).to(beCloseTo(0.2185, within: 0.0005))
        expect(strike.thickness).to(beCloseTo(3.12, within: 0.0001))
    }

    /// MS 워드 호환 문서의 취소선은 글꼴 줄 상자의 **베이스라인 높이**(줄 상자 윗변 → 베이스라인)의
    /// 0.23배다 (#257). 기대값은 한글 12.30.0 build 6523이 내보낸 PDF의 실측(2026-10-07, 베이스라인 →
    /// 취소선 중심, pt)이고, 상자는 그 PDF에 실린 글꼴의 표 값(OS/2 win 지표·hhea lineGap, OS/2가 없는
    /// AppleMyungjo는 hhea)으로 푼다. 장치 단위 한 칸(0.12pt) 안이어야 한다 — 558표본 최대 0.115pt.
    /// 종전 `ascent`(베이스라인 − 0.15 cell) × 0.273은 `descent`·`lineGap`이 큰 글꼴에서 갈렸다:
    /// Zapfino 100pt 35.33pt(한글 43.20), Palatino 32.03(32.76), Palatino Linotype 32.45(31.80).
    func testMsWordStrikethroughFollowsTheFontLineBoxBaseline() {
        struct Sample {
            let font: String
            let winAscent: CGFloat
            let winDescent: CGFloat
            let lineGap: CGFloat
            let unitsPerEm: CGFloat
            let isCJK: Bool
            /// (기본 크기, 한글 PDF 취소선 높이)
            let hancom: [(size: CGFloat, height: CGFloat)]
        }
        let samples = [
            // `descent`가 `ascent`의 두 배 — 종전 모형이 가장 크게 갈린 글꼴
            Sample(font: "Zapfino", winAscent: 750, winDescent: 1264, lineGap: 0, unitsPerEm: 400,
                   isCJK: false, hancom: [(40, 17.28), (100, 43.20)]),
            // CJK 갈래(비트 59·61)이면서 `descent`가 큰 글꼴
            Sample(font: "Palatino", winAscent: 2403, winDescent: 989, lineGap: 0, unitsPerEm: 2048,
                   isCJK: true, hancom: [(40, 13.08), (100, 32.76)]),
            // 그 밖 갈래의 큰 lineGap(0.33em) — 베이스라인 높이에 든다
            Sample(font: "Palatino Linotype", winAscent: 2150, winDescent: 613, lineGap: 682,
                   unitsPerEm: 2048, isCJK: false, hancom: [(40, 12.72), (100, 31.80)]),
            Sample(font: "Times New Roman", winAscent: 1825, winDescent: 443, lineGap: 87,
                   unitsPerEm: 2048, isCJK: false, hancom: [(40, 8.64), (100, 21.48)]),
            Sample(font: "Arial", winAscent: 1854, winDescent: 434, lineGap: 67, unitsPerEm: 2048,
                   isCJK: false, hancom: [(40, 8.64), (100, 21.48)]),
            Sample(font: "Baskerville", winAscent: 1968, winDescent: 705, lineGap: 0,
                   unitsPerEm: 2048, isCJK: true, hancom: [(40, 10.68), (100, 26.64)]),
            Sample(font: "Apple SD 산돌고딕 Neo", winAscent: 900, winDescent: 300, lineGap: 0,
                   unitsPerEm: 1000, isCJK: true, hancom: [(40, 9.96), (100, 24.84)]),
            // OS/2 없음 — hhea ascent·descent가 win 자리
            Sample(font: "AppleMyungjo", winAscent: 891, winDescent: 326, lineGap: 0,
                   unitsPerEm: 1025, isCJK: false, hancom: [(40, 8.04), (100, 20.04)]),
        ]
        for sample in samples {
            let emBox = HwpMsWordLineBox(
                winAscent: sample.winAscent / sample.unitsPerEm,
                winDescent: sample.winDescent / sample.unitsPerEm,
                lineGap: sample.lineGap / sample.unitsPerEm, isCJK: sample.isCJK
            )
            for (size, height) in sample.hancom {
                let strike = HwpDecorationLineGeometry.msWordStrikethrough(
                    runBox: emBox.scaled(by: size), thicknessFontSize: size
                )
                expect(strike.center).to(
                    beCloseTo(emBox.baseline * 0.23 * size, within: 1e-9),
                    description: "\(sample.font) \(size)pt 산식"
                )
                expect(strike.center).to(
                    beCloseTo(height, within: 0.12), description: "\(sample.font) \(size)pt 한글"
                )
            }
        }
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
