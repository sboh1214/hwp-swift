import CoreGraphics
import CoreText
import Foundation

/// 한글 줄 모델의 베이스라인 앵커와 줄 상자 지표 (#178).
///
/// 앵커 규칙 자체와 실측 근거는 `HwpRenderTuning.Text.baselineAnchorRatio`가
/// 소유한다. 여기에는 그 규칙을 CTLine에 적용하는 산식만 둔다.
///
/// **baseline은 앵커가 정한다.** `HwpDrawnTextLayout.lines`는 줄 상자 상단
/// (`lineGeometries`) 을 찾고 각 줄의 baseline을 그 아래 자기 앵커만큼에 둔다 — 종전
/// 구현은 CT가 강제 줄 높이 안에서 나눈 ascent를 기준점으로 써 그 몫이 베이스라인에 새어
/// 나갔다. 상자 상단은 첫 줄을 블록 상단에 정확히 핀하고 나머지는 CT 줄 origin 델타에서
/// **배치 ascent 몫을 되돌려** 타일한다 (`placementAscents`).
extension HwpDrawnTextLayout {
    /// 한글 줄 모델의 **베이스라인 앵커** — 줄 상자 상단에서 베이스라인까지의
    /// 거리 = 줄 상자 높이 × `HwpRenderTuning.Text.baselineAnchorRatio`.
    ///
    /// 줄 상자 높이는 줄 캐시 (`PARA_LINE_SEG`)의 `vertsize`에 해당하는 값이다 —
    /// 그 줄 글자들의 **상대크기 적용 전 기본 크기** 최대값이고, 줄 공간을 예약한
    /// 글자처럼 취급 개체 (run delegate)가 더 크면 그 개체 높이다. 줄 간격 종류·
    /// 값과 글꼴 지표는 앵커에 관여하지 않는다 (#178 실측).
    ///
    /// **남는 근사는 줄 상자 높이가 문단 단위라는 것이다.** 한글은 상자 높이도 줄마다
    /// 그 줄의 최대 글자 크기로 잡는데 (2026-09-12 실측: 10pt 45자 + 40pt 12자 한 문단의
    /// `vertsize`가 줄별로 1000·4000·4000), 우리는 강제 줄 높이를 문단 전체의 최대 크기로
    /// 정하므로 (`HwpParagraphMetrics.maxFontSize`) 그런 문단의 둘째 줄부터는 상자 상단이
    /// 어긋난다 (같은 문단 실측: 최대 오차 73.3 → 61.0pt, 각 문단 첫 줄은 정확). 상자를 줄
    /// 단위로 내는 것은 줄 **전진량** 축 (#180·#192) 몫이다.
    public static func baselineAnchor(of line: CTLine) -> CGFloat {
        max(0, lineMetrics(of: line).boxHeight) * HwpRenderTuning.Text.baselineAnchorRatio
    }

    /// 청크 줄 하나의 세로 기하 — 줄 상자 상단과 그 아래 앵커만큼 내린 baseline.
    struct LineGeometry {
        let boxTop: CGFloat
        let baseline: CGFloat
    }

    /// 청크 줄들의 세로 기하 (top-down).
    ///
    /// 첫 줄 상자 상단은 `base` (블록 상단, 이월이면 재개 상자 상단) 에 조건 없이 핀한다 —
    /// 블록 상단이 곧 첫 상자 상단인 것이 정의다. 재구성값으로 보정하면 그만큼 첫 줄이 블록
    /// 위로 올라간다 (실제로 그 형태의 회귀를 한 번 냈다 — 헌법주석 각주 0.63pt).
    ///
    /// 나머지 줄은 CT 줄 origin 델타에서 **배치 ascent 몫을 되돌린다**:
    /// `base + (origins[0].y − origins[k].y) + ascent_0 − ascent_k`. 델타는 baseline
    /// 간격이라 다음 줄의 ascent를 품고 있으므로 (`delta_k = 앞 줄 baseline 아래 몫 +
    /// 줄 사이 간격 + ascent_{k+1}`) 그것을 그대로 상자 간격으로 쓰면 줄마다 상자가 다른
    /// 문단에서 어긋난다 — 합성 실측 (Helvetica 10pt + 60pt 개체):
    ///
    /// | 개체 자리 | 델타 그대로 | 이 산식 |
    /// | --- | ---: | ---: |
    /// | 둘째 줄 | 213.0 (개체 바닥 169.7보다 43.3pt 아래) | 160.7 (= 바닥 − 0.15em) |
    /// | 첫 줄 | 120.5 (**첫 줄 baseline 151.0보다 위**) | 172.8 |
    ///
    /// 되돌리는 ascent는 `placementAscents`가 **정확한 배치값**으로 돌려준다. 강제 줄 높이
    /// 종류에 따른 갈래는 그쪽이 소유하므로 여기서는 상자 상단과 앵커만 본다.
    static func lineGeometries(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString,
        base: CGFloat
    ) -> [LineGeometry] {
        guard let firstOrigin = chunk.origins.first else { return [] }
        // 줄 지표는 한 번만 걷는다 — 앵커와 상자 높이가 같은 값에서 나온다.
        let metrics = chunk.lines.map { lineMetrics(of: $0) }
        let ascents = Self.placementAscents(
            of: chunk, in: attributedString, metrics: metrics
        )
        return chunk.lines.indices.map { index in
            let boxTop = index == 0
                ? base
                : base + firstOrigin.y - chunk.origins[index].y + ascents[0] - ascents[index]
            let anchor = max(0, metrics[index].boxHeight)
                * HwpRenderTuning.Text.baselineAnchorRatio
            return LineGeometry(boxTop: boxTop, baseline: boxTop + anchor)
        }
    }

    /// 청크 각 줄의 **배치 ascent** — CT가 그 줄 슬롯 상단에서 baseline까지 내린 거리.
    ///
    /// `CTLineGetTypographicBounds`의 **ascent는 이 값이 아니다.** CT는 슬롯의 여분을
    /// baseline 위에 넣으면서 그 몫을 줄 객체에 되돌려 주지 않는다 (Helvetica 10pt 자연
    /// 조판: 보고 7.70, 배치 9.70). 2026-09-13 실측으로 배치값을 직접 재고 (프레임 높이를
    /// 줄여 줄이 떨어지는 임계를 이분 탐색하면 CT의 실제 슬롯 경계가 나온다) 규칙을
    /// 글꼴 4종 × 라틴·한글 × 강제 줄 높이 5종 × 개체 유무 80조합에서 대조한 결과:
    ///
    /// | 청크 | 줄별 보고 ascent | 첫 줄 `floor` 균일 | 델타 − 앞 줄(descent+leading) |
    /// | --- | ---: | ---: | ---: |
    /// | 못박힘 (min = max) | 0.0003 | **0.0003** | 0.0003 |
    /// | 자유·상한만 | 0.50 | 0.50 | **0.0002** |
    /// | 자유·상한만 + 개체 | 3.00 | 31.36 | **0.0002** |
    /// | 하한만 + 개체 | 0.50 | 27.38 | **0.0003** |
    ///
    /// 그래서 두 갈래를 쓴다 — 어느 쪽도 보고 ascent를 쓰지 않는다:
    /// - **못박힌 청크**는 모든 슬롯이 그 높이라 배치 ascent가 줄마다 같다 → 첫 줄의
    ///   정확값 `floor` (`chunk.height − origins[0].y`, CT가 첫 슬롯을 프레임 상단에 붙인다).
    /// - **나머지**는 슬롯이 줄마다 다르다 → `델타 − 앞 줄의 baseline 아래 몫 − 줄 사이
    ///   간격`. 보고 descent + leading은 **그 줄 슬롯의 baseline 아래 몫과 같다** (같은
    ///   실측: 못박히지 않은 40조합 전부 0.0003pt 이내).
    ///
    /// 못박힌 청크에서 복원식을 쓸 수 없는 이유는 그 조건에서 CT가 클램프 **전** descent를
    /// 보고하기도 하기 때문이다 — `Column` 픽스처 실측 (Menlo 10pt·못박힘 16·줄 0에 개체
    /// 마커): 앞 6줄은 자연값 2.36, 마지막 줄만 클램프값 5.00을 보고하는데 배치값은 전부
    /// 5.00이다. 반대로 못박히지 않은 청크는 클램프가 없어 보고값이 배치값이다.
    private static func placementAscents(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString,
        metrics: [LineMetrics]
    ) -> [CGFloat] {
        guard let firstOrigin = chunk.origins.first else { return [] }
        let floor = chunk.height - firstOrigin.y
        if Self.pinnedLineHeight(of: chunk, in: attributedString) > 0 {
            // 개체가 예약한 높이보다는 작을 수 없다 (개체 문단을 못박는 경로는
            // `HwpParagraphMetrics`에 없지만 공개 API 호출자는 만들 수 있다).
            return chunk.lines.indices.map { max(floor, metrics[$0].delegateAscent) }
        }
        var ascents = [floor]
        guard chunk.lines.count > 1 else { return ascents }
        let text = attributedString.string as NSString
        for index in 1 ..< chunk.lines.count {
            let delta = chunk.origins[index - 1].y - chunk.origins[index].y
            ascents.append(
                delta
                    - belowBaseline(of: chunk.lines[index - 1])
                    - interlineGap(after: index - 1, of: chunk, in: attributedString, text: text)
            )
        }
        return ascents
    }

    /// 이 청크 문단이 줄 높이를 **못박았는지** (그 높이, 아니면 0).
    ///
    /// 못박힘은 `minimumLineHeight == maximumLineHeight`이고 **둘 다 양수**인 것이다 —
    /// 한글의 비율·고정 줄 간격이 그렇게 걸린다 (`HwpParagraphMetrics.applyLineHeight`).
    ///
    /// **하한만·상한만은 못박은 것이 아니다.** 하한만 (`.atLeast`·개체 문단) 은 자연 높이가
    /// 더 큰 줄을 그대로 두므로 슬롯이 줄마다 다르고, 상한만은 그 아래 높이를 전혀 건드리지
    /// 않는다 — 무해한 상한 (`maximumLineHeight = 1000`) 을 얹었을 때 CT 원점이 그대로인데
    /// 우리 baseline이 `[108.5, 151.9, 199.9]` → `[108.5, 175.0, 223.0]`으로 바뀌던 것이
    /// 상한만을 못박힌 쪽으로 본 탓이었다 (10pt 첫 줄 + 40pt 후속 줄, 실측).
    private static func pinnedLineHeight(
        of chunk: HwpLineBreaker.FrameChunk, in attributedString: NSAttributedString
    ) -> CGFloat {
        guard let line = chunk.lines.first else { return 0 }
        let location = CTLineGetStringRange(line).location
        let style = HwpLineBreaker.paragraphStyle(in: attributedString, at: location)
        let minimum = max(0, HwpLineBreaker.paragraphCGFloat(.minimumLineHeight, in: style) ?? 0)
        let maximum = max(0, HwpLineBreaker.paragraphCGFloat(.maximumLineHeight, in: style) ?? 0)
        guard minimum > 0, abs(minimum - maximum) < 0.001 else { return 0 }
        return maximum
    }

    /// 줄 슬롯에서 baseline **아래** 몫 — 보고 descent + leading (실측상 정확한 배치값).
    private static func belowBaseline(of line: CTLine) -> CGFloat {
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, nil, &descent, &leading)
        return descent + leading
    }

    /// 줄 `index`와 다음 줄 **사이**에 문단 스타일이 넣은 간격 — 줄 뒤 간격
    /// (`lineSpacingAdjustment`) 과, 그 줄이 문단을 끝내면 문단 아래·위 간격.
    ///
    /// CT는 이 몫을 **다음 줄 슬롯의 ascent 안에** 넣는다 (실측: 간격 6+4를 준 둘째 문단
    /// 첫 줄의 배치 ascent가 9.70 → 19.70). 배치 ascent 복원에서 빼 주면 간격이 상자
    /// **사이**에 남아 한글과 같아진다 — 한글은 줄 간격 여분을 상자 아래 `lineSpacing`으로
    /// 적고 다음 상자를 그 아래에 둔다. 개체 문단이 바로 이 경로다
    /// (`HwpParagraphMetrics.applyLineHeight`가 여분을 줄 뒤 간격으로 돌린다): 하한 16 +
    /// 줄 뒤 4 문단의 상자 전진량이 정확히 20pt = 한글의 전진량이 된다.
    private static func interlineGap(
        after index: Int,
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString,
        text: NSString
    ) -> CGFloat {
        let range = CTLineGetStringRange(chunk.lines[index])
        let style = HwpLineBreaker.paragraphStyle(in: attributedString, at: range.location)
        let adjustment = HwpLineBreaker.paragraphCGFloat(.lineSpacingAdjustment, in: style) ?? 0
        let spacing = HwpLineBreaker.paragraphCGFloat(.paragraphSpacing, in: style) ?? 0
        let nextLocation = CTLineGetStringRange(chunk.lines[index + 1]).location
        let nextStyle = HwpLineBreaker.paragraphStyle(in: attributedString, at: nextLocation)
        let before = HwpLineBreaker.paragraphCGFloat(.paragraphSpacingBefore, in: nextStyle) ?? 0
        guard spacing != 0 || before != 0, endsParagraph(range, in: text) else { return adjustment }
        return adjustment + spacing + before
    }

    /// 이 줄이 CT 문단을 끝내는지 — 마지막 글자가 문단 구분자 (LF·CR·U+2029) 인지.
    /// 줄 구분자 (U+2028·U+0085) 는 문단을 끝내지 않아 문단 간격도 들어가지 않는다.
    private static func endsParagraph(_ range: CFRange, in text: NSString) -> Bool {
        let end = range.location + range.length
        guard end > 0, end <= text.length else { return false }
        let unit = text.character(at: end - 1)
        return unit == 0x0A || unit == 0x0D || unit == 0x2029
    }

    /// 인라인 개체 줄에서 밑줄이 되돌아갈 양 — 실물은 밑줄을 개체 하단
    /// (= 줄 상자 바닥, 베이스라인 아래 `1 − baselineAnchorRatio` 몫) 근처에
    /// 남긴다 (공공누리 실물 실측)
    public static func underlineReturnDrop(of line: CTLine) -> CGFloat {
        let metrics = lineMetrics(of: line)
        guard metrics.delegateAscent > metrics.maxAscent, metrics.boxHeight > 0
        else { return 0 }
        return metrics.delegateAscent * HwpRenderTuning.Text.baselineLiftRatio
    }

    private struct LineMetrics {
        /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`)
        var boxHeight: CGFloat = 0
        var maxAscent: CGFloat = 0
        var delegateAscent: CGFloat = 0
    }

    private static func lineMetrics(of line: CTLine) -> LineMetrics {
        var metrics = LineMetrics()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return metrics }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            // **개체 마커 run도 자기 글자 모양을 싣는다** (`HwpTextRunBuilder.appendMarker`)
            // — delegate 분기보다 먼저 봐야 마커만 있는 줄(자리 차지 개체 앵커·필드 표식·
            // 메모 앵커는 폭 0 delegate를 단다)의 상자가 0이 되지 않는다.
            if let declared = declaredSize(in: attributes) {
                metrics.boxHeight = max(metrics.boxHeight, declared)
            }
            guard attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] == nil
            else {
                var ascent: CGFloat = 0
                _ = CTRunGetTypographicBounds(
                    run, CFRange(location: 0, length: 0), &ascent, nil, nil
                )
                metrics.delegateAscent = max(metrics.delegateAscent, ascent)
                // 개체 run의 ascent는 개체 높이다 (`HwpInlineObjectReservation`).
                metrics.boxHeight = max(metrics.boxHeight, ascent)
                continue
            }
            guard let font = ctFont(in: attributes) else { continue }
            metrics.maxAscent = max(metrics.maxAscent, CTFontGetAscent(font))
        }
        return metrics
    }

    /// run이 선언한 줄 상자 기준 크기 — 상대크기 적용 **전** 기본 글자 크기이고,
    /// 표식이 없는 합성 문자열에서는 조판 글꼴 크기로 떨어진다.
    private static func declaredSize(in attributes: [NSAttributedString.Key: Any]?) -> CGFloat? {
        if let number = attributes?[HwpAttributedStringKey.baseFontSize] as? NSNumber,
           number.doubleValue > 0
        {
            return CGFloat(number.doubleValue)
        }
        return ctFont(in: attributes).map(CTFontGetSize)
    }

    private static func ctFont(in attributes: [NSAttributedString.Key: Any]?) -> CTFont? {
        guard let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! CTFont)
    }
}
