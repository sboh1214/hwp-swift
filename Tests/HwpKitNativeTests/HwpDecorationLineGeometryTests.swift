import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 글자 장식 선(취소선·글자 위/아래 밑줄·변경 추적 삭제선/삽입 밑줄)의 세로
/// 위치와 **두께**가 한글 문서에서 **글자 크기에 비례**한다는 것과 그 비율을 고정한다
/// (#136, #176, #187, #226). MS 워드 호환 문서의 글꼴 지표 기하는 `+Compat`가, 밑줄의
/// 줄 단위 기준(줄 상자·줄 글자 크기)은 `+LineWide`가 잡는다.
///
/// 한 줄에 크기가 다른 두 run을 놓으면 베이스라인이 하나로 공유되므로, run 단위인
/// 취소선은 두 선의 행 간격이 곧 `비율 × 크기 차`다 — 폰트·조판 구현과 무관하게 비율만
/// 잰다. 밑줄은 줄 단위라 같은 줄의 두 run이 한 행·한 두께이고, 비율은 같은 run의
/// 취소선과의 간격으로 잰다. 두께는 글리프가 없는 빈칸 run 위에 그린 선의 세로 잉크
/// 합(안티앨리어싱 커버리지 합 = 면적)으로 잰다. 절대 위치(실물 문서에서 어느 행에
/// 떨어지는지)는 `FixtureDecorationLineRenderTests`가 픽스처로 잡는다.
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

    /// 밑줄 '글자 위'(표 33 밑줄 종류 3)는 **줄 단위**다 (#226) — 크기가 다른 두 run이 한
    /// 줄에 있으면 둘 다 그 줄 상자 상단(0.85 × 40pt) 위에 한 행으로 놓인다. 종전에는 run
    /// 크기 × 0.87이라 20pt run의 선이 17.4pt 낮았다 (한글 12.30: 40pt 글자와 한 줄인 10pt 위
    /// 밑줄 +34.20~34.80pt).
    func testAboveUnderlinesShareTheLineBoxTop() throws {
        let probe = try probe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        // run 단위로 그리면 0.87 × (40 − 20) = 17.4pt 벌어진다.
        expect(probe.rise).to(beCloseTo(0, within: 0.2))
    }

    /// 키 큰 인라인 개체가 줄 상자를 정한 줄에서 '글자 위' 밑줄은 그 상자 **상단**(= 개체
    /// 윗변, 베이스라인 위 0.85 × 100pt)에 붙는다 (#226, 한글 12.30: 10pt 위 밑줄이 40pt 그림·
    /// 표와 한 줄이면 +34.20pt). 같은 run의 취소선은 run 단위라 베이스라인 위 0.35 × 10pt에
    /// 남으므로 둘의 간격이 상자 상단을 고정한다. 아래 밑줄의 개체 하단 규칙(공공누리
    /// 실물)을 위 밑줄에 그대로 옮기면 선이 글자 **아래**로 떨어진다 (PR #175 리뷰 재현).
    func testAboveUnderlineSitsOnTheInlineObjectTop() throws {
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
        let expected = HwpDecorationLineGeometry.underlineAbove(
            lineBoxHeight: 100, thicknessFontSize: size
        ).center - HwpRenderTuning.Text.strikethroughCenterRatio * size
        expect(strike - above).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(81.7, within: 0.001))
    }

    /// 첨자로 글꼴이 줄어도 '글자 위' 밑줄은 **줄기 전 크기**로 그린다 — 한글이
    /// 아래·위 밑줄과 선 두께를 기본 크기로 유지하기 때문이다 (2026-09-09·09-15
    /// 실측, #179). 같은 run의 취소선은 반대로 줄어든 글꼴 크기를 따르므로, 두 선의
    /// 간격이 두 기준을 한꺼번에 고정한다. 이 run은 첨자 이동 키
    /// (`scriptBaselineOffset`)를 싣지 않아 취소선이 옮겨지지 않는다 — 첨자 이동을
    /// 실은 조합은 `+Script`가 잡는다.
    func testAboveUnderlineKeepsPreScriptSize() throws {
        let preScript: CGFloat = 10
        let shrunk = preScript * 0.64 // HwpTextRunBuilder.superscriptScale
        let text = NSAttributedString(string: "AA", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, shrunk, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(preScript)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(preScript)),
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
        let expected = HwpDecorationLineGeometry.underlineAbove(fontSize: preScript).center
            - HwpRenderTuning.Text.strikethroughCenterRatio * shrunk
        expect(strike - above).to(beCloseTo(expected, within: 0.2))
        // 위 밑줄까지 줄어든 글꼴 크기로 그리면 8.7이 5.568로 내려가 간격이
        // 6.46 → 3.328로 좁아진다.
        expect(expected).to(beCloseTo(6.46, within: 0.001))
    }

    /// 밑줄 '글자 아래'는 **줄 단위**다 (#226) — 크기가 다른 두 run이 한 줄에 있으면 둘 다
    /// 그 줄 상자 바닥(베이스라인 아래 0.15 × 40pt) 아래 한 행에 놓인다. 종전에는 run 크기 ×
    /// 0.17이라 20pt run의 선이 3.4pt 높았다 (한글 12.30: 10pt 밑줄 + 40pt 밑줄 줄은 두 run
    /// 모두 −6.72pt 한 선).
    func testBelowUnderlinesShareTheLineBoxBottom() throws {
        let probe = try probe { size, color in
            belowUnderlineAttributes(size: size, color: color)
        }
        expect(probe.rise).to(beCloseTo(0, within: 0.2))
    }

    /// 밑줄 '글자 아래'의 자리 비율 — 한 크기만 있는 줄에서 같은 run의 취소선과 밑줄 사이가
    /// (0.35 + 0.17) × 크기다 (#136·#176: 취소선 +0.35em, 밑줄 −0.17em = 줄 상자 바닥 0.15em +
    /// 두께 절반 0.02em). 종전 0.20em은 한글보다 10pt에서 0.3pt, 40pt에서 1.2pt 낮았다.
    func testBelowUnderlineSitsUnderTheLineBoxBottom() throws {
        let size = Self.largeSize
        var attributes = belowUnderlineAttributes(
            size: size, color: CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        )
        attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
        attributes[HwpAttributedStringKey.strikethroughColor] = CGColor(
            red: 1, green: 0, blue: 1, alpha: 1
        )
        let raster = try render(text: NSAttributedString(string: "    ", attributes: attributes))
        let below = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "밑줄"
        )
        let strike = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "취소선"
        )
        let expected = HwpRenderTuning.Text.strikethroughCenterRatio * size
            - HwpDecorationLineGeometry.underlineBelow(fontSize: size).center
        expect(below - strike).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(20.8, within: 0.001))
    }

    /// 변경 추적 삽입 밑줄은 한글 문서에서 일반 '글자 아래' 밑줄과 같은 자리다 (#187 실측:
    /// 13개 글꼴 전부 삽입 밑줄 = 일반 밑줄; #226 실측: 크기가 섞인 줄에서도 같은 줄의 일반
    /// 밑줄과 같은 y). 삽입 20pt run과 일반 밑줄 40pt run을 한 줄에 두면 한 행이다. 종전(#176)의
    /// 전용 상수 −0.26em은 `track-changes` 실물(MS 워드 호환 문서)의 함초롬돋움 값이었다.
    func testTrackInsertUnderlineSharesTheUnderlineRow() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "AA ",
            attributes: trackInsertUnderlineAttributes(size: Self.smallSize, color: cyan)
        ))
        text.append(NSAttributedString(
            string: "BB", attributes: belowUnderlineAttributes(size: Self.largeSize, color: magenta)
        ))
        let raster = try render(text: text)
        let insert = try XCTUnwrap(
            Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "삽입 밑줄"
        )
        let underline = try XCTUnwrap(
            Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "일반 밑줄"
        )
        expect(insert).to(beCloseTo(underline, within: 0.2))
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

    /// 아래·위 밑줄도 취소선과 같은 0.04em 두께지만 **줄 단위**다 (#226) — 한 줄의 밑줄은
    /// 모두 그 줄 글자의 가장 큰 기본 크기로 두께가 같다 (한글 12.30: 40pt 글자와 한 줄인
    /// 10pt 밑줄 1.56pt). 20pt만 있는 줄은 0.8pt다.
    func testUnderlineThicknessFollowsTheLargestTextOnTheLine() throws {
        let ratio = HwpRenderTuning.Text.decorationLineThicknessRatio
        let below = try thicknessProbe { size, color in
            belowUnderlineAttributes(size: size, color: color)
        }
        expect(below.small).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(below.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        let alone = try render(text: NSAttributedString(
            string: "    ",
            attributes: belowUnderlineAttributes(
                size: Self.smallSize, color: CGColor(red: 0, green: 1, blue: 1, alpha: 1)
            )
        ))
        expect(Self.lineThickness(alone) { red, _, _ in red })
            .to(beCloseTo(ratio * Self.smallSize, within: 0.05))

        let above = try thicknessProbe { size, color in
            [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                    "Menlo" as CFString, size, nil
                ),
                HwpAttributedStringKey.underlineAboveStyle: NSNumber(value: 1),
                HwpAttributedStringKey.underlineColor: color,
            ]
        }
        expect(above.small).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(above.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(ratio * Self.smallSize).to(beCloseTo(0.8, within: 0.001))
    }

    /// 변경 추적 삽입 밑줄의 두께도 한글 문서에서 일반 밑줄과 같은 0.04em이고 줄 단위다 —
    /// 20pt와 40pt가 한 줄이면 둘 다 1.6pt (#226 실측: 40pt 글자와 한 줄인 10pt 삽입 밑줄도
    /// 40pt 몫). 종전(#176)의 0.064em은 MS 워드 호환 문서의 함초롬돋움 값이라 한글
    /// 문서에서는 1.6배 굵었다.
    func testTrackInsertUnderlineThicknessMatchesTheUnderline() throws {
        let probe = try thicknessProbe { size, color in
            trackInsertUnderlineAttributes(size: size, color: color)
        }
        let ratio = HwpRenderTuning.Text.decorationLineThicknessRatio
        expect(probe.small).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(probe.large).to(beCloseTo(ratio * Self.largeSize, within: 0.05))
        expect(ratio * Self.largeSize).to(beCloseTo(1.6, within: 0.001))
    }
}
