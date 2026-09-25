import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 줄 상자를 정하는 **지표**와 그 수집 (#178·#180·#194·#223·#226).
///
/// 앵커(`baselineAnchor`)·줄 전진량(`HwpLineAdvance`)·줄 단위 밑줄의 기준
/// (`underlineReference` — 한글 문서·한글 2007 호환은 줄 상자 높이와 글자 기본 크기, MS 워드
/// 호환은 줄 상자 `msWordLineBox`)이 모두 이 한 벌을 쓴다 — 줄에서 무엇을 읽는지의 단일
/// 원본이라 갈래마다 다른 지표를 보는 일이 생기지 않는다. 밑줄이 세로 배치와 같은 상자에서
/// 나오므로 줄 상자 바닥·상단에 정확히 붙는다.
extension HwpDrawnTextLayout {
    /// 줄 상자를 정하는 지표 — 한글 줄 캐시(`PARA_LINE_SEG`)의 `vertsize`·`baseline`에
    /// 해당하는 값을 글자 몫과 개체 몫으로 나눠 든다.
    ///
    /// 한글 문서에서는 글꼴 지표(ascent·descent·leading)가 세로 배치에 관여하지 않는다 —
    /// 글자 상자는 기본 글자 크기, 베이스라인은 상자의 0.85. MS 워드 호환 문서
    /// (`hwp.compatibleDocumentTarget` == `msWord`, #194)에서는 반대로 글꼴의 OS/2 win
    /// 지표가 줄 상자를 정한다 (`HwpMsWordLineBox`) — 글자 상자(`msWordTextBox`)에 문단 끝
    /// 글자 상자와 개체를 들인 `msWordLineBox`가 그 줄 상자다 (#223).
    struct LineMetrics {
        /// 한글 문서 줄 상자의 **글자 몫** — 이 줄 글자 run들과 **줄 공간을 예약하지 않은**
        /// 마커 run(책갈피·필드 표식·자리 차지 개체 앵커처럼 높이 0 delegate를 단 run)의
        /// **상대크기 적용 전 기본 크기** 최댓값이고, 문단의 마지막 줄이면 조판 문자열에서
        /// 접힌 **문단 끝 글자**(CR)의 글자 모양(`hwp.paragraphEndBaseFontSize`, #206)도
        /// 포함한다. 줄 공간을 예약한 개체 마커의 글자 모양은 들지 않는다
        /// (`objectMarkerBaseFontSize`, #217). 쪽 번호 상자처럼 글자 크기 자체가 필요한 곳
        /// (`HwpPageChromeBuilder.pageNumberFrame`)도 읽는다.
        var baseFontSize: CGFloat = 0
        /// 줄 **글자** run의 상대크기 적용 전 기본 크기 최댓값 — 한글 문서·한글 2007 호환
        /// 문서에서 밑줄 두께와 선 모양 축척의 기준이다 (#226, `UnderlineReference.textFontSize`).
        /// `baseFontSize`와 달리 문단 끝 글자(CR)·한 줄 끝(`hwp.lineBreak`)·빈 줄 앵커·결합
        /// 문자열의 문단 구분자와 **모든** 마커 run(높이 0 마커 포함)을 세지 않는다 — 한글
        /// 12.30 실측 (2026-09-25): 10pt 밑줄이 40pt 무장식 글자·40pt 공백과 한 줄이면 두께
        /// 1.56pt(40pt 몫)인데, 40pt 문단 끝 글자·40pt 한 줄 끝·40pt 책갈피·40pt 글자 모양
        /// 마커의 그림과 한 줄이면 0.36pt(10pt 몫)다. 그 넷은 줄 상자(밑줄 자리)에는 든다.
        var textFontSize: CGFloat = 0
        /// 줄 공간을 **예약한** 글자처럼 취급 개체 마커 run(높이 > 0 delegate)의 기본 크기
        /// 최댓값 — 한글 문서에서 비율 줄 간격의 여분 기준(`textBoxHeight`)에만 들고 줄
        /// 상자(`boxHeight`)·베이스라인에는 들지 않는다 (#217). 한글 12.30 실측 (2026-09-24,
        /// 함초롬바탕 10pt 글·160%의 합성 HWPX를 다시 저장한 줄 캐시): 40pt 글자 모양 마커의
        /// 20pt 그림 줄 `vertsize` 2000·`baseline` 1700·`spacing` 2400, 8pt 그림 1000·850·2400,
        /// 20pt 마커의 8pt 그림 1000·850·1200, 개체만 남은 가운데 줄(8pt 그림 7개, 마커 40pt)
        /// 800·680·2400 — 마커가 10pt여도 800이다. 같은 줄의 40pt 책갈피(높이 0 마커)는
        /// 상자에 든다 (4000·3400·2400). 이 값이 없던 동안 개체 마커가 글자보다 크면 상자가
        /// 마커 크기로 부풀어 글자와 개체가 함께 내려갔다.
        var objectMarkerBaseFontSize: CGFloat = 0
        /// 이 줄이 예약한 글자처럼 취급 개체(run delegate)의 높이 최댓값 — 없으면 0.
        var delegateAscent: CGFloat = 0
        /// MS 워드 호환 문서의 **글자 상자** (pt) — 줄의 글자 run(장식 없는 run·CoreText
        /// 대체 글꼴 run 포함)의 글꼴 상자를 글자 모양 기본 크기로 곱해 축별 최댓값으로 합친
        /// 것(`HwpMsWordLineBox.union`). 줄 끝 글자(문단 끝 CR·한 줄 끝 LF)의 상자는 여기 들지
        /// 않고 `msWordLineEndBox`로 따로 든다 — 둘은 합치는 규칙이 다르다 (`msWordLineBox`,
        /// #223). 빈 줄 앵커·결합 문자열의 문단 구분자는 줄 끝 상자가 있으면 빠지고 없으면
        /// 글자로 든다 (`HwpMsWordRunFonts`). **개체 마커 run(run delegate)의 글꼴은 들지
        /// 않는다** — 한글 12.30 실측 (2026-09-20 `cm194-markers`): Apple SD/Menlo 10pt
        /// 줄(1559/1104)에 글자 모양이 함초롬돋움 10·20pt인 글자처럼 취급 표(높이 10.62pt)나
        /// 책갈피 컨트롤을 넣어도 `vertsize`·`baseline`이 1559·1104 그대로다 (함초롬돋움 상자
        /// 1692/1266·3383/2531이 들면 달라졌을 값). 글자 run도 줄 끝 글자도 개체도 없는 줄만
        /// 줄 공간을 **예약하지 않은** 마커(구역·단 정의, 책갈피, 자리 차지 개체 앵커)의 글꼴로
        /// 떨어진다. 개체가 있는 줄은 어느 마커의 글꼴로도 떨어지지 않는다 — 그런 줄은 개체가
        /// 상자다 (`msWordObjectMarkerBox`). 한글 문서 줄이면 nil.
        var msWordTextBox: HwpMsWordLineBox?
        /// MS 워드 호환 문서에서 줄을 끝내는 **줄 끝 글자의 상자** (pt) — 문단의 마지막 줄이면
        /// 문단 끝 글자(CR)의 상자(조판이 문단 전체에 실은 `hwp.msWordParagraphEndBox`), 한 줄
        /// 끝(코드 10)으로 끝나는 줄이면 그 글자(`hwp.lineBreak` run)의 상자다. 한글은 두
        /// 글자를 같은 규칙으로 줄 상자에 들인다 (`msWordLineBox`, #223 실측: 함초롬돋움 10pt
        /// 글 + 20pt 한 줄 끝의 줄 `textheight` 38.09 = 33.84 + 4.26 — 16pt CR과 같은 꼴). 그런
        /// 글자가 없는 줄(자동 줄바꿈)이거나 한글 문서 줄이면 nil.
        var msWordLineEndBox: HwpMsWordLineBox?
        /// MS 워드 호환 문서에서 줄 공간을 **예약한** 개체 마커 run 글꼴 상자의 축별 최댓값
        /// (pt) — 줄 상자에는 들지 않고, 글자 상자도 줄 끝 글자 상자도 없이 개체만 있는 줄에서
        /// 장식선 기준 상자(`cellHeight`)로만 쓴다 (`msWordLineBox`). 그런 줄은 상자 = 개체다
        /// (#223 PR 리뷰, 한글 12.30 실측 2026-09-25 — 넓은 표 둘·셋이 자동 줄바꿈으로 한 줄에
        /// 하나씩 놓인 문단의 앞 줄: 함초롬돋움 10pt 마커의 30pt 표 `vertsize` 30.00·`baseline`
        /// 30.00·160% `spacing` 6.00 = 0.6 × 마커 기본 크기, 16pt 마커면 9.60, Apple SD/Menlo
        /// 마커도 같고 셀 내용으로 16.92pt가 된 표는 16.92/16.92·6.00 — 마커 글꼴 상자
        /// 16.92/12.66을 글자 상자로 삼으면 30pt 표 줄이 34.26, 여분이 10.16이 된다). 그 줄에
        /// 폭·높이 0인 마커(구역 첫 문단의 구역·단 정의, 10·16pt 책갈피)가 함께 있어도 같다
        /// (`mk223`: 3000/3000·600 — 16pt 책갈피의 크기도 여분에 들지 않는다). 한글 문서 줄이면
        /// nil.
        var msWordObjectMarkerBox: HwpMsWordLineBox?
        /// MS 워드 호환 문서에서 비율 여분의 기준이 되는 기본 크기 — 글자 run과 **줄 공간을
        /// 예약한** 개체 마커의 기본 크기 최댓값. 같은 실측에서 20pt 글자 모양의 표 마커가
        /// 든 10pt 줄의 160% `spacing`이 1200(= 0.6 × 2000)이고, 20pt 글자 모양의 책갈피
        /// 컨트롤(폭 0 마커)은 932 그대로였다.
        var msWordSpacingBase: CGFloat = 0

        /// MS 워드 호환 문서의 **줄 상자** (pt, 한글 줄 캐시의 `vertsize`·`baseline`) —
        /// 글자 상자 T(`msWordTextBox`)에 줄 끝 글자 상자 C(`msWordLineEndBox` — 문단 끝
        /// 글자·한 줄 끝)와 개체 높이 O(`delegateAscent`)를 들인다. 둘은 T와 **축별 최댓값으로
        /// 합쳐지지 않는다**:
        ///
        /// - 베이스라인 = max(T 베이스라인, C 베이스라인, O).
        /// - 높이 = T 높이. 다만 C가 **T보다 높으면** C 높이 + T의 베이스라인 아래 몫이고,
        ///   O가 **T보다 높으면** O + T의 베이스라인 아래 몫과 견줘 큰 것이다.
        /// - 장식선 기준 상자(`cellHeight`)는 T의 것 — 밑줄은 이 줄 상자의 가장자리에서 T의
        ///   0.129 cell만큼 안쪽에 놓인다 (`HwpDecorationLineGeometry.msWordUnderlineBelow`).
        ///   T가 없는 줄은 줄 끝 글자 C의 cell, T도 C도 없이 개체만 있는 줄은 개체 마커 글꼴의
        ///   cell이다.
        ///
        /// 한글 12.30 실측 (2026-09-25, `targetProgram="MS_WORD"` 합성 HWPX 4종 ~140문단을
        /// 한글이 다시 저장한 줄 캐시와 PDF; 함초롬돋움 상자 1.692/1.266em, 아래 몫 0.426em):
        /// 10pt 본문 + 16pt 문단 끝 글자는 `vertsize` 31.32 = 27.06 + 4.26·`baseline` 20.25
        /// (C.b)·160% `spacing` 16.24(= C 기준 여분) — 12·14·20·24·30·40pt도, 함초롬돋움·Apple
        /// SD·Menlo·Helvetica·Times New Roman과 그 교차 조합(본문 Helvetica 10 + 끝 글자 함초롬
        /// 16 → 27.06 + 2.26)도 같다. 크기가 아니라 **상자 높이**로 가른다: Menlo 10pt 본문
        /// (15.15)에 함초롬돋움 10pt 끝 글자(16.92)는 21.03으로 쌓이고, 함초롬돋움 10pt 본문에
        /// Menlo 11pt 끝 글자(16.66)는 16.92 그대로다. 베이스라인이 더 깊어도 상자가 낮으면
        /// 합친다 (Apple SD 20pt + Menlo 20pt 끝 글자 3119/2207 — #194), 상자가 높고
        /// 베이스라인이 얕아도 쌓는다 (Menlo 10pt + Apple SD 10pt 끝 글자 1970/1104). 아래 몫은
        /// **합친 T**의 것이다 — Apple SD 20pt 한글 + Menlo 20pt 라틴 + 30pt 끝 글자는
        /// 59.86 = 50.74 + (31.19 − 22.07) (한글 캐시 값), Apple SD의 9.59가 아니다. 개체:
        /// 10pt 본문 + 30pt 표 + 16pt 끝 글자 34.26/30, 26pt 표 31.32/26, 28pt 표 32.26/28, 22pt 표 31.32/22;
        /// T보다 낮은 개체는 베이스라인만 옮긴다 (Apple SD 20pt + 25pt 표 3119/2500 — 종전
        /// 산식은 34.12; 10+20pt 본문 + 30pt 표 3383/3000); 표만 있는 문단은 끝 글자 10pt면
        /// 30/30, 40pt면 67.66/50.63. 글자도 줄 끝 글자도 없이 개체만 있는 줄(자동 줄바꿈으로
        /// 나뉜 개체 줄)은 T도 C도 없어 상자 = 개체다 (`msWordObjectMarkerBox`의 실측: 30pt 표
        /// 30/30 — 같은 문단의 마지막 줄 max(C, O)와 같은 규칙). 이 규칙이 없던 동안(#194의
        /// 축별 최댓값) 끝 글자가 큰 줄은 T의 아래 몫만큼 짧아 다음 문단이 그만큼 위로
        /// 당겨졌다 (#223).
        var msWordLineBox: HwpMsWordLineBox? {
            let text = msWordTextBox
            let end = msWordLineEndBox
            // 개체만 있는 줄의 장식선 기준 상자는 개체 마커 글꼴의 것이다 (상자에는 안 든다).
            let objectOnly = delegateAscent > 0 ? msWordObjectMarkerBox : nil
            guard let reference = text ?? end ?? objectOnly else { return nil }
            let textHeight = text?.lineHeight ?? 0
            let textBaseline = text?.baseline ?? 0
            let textBelow = max(0, textHeight - textBaseline)
            // 같은 글꼴·크기의 끝 글자는 글자 상자와 정확히 같은 값이다 (같은 em 상자 × 같은
            // 기본 크기) — 부동소수 잡음으로 쌓이지 않게 문턱을 둔다 (`compat-decorations`의
            // 절반이 이 등호 위에 있다: 쌓이면 Menlo 아래 몫 4.10pt가 붙는다).
            let threshold = textHeight + Self.stackingTolerance
            var height = textHeight
            if let end, end.lineHeight > threshold {
                height = end.lineHeight + textBelow
            }
            if delegateAscent > threshold {
                height = max(height, delegateAscent + textBelow)
            }
            return HwpMsWordLineBox(
                lineHeight: height,
                baseline: max(textBaseline, end?.baseline ?? 0, delegateAscent),
                cellHeight: reference.cellHeight
            )
        }

        /// 끝 글자·개체가 글자 상자보다 **높다**고 보는 문턱 (pt) — 같은 상자의 등호를 쌓기로
        /// 읽지 않게 하는 부동소수 여유다 (한글 캐시 단위 0.01pt보다 작다).
        static let stackingTolerance: CGFloat = 0.001

        /// 글자 상자 높이 — 비율 줄 간격의 여분(`spacing`)은 이 값 기준이다 (개체가 상자를
        /// 정한 줄에서도). 한글 문서는 `baseFontSize`와 `objectMarkerBaseFontSize` 가운데 큰
        /// 것 — 개체 마커의 글자 모양은 상자에는 안 들어도 여분 기준에는 든다 (#217 실측:
        /// 10pt 글 + 40pt 마커의 8pt 그림 줄 `vertsize` 1000에 160% `spacing` 2400). MS 워드
        /// 호환 문서는 글자 상자·문단 끝 상자 높이와 `msWordSpacingBase` 가운데 큰 것 (한글
        /// 12.30 실측 2026-09-20: Apple SD 산돌고딕 Neo 10pt 줄 `vertsize` 1559에 160%의
        /// `spacing` 932, 30pt 표가 든 같은 줄도 932) — 문단 끝 상자가 줄 상자를 키운 줄도
        /// 여분은 끝 상자 기준이다 (#223: 10pt + 16pt 끝 글자 `vertsize` 31.32에 `spacing`
        /// 16.24 = 0.6 × 27.06, 200%는 27.04). 개체만 있는 줄은 글자 상자가 없어 개체 마커의
        /// 기본 크기가 기준이다 (#223 PR 리뷰 실측: 10pt 마커의 30pt 표 줄 `spacing` 6.00,
        /// 16pt 마커 9.60).
        var textBoxHeight: CGFloat {
            guard msWordLineBox != nil else {
                return max(baseFontSize, objectMarkerBaseFontSize)
            }
            return max(
                msWordTextBox?.lineHeight ?? 0, msWordLineEndBox?.lineHeight ?? 0,
                msWordSpacingBase
            )
        }

        /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`).
        ///
        /// 한글 문서는 글자 몫(`baseFontSize` — 개체 마커의 글자 모양 제외)과 개체 높이
        /// 가운데 큰 것. MS 워드 호환 문서는 `msWordLineBox`의 높이 — 개체가 글자 상자보다
        /// 높으면 개체 + 글자 상자의 베이스라인 아래 몫이다 (한글 12.30 실측 2026-09-20
        /// `cm194-objects`: Apple SD/Menlo 10pt 줄(1559/1104)에 30pt 표를 글자처럼 넣으면
        /// `vertsize` 3455 = 3000 + 455, `baseline` 3000; 셀 내용으로 18.41pt가 된 표는
        /// 2296 = 1841 + 455, 1841).
        var boxHeight: CGFloat {
            guard let msWordLineBox else { return max(baseFontSize, delegateAscent) }
            return msWordLineBox.lineHeight
        }

        /// 줄 상자 상단에서 베이스라인까지 (한글 줄 캐시의 `baseline`) — 한글 문서는 상자
        /// 높이 × `HwpRenderTuning.Text.baselineAnchorRatio`(0.85), MS 워드 호환 문서는
        /// `msWordLineBox`의 베이스라인 (글자·문단 끝 글자 상자의 베이스라인과 개체 높이
        /// 가운데 큰 것 — 개체 바닥이 베이스라인에 놓인다, 위 실측의 `baseline` 3000·1841).
        var baselineAnchor: CGFloat {
            guard let msWordLineBox else {
                return max(0, max(baseFontSize, delegateAscent))
                    * HwpRenderTuning.Text.baselineAnchorRatio
            }
            return msWordLineBox.baseline
        }

        /// 글자처럼 취급 개체의 **바깥 상자**(개체 + 바깥 여백)가 줄 베이스라인에 맞추는 자리 —
        /// 바깥 상자 상단에서 그 자리까지가 상자 높이의 이 비율이다 (`HwpLineFrame.objectBaselineRatio`,
        /// `HwpObjectAnchorGeometry.inlineAnchorOrigin`). 한글 문서는 글자 상자와 같은
        /// `HwpRenderTuning.Text.baselineAnchorRatio`(0.85) — 개체 바깥 상자를 그 높이의 글자
        /// 하나로 보고 베이스라인을 맞춘다. MS 워드 호환 문서는 1 — 바깥 상자 바닥이 베이스라인에
        /// 놓인다 (`hh:adjustBaselineOfObjectToBottom`). 한글 12.30 실측 (2026-09-21, #195): 함초롬바탕
        /// 40pt 줄에 4·8·20·30·36·40·50pt 그림을 글자처럼 넣으면 한글 문서는 그림 상단 =
        /// 베이스라인 − 0.85 × 높이(바깥 여백 위 7·아래 3pt를 주면 바깥 30pt 상자의 0.85), MS 워드
        /// 호환 문서는 베이스라인 − 높이(여백은 바깥 상자 바닥 기준)였다 — 둘 다 0.12pt 안.
        var inlineObjectBaselineRatio: CGFloat {
            msWordLineBox == nil ? HwpRenderTuning.Text.baselineAnchorRatio : 1
        }
    }

    /// 이 줄의 상자 지표 — 갈래마다 다시 걷지 않게 한 번만 걷는다. `endsParagraph`는 이
    /// 줄이 문단의 마지막 줄인지(`HwpDrawnLine.endsParagraph`) — 조판 문자열에서 접힌 문단
    /// 끝 글자(CR)의 글자 모양이 그 줄에만 든다: 한글 문서는 그 기본 크기
    /// (`hwp.paragraphEndBaseFontSize`, #206)가 글자 상자에, MS 워드 호환 문서는 그 글꼴 상자
    /// (`hwp.msWordParagraphEndBox`, #194)가 줄 상자에. 문단 문자열이 있으면
    /// `lineMetrics(of:in:)`가 판정한다.
    static func lineMetrics(of line: CTLine, endsParagraph: Bool = false) -> LineMetrics {
        var metrics = LineMetrics()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return metrics }
        var isMsWord = false
        var fonts = HwpMsWordRunFonts()
        var endBox: HwpMsWordLineBox?
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            let font = ctFont(in: attributes)
            let declared = declaredSize(in: attributes, font: font)
            let isMarker = attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] != nil
            let ascent = isMarker ? delegateAscent(of: run) : 0
            // **마커 run도 자기 글자 모양을 싣는다** (`HwpTextRunBuilder.appendControlMarker`)
            // — 그 크기가 어디에 드는지는 줄 공간을 예약했는지(ascent > 0)가 가른다 (#217,
            // 폭이 아니다: 폭 0이어도 높이가 있으면 개체다). 예약하지 않은 마커는 글자처럼
            // 상자에 든다 — 마커만 있는 줄(noori 1쪽 자리 차지 그림 문단)의 상자가 0이 되지
            // 않고, 한글도 10pt 글에 든 40pt 책갈피·자리 차지 그림의 마커로 상자를 40pt로
            // 잡는다. 예약한 개체 마커는 비율 여분의 기준에만 든다 — 상자는 개체 높이가
            // 정한다 (`objectMarkerBaseFontSize`의 실측).
            if ascent > 0 {
                metrics.objectMarkerBaseFontSize = max(
                    metrics.objectMarkerBaseFontSize, declared ?? 0
                )
            }
            // 문단의 마지막 줄에는 접힌 문단 끝 글자(CR)의 글자 모양 크기도 글자 상자에 든다
            // — 한글 12.30 실측: 10pt 본문 + 16pt CR 문단의 마지막 줄만 `vertsize` 1600·
            // 160% `spacing` 960 (`HwpTextRunBuilder.attachParagraphEndBaseFontSize`). 키는
            // 문단 전체에 실리므로 줄 판정은 키가 아니라 `endsParagraph`다. 한 줄 끝으로
            // 나뉜 앞 줄에는 들지 않는다 (실측: 그 줄은 `baseline` 850·`spacing` 600 그대로).
            // 개체 마커 run에 실린 값도 CR 자신의 글자 모양이라 상자에 든다 (#217 실측:
            // 40pt 마커의 8pt 그림만 있는 문단은 CR이 10pt면 `vertsize` 1000, 40pt면 4000).
            metrics.baseFontSize = max(
                metrics.baseFontSize, ascent > 0 ? 0 : declared ?? 0,
                endsParagraph ? paragraphEndBaseFontSize(in: attributes) : 0
            )
            if !isMarker, isGlyphText(attributes) {
                metrics.textFontSize = max(metrics.textFontSize, declared ?? 0)
            }
            if isMsWordCompatible(attributes) {
                isMsWord = true
                if endsParagraph, endBox == nil,
                   let end = attributes?[HwpAttributedStringKey.msWordParagraphEndBox] as? [NSNumber],
                   end.count == 2
                {
                    endBox = HwpMsWordLineBox(
                        lineHeight: CGFloat(end[0].doubleValue),
                        baseline: CGFloat(end[1].doubleValue)
                    )
                }
            }
            if let font, let declared {
                fonts.append(
                    (font, declared), marker: isMarker ? (ascent > 0 ? .object : .anchor) : nil,
                    attributes: attributes
                )
                if !isMarker {
                    metrics.msWordSpacingBase = max(metrics.msWordSpacingBase, declared)
                }
            }
            // 줄 공간을 예약한 마커의 기본 크기는 MS 워드 호환 비율 여분의 기준에 든다
            // (`msWordSpacingBase`의 실측).
            metrics.delegateAscent = max(metrics.delegateAscent, ascent)
            if ascent > 0, let declared {
                metrics.msWordSpacingBase = max(metrics.msWordSpacingBase, declared)
            }
        }
        // 문서 단위 속성이라 줄의 run 하나가 MS 워드면 줄 전체가 그렇다 — 표식 run(한 줄
        // 끝·빈 줄 앵커)처럼 허용 목록으로 깎인 run도 글꼴이 있는 한 후보로 넣는다
        // (한글도 그 줄의 글자 모양으로 줄 상자를 잡는다). 글꼴 상자는 PostScript 이름으로
        // 캐시되므로 한글 문서 줄에서는 읽지 않는다.
        if isMsWord {
            let boxes = fonts.boxes(paragraphEnd: endBox)
            metrics.msWordTextBox = boxes.text
            metrics.msWordLineEndBox = boxes.lineEnd
            metrics.msWordObjectMarkerBox = boxes.objectMarker
        }
        return metrics
    }

    /// 문단 문자열 안의 줄 지표 — 줄이 문단의 마지막 줄인지를 문자열로 판정해
    /// (`endsParagraph(_:in:)`) MS 워드 호환 문단 끝 상자를 포함한다.
    static func lineMetrics(
        of line: CTLine, in attributedString: NSAttributedString
    ) -> LineMetrics {
        lineMetrics(
            of: line,
            endsParagraph: endsParagraph(CTLineGetStringRange(line), in: attributedString)
        )
    }

    /// MS 워드 호환 문서에서 이 줄의 줄 상자 (pt) — 장식선 기하
    /// (`HwpPageLayerDecorations`)가 밑줄 자리·두께의 기준으로 쓴다. 세로 배치가 쓰는 상자와
    /// 같은 값이라(`LineMetrics.msWordLineBox` — 문단 끝 글자·글자처럼 취급 개체가 키운 몫
    /// 포함) 밑줄이 그 줄의 베이스라인 자리와 어긋나지 않는다. 장식선 기준 상자
    /// (`cellHeight`)는 글자 상자의 것이다 (#223 한글 PDF: 16pt 문단 끝 글자가 키운 10pt 밑줄
    /// 줄의 밑줄은 상자 바닥에서 1.71pt 위 — 산식 1.68, 30pt 표 줄의 위 밑줄은 표 윗변에서
    /// 1.68pt 아래). 글자가 없는 줄은 줄 끝 글자의 cell, 글자도 줄 끝 글자도 없이 개체만 있는
    /// 줄은 개체 마커 글꼴의 cell이다.
    /// 한글 문서 줄이면 nil.
    public static func msWordLineBox(of line: CTLine, endsParagraph: Bool) -> HwpMsWordLineBox? {
        lineMetrics(of: line, endsParagraph: endsParagraph).msWordLineBox
    }

    /// 이 줄의 밑줄(글자 아래·글자 위·변경 추적 삽입 밑줄)이 공유하는 기준 (#226) — 장식선
    /// 기하(`HwpPageLayerDecorations`)가 줄마다 한 번 부른다. 한글 문서·한글 2007 호환
    /// 문서는 줄 상자 높이(`lineBoxHeight` — 세로 배치가 쓰는 `vertsize`와 같은 값이라 밑줄이
    /// 그 상자의 바닥·상단에 붙는다)와 줄 글자의 기본 크기 최댓값(`textFontSize` — 두께·선
    /// 모양 축척)을, MS 워드 호환 문서는 줄 상자(`msWordLineBox(of:endsParagraph:)`와 같은
    /// 값)를 싣는다. `endsParagraph`(`HwpDrawnLine.endsParagraph`)는 이 줄이 문단의 마지막
    /// 줄인지 — 그 줄의 상자에는 접힌 문단 끝 글자(CR)의 글자 모양도 든다 (#206, 한글 실측:
    /// 10pt 밑줄 + 40pt 문단 끝 글자 줄의 밑줄은 40pt 상자 바닥 −6.24pt에 10pt 두께 0.36pt).
    public static func underlineReference(
        of line: CTLine, endsParagraph: Bool
    ) -> HwpDecorationLineGeometry.UnderlineReference {
        let metrics = lineMetrics(of: line, endsParagraph: endsParagraph)
        return HwpDecorationLineGeometry.UnderlineReference(
            lineBoxHeight: metrics.boxHeight, textFontSize: metrics.textFontSize,
            msWordLineBox: metrics.msWordLineBox
        )
    }

    /// 문자열이 문단을 끝내면(`endsParagraph` — 다음 단·쪽으로 이어지는 조각이 아니면) 그 문단 끝
    /// 글자(CR)의 기본 크기(`hwp.paragraphEndBaseFontSize`, #206), 아니면 0. 한글은 이 크기를 문단
    /// 마지막 줄의 줄 상자에 넣는다 — 개체 마커로 끝나는 문단에서도 (#217: 40pt 마커의 8pt 그림만
    /// 있는 문단은 CR이 10pt면 `vertsize` 1000, 40pt면 4000).
    static func paragraphEndBaseFontSize(of attributedString: NSAttributedString) -> CGFloat {
        let length = attributedString.length
        guard length > 0, endsParagraph(CFRange(location: 0, length: length), in: attributedString)
        else { return 0 }
        return paragraphEndBaseFontSize(
            in: attributedString.attributes(at: length - 1, effectiveRange: nil)
        )
    }

    /// run이 MS 워드 호환 문서의 것인지 — 조판이 한글 문서가 아닌 문서의 모든 run에 싣는
    /// `hwp.compatibleDocumentTarget`(표 55)이 `msWord`일 때만 참이다. 한글 2007 호환·
    /// 훈민정음 호환·record 없음은 한글 문서와 같은 줄 상자다.
    static func isMsWordCompatible(_ attributes: [NSAttributedString.Key: Any]?) -> Bool {
        guard let raw = attributes?[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.msWord.rawValue
    }

    /// run이 **글자**인지 — 조판 문자열에만 있거나 줄 끝 글자의 자리를 대신하는 표식 run
    /// (한 줄 끝 `hwp.lineBreak`, 빈 줄·빈 문단 앵커 `hwp.emptyLineAnchor`, 결합 문자열의 문단
    /// 구분자 `combinedParagraphSeparator`)이 아니면 참이다. 마커 run(run delegate)은
    /// 호출자가 따로 거른다. 밑줄 두께의 기준(`LineMetrics.textFontSize`)이 이 run만 센다.
    private static func isGlyphText(_ attributes: [NSAttributedString.Key: Any]?) -> Bool {
        attributes?[HwpAttributedStringKey.lineBreak] == nil
            && attributes?[HwpAttributedStringKey.emptyLineAnchor] == nil
            && attributes?[HwpAttributedStringKey.combinedParagraphSeparator] == nil
    }

    /// 마커 run이 줄에 예약한 높이 — run delegate의 ascent다 (`HwpInlineObjectReservation`:
    /// 글자처럼 취급 개체는 바깥 상자 높이, 자리 차지 개체 앵커·필드 표식·메모 앵커·책갈피처럼
    /// 줄 공간을 예약하지 않는 마커는 0).
    private static func delegateAscent(of run: CTRun) -> CGFloat {
        var ascent: CGFloat = 0
        _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, nil, nil)
        return ascent
    }

    /// run이 실은 문단 끝 글자(CR)의 기본 크기 (`hwp.paragraphEndBaseFontSize`, #206) — 잘리지
    /// 않은 문단의 조판 문자열 전체에 실리며, 없거나 0 이하면 0.
    private static func paragraphEndBaseFontSize(
        in attributes: [NSAttributedString.Key: Any]?
    ) -> CGFloat {
        let value = attributes?[HwpAttributedStringKey.paragraphEndBaseFontSize]
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return 0 }
        return CGFloat(number.doubleValue)
    }

    /// run이 선언한 줄 상자 기준 크기 — 상대크기 적용 **전** 기본 글자 크기이고,
    /// 표식이 없는 합성 문자열에서는 조판 글꼴 크기로 떨어진다.
    private static func declaredSize(
        in attributes: [NSAttributedString.Key: Any]?, font: CTFont?
    ) -> CGFloat? {
        if let number = attributes?[HwpAttributedStringKey.baseFontSize] as? NSNumber,
           number.doubleValue > 0
        {
            return CGFloat(number.doubleValue)
        }
        return font.map(CTFontGetSize)
    }

    private static func ctFont(in attributes: [NSAttributedString.Key: Any]?) -> CTFont? {
        guard let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! CTFont)
    }
}

/// MS 워드 호환 줄의 run 글꼴을 상자 역할별로 모은다 (#194·#223).
///
/// - 글자: 보통 글자 run — 축별 최댓값으로 합친 것이 글자 상자 T다.
/// - 줄 끝 글자: 한 줄 끝(`hwp.lineBreak`) run — 문단 끝 글자(CR)처럼 T에 쌓인다 (한글
///   12.30 실측: 함초롬돋움 10pt 글 + 20pt 한 줄 끝 `textheight` 38.09 = 33.84 + 4.26, 16pt면
///   축별 최댓값 27.06이 아니라 31.32). 문단의 마지막 줄은 CR 상자가 그 자리다.
/// - 끝 글자 대역: 한 줄 끝 뒤 빈 줄 앵커(`hwp.emptyLineAnchor`)와 결합 문자열의 문단
///   구분자(`combinedParagraphSeparator`) — 조판 문자열에만 있는 글자로, 한글의 그 자리엔
///   줄 끝 글자뿐이다 (실측: 10pt 한 줄 끝 + 16pt CR의 빈 마지막 줄 2706/2025, 16pt 한 줄
///   끝 + 10pt CR은 1692/1266 = CR 상자만). 줄 끝 상자가 있으면 T에서 빠지고, 없으면(빈
///   문단 앵커는 문단 끝 상자를 싣지 않는다) 글자다.
/// - 앵커 마커: 줄 공간을 예약하지 않은 run delegate(구역·단 정의, 책갈피·필드 표식, 자리
///   차지 개체 앵커) — 글자도 줄 끝 상자도 개체도 없을 때만 T로 떨어진다.
/// - 개체 마커: 줄 공간을 예약한 run delegate(글자처럼 취급 개체) — T로 떨어지지 않는다.
///   개체만 있는 줄은 개체가 상자이고(`LineMetrics.msWordLineBox`) 이 글꼴은 그 줄의 장식선
///   기준 상자로만 쓴다 (#223 PR 리뷰 실측: 자동 줄바꿈으로 나뉜 30pt 표 줄 30/30).
private struct HwpMsWordRunFonts {
    typealias Entry = (font: CTFont, size: CGFloat)

    /// run delegate를 단 마커의 갈래 — 줄 공간을 예약했는지가 가른다 (#217).
    enum Marker {
        case anchor
        case object
    }

    var text: [Entry] = []
    var lineBreaks: [Entry] = []
    var endStandIns: [Entry] = []
    var anchorMarkers: [Entry] = []
    var objectMarkers: [Entry] = []

    mutating func append(
        _ entry: Entry, marker: Marker?, attributes: [NSAttributedString.Key: Any]?
    ) {
        switch marker {
        case .anchor:
            anchorMarkers.append(entry)
        case .object:
            objectMarkers.append(entry)
        case nil:
            if attributes?[HwpAttributedStringKey.lineBreak] != nil {
                lineBreaks.append(entry)
            } else if attributes?[HwpAttributedStringKey.emptyLineAnchor] != nil
                || attributes?[HwpAttributedStringKey.combinedParagraphSeparator] != nil
            {
                endStandIns.append(entry)
            } else {
                text.append(entry)
            }
        }
    }

    /// 글자 상자 T·줄 끝 상자·개체 마커 상자 — `paragraphEnd`는 문단의 마지막 줄이면 CR 상자.
    func boxes(
        paragraphEnd: HwpMsWordLineBox?
    ) -> (text: HwpMsWordLineBox?, lineEnd: HwpMsWordLineBox?, objectMarker: HwpMsWordLineBox?) {
        // CR이 줄을 끝내면 같은 줄의 한 줄 끝 run(조판 문자열 끝에 남은 한 줄 끝)도 끝 글자
        // 대역이라 어느 쪽에도 넣지 않는다.
        let lineEnd = paragraphEnd ?? Self.union(lineBreaks)
        let glyphs = lineEnd == nil ? text + endStandIns : text
        // 앵커 마커는 개체가 없는 줄에서만 T의 대역이다 — 개체가 있으면 상자는 개체다 (한글
        // 12.30 실측 `mk223`: 구역 첫 문단의 구역·단 정의나 10·16pt 책갈피가 자동 줄바꿈된 30pt
        // 표와 한 줄에 있어도 3000/3000·160% `spacing` 600).
        let bare = glyphs.isEmpty && lineEnd == nil && objectMarkers.isEmpty
        let chosen = bare ? anchorMarkers : glyphs
        return (Self.union(chosen), lineEnd, Self.union(objectMarkers))
    }

    private static func union(_ entries: [Entry]) -> HwpMsWordLineBox? {
        HwpMsWordLineBox.union(
            entries.map { HwpMsWordLineBox.metrics(of: $0.font).scaled(by: $0.size) }
        )
    }
}
