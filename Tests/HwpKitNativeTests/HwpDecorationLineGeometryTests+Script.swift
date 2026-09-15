import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 첨자 run의 장식선 (#179) — 취소선(글자 가운데 밑줄 포함)은 **첨자로 옮겨진
/// 베이스라인**을 따라가고 글자 위치로 옮겨진 글리프는 따라가지 않으며, 아래쪽
/// 밑줄과 모든 선의 두께는 **첨자 축소 전 크기**를 기준으로 한다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-15, 함초롬바탕·Apple SD
/// 산돌고딕 Neo 두 글꼴이 같은 값, 10·20pt):
///
/// | 조합 | 글리프 | 취소선·가운데 밑줄 | 아래 밑줄 | 위 밑줄 |
/// |---|---|---|---|---|
/// | 위 첨자 | 6.36pt · +4.44 | 옮겨진 베이스라인 + 0.35 × 6.36 | 원래 −0.17 × 10 | 원래 +0.87 × 10 |
/// | 아래 첨자 | 6.36pt · −1.20 | 옮겨진 베이스라인 + 0.35 × 6.36 | 원래 −0.17 × 10 | 원래 +0.87 × 10 |
/// | 글자 위치 50 | 10pt · −5.04 | 제자리 | 제자리 | 제자리 |
/// | 위 첨자 + 위치 50 | 6.36pt · −0.60 | 위 첨자와 같은 자리 | 제자리 | 제자리 |
///
/// 선 두께는 네 조합 모두 본문과 같은 0.36pt(0.04em = 0.4pt의 0.12pt 장치 양자화)다.
///
/// `extension`에 두는 이유는 `HwpDecorationLineGeometryTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다. 래스터·측정 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let baseSize: CGFloat = 10
    /// `HwpTextRunBuilder.superscriptScale` — 첨자 글꼴 크기
    private static let scriptSize: CGFloat = 10 * 0.67
    /// `HwpTextRunBuilder.superscriptBaselineRatio` × 기본 크기 — 첨자 올림
    private static let scriptShift: CGFloat = 10 * 0.33
    /// 글자 위치 50 → 아래 5pt (렌더러 규약 양수 = 위). 첨자 몫 +3.3과 합치면 합산 키가
    /// −1.7이라, 합산 키를 잘못 더하는 회귀가 아래 밑줄 테스트에서 1.7pt 차로 드러난다
    /// (글자 위치 30이면 합이 +0.3이라 허용 오차 안에 묻힌다).
    private static let locationShift: CGFloat = -5

    private static func isGreen(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue < 100
    }

    private func font(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("Menlo" as CFString, size, nil)
    }

    /// 취소선 run 속성 — `script`가 참이면 첨자 run(줄어든 글꼴·축소 전 크기·첨자
    /// 몫 키), `location`은 글자 위치 몫. 합산 키는 두 몫의 합이다.
    private func strikethroughRun(
        color: CGColor, script: Bool = false, location: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font(
                script ? Self.scriptSize : Self.baseSize
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(Self.baseSize)),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: color,
        ]
        let shift = (script ? Self.scriptShift : 0) + location
        if shift != 0 {
            attributes[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(
                value: Double(shift)
            )
        }
        if script {
            attributes[HwpAttributedStringKey.scriptBaselineOffset] = NSNumber(
                value: Double(Self.scriptShift)
            )
        }
        return attributes
    }

    private func belowUnderlineRun(
        color: CGColor, script: Bool = false, location: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        underlineRun(
            HwpAttributedStringKey.underlineStyle, color: color, script: script, location: location
        )
    }

    private func aboveUnderlineRun(
        color: CGColor, script: Bool = false, location: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        underlineRun(
            HwpAttributedStringKey.underlineAboveStyle, color: color, script: script,
            location: location
        )
    }

    private func underlineRun(
        _ style: NSAttributedString.Key, color: CGColor, script: Bool, location: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attributes = strikethroughRun(color: color, script: script, location: location)
        attributes[HwpAttributedStringKey.strikethroughStyle] = nil
        attributes[HwpAttributedStringKey.strikethroughColor] = nil
        attributes[style] = NSNumber(value: 1)
        attributes[HwpAttributedStringKey.underlineColor] = color
        return attributes
    }

    /// 취소선은 첨자 몫만 따라간다 — 글자 위치만 준 run(자홍)의 선은 본문(청록)과
    /// 같은 행이고, 첨자 + 글자 위치 run(초록)의 선은 첨자 몫 3.3pt만큼 올라간 자리에
    /// 줄어든 크기의 0.35배로 놓인다. 종전에는 첨자 선만 원래 베이스라인 위
    /// 0.35 × 6.7 = 2.3pt(본문보다 1.2pt 아래)에 그려 첨자 글리프 밖으로 벗어났다.
    func testStrikethroughFollowsScriptShiftButNotFaceLocation() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "AA ", attributes: strikethroughRun(color: cyan)))
        text.append(NSAttributedString(
            string: "BB ",
            attributes: strikethroughRun(color: magenta, location: Self.locationShift)
        ))
        text.append(NSAttributedString(
            string: "CC",
            attributes: strikethroughRun(color: green, script: true, location: Self.locationShift)
        ))

        let raster = try render(text: text)
        let plain = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "본문 취소선"
        )
        let located = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "글자 위치 취소선"
        )
        let scripted = try XCTUnwrap(Self.rowCenter(raster, where: Self.isGreen), "첨자 취소선")

        expect(located).to(beCloseTo(plain, within: 0.2), description: "글자 위치는 선을 안 옮긴다")
        // 위 방향 = 위에서부터 잰 행이 작아진다. 본문 선은 +0.35 × 10, 첨자 선은
        // +3.3 + 0.35 × 6.7이라 차는 3.3 − 0.35 × 3.3 = 2.145pt다.
        let ratio = HwpRenderTuning.Text.strikethroughCenterRatio
        let expected = Self.scriptShift + ratio * Self.scriptSize - ratio * Self.baseSize
        expect(plain - scripted).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(2.145, within: 0.001))
    }

    /// 아래쪽 밑줄은 첨자에도 글자 위치에도 제자리이고 축소 전 크기 기준이다 —
    /// 첨자 + 글자 위치 run(자홍)의 선이 본문(청록)과 같은 행에 놓인다. 종전에는
    /// 줄어든 6.7pt 기준(−1.14pt)이라 0.56pt 위였다. 합산 키(−1.7)를 더하는 회귀는
    /// 1.7pt 차로, 첨자 키(+3.3)를 더하는 회귀는 3.3pt 차로 갈린다.
    func testBelowUnderlineIgnoresScriptShiftAndKeepsPreScriptSize() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "AA ", attributes: belowUnderlineRun(color: cyan)))
        text.append(NSAttributedString(
            string: "BB",
            attributes: belowUnderlineRun(
                color: magenta, script: true, location: Self.locationShift
            )
        ))

        let raster = try render(text: text)
        let plain = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "본문 밑줄"
        )
        let scripted = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "첨자 밑줄"
        )
        expect(scripted).to(beCloseTo(plain, within: 0.2))
        // 줄어든 크기를 기준으로 그리면 0.17 × (10 − 6.7) = 0.561pt 올라간다.
        let drift = HwpRenderTuning.Text.underlineBelowCenterRatio
            * (Self.baseSize - Self.scriptSize)
        expect(drift).to(beGreaterThan(0.5))
    }

    /// 위쪽 밑줄도 첨자 이동을 따라가지 않는다 — 첨자 + 글자 위치 run(자홍)의 선이
    /// 본문(청록)과 같은 행이다. 크기 기준(축소 전)은 기존
    /// `testAboveUnderlineKeepsPreScriptSize`가 잡고, 여기서는 첨자 키를 실은 run이
    /// 옮겨지지 않는 것만 더한다 (픽스처 문단 7·8의 절대 핀과 같은 성질).
    func testAboveUnderlineIgnoresScriptShift() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "AA ", attributes: aboveUnderlineRun(color: cyan)))
        text.append(NSAttributedString(
            string: "BB",
            attributes: aboveUnderlineRun(
                color: magenta, script: true, location: Self.locationShift
            )
        ))

        let raster = try render(text: text)
        let plain = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "본문 위 밑줄"
        )
        let scripted = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "첨자 위 밑줄"
        )
        expect(scripted).to(beCloseTo(plain, within: 0.2))
    }

    /// 첨자 run의 취소선·아래쪽·위쪽 밑줄 두께는 본문과 같다 (한글: 10pt 첨자 선
    /// 0.36pt = 본문). 빈칸 run 위 선의 열 커버리지 합으로 잰다 — 청록은 본문, 자홍은
    /// 첨자.
    func testScriptRunDecorationLinesKeepPreScriptThickness() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let ratio = HwpRenderTuning.Text.decorationLineThicknessRatio
        let lines: [(name: String, run: (CGColor, Bool) -> [NSAttributedString.Key: Any])] = [
            ("취소선", { self.strikethroughRun(color: $0, script: $1) }),
            ("아래 밑줄", { self.belowUnderlineRun(color: $0, script: $1) }),
            ("위 밑줄", { self.aboveUnderlineRun(color: $0, script: $1) }),
        ]
        for line in lines {
            let text = NSMutableAttributedString()
            text.append(NSAttributedString(string: "    ", attributes: line.run(cyan, false)))
            text.append(NSAttributedString(string: "    ", attributes: line.run(magenta, true)))
            let raster = try render(text: text)
            let plain = try XCTUnwrap(
                Self.lineThickness(raster) { red, _, _ in red }, "본문 선 두께"
            )
            let scripted = try XCTUnwrap(
                Self.lineThickness(raster) { _, green, _ in green }, "첨자 선 두께"
            )
            expect(plain).to(beCloseTo(ratio * Self.baseSize, within: 0.05))
            expect(scripted).to(
                beCloseTo(ratio * Self.baseSize, within: 0.05), description: line.name
            )
        }
        // 줄어든 글꼴 크기 기준이면 0.268pt로 0.4pt와 0.05 밖에서 갈린다.
        expect(ratio * Self.scriptSize).to(beCloseTo(0.268, within: 0.001))
    }
}
