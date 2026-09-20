import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 줄 상자를 정하는 **지표**와 그 수집 (#178·#180·#194).
///
/// 앵커(`baselineAnchor`)·줄 전진량(`HwpLineAdvance`)·밑줄 되돌림(`underlineReturnDrop`)·
/// MS 워드 호환 장식선의 줄 상자(`msWordLineBox`)가 모두 이 한 벌을 쓴다 — 줄에서 무엇을
/// 읽는지의 단일 원본이라 갈래마다 다른 지표를 보는 일이 생기지 않는다.
extension HwpDrawnTextLayout {
    /// 줄 상자를 정하는 지표 — 한글 줄 캐시(`PARA_LINE_SEG`)의 `vertsize`·`baseline`에
    /// 해당하는 값을 글자 몫과 개체 몫으로 나눠 든다.
    ///
    /// 한글 문서에서는 글꼴 지표(ascent·descent·leading)가 세로 배치에 관여하지 않는다 —
    /// 글자 상자는 기본 글자 크기, 베이스라인은 상자의 0.85. MS 워드 호환 문서
    /// (`hwp.compatibleDocumentTarget` == `msWord`, #194)에서는 반대로 글꼴의 OS/2 win
    /// 지표가 줄 상자를 정한다 (`HwpMsWordLineBox`) — `msWordTextBox`가 그 상자이고
    /// `textBoxHeight`는 그 높이다.
    struct LineMetrics {
        /// 이 줄 글자 run들의 **상대크기 적용 전 기본 크기** 최댓값 — 개체 마커 run이 실은
        /// 글자 모양도 포함한다. 한글 문서의 글자 상자 높이이고, 쪽 번호 상자처럼 글자 크기
        /// 자체가 필요한 곳(`HwpPageChromeBuilder.pageNumberFrame`)이 읽는다.
        var baseFontSize: CGFloat = 0
        /// 이 줄이 예약한 글자처럼 취급 개체(run delegate)의 높이 최댓값 — 없으면 0.
        var delegateAscent: CGFloat = 0
        /// MS 워드 호환 문서의 **글자 줄 상자** (pt) — 줄의 글자 run(장식 없는 run·CoreText
        /// 대체 글꼴 run·표식 run 포함)의 글꼴 상자를 글자 모양 기본 크기로 곱해 축별
        /// 최댓값으로 합치고(`HwpMsWordLineBox.union`), 문단의 마지막 줄이면 조판이 문단
        /// 전체에 실은 문단 끝 글자 상자(`hwp.msWordParagraphEndBox`)를 더한 것. **개체
        /// 마커 run(run delegate)의 글꼴은 들지 않는다** — 한글 12.30 실측 (2026-09-20
        /// `cm194-markers`): Apple SD/Menlo 10pt 줄(1559/1104)에 글자 모양이 함초롬돋움
        /// 10·20pt인 글자처럼 취급 표(높이 10.62pt)나 책갈피 컨트롤을 넣어도 `vertsize`·
        /// `baseline`이 1559·1104 그대로다 (함초롬돋움 상자 1692/1266·3383/2531이 들면
        /// 달라졌을 값). 글자 run이 하나도 없는 줄(컨트롤만 있는 조각)은 마커 글꼴로
        /// 떨어진다. 한글 문서 줄이면 nil.
        var msWordTextBox: HwpMsWordLineBox?
        /// MS 워드 호환 문서에서 비율 여분의 기준이 되는 기본 크기 — 글자 run과 **줄 공간을
        /// 예약한** 개체 마커의 기본 크기 최댓값. 같은 실측에서 20pt 글자 모양의 표 마커가
        /// 든 10pt 줄의 160% `spacing`이 1200(= 0.6 × 2000)이고, 20pt 글자 모양의 책갈피
        /// 컨트롤(폭 0 마커)은 932 그대로였다.
        var msWordSpacingBase: CGFloat = 0

        /// 글자 상자 높이 — 비율 줄 간격의 여분(`spacing`)은 이 값 기준이다 (개체가 상자를
        /// 정한 줄에서도). 한글 문서는 `baseFontSize`, MS 워드 호환 문서는 글꼴 줄 상자 높이와
        /// `msWordSpacingBase` 가운데 큰 것 (한글 12.30 실측 2026-09-20: Apple SD 산돌고딕
        /// Neo 10pt 줄 `vertsize` 1559에 160%의 `spacing` 932, 30pt 표가 든 같은 줄도 932).
        var textBoxHeight: CGFloat {
            guard let msWordTextBox else { return baseFontSize }
            return max(msWordTextBox.lineHeight, msWordSpacingBase)
        }

        /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`).
        ///
        /// 한글 문서는 글자 상자와 개체 높이 가운데 큰 것. MS 워드 호환 문서는 베이스라인
        /// 위가 max(글꼴 상자 베이스라인, 개체 높이)이고 아래는 글꼴 상자의 베이스라인 아래
        /// 몫 그대로다 — 한글 12.30 실측(2026-09-20 `cm194-objects`): Apple SD/Menlo 10pt
        /// 줄(1559/1104)에 30pt 표를 글자처럼 넣으면 `vertsize` 3455 = 3000 + 455,
        /// `baseline` 3000; 셀 내용으로 18.41pt가 된 표는 2296 = 1841 + 455, 1841.
        var boxHeight: CGFloat {
            guard let msWordTextBox else { return max(baseFontSize, delegateAscent) }
            return baselineAnchor + max(0, msWordTextBox.lineHeight - msWordTextBox.baseline)
        }

        /// 줄 상자 상단에서 베이스라인까지 (한글 줄 캐시의 `baseline`) — 한글 문서는 상자
        /// 높이 × `HwpRenderTuning.Text.baselineAnchorRatio`(0.85), MS 워드 호환 문서는
        /// 글꼴 줄 상자의 베이스라인과 개체 높이 가운데 큰 것 (개체 바닥이 베이스라인에
        /// 놓인다 — 위 실측의 `baseline` 3000·1841).
        var baselineAnchor: CGFloat {
            guard let msWordTextBox else {
                return max(0, max(baseFontSize, delegateAscent))
                    * HwpRenderTuning.Text.baselineAnchorRatio
            }
            return max(msWordTextBox.baseline, delegateAscent)
        }
    }

    /// 이 줄의 상자 지표 — 갈래마다 다시 걷지 않게 한 번만 걷는다. `endsParagraph`는 이
    /// 줄이 문단의 마지막 줄인지(`HwpDrawnLine.endsParagraph`) — MS 워드 호환 문서의 문단
    /// 끝 글자 상자가 그 줄에만 든다. 문단 문자열이 있으면 `lineMetrics(of:in:)`가 판정한다.
    static func lineMetrics(of line: CTLine, endsParagraph: Bool = false) -> LineMetrics {
        var metrics = LineMetrics()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return metrics }
        var isMsWord = false
        var textFonts: [(font: CTFont, size: CGFloat)] = []
        var markerFonts: [(font: CTFont, size: CGFloat)] = []
        var endBox: HwpMsWordLineBox?
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            let font = ctFont(in: attributes)
            // **개체 마커 run도 자기 글자 모양을 싣는다** (`HwpTextRunBuilder.appendMarker`)
            // — delegate 분기보다 먼저 봐야 마커만 있는 줄(자리 차지 개체 앵커·필드 표식·
            // 메모 앵커는 폭 0 delegate를 단다)의 상자가 0이 되지 않는다.
            let declared = declaredSize(in: attributes, font: font)
            if let declared {
                metrics.baseFontSize = max(metrics.baseFontSize, declared)
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
            let isMarker = attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] != nil
            if let font, let declared {
                if isMarker {
                    markerFonts.append((font, declared))
                } else {
                    textFonts.append((font, declared))
                    metrics.msWordSpacingBase = max(metrics.msWordSpacingBase, declared)
                }
            }
            guard isMarker else { continue }
            var ascent: CGFloat = 0
            _ = CTRunGetTypographicBounds(
                run, CFRange(location: 0, length: 0), &ascent, nil, nil
            )
            // 개체 run의 ascent는 개체 높이다 (`HwpInlineObjectReservation`). 줄 공간을
            // 예약한 마커의 기본 크기는 MS 워드 호환 비율 여분의 기준에 든다 (위 실측).
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
            let fonts = textFonts.isEmpty && endBox == nil ? markerFonts : textFonts
            var boxes = fonts.map { HwpMsWordLineBox.metrics(of: $0.font).scaled(by: $0.size) }
            if let endBox {
                boxes.append(endBox)
            }
            metrics.msWordTextBox = HwpMsWordLineBox.union(boxes)
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

    /// MS 워드 호환 문서에서 이 줄의 글자 줄 상자 (pt) — 장식선 기하
    /// (`HwpPageLayerDecorations`)가 밑줄 자리·두께의 기준으로 쓴다. 세로 배치가 쓰는 상자와
    /// 같은 값이라 밑줄이 그 줄의 베이스라인 자리와 어긋나지 않는다. 한글 문서 줄이면 nil.
    public static func msWordLineBox(of line: CTLine, endsParagraph: Bool) -> HwpMsWordLineBox? {
        lineMetrics(of: line, endsParagraph: endsParagraph).msWordTextBox
    }

    /// 문자열 `index`의 글자 run이 홀로 이루는 줄의 글자 상자 높이 — 한글 문서는 기본 글자
    /// 크기, MS 워드 호환 문서는 그 글꼴의 줄 상자 높이. 줄 경계를 모르는 근사
    /// (`HwpColumnBandController.measuredTrailingSpacing`)가 쓴다. 글자 크기를 알 수 없으면 0.
    static func textBoxHeight(at index: Int, in attributedString: NSAttributedString) -> CGFloat {
        guard attributedString.length > 0 else { return 0 }
        let attributes = attributedString.attributes(
            at: min(max(index, 0), attributedString.length - 1), effectiveRange: nil
        )
        let font = ctFont(in: attributes)
        guard let size = declaredSize(in: attributes, font: font), size > 0 else { return 0 }
        guard isMsWordCompatible(attributes), let font else { return size }
        return HwpMsWordLineBox.metrics(of: font).scaled(by: size).lineHeight
    }

    /// 문자열 **마지막 줄**의 글자 상자 높이 근사 — 마지막 글자의 상자(`textBoxHeight(at:in:)`)에,
    /// 문자열이 문단을 끝내면(`endsParagraph`) MS 워드 호환 문단 끝 글자 상자
    /// (`hwp.msWordParagraphEndBox`)의 높이를 합친다. 접힌 문단 끝 글자(CR)는 마지막 글자와
    /// 다른 라틴 슬롯 글꼴이거나 CR만의 글자 모양일 수 있어 그 상자가 더 클 수 있다 (PR 리뷰:
    /// 다단 밴드 바닥의 구분선이 그만큼 마지막 줄 상자 아래로 길어졌다). 다음 단·쪽으로
    /// 이어지는 조각의 끝 줄은 문단 끝이 아니라 끝 상자가 들지 않는다.
    static func trailingTextBoxHeight(in attributedString: NSAttributedString) -> CGFloat {
        guard attributedString.length > 0 else { return 0 }
        let index = attributedString.length - 1
        let height = textBoxHeight(at: index, in: attributedString)
        guard endsParagraph(
            CFRange(location: 0, length: attributedString.length), in: attributedString
        ), let end = attributedString.attribute(
            HwpAttributedStringKey.msWordParagraphEndBox, at: index, effectiveRange: nil
        ) as? [NSNumber], end.count == 2
        else { return height }
        return max(height, CGFloat(end[0].doubleValue))
    }

    /// run이 MS 워드 호환 문서의 것인지 — 조판이 한글 문서가 아닌 문서의 모든 run에 싣는
    /// `hwp.compatibleDocumentTarget`(표 55)이 `msWord`일 때만 참이다. 한글 2007 호환·
    /// 훈민정음 호환·record 없음은 한글 문서와 같은 줄 상자다.
    static func isMsWordCompatible(_ attributes: [NSAttributedString.Key: Any]?) -> Bool {
        guard let raw = attributes?[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.msWord.rawValue
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
