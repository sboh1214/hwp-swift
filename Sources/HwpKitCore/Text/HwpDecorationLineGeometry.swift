import CoreGraphics
import CoreText
import Foundation

/// 글자 장식선(글자 아래·글자 위 밑줄, 취소선 = 글자 가운데 밑줄, 변경 추적 삽입 밑줄·
/// 삭제선)의 **세로 위치와 두께** — 한글 문서·한글 2007 호환 문서·MS 워드 호환 문서의
/// 세 기하를 한 곳에 모은다 (#136·#176·#179·#187·#210). 렌더러
/// (`HwpPageLayerDecorations`)가 이 값을 그대로 그린다.
///
/// - 한글 문서: 아래 밑줄(삽입 밑줄 포함) −0.17em · 위 밑줄 +0.87em · 취소선(가운데
///   밑줄·삭제선 포함) +0.35em, 두께 모두 0.04em.
/// - 한글 2007 호환(`HwpCompatibleDocumentTarget.hwp200X`): 두께가 크기와 무관한 고정
///   0.36pt이고, 밑줄은 한글 문서와 **같은 가장자리**(아래 0.15em·위 0.85em)에 그 얇은
///   선을 얹는다 — 중심은 −(0.15em + 0.18pt) · +(0.85em + 0.18pt)이고 취소선 중심은
///   한글 문서와 같은 +0.35em이다.
/// - MS 워드 호환: 아래 밑줄 −(descent + 0.021 cell) · 위 밑줄 ascent + 0.021 cell, 두께
///   0.05 cell · 취소선 0.273 ascent, 두께 0.04em.
///
/// (em = 글자 크기, 첨자면 두께는 축소 전 크기)
///
/// MS 워드 호환 문서의 `ascent`·`descent`·`cell`은 글꼴의 win 지표에서 푼 상자
/// (`HwpMsWordLineBox`)에 **글자 모양 기본 크기**를 곱한 pt다 — 슬롯 상대 크기는 곱하지
/// 않는다 (2026-09-16 실측: 한글 슬롯 50%·라틴 100%로 갈린 글자 모양의 밑줄·취소선이
/// 100%와 같은 자리·두께, `HwpPageLayerDecorations.decorationBaseFontSize`). 한글은 그 문서에서
/// **밑줄을 줄 단위로, 취소선을 run 단위로** 놓는다 (2026-09-15 한글 12.30 실측, 12조합 +
/// 픽스처):
///
/// - 글자 아래·위 밑줄과 삽입 밑줄은 **줄 상자**(run 상자들의 축별 최댓값 — 밑줄이 없는
///   run·대체 글꼴 run도 후보다, `HwpMsWordLineBox.union`; 문단 끝 글자·한 줄 끝·개체가 그보다
///   높으면 쌓여 커진 줄 상자, `HwpDrawnTextLayout.msWordLineBox`)의 가장자리에서 글자 상자의
///   cell × 0.129만큼 안쪽에 줄 전체가 한 자리·한 두께다 (#223: 16pt 문단 끝 글자가 쌓인
///   함초롬돋움 10pt 밑줄 줄은 베이스라인 아래 9.36pt; 함초롬돋움 40pt 무장식 run 뒤의 Apple SD 40pt 밑줄
///   run이 함초롬 자리 −0.2583em·0.0661em, Apple SD 40pt 무장식 run 뒤의 함초롬 10pt
///   밑줄 run이 Apple SD 40pt 자리 −0.3273em·2.40pt, 같은 글꼴 10pt + 40pt 밑줄 run
///   둘은 40pt 자리 한 줄).
/// - 취소선은 run마다 자기 글꼴 상자의 `ascent`다 (Apple SD + 함초롬 두 취소선 run이
///   각각 +0.2492·+0.2913em, 맑은 고딕 무장식 run 뒤의 Courier New 취소선 run은 Courier의
///   +0.1892em). 글자 모양 run이 슬롯으로 갈려도 첫 글리프의 글꼴 × 기본 크기 한 줄이다
///   (`가나Ag`에서 한글 50%·라틴 100%든 그 반대든 함초롬 × 40pt 자리 +11.64pt, `Ag가나`는
///   Helvetica × 40pt 자리 +8.76pt).
///
/// 한글 2007 호환 문서의 값도 글꼴과 무관하다 (2026-09-22 실측, 9개 글꼴 × 5~100pt 22개
/// 크기: 위치는 장치 양자화 0.12pt 안에서 같고 두께는 전부 0.36pt). 한글 문서와 달리 em을
/// 곱하는 크기는 **글자 모양 기본 크기**(`hwp.baseFontSize`, 슬롯 상대 크기 전)다 — 기본
/// 40pt·한글 슬롯 50%인 run의 밑줄이 20pt 자리가 아니라 40pt 자리(−6.24pt)이고 취소선도
/// 40pt 자리(+13.92pt)다. 밑줄을 **줄 단위**로 놓는 축(크기가 섞인 줄에서 줄의 가장 큰
/// 글자 모양이 자리를 정한다)은 한글 문서 갈래도 같은 규칙이라 이 수정의 범위 밖이다
/// (#226).
///
/// 한글 문서의 값은 글꼴과 무관하고 (13개 글꼴 전부 같은 값) 첨자 규칙(#179)은 두 문서
/// 갈래가 같다 — 취소선 중심은 첨자로 옮겨진 베이스라인 + 줄어든 크기 기준, 두께와
/// 밑줄은 축소 전 크기 기준 (호환 문서의 첨자 표본은 없어 같은 규칙을 적용한다).
public enum HwpDecorationLineGeometry {
    /// 선 하나 — `center`는 베이스라인 기준 세로 위치 (pt, 위가 양수), `thickness`는
    /// 두께 (pt). 렌더러는 중심을 기준으로 위아래 반씩 채운다.
    public struct Line: Equatable, Sendable {
        public let center: CGFloat
        public let thickness: CGFloat

        public init(center: CGFloat, thickness: CGFloat) {
            self.center = center
            self.thickness = thickness
        }
    }

    // MARK: - 한글 문서

    /// 글자 아래 밑줄 — 베이스라인 아래 0.17em, 두께 0.04em. `fontSize`는 첨자 축소 전
    /// 크기다.
    public static func underlineBelow(fontSize: CGFloat) -> Line {
        Line(
            center: -fontSize * HwpRenderTuning.Text.underlineBelowCenterRatio,
            thickness: fontSize * HwpRenderTuning.Text.decorationLineThicknessRatio
        )
    }

    /// 글자 위 밑줄 — 베이스라인 위 0.87em, 두께 0.04em.
    public static func underlineAbove(fontSize: CGFloat) -> Line {
        Line(
            center: fontSize * HwpRenderTuning.Text.underlineAboveCenterRatio,
            thickness: fontSize * HwpRenderTuning.Text.decorationLineThicknessRatio
        )
    }

    /// 취소선 — 베이스라인 위 0.35 × `fontSize`(첨자면 줄어든 크기), 두께 0.04 ×
    /// `thicknessFontSize`(첨자 축소 전 크기).
    public static func strikethrough(fontSize: CGFloat, thicknessFontSize: CGFloat) -> Line {
        Line(
            center: fontSize * HwpRenderTuning.Text.strikethroughCenterRatio,
            thickness: thicknessFontSize * HwpRenderTuning.Text.decorationLineThicknessRatio
        )
    }

    // MARK: - 한글 2007 호환 문서

    /// 글자 아래 밑줄(변경 추적 삽입 밑줄 포함) — 베이스라인 아래 0.15em에 **위
    /// 가장자리**가 닿는 고정 0.36pt 선이라 중심은 −(0.15em + 0.18pt)다. `fontSize`는
    /// 글자 모양 기본 크기(첨자 축소·슬롯 상대 크기 전)다.
    public static func hwp200XUnderlineBelow(fontSize: CGFloat) -> Line {
        let thickness = HwpRenderTuning.Text.hwp200XDecorationLineThickness
        return Line(
            center: -(fontSize * HwpRenderTuning.Text.hwp200XUnderlineBelowEdgeRatio
                + thickness / 2),
            thickness: thickness
        )
    }

    /// 글자 위 밑줄 — 베이스라인 위 0.85em에 **아래 가장자리**가 닿는 고정 0.36pt 선.
    public static func hwp200XUnderlineAbove(fontSize: CGFloat) -> Line {
        let thickness = HwpRenderTuning.Text.hwp200XDecorationLineThickness
        return Line(
            center: fontSize * HwpRenderTuning.Text.hwp200XUnderlineAboveEdgeRatio
                + thickness / 2,
            thickness: thickness
        )
    }

    /// 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함) — 중심은 한글 문서와 같은
    /// 0.35em이고 두께만 고정 0.36pt다. 밑줄과 달리 가장자리가 아니라 중심을 맞춘다
    /// (실측: 22개 크기에서 0.349~0.357em, 0.35em + 두께 절반은 18개 크기가 어긋난다).
    /// `fontSize`는 첨자면 줄어든 크기다 — 취소선만 첨자로 옮겨진 베이스라인을 따른다.
    public static func hwp200XStrikethrough(fontSize: CGFloat) -> Line {
        Line(
            center: fontSize * HwpRenderTuning.Text.strikethroughCenterRatio,
            thickness: HwpRenderTuning.Text.hwp200XDecorationLineThickness
        )
    }

    // MARK: - MS 워드 호환 문서

    /// 글자 아래 밑줄 — 줄 상자(`lineBox`, pt)의 `descent` 아래 0.021 cell, 두께 0.05 cell.
    public static func msWordUnderlineBelow(lineBox: HwpMsWordLineBox) -> Line {
        let cell = lineBox.cellHeight
        return Line(
            center: -(lineBox.descent + cell * HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio),
            thickness: cell * HwpRenderTuning.Text.msWordUnderlineThicknessCellRatio
        )
    }

    /// 글자 위 밑줄 — 줄 상자의 `ascent` 위 0.021 cell, 두께 0.05 cell.
    public static func msWordUnderlineAbove(lineBox: HwpMsWordLineBox) -> Line {
        let cell = lineBox.cellHeight
        return Line(
            center: lineBox.ascent + cell * HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio,
            thickness: cell * HwpRenderTuning.Text.msWordUnderlineThicknessCellRatio
        )
    }

    /// 취소선 — run 자신의 상자(`runBox`, pt)의 `ascent` × 0.273, 두께는 한글 문서와
    /// 같은 0.04 × `thicknessFontSize`.
    public static func msWordStrikethrough(
        runBox: HwpMsWordLineBox, thicknessFontSize: CGFloat
    ) -> Line {
        Line(
            center: runBox.ascent * HwpRenderTuning.Text.msWordStrikethroughAscentRatio,
            thickness: thicknessFontSize * HwpRenderTuning.Text.decorationLineThicknessRatio
        )
    }
}
