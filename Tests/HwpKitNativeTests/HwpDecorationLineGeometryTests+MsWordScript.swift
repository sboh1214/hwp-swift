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
/// 워드 호환 문서가 축소 전 기본 크기의 장치 단위 획(#252), 한글 2007 호환 문서가 크기와 무관한
/// 고정 0.36pt다 (#210).
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-02, 글꼴 10종 × 8~100pt × 위·아래
/// 첨자 360표본 — `HwpRenderTuning.Text.msWordScriptStrikethroughScale`의 doc-comment). 여기서는
/// Menlo(win 0.9282/0.2358, CJK 비트 → 줄 상자 베이스라인 높이 0.9282 + 0.15 × 1.1641 = 1.1028em)로
/// 산식을 수치와 픽셀로 잰다 — 쪽 좌표의 실물 핀은 `ms-word-script-strikethrough` 픽스처 쌍
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

    /// 보통 글자 취소선 높이 F = 0.23 × 글꼴 줄 상자 베이스라인 높이 × 기본 크기 (#257 — Menlo
    /// 40pt 0.23 × 1.1028 × 40 = 10.146pt)
    private var msWordPlainStrikeHeight: CGFloat {
        HwpMsWordLineBox.metrics(of: menlo(Self.msWordScriptSize)).baseline
            * HwpRenderTuning.Text.msWordStrikethroughBaselineRatio * Self.msWordScriptSize
    }

    /// 산식 자체 — MS 워드 호환 문서의 첨자 run은 보통 run 취소선 높이의 0.696배(7.062pt), 두께는
    /// 기본 크기 40pt 몫의 획 13u = 1.56pt다 (#252). 한글 문서·한글 2007 호환 문서의 첨자 run은 종전대로 0.35 × 축소 크기
    /// (8.96pt)다 — 그 갈래는 첨자 배율로 글리프 축소 비율을 쓴다. 수정 전 MS 워드 갈래는 0.64배
    /// (6.493pt)라 40pt에서 0.57pt 낮았다.
    func testMsWordScriptStrikethroughHeightIsTheScaledPlainHeight() {
        let layer = HwpPageLayer()
        let size = Self.msWordScriptSize
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let plain = layer.strikethroughLine(
            msWordScriptRun(size: size, color: cyan), msWordFont: menlo(size), fontSize: size
        )
        expect(plain.center).to(beCloseTo(msWordPlainStrikeHeight, within: 0.000_1))
        expect(plain.center).to(beCloseTo(10.146, within: 0.001))

        let scriptSize = size * Self.glyphScriptScale
        let scripted = layer.strikethroughLine(
            msWordScriptRun(size: size, shift: 0.44 * size, color: cyan),
            msWordFont: menlo(scriptSize), fontSize: scriptSize
        )
        expect(scripted.center).to(beCloseTo(
            plain.center * HwpRenderTuning.Text.msWordScriptStrikethroughScale, within: 0.000_1
        ))
        expect(scripted.center).to(beCloseTo(7.062, within: 0.001))
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
    /// 각주·미주 참조 번호(0.75배)는 첨자가 아니다 — 번호 run은 `noteReferenceScale`을 실어
    /// 렌더러가 그 축소를 무르므로(`strikethroughRunFontSize`) 보통 높이에 그린다. 한글도 번호의
    /// 취소선을 본문 자리에 그린다 (#256, 2026-10-06 실측: 함초롬바탕 20pt 본문·번호 모두 +5.88pt).
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
        var noteRun = msWordScriptRun(size: size, color: cyan)
        noteRun[kCTFontAttributeName as NSAttributedString.Key] = menlo(noteSize)
        noteRun[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(value: Double(0.21 * size))
        noteRun[HwpAttributedStringKey.noteReferenceScale] = NSNumber(value: 0.75)
        let note = layer.strikethroughLine(
            noteRun, msWordFont: menlo(noteSize),
            fontSize: layer.strikethroughRunFontSize(noteRun)
        )
        expect(note.center).to(beCloseTo(msWordPlainStrikeHeight, within: 0.000_1))
    }

    /// 픽셀로 — Menlo 40pt 보통(청록)·위 첨자(자홍)·아래 첨자(초록) 취소선을 한 줄에 그리면, 위
    /// 첨자 선은 보통 선보다 17.6 − (1 − 0.696) × 10.146 = 14.52pt 위, 아래 첨자 선은 4.8 + 3.08
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
        expect(0.44 * size - rest).to(beCloseTo(14.516, within: 0.001))
        expect(0.12 * size + rest).to(beCloseTo(7.884, within: 0.001))
    }

    /// 렌더러 경로 (#257) — `strikethroughLine`은 run의 취소선 글꼴(`msWordStrikethroughFonts`가 고른 첫
    /// 글리프 글꼴)의 표에서 줄 상자를 읽어 **베이스라인 높이**(줄 상자 윗변 → 베이스라인)의 0.23배에
    /// 선을 놓는다. 시스템 글꼴 40pt가 한글 12.30.0 PDF(2026-10-07)와 장치 단위 한 칸(0.12pt) 안이다 —
    /// Zapfino 17.28·Palatino 13.08·Times New Roman 8.64pt. 종전 장식 상자 `ascent` × 0.273은 Zapfino
    /// 14.13·Palatino 12.81pt였다 (`descent`가 클수록 낮다). 글꼴이 없는 기기는 그 글꼴을 건너뛴다.
    func testMsWordStrikethroughReadsTheBaselineHeightOfTheRunFont() throws {
        let layer = HwpPageLayer()
        let size: CGFloat = 40
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        struct SystemFont {
            let name: String
            let postScript: String
            /// 한글 PDF의 취소선 높이 (pt)
            let hancom: CGFloat
        }
        let fonts = [
            SystemFont(name: "Zapfino", postScript: "Zapfino", hancom: 17.28),
            SystemFont(name: "Palatino", postScript: "Palatino-Roman", hancom: 13.08),
            SystemFont(name: "Times New Roman", postScript: "TimesNewRomanPSMT", hancom: 8.64),
        ]
        var measured = 0
        for sample in fonts {
            let font = CTFontCreateWithName(sample.name as CFString, size, nil)
            guard (CTFontCopyPostScriptName(font) as String) == sample.postScript else { continue }
            measured += 1
            let line = layer.strikethroughLine(
                msWordScriptRun(size: size, color: cyan), msWordFont: font, fontSize: size
            )
            let box = HwpMsWordLineBox.metrics(of: font)
            expect(line.center).to(
                beCloseTo(0.23 * box.baseline * size, within: 0.000_1), description: sample.name
            )
            expect(line.center).to(
                beCloseTo(sample.hancom, within: 0.12), description: "\(sample.name) 한글"
            )
        }
        try XCTSkipIf(measured == 0, "Zapfino·Palatino·Times New Roman이 모두 없음")
    }
}
