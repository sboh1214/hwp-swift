import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 장식선 기하의 산식 핀 (#187) — 렌더러 없이 `HwpDecorationLineGeometry`만 잰다.
/// 한글 문서는 글자 크기 비례, MS 워드 호환 문서는 줄 상자(밑줄)·run 상자(취소선)에서
/// 나온다. 수치는 한글 12.30.0 실측(`HwpRenderTuning.Text`의 `msWord*` doc-comment).
final class HwpDecorationLineGeometryModelTests: XCTestCase {
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
