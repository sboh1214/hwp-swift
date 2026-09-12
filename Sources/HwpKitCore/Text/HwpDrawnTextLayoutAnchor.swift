import CoreGraphics
import CoreText
import Foundation

/// 한글 줄 모델의 베이스라인 앵커와 줄 상자 지표 (#178).
///
/// 앵커 규칙 자체와 실측 근거는 `HwpRenderTuning.Text.baselineAnchorRatio`가
/// 소유한다. 여기에는 그 규칙을 CTLine에 적용하는 산식만 둔다.
///
/// **baseline은 앵커가 정한다.** `HwpDrawnTextLayout.lines`는 줄 상자 상단
/// (`boxTops(of:base:)`) 을 찾고 각 줄의 baseline을 그 아래 자기 앵커만큼에 둔다 — 종전
/// 구현은 CT가 강제 줄 높이 안에서 나눈 ascent를 기준점으로 써 그 몫이 베이스라인에 새어
/// 나갔다. 상자 상단은 첫 줄을 블록 상단에 정확히 핀하고 나머지는 CT 줄 origin 델타로
/// 타일하되 (그 델타가 문단 스타일의 전진량이다) 글자처럼 취급 개체가 예약한 높이만
/// 슬롯을 키우는 것으로 본다 (`placementAscent`).
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

    /// 청크 줄들의 **줄 상자 상단** (top-down). 첫 줄은 `base`에 정확히 핀하고 (블록
    /// 상단, 이월이면 재개 상자 상단) 나머지는 CT가 그 줄을 배치한 슬롯 상단
    /// `CT baseline − placementAscent`를 쓴다.
    ///
    /// 첫 줄은 `placementAscent` 재구성에 기대지 않는다 — 블록 상단이 곧 첫 상자 상단인
    /// 것이 정의이고, 그 배치 ascent는 `chunk.height − origins[0].y`로 정확히 알 수 있다.
    /// 재구성이 하한을 넘겨 잡으면 그만큼 첫 줄이 블록 위로 올라가므로 (실제로 그 형태의
    /// 회귀를 한 번 냈다 — 헌법주석 각주가 0.63pt 올라갔다) 조건 없이 핀한다.
    static func boxTops(of chunk: HwpLineBreaker.FrameChunk, base: CGFloat) -> [CGFloat] {
        guard let firstOrigin = chunk.origins.first else { return [] }
        let floor = chunk.height - firstOrigin.y
        let datum = base + floor + firstOrigin.y
        return chunk.lines.indices.map { index in
            index == 0
                ? base
                : datum - chunk.origins[index].y
                - placementAscent(of: chunk.lines[index], floor: floor)
        }
    }

    /// CT가 이 줄을 **배치할 때 쓴** ascent — 줄 상자 상단을 찾는 데만 쓴다.
    ///
    /// 기준은 **청크 첫 줄의 배치 ascent** (`floor` = `chunk.height − origins[0].y`,
    /// 정의상 정확하다) 이고, 그보다 큰 것은 **글자처럼 취급 개체가 예약한 높이**뿐이다.
    ///
    /// `CTLineGetTypographicBounds`의 ascent를 쓰면 안 된다 — 그것은 배치값이 아니다.
    /// ① 강제 줄 높이가 걸린 청크에서 CT는 줄마다 자연 ascent와 클램프된 ascent를 섞어
    /// 보고한다 (noori 15pt·170% 문단 실측: 같은 25.5pt 슬롯의 세 줄이 16.05·16.05·**18.0**
    /// 을 보고하고 배치는 전부 18.0이다). ② 여러 글꼴이 섞인 줄은 보고값이 하한보다
    /// 커진다 (헌법주석 각주: 함초롬 9.63 vs 배치 9.0) — 그것을 상자 상단에 반영하면 그 줄이
    /// 0.63pt 올라가 저장본 줄 간격 (11.70pt) 과 갈린다. 반면 개체 예약 높이는 슬롯을
    /// 실제로 키운다: 개체 문단은 `HwpParagraphMetrics.applyLineHeight`가 min/max를 걸지
    /// 않아 CT가 그 줄에 개체 높이만큼의 슬롯을 준다.
    private static func placementAscent(of line: CTLine, floor: CGFloat) -> CGFloat {
        max(floor, lineMetrics(of: line).delegateAscent)
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
