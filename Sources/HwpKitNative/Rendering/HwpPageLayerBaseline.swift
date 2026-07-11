import CoreText
import Foundation

extension HwpPageLayer {
    /// 한글 줄 모델의 베이스라인은 글자 크기의 ~0.85배 지점이다 (HCR 폰트의
    /// CT ascent 1.07em보다 높음 — plain-text 실물 실측: 첫 줄 잉크가 1.1mm
    /// 위). CT ascent와의 차이만큼 줄을 위로 올린다 (y-up 공간에서 +y).
    static func baselineLift(of line: CTLine) -> CGFloat {
        // 한글 줄 모델은 텍스트든 개체든 베이스라인을 칸 높이의 ~0.85
        // 지점에 둔다. 키 큰 인라인 개체 (run delegate)가 있으면 개체
        // ascent의 0.85 지점 (공공누리 실물 라운드 11: 0.859 실측),
        // 아니면 폰트 ascent 기준.
        var maxSize: CGFloat = 0
        var maxAscent: CGFloat = 0
        var delegateAscent: CGFloat = 0
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                guard attributes?[kCTRunDelegateAttributeName
                    as NSAttributedString.Key] == nil
                else {
                    var ascent: CGFloat = 0
                    _ = CTRunGetTypographicBounds(
                        run, CFRange(location: 0, length: 0), &ascent, nil, nil
                    )
                    delegateAscent = max(delegateAscent, ascent)
                    continue
                }
                guard let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
                      CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                else { continue }
                // swiftlint:disable:next force_cast
                let font = value as! CTFont
                maxSize = max(maxSize, CTFontGetSize(font))
                maxAscent = max(maxAscent, CTFontGetAscent(font))
            }
        }
        guard maxSize > 0 else { return 0 }
        let fontLift = max(0, maxAscent - maxSize * 0.85)
        guard delegateAscent > maxAscent else { return fontLift }
        return max(fontLift, delegateAscent * 0.15)
    }

    /// 인라인 개체 줄에서 밑줄이 되돌아갈 양 — 실물은 밑줄을 개체 하단
    /// (lift 전 베이스라인) 근처에 남긴다 (공공누리 라운드 11 실측)
    static func underlineReturnDrop(of line: CTLine) -> CGFloat {
        baselineLift(of: line) > 0 ? deltaToUnliftedBaseline(of: line) : 0
    }

    private static func deltaToUnliftedBaseline(of line: CTLine) -> CGFloat {
        var maxFontAscent: CGFloat = 0
        var maxFontSize: CGFloat = 0
        var delegateAscent: CGFloat = 0
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                if attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] != nil {
                    var ascent: CGFloat = 0
                    _ = CTRunGetTypographicBounds(
                        run, CFRange(location: 0, length: 0), &ascent, nil, nil
                    )
                    delegateAscent = max(delegateAscent, ascent)
                    continue
                }
                if let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
                   CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                {
                    // swiftlint:disable:next force_cast
                    let font = value as! CTFont
                    maxFontSize = max(maxFontSize, CTFontGetSize(font))
                    maxFontAscent = max(maxFontAscent, CTFontGetAscent(font))
                }
            }
        }
        guard delegateAscent > maxFontAscent, maxFontSize > 0 else { return 0 }
        return delegateAscent * 0.15
    }
}
