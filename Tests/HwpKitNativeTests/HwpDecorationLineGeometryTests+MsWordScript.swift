import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// MS 워드 호환 문서의 첨자 취소선 (#248) — 위·아래 첨자 run의 취소선(글자 가운데 밑줄 포함)은
/// **첨자로 옮겨진 베이스라인** 위, 같은 글꼴·기본 크기 보통 글자 취소선 높이의
/// `msWordScriptStrikethroughScale`(0.696)배에 놓인다. 한글 문서·한글 2007 호환 문서 갈래는 그
/// 배율로 첨자 글리프 축소 비율(0.64)을 쓴다 (#179·#210 — 한글 실측은 0.636). 두께는 한글 문서·MS
/// 워드 호환 문서가 축소 전 기본 크기 × 0.04, 한글 2007 호환 문서가 크기와 무관한 고정 0.36pt다
/// (#210).
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-02, 글꼴 10종 × 8~100pt × 위·아래
/// 첨자 360표본 — `HwpRenderTuning.Text.msWordScriptStrikethroughScale`의 doc-comment). 여기서는
/// Menlo(win 0.9282/0.2358, CJK 비트 → 장식 상자 `ascent` 0.9282em)로 산식을 수치와 픽셀로 잰다 —
/// 쪽 좌표의 실물 핀은 `ms-word-script-strikethrough` 픽스처 쌍
/// (`FixtureDecorationLineRenderTests+MsWordScript`)이다.
///
/// `extension`에 두는 이유는 `HwpDecorationLineGeometryTests` 본문이 `type_body_length`
/// 경고선에 닿아 있어서다. 래스터·측정 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    /// `HwpTextRunBuilder.superscriptScale` — 첨자 글리프 축소 비율 (#204)
    private static let glyphScriptScale: CGFloat = 0.64
    private static let msWordScriptSize: CGFloat = 40

    /// 조판이 싣는 run 속성을 흉내 낸다 — `shift`가 있으면 첨자 run(줄어든 글꼴, 축소 전 크기
    /// `spaceTargetSize`, 첨자 몫 키 두 개), 없으면 보통 run. `target`이 nil이면 한글 문서다.
    private func msWordScriptRun(
        size: CGFloat, shift: CGFloat? = nil, color: CGColor,
        target: HwpCompatibleDocumentTarget? = .msWord
    ) -> [NSAttributedString.Key: Any] {
        let fontSize = shift == nil ? size : size * Self.glyphScriptScale
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, fontSize, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: color,
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                value: target.rawValue
            )
        }
        if let shift {
            for key in [
                HwpAttributedStringKey.glyphBaselineOffset,
                HwpAttributedStringKey.scriptBaselineOffset,
            ] {
                attributes[key] = NSNumber(value: Double(shift))
            }
        }
        return attributes
    }

    private func menlo(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("Menlo" as CFString, size, nil)
    }

    /// 보통 글자 취소선 높이 F = 0.273 × `ascent` × 기본 크기 (Menlo 40pt 10.136pt)
    private var msWordPlainStrikeHeight: CGFloat {
        HwpMsWordLineBox.metrics(of: menlo(Self.msWordScriptSize)).ascent
            * HwpRenderTuning.Text.msWordStrikethroughAscentRatio * Self.msWordScriptSize
    }

    /// 산식 자체 — MS 워드 호환 문서의 첨자 run은 보통 run 취소선 높이의 0.696배(7.055pt), 두께는
    /// 기본 크기 40pt 몫의 획 13u = 1.56pt다 (#252). 한글 문서·한글 2007 호환 문서의 첨자 run은 종전대로 0.35 × 축소 크기
    /// (8.96pt)다 — 그 갈래는 첨자 배율로 글리프 축소 비율을 쓴다. 수정 전 MS 워드 갈래는 0.64배
    /// (6.487pt)라 40pt에서 0.57pt 낮았다.
    func testMsWordScriptStrikethroughHeightIsTheScaledPlainHeight() {
        let layer = HwpPageLayer()
        let size = Self.msWordScriptSize
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let plain = layer.strikethroughLine(
            msWordScriptRun(size: size, color: cyan), msWordFont: menlo(size), fontSize: size
        )
        expect(plain.center).to(beCloseTo(msWordPlainStrikeHeight, within: 0.000_1))
        expect(plain.center).to(beCloseTo(10.136, within: 0.001))

        let scriptSize = size * Self.glyphScriptScale
        let scripted = layer.strikethroughLine(
            msWordScriptRun(size: size, shift: 0.44 * size, color: cyan),
            msWordFont: menlo(scriptSize), fontSize: scriptSize
        )
        expect(scripted.center).to(beCloseTo(
            plain.center * HwpRenderTuning.Text.msWordScriptStrikethroughScale, within: 0.000_1
        ))
        expect(scripted.center).to(beCloseTo(7.055, within: 0.001))
        expect(scripted.thickness).to(beCloseTo(1.56, within: 0.000_1))

        // 한글 문서·한글 2007 호환 문서 — 첨자 배율은 글리프 축소 비율 그대로
        for target in [nil, HwpCompatibleDocumentTarget.hwp200X] {
            let native = layer.strikethroughLine(
                msWordScriptRun(size: size, shift: 0.44 * size, color: cyan, target: target),
                msWordFont: nil, fontSize: scriptSize
            )
            expect(native.center).to(
                beCloseTo(0.35 * scriptSize, within: 0.000_1),
                description: "\(String(describing: target))"
            )
        }
    }

    /// 첨자 판정은 축소 비율이 1보다 **확실히** 작을 때다 — 보통 run의 글꼴 크기가 부동소수 오차로
    /// 축소 전 크기보다 아주 조금 작아도 첨자 배율로 떨어지지 않는다(떨어지면 선이 보통 높이의
    /// 0.3배만큼 — Menlo 40pt에서 3.08pt — 내려간다).
    /// 각주·미주 참조 번호(0.75배)는 첨자 배율을 받는다 — 한글은 그 번호의 취소선을 본문 자리에
    /// 그리므로 두 갈래 모두 아직 한글과 다르다(#256).
    func testMsWordScriptStrikethroughNeedsARealScriptReduction() {
        let layer = HwpPageLayer()
        let size = Self.msWordScriptSize
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let nearlyPlain = size * (1 - 1e-9)
        let plain = layer.strikethroughLine(
            msWordScriptRun(size: size, color: cyan), msWordFont: menlo(nearlyPlain),
            fontSize: nearlyPlain
        )
        expect(plain.center).to(beCloseTo(msWordPlainStrikeHeight, within: 0.000_1))

        let noteSize = size * 0.75
        let note = layer.strikethroughLine(
            msWordScriptRun(size: size, shift: 0.21 * size, color: cyan),
            msWordFont: menlo(noteSize), fontSize: noteSize
        )
        expect(note.center).to(beCloseTo(
            msWordPlainStrikeHeight * HwpRenderTuning.Text.msWordScriptStrikethroughScale,
            within: 0.000_1
        ))
    }

    /// 픽셀로 — Menlo 40pt 보통(청록)·위 첨자(자홍)·아래 첨자(초록) 취소선을 한 줄에 그리면, 위
    /// 첨자 선은 보통 선보다 17.6 − (1 − 0.696) × 10.136 = 14.52pt 위, 아래 첨자 선은 4.8 + 3.08
    /// = 7.88pt 아래다 (수정 전 0.64배면 13.95·8.45pt — 0.57pt씩 갈린다). 위 첨자 선이 첨자 글리프가
    /// 옮겨진 만큼 함께 오르는지도 이 간격이 잡는다.
    func testMsWordScriptStrikethroughsSitAtTheScaledHeightInARaster() throws {
        let size = Self.msWordScriptSize
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let text = NSMutableAttributedString(
            string: "xx ", attributes: msWordScriptRun(size: size, color: cyan)
        )
        text.append(NSAttributedString(
            string: "xx ",
            attributes: msWordScriptRun(size: size, shift: 0.44 * size, color: magenta)
        ))
        text.append(NSAttributedString(
            string: "xx",
            attributes: msWordScriptRun(size: size, shift: -0.12 * size, color: green)
        ))
        let raster = try render(text: text)
        let plain = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "보통 취소선"
        )
        let superscript = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "위 첨자 취소선"
        )
        let `subscript` = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 < 100 }, "아래 첨자 취소선"
        )
        let scale = HwpRenderTuning.Text.msWordScriptStrikethroughScale
        let rest = (1 - scale) * msWordPlainStrikeHeight
        // 위 방향 = 위에서부터 잰 행이 작아진다.
        expect(plain - superscript).to(beCloseTo(0.44 * size - rest, within: 0.15))
        expect(`subscript` - plain).to(beCloseTo(0.12 * size + rest, within: 0.15))
        expect(0.44 * size - rest).to(beCloseTo(14.519, within: 0.001))
        expect(0.12 * size + rest).to(beCloseTo(7.881, within: 0.001))
    }
}
