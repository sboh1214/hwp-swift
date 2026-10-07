import CoreGraphics
import CoreText
import Foundation

/// 글자 장식선(글자 아래·글자 위 밑줄, 취소선 = 글자 가운데 밑줄, 변경 추적 삽입 밑줄·
/// 삭제선)의 **세로 위치와 두께** — 한글 문서·한글 2007 호환 문서·MS 워드 호환 문서의
/// 세 기하를 한 곳에 모은다 (#136·#176·#179·#187·#210·#226·#258). 렌더러
/// (`HwpPageLayerDecorations`)가 이 값을 그대로 그린다.
///
/// - 한글 문서: 아래 밑줄(삽입 밑줄 포함)은 **위 가장자리가 줄 상자 바닥**(베이스라인
///   아래 0.15L), 위 밑줄은 **아래 가장자리가 줄 상자 상단**(위 0.85L), 두께는 T의 획 두께 —
///   한 크기만 있는 줄(L = T = em)이면 중심이 −0.17em · +0.87em 근처다. 취소선(가운데 밑줄·
///   삭제선 포함)은 +0.35em, 두께는 em의 획 두께. 획 두께는 기준 크기에서 푼 600dpi 장치
///   단위(0.12pt)의 정수다 — max(1, round(round(X × 39/1000) ÷ 12))u, X = 기준 크기 HWPUNIT
///   (`strokeThickness(referenceSize:)`, #252; 10pt 0.36pt·5pt 0.24pt·80pt 3.12pt).
/// - 한글 2007 호환(`HwpCompatibleDocumentTarget.hwp200X`): 두께가 크기와 무관한 고정
///   0.36pt이고, 밑줄은 한글 문서와 **같은 가장자리**(아래 0.15L·위 0.85L)에 그 얇은
///   선을 얹는다 — 중심은 −(0.15L + 0.18pt) · +(0.85L + 0.18pt)이고 취소선 중심은
///   한글 문서와 같은 +0.35em이다.
/// - MS 워드 호환: 아래 밑줄 −(descent + 0.021 cell) · 위 밑줄 ascent + 0.021 cell, 두께는
///   줄 글자 상자 높이(cell × 1.3)의 획 두께 · 취소선은 글꼴 줄 상자의 베이스라인 높이
///   (줄 상자 윗변 → 베이스라인)의 0.23배, 두께는 em의 획 두께.
///
/// (L = 줄 상자 높이, T = 줄 글자의 기본 크기 최댓값 — 둘 다 줄 단위, `UnderlineReference`;
/// em = run의 글자 모양 기본 크기, 첨자면 취소선 자리만 줄인다 — 한글 문서·한글 2007 호환
/// 문서는 `scriptStrikethroughScale`을, MS 워드 호환 문서는 `msWordScriptStrikethroughScale`을 곱한다)
///
/// **밑줄 세 종은 줄 단위, 취소선은 run 단위다** — 세 문서 갈래가 같다 (#187·#226). 한글
/// 문서·한글 2007 호환 문서에서 밑줄 자리를 정하는 L은 줄 상자 높이(한글 줄 캐시의
/// `vertsize` — 줄의 글자·문단 끝 글자·한 줄 끝·높이 0 마커의 기본 크기와 글자처럼 취급
/// 개체의 바깥 상자 높이 가운데 최댓값)이고, 한글 문서의 두께·선 모양 축척을 정하는 T는 그
/// 가운데 **글자**의 기본 크기만 본다 (`HwpDrawnTextLayout.underlineReference(of:endsParagraph:)`).
/// 한글 2007 호환 문서는 T를 쓰지 않는다 — 두께는 고정 0.36pt(#210), 선 모양은 고정 축척
/// `HwpLineShapeGeometry.Scale.hwp200XCharacterLine`(#227)이다.
/// 한글 12.30 실측 (2026-09-22·25, #226 — 함초롬바탕 10pt 밑줄 run과 같은 줄에 무엇이
/// 있는가): 40pt 무장식 글자 −6.84pt·두께 1.56pt, 40pt 문단 끝 글자·한 줄 끝·책갈피·
/// 그림·표 −6.12~−6.24pt·0.36pt, 20pt 무장식 글자 + 40pt 문단 끝 글자 −6.36pt·0.84pt,
/// 바깥 여백 위 7·아래 3pt인 20pt 그림(상자 30pt) −4.68pt·0.36pt. 위 밑줄도 같은 규칙이라
/// 두께 기준이 10pt인 줄(40pt 문단 끝 글자·한 줄 끝·책갈피·그림·표)은 +34.20pt, 30pt 상자
/// 그림 줄은 +25.68pt, 두께 기준도 40pt인 줄(40pt 무장식 글자·기본 40pt run)은 +34.68~34.80pt·
/// 1.56pt다. 변경 추적 삽입 밑줄은 같은 줄의 밑줄과 같은 자리·두께다. 종전에는 run마다 그 run 글꼴 크기로 −0.17em·+0.87em에 그려
/// 같은 줄의 밑줄이 크기마다 계단이 졌다.
///
/// 크기는 전부 **글자 모양 기본 크기**(`hwp.baseFontSize`, 슬롯 상대 크기 전)다 — 기본 40pt·
/// 상대 크기 50%인 run의 밑줄은 −6.84pt·1.56pt, 취소선은 +14.04pt (20pt 자리가 아니다,
/// #226·#210). 첨자는 #179 규칙 그대로 — 밑줄은 원래 베이스라인·축소 전 기본 크기,
/// 취소선은 첨자로 옮겨진 베이스라인 + 기본 크기의 취소선 높이 × 89/140이다 (#258 — MS 워드
/// 호환 문서는 0.696배, 맨 아래 문단).
///
/// MS 워드 호환 문서의 `ascent`·`descent`·`cell`·베이스라인 높이는 글꼴의 win 지표에서 푼 상자
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
/// - 취소선은 run마다 자기 글꼴 상자의 베이스라인 높이(`HwpMsWordLineBox.baseline`)에서 잰다
///   (Apple SD + 함초롬 두 취소선 run이 각각 +0.2492·+0.2913em, 맑은 고딕 무장식 run 뒤의
///   Courier New 취소선 run은 Courier의 +0.1892em; #257: Times New Roman 40pt + Palatino 40pt
///   두 run이 각각 +8.52·+13.08pt). 글자 모양 run이 슬롯으로 갈려도 첫 글리프의 글꼴 × 기본 크기 한 줄이다
///   (`가나Ag`에서 한글 50%·라틴 100%든 그 반대든 함초롬 × 40pt 자리 +11.64pt, `Ag가나`는
///   Helvetica × 40pt 자리 +8.76pt). 각주·미주 참조 번호는 같은 글자 모양이어도 **따로 된
///   글자 모양 run**이다 (#256 실측: 한글 함초롬바탕·라틴 Apple SD 40pt `가나L` + 각주 + `AB`의
///   번호와 `AB`는 각각 자기 첫 글리프 Apple SD 자리 +9.96pt, `가나L`은 함초롬 자리 +11.64pt).
///
/// 한글 2007 호환 문서의 값도 글꼴과 무관하다 (2026-09-22 실측, 9개 글꼴 × 5~100pt 22개
/// 크기: 위치는 장치 양자화 0.12pt 안에서 같고 두께는 전부 0.36pt). 크기는 한글 문서와
/// 같은 글자 모양 기본 크기다 — 기본 40pt·한글 슬롯 50%인 run의 밑줄이 20pt 자리가 아니라
/// 40pt 자리(−6.24pt)이고 취소선도 40pt 자리(+13.92pt)다. 줄 단위 밑줄도 한글 문서와 같은
/// 규칙이다 (#226 실측: 40pt 상자 표본의 밑줄이 −6.12~−6.24pt·위 밑줄 +34.08~34.20pt, 바깥
/// 여백을 준 그림의 30pt 상자 줄은 −4.68·+25.68pt, 크기가 섞인 줄의 변경 추적 삽입 밑줄도 같은
/// 줄 상자 자리 — 0.8배 축소 쪽에서 −4.92pt).
///
/// 한글 문서의 값은 글꼴과 무관하고 (13개 글꼴 전부 같은 값) 첨자 규칙(#179)은 세 문서
/// 갈래가 같은 틀이다 — 취소선 중심은 첨자로 옮겨진 베이스라인 위, 두께와 밑줄은 축소 전
/// 크기 기준. 취소선의 높이만 갈래마다 다르다: 한글 문서·한글 2007 호환 문서는 보통 글자 취소선
/// 높이(0.35em)의 89/140 ≈ 0.6357배 — 첨자 글리프 축소 비율 0.64가 아니다
/// (`HwpRenderTuning.Text.scriptStrikethroughScale`, #258 — 한글 12.30 실측 두 갈래 × 8~250pt
/// 1,324표본이 ⌊89 × 기본 크기(HWPUNIT) ÷ 400⌋; 0.64는 크기에 비례해 높아 100pt 0.15pt·250pt
/// 0.375pt 어긋났다), MS 워드 호환 문서는 같은 글꼴·기본 크기 보통 글자 취소선 높이의 0.696배다
/// (`HwpRenderTuning.Text.msWordScriptStrikethroughScale`, #248 — 한글 12.30 실측 글꼴 10종 ×
/// 8~100pt × 위·아래 첨자 360표본).
///
/// **각주·미주 참조 번호는 첨자가 아니다** (#256) — 번호 글리프는 0.75배로 줄고 설정 크기의
/// 0.21배 올라가지만(#204), 한글은 번호의 취소선·글자 가운데 밑줄을 번호가 놓인 글자 모양의
/// 자리·두께에 그린다 (2026-10-06 한글 12.30 PDF 실측: 세 문서 갈래 × 함초롬바탕·함초롬돋움
/// 10~80pt에서 번호 선 = 본문 선, 미주·상대 크기 50%·각주 내용의 위 첨자 번호도 같다; 위 첨자 글자
/// 모양 안의 번호는 그 첨자의 선). 렌더러는 번호 run의 축소(`HwpAttributedStringKey.noteReferenceScale`)를
/// 무른 크기로 이 산식을 부른다.
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

    /// 한 줄의 밑줄(글자 아래·글자 위·변경 추적 삽입 밑줄)이 **모두 공유하는** 기준 (#226) —
    /// `HwpDrawnTextLayout.underlineReference(of:endsParagraph:)`가 줄마다 한 번 푼다. 어느
    /// 기하를 쓸지(한글 문서·한글 2007 호환·MS 워드 호환)는 run의 문서 갈래가 정하고, 이
    /// 값은 그 셋이 필요로 하는 줄 단위 입력을 함께 싣는다.
    public struct UnderlineReference: Equatable, Sendable {
        /// 줄 상자 높이 (pt, 한글 줄 캐시의 `vertsize`) — 한글 문서·한글 2007 호환 문서의
        /// 밑줄 가장자리가 이 상자의 바닥(글자 아래)·상단(글자 위)에 닿는다. 줄의 글자·
        /// 문단 끝 글자(마지막 줄)·한 줄 끝·높이 0 마커의 기본 크기와 글자처럼 취급 개체의
        /// 바깥 상자 높이 가운데 최댓값이다 (세로 배치가 쓰는 상자와 같은 값). 줄에 크기를 가진
        /// 것이 없으면 0이다 — 호출자가 그리는 run의 글자 모양 기본 크기로 대신한다 (번들
        /// 렌더러 `HwpPageLayer`가 그렇게 한다).
        public let lineBoxHeight: CGFloat
        /// 한글 문서의 두께·선 모양 축척 기준 크기 (pt) — 줄 **글자**의 글자 모양 기본 크기
        /// 최댓값. 문단 끝 글자·한 줄 끝·마커(책갈피·개체)의 글자 모양과 개체 높이는 들지
        /// 않는다. 한글 2007 호환 문서는 두께가 고정 0.36pt이고(#210) 선 모양도 크기와 무관한
        /// 고정 무늬라(#227, `HwpLineShapeGeometry.Scale.hwp200XCharacterLine`) 이 값을 쓰지
        /// 않는다. 글자가 없는 줄이면 0이다 — 호출자가 그리는 run의 글자 모양 기본
        /// 크기로 대신한다 (번들 렌더러 `HwpPageLayer`가 그렇게 한다).
        public let textFontSize: CGFloat
        /// MS 워드 호환 문서의 줄 상자 — 있으면 밑줄은 이 상자에서 잰다 (#187·#223,
        /// `HwpDrawnTextLayout.msWordLineBox(of:endsParagraph:)`). 한글 문서·한글 2007 호환
        /// 문서 줄이면 nil.
        public let msWordLineBox: HwpMsWordLineBox?

        public init(
            lineBoxHeight: CGFloat, textFontSize: CGFloat, msWordLineBox: HwpMsWordLineBox? = nil
        ) {
            self.lineBoxHeight = lineBoxHeight
            self.textFontSize = textFontSize
            self.msWordLineBox = msWordLineBox
        }
    }

    // MARK: - 한글 문서

    /// 글자 아래 밑줄 — **위 가장자리가 줄 상자 바닥**(베이스라인 아래 0.15 ×
    /// `lineBoxHeight`)에 닿고 아래로 `thicknessFontSize`의 획 두께(`strokeThickness(referenceSize:)`)
    /// 만큼 그려진다. 중심은 −(0.15L + 획/2) (#226 — `HwpRenderTuning.Text.underlineBelowEdgeRatio`의 실측).
    public static func underlineBelow(lineBoxHeight: CGFloat, thicknessFontSize: CGFloat) -> Line {
        let thickness = strokeThickness(referenceSize: thicknessFontSize)
        return Line(
            center: -(lineBoxHeight * HwpRenderTuning.Text.underlineBelowEdgeRatio + thickness / 2),
            thickness: thickness
        )
    }

    /// 글자 위 밑줄 — **아래 가장자리가 줄 상자 상단**(베이스라인 위 0.85 ×
    /// `lineBoxHeight`)에 닿고 위로 `thicknessFontSize`의 획 두께만큼 그려진다.
    public static func underlineAbove(lineBoxHeight: CGFloat, thicknessFontSize: CGFloat) -> Line {
        let thickness = strokeThickness(referenceSize: thicknessFontSize)
        return Line(
            center: lineBoxHeight * HwpRenderTuning.Text.underlineAboveEdgeRatio + thickness / 2,
            thickness: thickness
        )
    }

    /// 한 크기만 있는 줄의 글자 아래 밑줄 — 줄 상자와 두께 기준이 모두 `fontSize`라
    /// 위 가장자리가 베이스라인 아래 0.15em이고 두께는 그 크기의 획 두께다 (#176·#252 — 중심은
    /// 0.17em 근처, 10pt면 −1.68pt·0.36pt).
    public static func underlineBelow(fontSize: CGFloat) -> Line {
        underlineBelow(lineBoxHeight: fontSize, thicknessFontSize: fontSize)
    }

    /// 한 크기만 있는 줄의 글자 위 밑줄 — 아래 가장자리가 베이스라인 위 0.85em이고 두께는 그
    /// 크기의 획 두께다 (#136·#252 — 중심은 0.87em 근처, 10pt면 +8.68pt·0.36pt).
    public static func underlineAbove(fontSize: CGFloat) -> Line {
        underlineAbove(lineBoxHeight: fontSize, thicknessFontSize: fontSize)
    }

    /// 취소선 — 베이스라인 위 0.35 × `fontSize`(글자 모양 기본 크기, 첨자면 ×
    /// `HwpRenderTuning.Text.scriptStrikethroughScale`, #258),
    /// 두께는 `thicknessFontSize`(첨자 축소 전 기본 크기)의 획 두께. 밑줄과 달리 run 단위다.
    public static func strikethrough(fontSize: CGFloat, thicknessFontSize: CGFloat) -> Line {
        Line(
            center: fontSize * HwpRenderTuning.Text.strikethroughCenterRatio,
            thickness: strokeThickness(referenceSize: thicknessFontSize)
        )
    }

    // MARK: - 한글 2007 호환 문서

    /// 글자 아래 밑줄(변경 추적 삽입 밑줄 포함) — 줄 상자 바닥(베이스라인 아래 0.15 ×
    /// `lineBoxHeight`)에 **위 가장자리**가 닿는 고정 0.36pt 선이라 중심은
    /// −(0.15L + 0.18pt)다. 한 크기만 있는 줄이면 `lineBoxHeight`는 글자 모양 기본 크기다.
    public static func hwp200XUnderlineBelow(lineBoxHeight: CGFloat) -> Line {
        let thickness = HwpRenderTuning.Text.hwp200XDecorationLineThickness
        return Line(
            center: -(lineBoxHeight * HwpRenderTuning.Text.underlineBelowEdgeRatio
                + thickness / 2),
            thickness: thickness
        )
    }

    /// 글자 위 밑줄 — 줄 상자 상단(베이스라인 위 0.85 × `lineBoxHeight`)에 **아래
    /// 가장자리**가 닿는 고정 0.36pt 선.
    public static func hwp200XUnderlineAbove(lineBoxHeight: CGFloat) -> Line {
        let thickness = HwpRenderTuning.Text.hwp200XDecorationLineThickness
        return Line(
            center: lineBoxHeight * HwpRenderTuning.Text.underlineAboveEdgeRatio
                + thickness / 2,
            thickness: thickness
        )
    }

    /// 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함) — 중심은 한글 문서와 같은
    /// 0.35em이고 두께만 고정 0.36pt다. 밑줄과 달리 가장자리가 아니라 중심을 맞춘다
    /// (실측: 22개 크기에서 0.349~0.357em, 0.35em + 두께 절반은 18개 크기가 어긋난다).
    /// `fontSize`는 첨자면 기본 크기 × `HwpRenderTuning.Text.scriptStrikethroughScale`(#258)이다 —
    /// 취소선만 첨자로 옮겨진 베이스라인을 따른다.
    public static func hwp200XStrikethrough(fontSize: CGFloat) -> Line {
        Line(
            center: fontSize * HwpRenderTuning.Text.strikethroughCenterRatio,
            thickness: HwpRenderTuning.Text.hwp200XDecorationLineThickness
        )
    }

    // MARK: - MS 워드 호환 문서

    /// 글자 아래 밑줄 — 줄 상자(`lineBox`, pt)의 `descent` 아래 0.021 cell, 두께는 줄 글자 상자
    /// 높이(cell × 1.3 — 한글 줄 캐시의 `vertsize`)의 획 두께 (`msWordUnderlineStrokeThickness(lineBox:)`).
    public static func msWordUnderlineBelow(lineBox: HwpMsWordLineBox) -> Line {
        let cell = lineBox.cellHeight
        return Line(
            center: -(lineBox.descent + cell * HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio),
            thickness: msWordUnderlineStrokeThickness(lineBox: lineBox)
        )
    }

    /// 글자 위 밑줄 — 줄 상자의 `ascent` 위 0.021 cell, 두께는 아래 밑줄과 같다.
    public static func msWordUnderlineAbove(lineBox: HwpMsWordLineBox) -> Line {
        let cell = lineBox.cellHeight
        return Line(
            center: lineBox.ascent + cell * HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio,
            thickness: msWordUnderlineStrokeThickness(lineBox: lineBox)
        )
    }

    /// 취소선 — run 자신의 글꼴 상자(`runBox`, pt)의 **베이스라인 높이**(`baseline` — 줄 상자
    /// 윗변에서 베이스라인까지) × 0.23(`HwpRenderTuning.Text.msWordStrikethroughBaselineRatio`), 두께는
    /// 한글 문서와 같은 `thicknessFontSize`(글자 모양 기본 크기)의 획 두께 (#257). 장식선 기준
    /// 상자의 `ascent`(베이스라인 − 0.15 cell)가 아니다 — 그 0.273배(#187)는 `descent`가 큰
    /// 글꼴일수록 한글보다 낮았다 (Baskerville 100pt 0.41pt, Zapfino 100pt 7.9pt).
    public static func msWordStrikethrough(
        runBox: HwpMsWordLineBox, thicknessFontSize: CGFloat
    ) -> Line {
        Line(
            center: runBox.baseline * HwpRenderTuning.Text.msWordStrikethroughBaselineRatio,
            thickness: strokeThickness(referenceSize: thicknessFontSize)
        )
    }

    /// MS 워드 호환 문서 밑줄(글자 아래·위·변경 추적 삽입)의 획 두께 — 기준 크기는 줄 글자 상자의
    /// 높이 `cellHeight` × 1.3(`HwpRenderTuning.Text.msWordLineHeightCellRatio`)이다. 선 모양의 무늬
    /// 축척과 같은 크기다 (#244 — 렌더러의 `underlineShapeScale`).
    static func msWordUnderlineStrokeThickness(lineBox: HwpMsWordLineBox) -> CGFloat {
        strokeThickness(
            referenceSize: lineBox.cellHeight * HwpRenderTuning.Text.msWordLineHeightCellRatio
        )
    }

    // MARK: - 획 두께

    /// 한글 문서·MS 워드 호환 문서 장식선의 획 두께 (pt) — 기준 크기 `referenceSize`(pt)를
    /// HWPUNIT 정수로 둔 X에서 무늬 두께 t = round(X × 39/1000)를 풀고, t ÷ 12를 600dpi 장치
    /// 단위(0.12pt)로 반올림한 값이다. 최소 1u(0.12pt)이고 반올림은 0.5를 올린다 (#252):
    ///
    ///     획 = max(1, round(round(X × 39 / 1000) / 12)) × 0.12pt
    ///
    /// t는 대시·원형 점선의 무늬 두께와 같은 값이고 (`HwpLineShapeGeometry.characterPatternHwpUnits`),
    /// 실선과 대시 다섯 종(점선·긴 점선·일점쇄선·이점쇄선·긴 파선)이 같은 크기에서 같은 획이다.
    /// 기준 크기는 선마다 다르다 — 한글 문서는 밑줄 세 종이 줄 글자 기본 크기 최댓값(#226), 취소선·
    /// 글자 가운데 밑줄이 run의 글자 모양 기본 크기(첨자 축소 전)이고, MS 워드 호환 문서는 밑줄이 줄
    /// 글자 상자의 높이(#244), 취소선이 글자 모양 기본 크기다. 한글 2007 호환 문서는 이 식 밖의
    /// 고정 0.36pt다 (#210, `HwpRenderTuning.Text.hwp200XDecorationLineThickness`).
    ///
    /// 실측: 한컴오피스 한글 12.30.0 PDF — build 6446 (2026-10-01 재집계, #210·#227·#244·#245 자료)
    /// 한글 문서 실선 69 + 대시 1,206표본·MS 워드 호환 문서 실선 92 + 대시 880표본, build 6523
    /// (2026-10-03, `probes/252`) 한글 문서 실선 취소선·아래 밑줄·위 밑줄 237표본(t가 12k+5·12k+6으로
    /// 갈리는 0.01pt 이웃 쌍 34개씩 + 1~3pt)·점선·긴 점선 취소선 158표본·기준 크기 갈래(크기가 섞인
    /// 줄·문단 끝 글자·상대 크기·첨자) 32표본·MS 워드 호환 문서 글꼴 11종 밑줄 248 + 취소선 135표본이
    /// **모두** 이 식과 같다 (MS 워드 호환 밑줄은 한글 줄 캐시의 `vertsize`를 넣었을 때 — 우리 글꼴
    /// 상자는 그 반올림을 재현하지 않아 7표본이 1u 갈린다, #194). 종전 연속값(0.04em, MS 워드 호환
    /// 밑줄 0.05 cell)은 10pt에서 0.40pt(한글 0.36), 5pt에서 0.20pt(0.24), 1.02pt 취소선에서
    /// 0.04pt(0.12)였고, `round(크기 ÷ 3)`u(#176의 13개 크기 실측에서 읽은 식)는 56pt 18u·80pt
    /// 26u에서 반증된다 (같은 경계 쌍 237표본 중 138개만 맞는다). 0 이하·NaN이면 0이다.
    public static func strokeThickness(referenceSize: CGFloat) -> CGFloat {
        HwpLineShapeGeometry.characterStrokeThickness(fontSize: referenceSize)
    }
}
