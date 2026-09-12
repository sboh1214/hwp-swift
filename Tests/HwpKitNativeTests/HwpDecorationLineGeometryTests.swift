import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 글자 장식 선(취소선·글자 위/아래 밑줄·변경 추적 삭제선/삽입 밑줄)의 세로
/// 위치와 **두께**가 **글자 크기에 비례**한다는 것과 그 비율을 고정한다 (#136, #176).
///
/// 한 줄에 크기가 다른 두 run을 놓으면 베이스라인이 하나로 공유되므로, 두 선의
/// 행 간격이 곧 `비율 × 크기 차`다 — 폰트·조판 구현과 무관하게 비율만 잰다.
/// 두께는 글리프가 없는 빈칸 run 위에 그린 선의 세로 잉크 합(안티앨리어싱
/// 커버리지 합 = 면적)으로 잰다. 절대 위치(실물 문서에서 어느 행에 떨어지는지)는
/// `FixtureDecorationLineRenderTests`가 픽스처로 잡는다.
///
/// 실측 근거는 `HwpRenderTuning.Text`의 각 상수 doc-comment에 있다
/// (한글.app 12.30.0 PDF 내보내기, 2026-09-08·2026-09-12).
final class HwpDecorationLineGeometryTests: XCTestCase {
    static let scale: CGFloat = 8
    static let smallSize: CGFloat = 20
    static let largeSize: CGFloat = 40

    struct Probe {
        let small: CGFloat
        let large: CGFloat
        /// 위 방향(작은 크기 → 큰 크기) 이동량. 베이스라인 **위** 장식이면 양수.
        var rise: CGFloat {
            small - large
        }
    }

    /// 취소선은 베이스라인 **위** 0.35em이다 — 크기가 2배가 되면 선도 그만큼
    /// 위로 간다. 종전 산식(폰트 x-height의 절반)은 한글 실물보다 낮았다.
    func testStrikethroughRisesWithFontSize() throws {
        let probe = try probe { size, color in
            strikethroughAttributes(size: size, color: color)
        }
        let expected = HwpRenderTuning.Text.strikethroughCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(7.0, within: 0.001))
    }

    /// 변경 추적 삭제선은 같은 취소선 경로를 쓰되 `trackChangeStrikethroughCenterRatio`
    /// (0.29em, `track-changes` 실물 = MS Word 호환 문서의 값)로 갈린다 — 일반
    /// 취소선과 다른 비율로 그려짐을 고정한다. 네이티브 문서에서 한글은 둘을 같은
    /// 자리에 그리므로 이 분리는 호환 모드 분기(#187)까지의 픽스처 정합이다.
    func testTrackChangeStrikethroughUsesItsOwnRatio() throws {
        let probe = try probe { size, color in
            strikethroughAttributes(size: size, color: color, trackChange: true)
        }
        let expected = HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio)
            < HwpRenderTuning.Text.strikethroughCenterRatio
    }

    /// 밑줄 '글자 위'(표 33 밑줄 종류 3)는 베이스라인 위 0.87em이다.
    func testAboveUnderlineRisesWithFontSize() throws {
        let probe = try probe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        let expected = HwpRenderTuning.Text.underlineAboveCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(17.4, within: 0.001))
    }

    /// 키 큰 인라인 개체가 섞인 줄에서도 '글자 위' 밑줄은 취소선과 같은
    /// 베이스라인을 기준으로 놓인다 — 둘의 간격은 항상 `(0.87 − 0.35) × 크기`다.
    ///
    /// 밑줄 '글자 아래'만 `underlineReturnDrop`으로 되돌린 원점을 쓴다 (실물은
    /// 밑줄을 개체 하단에 남긴다). 그 되돌림을 위쪽 밑줄에도 적용하면 선이
    /// 개체 ascent의 15%만큼 내려가 글자 **아래**로 떨어진다 (100pt 개체 + 10pt
    /// 글자에서 베이스라인 위 8.7pt 대신 아래 6.3pt).
    func testAboveUnderlineIgnoresInlineObjectReturnDrop() throws {
        let size: CGFloat = 10
        let text = NSMutableAttributedString(string: "AA ", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: CGColor(red: 0, green: 1, blue: 1, alpha: 1),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: CGColor(
                red: 1, green: 0, blue: 1, alpha: 1
            ),
        ])
        // 높이 100pt 인라인 개체 — 줄 베이스라인을 끌어올려 되돌림을 켠다.
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { _ in },
            getAscent: { _ in 100 },
            getDescent: { _ in 0 },
            getWidth: { _ in 40 }
        )
        let delegate = try XCTUnwrap(CTRunDelegateCreate(&callbacks, nil))
        text.append(NSAttributedString(string: "\u{FFFC}", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
        ]))

        let raster = try render(text: text)
        let above = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "위쪽 밑줄"
        )
        let strike = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "취소선"
        )
        let expected = (HwpRenderTuning.Text.underlineAboveCenterRatio
            - HwpRenderTuning.Text.strikethroughCenterRatio) * size
        expect(strike - above).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(5.2, within: 0.001))
    }

    /// 첨자로 글꼴이 줄어도 '글자 위' 밑줄은 **줄기 전 크기**로 그린다 — 한글이
    /// 이 선만 기본 크기를 유지하기 때문이다 (2026-09-09 실측). 같은 run의
    /// 취소선은 반대로 줄어든 글꼴 크기를 따르므로, 두 선의 간격이 두 기준을
    /// 한꺼번에 고정한다.
    func testAboveUnderlineKeepsPreScriptSize() throws {
        let preScript: CGFloat = 10
        let shrunk = preScript * 0.67 // HwpTextRunBuilder.superscriptScale
        let text = NSAttributedString(string: "AA", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, shrunk, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(preScript)),
            HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: CGColor(red: 0, green: 1, blue: 1, alpha: 1),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: CGColor(
                red: 1, green: 0, blue: 1, alpha: 1
            ),
        ])

        let raster = try render(text: text)
        let above = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "위쪽 밑줄"
        )
        let strike = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "취소선"
        )
        // 둘 다 베이스라인 **위**라 간격은 두 높이의 차다.
        let expected = HwpRenderTuning.Text.underlineAboveCenterRatio * preScript
            - HwpRenderTuning.Text.strikethroughCenterRatio * shrunk
        expect(strike - above).to(beCloseTo(expected, within: 0.2))
        // 위 밑줄까지 줄어든 글꼴 크기로 그리면 8.7이 5.83으로 내려가 간격이
        // 6.355 → 3.484로 좁아진다.
        expect(expected).to(beCloseTo(6.355, within: 0.001))
    }

    /// 밑줄 '글자 아래'는 베이스라인 **아래** 0.17em이다 (#176) — 큰 글자일수록
    /// 아래로 간다. 종전 0.20em은 한글보다 10pt에서 0.3pt, 40pt에서 1.2pt 낮았다.
    func testBelowUnderlineDropsWithFontSize() throws {
        let probe = try probe { size, color in
            belowUnderlineAttributes(size: size, color: color)
        }
        let expected = -HwpRenderTuning.Text.underlineBelowCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(-3.4, within: 0.001))
    }

    /// 변경 추적 삽입 밑줄은 베이스라인 아래 0.26em이다 (#176, `track-changes`
    /// 실물). 종전에는 사각형의 **아래 모서리**를 0.35em에 두어 중심이 크기에
    /// 비례하지 않았다 (두 크기의 차가 0.35 × 20 = 7.0pt로 나왔다).
    func testTrackInsertUnderlineDropsWithFontSize() throws {
        let probe = try probe { size, color in
            trackInsertUnderlineAttributes(size: size, color: color)
        }
        let expected = -HwpRenderTuning.Text.trackChangeInsertUnderlineCenterRatio
            * (Self.largeSize - Self.smallSize)
        expect(probe.rise).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(-5.2, within: 0.001))
    }

    /// 취소선 두께는 글자 크기의 0.04배다 (#176) — 20pt 0.8pt, 40pt 1.6pt.
    /// 종전 0.4pt 고정은 40pt에서 한글(1.56pt)의 1/4이었다.
    func testStrikethroughThicknessScalesWithFontSize() throws {
        let probe = try thicknessProbe { size, color in
            strikethroughAttributes(size: size, color: color)
        }
        let ratio = HwpRenderTuning.Text.decorationLineThicknessRatio
        expect(probe.small).to(beCloseTo(ratio * Self.smallSize, within: 0.05))
        expect(probe.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(ratio * Self.largeSize).to(beCloseTo(1.6, within: 0.001))
    }

    /// 아래·위 밑줄도 취소선과 같은 0.04em 두께다.
    func testUnderlineThicknessScalesWithFontSize() throws {
        let ratio = HwpRenderTuning.Text.decorationLineThicknessRatio
        let below = try thicknessProbe { size, color in
            belowUnderlineAttributes(size: size, color: color)
        }
        expect(below.small).to(beCloseTo(ratio * Self.smallSize, within: 0.05))
        expect(below.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))

        let above = try thicknessProbe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        expect(above.small).to(beCloseTo(ratio * Self.smallSize, within: 0.05))
        expect(above.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(ratio * Self.smallSize).to(beCloseTo(0.8, within: 0.001))
    }

    /// 변경 추적 삽입 밑줄은 일반 선보다 굵은 0.064em이다 — 20pt 1.28pt, 40pt 2.56pt.
    /// 종전 0.75pt 고정은 40pt에서 한글(0.064em = 2.56pt)보다 가늘었다.
    func testTrackInsertUnderlineThicknessScalesWithFontSize() throws {
        let probe = try thicknessProbe { size, color in
            trackInsertUnderlineAttributes(size: size, color: color)
        }
        let ratio = HwpRenderTuning.Text.trackChangeInsertUnderlineThicknessRatio
        expect(probe.small).to(beCloseTo(ratio * Self.smallSize, within: 0.05))
        expect(probe.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(ratio * Self.largeSize).to(beCloseTo(2.56, within: 0.001))
        expect(ratio).to(beGreaterThan(HwpRenderTuning.Text.decorationLineThicknessRatio))
    }
}
