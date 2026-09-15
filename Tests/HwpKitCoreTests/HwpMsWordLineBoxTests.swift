import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// MS 워드 호환 문서의 글꼴 줄 상자 (#187·#194) — win 지표와 OS/2 CJK 비트로 두 갈래를
/// 가르고, 장식선 기준 상자를 줄 상자에서 되푼다. 수치는 한글 12.30.0 실측
/// (`HwpMsWordLineBox` doc-comment).
final class HwpMsWordLineBoxTests: XCTestCase {
    /// CJK 갈래: 줄 상자 = 1.3 × win 상자, 베이스라인 = winAscent + 0.15 × win 상자 →
    /// 되푼 기준 상자가 win 지표 그대로다 (함초롬돋움 1.07/0.23).
    func testCJKFontKeepsWinMetricsAsTheDecorationBox() {
        let box = HwpMsWordLineBox(winAscent: 1.07, winDescent: 0.23, lineGap: 0, isCJK: true)
        expect(box.lineHeight).to(beCloseTo(1.69, within: 0.0001))
        expect(box.baseline).to(beCloseTo(1.265, within: 0.0001))
        expect(box.cellHeight).to(beCloseTo(1.30, within: 0.0001))
        expect(box.ascent).to(beCloseTo(1.07, within: 0.0001))
        expect(box.descent).to(beCloseTo(0.23, within: 0.0001))
    }

    /// 그 밖 갈래: 줄 상자 = win 상자 + lineGap, 베이스라인 = winAscent + lineGap →
    /// 기준 상자가 win 상자보다 작다 (Times New Roman 0.8911/0.2163 + gap 0.0425 →
    /// 0.8009/0.0836 — 한글 밑줄 −0.1023em·위 밑줄 +0.8201em·취소선 +0.2159em의 뿌리).
    func testNonCJKFontDerivesASmallerBoxFromTheLineHeight() {
        let box = HwpMsWordLineBox(
            winAscent: 0.8911, winDescent: 0.2163, lineGap: 0.0425, isCJK: false
        )
        expect(box.lineHeight).to(beCloseTo(1.1499, within: 0.0001))
        expect(box.baseline).to(beCloseTo(0.9336, within: 0.0001))
        expect(box.cellHeight).to(beCloseTo(0.8845, within: 0.0005))
        expect(box.ascent).to(beCloseTo(0.8009, within: 0.0005))
        expect(box.descent).to(beCloseTo(0.0836, within: 0.0005))
    }

    func testScaledMultipliesBothAxes() {
        let box = HwpMsWordLineBox(lineHeight: 1.69, baseline: 1.265).scaled(by: 20)
        expect(box.lineHeight).to(beCloseTo(33.8, within: 0.0001))
        expect(box.baseline).to(beCloseTo(25.3, within: 0.0001))
        expect(box.ascent).to(beCloseTo(21.4, within: 0.0001))
    }

    /// 줄 상자는 축별 최댓값이다 — 높이는 Apple SD 20pt(31.2), 베이스라인은 Menlo
    /// 20pt(22.06)에서 온다 (한글 줄 캐시 3119·2207).
    func testUnionTakesEachAxisFromTheTallestRun() {
        let appleSD = HwpMsWordLineBox(winAscent: 0.9, winDescent: 0.3, lineGap: 0, isCJK: true)
            .scaled(by: 20)
        let menlo = HwpMsWordLineBox(
            winAscent: 0.9282, winDescent: 0.2358, lineGap: 0, isCJK: true
        ).scaled(by: 20)
        let line = try? XCTUnwrap(HwpMsWordLineBox.union([appleSD, menlo]))
        expect(line?.lineHeight).to(beCloseTo(31.2, within: 0.001))
        expect(line?.baseline).to(beCloseTo(22.056, within: 0.001))
        expect(HwpMsWordLineBox.union([])).to(beNil())
        expect(HwpMsWordLineBox.union([appleSD])) == appleSD
    }

    /// Menlo는 CJK 글리프가 없지만 OS/2 `ulUnicodeRange2` 비트 57(비평면 0)이 켜져 있어
    /// CJK 갈래다 — win 0.9282/0.2358이 기준 상자 그대로다.
    func testMenloReadsAsCJKWinMetrics() {
        let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)
        let box = HwpMsWordLineBox.metrics(of: font)
        expect(box.cellHeight).to(beCloseTo(1.164, within: 0.001))
        expect(box.ascent).to(beCloseTo(0.9282, within: 0.001))
        expect(box.descent).to(beCloseTo(0.2358, within: 0.001))
        expect(box.lineHeight).to(beCloseTo(1.3 * 1.164, within: 0.002))
        // 같은 PostScript 이름은 크기가 달라도 같은 em 상자다 (캐시 열쇠).
        expect(HwpMsWordLineBox.metrics(of: CTFontCreateWithName("Menlo" as CFString, 40, nil)))
            == box
    }

    /// Helvetica는 CJK 비트가 없어 그 밖 갈래다 — win 0.9502/0.2251, gap 0 →
    /// 줄 상자 1.1753, 되푼 기준 상자 0.8146/0.0895 (한글 밑줄 −0.1080em의 뿌리).
    func testHelveticaReadsAsNonCJKLineHeight() throws {
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        try XCTSkipUnless(
            (CTFontCopyPostScriptName(font) as String) == "Helvetica", "Helvetica 없음"
        )
        let box = HwpMsWordLineBox.metrics(of: font)
        expect(box.lineHeight).to(beCloseTo(1.1753, within: 0.001))
        expect(box.baseline).to(beCloseTo(0.9502, within: 0.001))
        expect(box.ascent).to(beCloseTo(0.8146, within: 0.001))
        expect(box.descent).to(beCloseTo(0.0895, within: 0.001))
    }

    /// CJK 비트 마스크: 48–59·61만 — 60(사용자 영역)·62(알파벳 표현형)·63(아랍 표현형
    /// A)은 Courier New·Times New Roman·Arial이 갖고도 그 밖 갈래고, 47 아래는 라틴·
    /// 기호 블록이다 (한글 실측: Georgia 사본에 비트를 하나씩 켠 합성 글꼴).
    func testCJKMaskCoversTheMeasuredBits() {
        let mask = HwpMsWordLineBox.cjkUnicodeRange2Mask
        for bit in [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 61] {
            expect(mask & (1 << UInt32(bit - 32)) != 0).to(beTrue(), description: "\(bit)")
        }
        for bit in [32, 45, 46, 47, 60, 62, 63] {
            expect(mask & (1 << UInt32(bit - 32)) == 0).to(beTrue(), description: "\(bit)")
        }
    }

    /// win 합이 UInt16을 넘는 글꼴도 트랩 없이 읽는다 — macOS 기본 탑재 KhmerMN은
    /// usWinAscent 2294 + usWinDescent 64143 = 66,437(upem 2048)이라 UInt16 덧셈이면
    /// 산술 오버플로로 죽는다 (#187 리뷰; 크메르 글자의 대체 글꼴로 어느 문서에서든
    /// 나올 수 있다).
    func testWinSumBeyondUInt16DoesNotTrap() throws {
        let font = CTFontCreateWithName("KhmerMN" as CFString, 10, nil)
        try XCTSkipUnless((CTFontCopyPostScriptName(font) as String) == "KhmerMN", "KhmerMN 없음")
        let box = HwpMsWordLineBox.metrics(of: font)
        // 66,437 / 2048 = 32.44em — 그 밖 갈래면 그대로(+gap), CJK 갈래면 1.3배.
        expect(box.lineHeight).to(beGreaterThan(32.4))
        expect(box.lineHeight).to(beLessThan(43))
        expect(box.baseline).to(beGreaterThan(1.0))
    }

    /// 표를 못 읽는 글꼴은 CoreText 보고값으로 그 밖 갈래를 만든다.
    func testFallbackUsesCoreTextMetricsAsNonCJK() {
        let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)
        let box = HwpMsWordLineBox.fallback(from: font)
        let expected = HwpMsWordLineBox(
            winAscent: CTFontGetAscent(font) / 10, winDescent: CTFontGetDescent(font) / 10,
            lineGap: CTFontGetLeading(font) / 10, isCJK: false
        )
        expect(box) == expected
        expect(box.lineHeight).to(beCloseTo(1.164, within: 0.002))
    }
}
