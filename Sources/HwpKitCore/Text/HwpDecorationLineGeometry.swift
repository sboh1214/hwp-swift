import CoreGraphics
import CoreText
import Foundation

/// 글자 장식선(글자 아래·글자 위 밑줄, 취소선 = 글자 가운데 밑줄, 변경 추적 삽입 밑줄·
/// 삭제선)의 **세로 위치와 두께** — 한글 문서와 MS 워드 호환 문서의 두 기하를 한 곳에
/// 모은다 (#136·#176·#179·#187). 렌더러(`HwpPageLayerDecorations`)가 이 값을 그대로
/// 그린다.
///
/// - 한글 문서: 아래 밑줄(삽입 밑줄 포함) −0.17em · 위 밑줄 +0.87em · 취소선(가운데
///   밑줄·삭제선 포함) +0.35em, 두께 모두 0.04em.
/// - MS 워드 호환: 아래 밑줄 −(descent + 0.021 cell) · 위 밑줄 ascent + 0.021 cell, 두께
///   0.05 cell · 취소선 0.273 ascent, 두께 0.04em.
///
/// (em = 글자 크기, 첨자면 두께는 축소 전 크기)
///
/// MS 워드 호환 문서의 `ascent`·`descent`·`cell`은 글꼴의 win 지표에서 푼 상자
/// (`HwpMsWordLineBox`, 글자 크기를 곱한 pt)이고, 한글은 그 문서에서 **밑줄을 줄 단위로,
/// 취소선을 run 단위로** 놓는다 (2026-09-15 한글 12.30 실측, 12조합 + 픽스처):
///
/// - 글자 아래·위 밑줄과 삽입 밑줄은 **줄 상자**(run 상자들의 축별 최댓값 — 밑줄이 없는
///   run·대체 글꼴 run·마지막 줄의 문단 끝 글자도 후보다, `HwpMsWordLineBox.union`)에서
///   줄 전체가 한 자리·한 두께다 (함초롬돋움 40pt 무장식 run 뒤의 Apple SD 40pt 밑줄
///   run이 함초롬 자리 −0.2583em·0.0661em, Apple SD 40pt 무장식 run 뒤의 함초롬 10pt
///   밑줄 run이 Apple SD 40pt 자리 −0.3273em·2.40pt, 같은 글꼴 10pt + 40pt 밑줄 run
///   둘은 40pt 자리 한 줄).
/// - 취소선은 run마다 자기 글꼴 상자의 `ascent`다 (Apple SD + 함초롬 두 취소선 run이
///   각각 +0.2492·+0.2913em, 맑은 고딕 무장식 run 뒤의 Courier New 취소선 run은 Courier의
///   +0.1892em).
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
