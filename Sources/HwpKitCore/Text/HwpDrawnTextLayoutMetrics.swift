import CoreGraphics
import CoreText
import Foundation

/// 줄 슬롯을 정하는 **지표**와 그 수집 (#178).
///
/// 앵커(`baselineAnchor`)·상자 상단 복원(`lineGeometries`)·청크 이월 판정(`matchesSlot`)·
/// 밑줄 되돌림(`underlineReturnDrop`)이 모두 이 한 벌을 쓴다 — 줄에서 무엇을 읽는지의
/// 단일 원본이라 갈래마다 다른 지표를 보는 일이 생기지 않는다.
extension HwpDrawnTextLayout {
    /// 줄 슬롯을 정하는 지표 — 앵커(상자 높이)와 이월 판정에 쓴다.
    struct LineMetrics {
        /// 줄 상자 높이 (한글 줄 캐시의 `vertsize`)
        var boxHeight: CGFloat = 0
        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        /// 이 줄 글꼴들의 최대 leading — CT는 이 몫을 **다음 줄** 슬롯에 얹는다 (아래 실측).
        var maxLeading: CGFloat = 0
        var delegateAscent: CGFloat = 0

        /// 이월한 배치 ascent를 다음 청크 첫 줄에 써도 되는지 — **CT 슬롯을 정하는 지표**가
        /// 같아야 한다. 버린 줄은 **미완**이라 다음 청크에서 온전히 재조판되며 그때 큰 개체나
        /// 큰 글자가 그 줄에 들어올 수 있고, 그러면 그 자리의 배치 ascent가 달라진다 (실측:
        /// 60pt 개체가 붙은 줄에 미완 줄의 14pt를 쓰면 다음 텍스트 줄이 개체 줄보다 22.5pt 위로
        /// 올라가 겹친다).
        ///
        /// **`boxHeight`는 보지 않는다** — 그것은 상대크기 적용 **전** 기본 크기(앵커 몫)라
        /// 실제 조판 크기와 무관하게 달라질 수 있다. 경계 글자만 기본 20pt·상대크기 50%(실제
        /// 10pt)로 두면 슬롯은 그대로인데 이월 ascent가 버려져 뒤 줄이 4.8pt 올라갔다 (실측).
        /// 슬롯을 정하는 것은 **실제 글꼴 지표와 개체 예약**이다.
        ///
        /// **`maxLeading`도 보지 않는다** — CT는 글꼴 leading을 그 줄이 아니라 **다음 줄**
        /// 슬롯에 얹는다 (2026-09-14 임계 실측: ascent 18.0·descent 6.0이 같고 leading만
        /// 0 대 1.7143인 두 글꼴로 한 글자만 바꾸면, 그 글자가 든 줄의 슬롯은 24.0 그대로이고
        /// **다음** 줄이 26.0이 된다). 그러므로 재조판된 줄이 leading이 다른 run을 얻어도 그
        /// 줄 자신의 배치 ascent는 그대로고 이월 값은 유효하다. 다음 자리로 넘어가는 몫은
        /// `ResumedSlot.inflatingLeading`이 가른다.
        func matchesSlot(of other: LineMetrics) -> Bool {
            abs(maxAscent - other.maxAscent) < 0.001
                && abs(maxDescent - other.maxDescent) < 0.001
                && abs(delegateAscent - other.delegateAscent) < 0.001
        }
    }

    /// 이 줄의 슬롯 지표 — 갈래마다 다시 걷지 않게 한 번만 걷는다.
    static func lineMetrics(of line: CTLine) -> LineMetrics {
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
            metrics.maxDescent = max(metrics.maxDescent, CTFontGetDescent(font))
            metrics.maxLeading = max(metrics.maxLeading, CTFontGetLeading(font))
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
