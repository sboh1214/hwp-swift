import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 한글 2007 호환 문서(표 55 대상 프로그램 1, `HWP200X`)의 장식선 (#210) — 두께가
/// 글자 크기와 무관한 **고정 0.36pt**이고, 밑줄은 한글 문서와 **같은 가장자리**
/// (아래 0.15em·위 0.85em)에 그 얇은 선을 얹는다. 취소선 중심은 한글 문서와 같다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-22, `CharShape`
/// HWPX 기반 합성 문서에 `targetProgram="HWP200X"`를 적고 `hp:linesegarray`를 지워
/// 한글이 새로 조판하게 했다): 9개 글꼴 × 5~100pt 22개 크기에서 두께가 전부 0.36pt고
/// 중심은 40pt에서 밑줄 −6.12pt · 위 밑줄 +34.20pt · 취소선 +14.04pt다 (같은 문서를
/// 한글 문서 모드로 바꾸면 −6.84 · +34.80 · +13.92pt이고 두께는 1.56pt). 산식과
/// 실측 표는 `HwpRenderTuning.Text`의 `hwp200X*` doc-comment에 있다.
///
/// `extension`에 두는 이유는 본문 타입이 `type_body_length` 경고선에 닿아 있어서다.
/// 래스터·측정 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let hwp200X = NSNumber(value: HwpCompatibleDocumentTarget.hwp200X.rawValue)

    /// `baseSize`는 글자 모양 기본 크기(`baseFontSize`) — 슬롯 상대 크기로 줄어든 run은
    /// `size`가 작고 `baseSize`가 크다. `target`이 nil이면 한글 문서 run이다.
    private func hwp2007Run(
        size: CGFloat, color: CGColor,
        underline: Bool = false, above: Bool = false, strikethrough: Bool = false,
        trackInsert: Bool = false,
        target: NSNumber? = HwpDecorationLineGeometryTests.hwp200X,
        baseSize: CGFloat? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(baseSize ?? size)),
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = target
        }
        if underline {
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = color
        }
        if above {
            attributes[HwpAttributedStringKey.underlineAboveStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = color
        }
        if strikethrough {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = color
        }
        if trackInsert {
            attributes[HwpAttributedStringKey.trackInsertUnderline] = color
        }
        return attributes
    }

    private static let probeCyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)

    private static func isProbeCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    /// 빈칸 run 하나에 선을 그려 중심(pt, 위에서부터)과 두께(pt)를 잰다 — 글리프 잉크가
    /// 없으므로 열의 잉크는 선뿐이고, 청록은 R 채널이 0이라 커버리지 합이 두께가 된다.
    private func blankLine(
        _ attributes: [NSAttributedString.Key: Any]
    ) throws -> (center: CGFloat, thickness: CGFloat) {
        let raster = try render(text: NSAttributedString(string: "    ", attributes: attributes))
        return try (
            center: XCTUnwrap(Self.rowCenter(raster, where: Self.isProbeCyan), "선 중심"),
            thickness: XCTUnwrap(Self.lineThickness(raster) { red, _, _ in red }, "선 두께")
        )
    }

    private static let probeMagenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)

    private static func isProbeMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    /// 빈칸 run 둘(작게 청록 + 크게 자홍)을 **한 줄에** 그려 두 선의 행 중심을 잰다 —
    /// 크기가 달라도 베이스라인이 하나라 자리를 바로 견줄 수 있다.
    private func blankCenters(
        small: [NSAttributedString.Key: Any], large: [NSAttributedString.Key: Any]
    ) throws -> (small: CGFloat, large: CGFloat) {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "    ", attributes: small))
        text.append(NSAttributedString(string: "    ", attributes: large))
        let raster = try render(text: text)
        return try (
            small: XCTUnwrap(Self.rowCenter(raster, where: Self.isProbeCyan), "작은 선"),
            large: XCTUnwrap(Self.rowCenter(raster, where: Self.isProbeMagenta), "큰 선")
        )
    }

    /// 글자 아래 밑줄 — 한글 2007 호환 문서에서는 두께가 0.36pt이고 중심은 한글 문서보다
    /// 베이스라인 쪽으로 (1.56 − 0.36) / 2 = 0.6pt 올라온다 (40pt 기준: 한글 문서
    /// −6.80pt → 한글 2007 −6.18pt, 한글 PDF −6.84 → −6.12). **위 가장자리**(중심 +
    /// 두께 절반 = −6.0pt = −0.15em)는 두 갈래가 같다.
    func testHwp2007UnderlineKeepsTheNativeEdgeAndUsesAFixedThickness() throws {
        let size = Self.largeSize
        let compat = try blankLine(hwp2007Run(size: size, color: Self.probeCyan, underline: true))
        let native = try blankLine(
            hwp2007Run(size: size, color: Self.probeCyan, underline: true, target: nil)
        )
        expect(compat.thickness).to(beCloseTo(0.36, within: 0.06))
        expect(native.thickness).to(beCloseTo(size * 0.04, within: 0.12))
        // 래스터는 아래로 y가 커진다 — 밑줄이 베이스라인 쪽으로 올라오면 값이 작아진다.
        expect(native.center - compat.center)
            .to(beCloseTo((native.thickness - compat.thickness) / 2, within: 0.1))
        // 베이스라인 쪽 가장자리(래스터는 y가 아래로 커지므로 중심 − 두께 절반)는 같다.
        expect(compat.center - compat.thickness / 2)
            .to(beCloseTo(native.center - native.thickness / 2, within: 0.1))
    }

    /// 글자 위 밑줄 — 같은 규칙이 반대 방향이다: 중심이 한글 문서보다 0.6pt 내려오고
    /// (40pt: +34.80 → +34.18pt) **아래 가장자리** 0.85em은 같다.
    func testHwp2007AboveUnderlineKeepsTheNativeEdge() throws {
        let size = Self.largeSize
        let compat = try blankLine(hwp2007Run(size: size, color: Self.probeCyan, above: true))
        let native = try blankLine(
            hwp2007Run(size: size, color: Self.probeCyan, above: true, target: nil)
        )
        expect(compat.thickness).to(beCloseTo(0.36, within: 0.06))
        expect(compat.center - native.center)
            .to(beCloseTo((native.thickness - compat.thickness) / 2, within: 0.1))
        expect(compat.center + compat.thickness / 2)
            .to(beCloseTo(native.center + native.thickness / 2, within: 0.1))
    }

    /// 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함)은 **중심이 한글 문서와 같고**
    /// 두께만 갈린다 — 한글 PDF 40pt에서 +14.04pt(한글 2007)와 +13.92pt(한글 문서)가
    /// 장치 양자화 한 단위 안이다.
    func testHwp2007StrikethroughKeepsTheNativeCenter() throws {
        let size = Self.largeSize
        let compat = try blankLine(
            hwp2007Run(size: size, color: Self.probeCyan, strikethrough: true)
        )
        let native = try blankLine(
            hwp2007Run(size: size, color: Self.probeCyan, strikethrough: true, target: nil)
        )
        expect(compat.center).to(beCloseTo(native.center, within: 0.1))
        expect(compat.thickness).to(beCloseTo(0.36, within: 0.06))
        expect(native.thickness).to(beCloseTo(size * 0.04, within: 0.12))
    }

    /// 두께는 크기를 따라가지 않는다 — 20pt와 40pt 밑줄이 같은 0.36pt다 (한글 실측:
    /// 5~100pt 22개 크기 전부 0.36pt). 한글 문서에서는 0.8pt와 1.6pt로 갈린다.
    func testHwp2007LineThicknessDoesNotScaleWithFontSize() throws {
        let probe = try thicknessProbe { size, color in
            hwp2007Run(size: size, color: color, underline: true)
        }
        expect(probe.small).to(beCloseTo(0.36, within: 0.06))
        expect(probe.large).to(beCloseTo(0.36, within: 0.06))
        let native = try thicknessProbe { size, color in
            hwp2007Run(size: size, color: color, underline: true, target: nil)
        }
        expect(native.large - native.small)
            .to(beCloseTo((Self.largeSize - Self.smallSize) * 0.04, within: 0.12))
    }

    /// 자리의 기준 크기는 run 글꼴 크기가 아니라 **글자 모양 기본 크기**다 — 기본 40pt·
    /// 슬롯 상대 크기 50%로 20pt가 된 run의 밑줄이 40pt 자리에 남는다 (한글 실측
    /// 2026-09-22: −6.24pt, 20pt 자리라면 −3.24pt).
    func testHwp2007LinesUseTheCharShapeBaseFontSize() throws {
        // 기본 40pt·슬롯 50%인 20pt run과 40pt run을 한 줄에 — 베이스라인이 같으므로 두 선의
        // 행을 바로 견줄 수 있다. 기준이 기본 크기라면 같은 자리다.
        let scaled = try blankCenters(
            small: hwp2007Run(
                size: Self.smallSize, color: Self.probeCyan, underline: true,
                baseSize: Self.largeSize
            ),
            large: hwp2007Run(size: Self.largeSize, color: Self.probeMagenta, underline: true)
        )
        expect(scaled.small).to(beCloseTo(scaled.large, within: 0.1))
        // 대조: 기본 크기까지 20pt인 run은 0.15 × 20 = 3.0pt 위다 (두께가 같아 중심 차이가
        // 곧 가장자리 차이다).
        let plain = try blankCenters(
            small: hwp2007Run(size: Self.smallSize, color: Self.probeCyan, underline: true),
            large: hwp2007Run(size: Self.largeSize, color: Self.probeMagenta, underline: true)
        )
        expect(plain.large - plain.small)
            .to(beCloseTo(0.15 * (Self.largeSize - Self.smallSize), within: 0.1))
    }

    /// 변경 추적 삽입 밑줄은 일반 밑줄과 같은 자리·두께다 (한글 실측: 쪽이 0.8배로 줄어
    /// 글리프가 31.68pt로 찍힌 표본에서 삽입 밑줄 −4.92pt = 일반 밑줄).
    func testHwp2007TrackInsertUnderlineMatchesTheNormalUnderline() throws {
        let insert = try blankLine(
            hwp2007Run(size: Self.largeSize, color: Self.probeCyan, trackInsert: true)
        )
        let underline = try blankLine(
            hwp2007Run(size: Self.largeSize, color: Self.probeCyan, underline: true)
        )
        expect(insert.center).to(beCloseTo(underline.center, within: 0.05))
        expect(insert.thickness).to(beCloseTo(underline.thickness, within: 0.05))
    }
}
