import CoreGraphics
import CoreText
import Foundation

/// 줄 상자를 정하는 **지표**와 그 수집 (#178·#180).
///
/// 앵커(`baselineAnchor`)·줄 전진량(`HwpLineAdvance`)·밑줄 되돌림(`underlineReturnDrop`)이
/// 모두 이 한 벌을 쓴다 — 줄에서 무엇을 읽는지의 단일 원본이라 갈래마다 다른 지표를 보는
/// 일이 생기지 않는다.
extension HwpDrawnTextLayout {
    /// 줄 상자를 정하는 지표 — 한글 줄 캐시(`PARA_LINE_SEG`)의 `vertsize`에 해당하는 값을
    /// 글자 몫과 개체 몫으로 나눠 든다. 글꼴 지표(ascent·descent·leading)는 세로 배치에
    /// 관여하지 않으므로 여기 없다.
    struct LineMetrics {
        /// 이 줄 글자 run들의 **상대크기 적용 전 기본 크기** 최댓값 — 개체 마커 run이 실은
        /// 글자 모양도 포함한다. 비율 줄 간격의 여분(`spacing`)은 이 값 기준이다.
        var textBoxHeight: CGFloat = 0
        /// 이 줄이 예약한 글자처럼 취급 개체(run delegate)의 높이 최댓값 — 없으면 0.
        var delegateAscent: CGFloat = 0

        /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`) — 글자 상자와 개체 높이 가운데 큰 것.
        var boxHeight: CGFloat {
            max(textBoxHeight, delegateAscent)
        }
    }

    /// 이 줄의 상자 지표 — 갈래마다 다시 걷지 않게 한 번만 걷는다.
    static func lineMetrics(of line: CTLine) -> LineMetrics {
        var metrics = LineMetrics()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return metrics }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            // **개체 마커 run도 자기 글자 모양을 싣는다** (`HwpTextRunBuilder.appendMarker`)
            // — delegate 분기보다 먼저 봐야 마커만 있는 줄(자리 차지 개체 앵커·필드 표식·
            // 메모 앵커는 폭 0 delegate를 단다)의 상자가 0이 되지 않는다.
            if let declared = declaredSize(in: attributes) {
                metrics.textBoxHeight = max(metrics.textBoxHeight, declared)
            }
            guard attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] != nil
            else { continue }
            var ascent: CGFloat = 0
            _ = CTRunGetTypographicBounds(
                run, CFRange(location: 0, length: 0), &ascent, nil, nil
            )
            // 개체 run의 ascent는 개체 높이다 (`HwpInlineObjectReservation`).
            metrics.delegateAscent = max(metrics.delegateAscent, ascent)
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
