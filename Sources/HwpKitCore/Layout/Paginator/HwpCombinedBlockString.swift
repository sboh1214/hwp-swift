import CoreText
import Foundation

/// 컨테이너 블록(각주·글상자·자리 차지 개체 블록)의 문단들을 `\n`으로 이은 **블록 문자열** —
/// payload 없는 조각 블록은 이 문자열을 그대로 그린다 (`HwpBlockContentWalker.plainText`).
/// `HwpPaginator`에서 옮긴 순수 함수다 (#217 — 구분자 속성 규칙을 테스트에서 직접 부르려고).
enum HwpCombinedBlockString {
    /// 문단 문자열들을 구분자 `\n`으로 잇는다 — 비면 nil.
    static func combine(_ strings: [NSAttributedString]) -> NSAttributedString? {
        guard !strings.isEmpty else { return nil }
        let combined = NSMutableAttributedString()
        for (offset, string) in strings.enumerated() {
            if offset > 0 {
                // 구분자는 앞 문단 마지막 글자의 **조판 속성**(글꼴·기본 크기·줄 간격 규칙·문단
                // 스타일)을 물려받는다 — 속성 없는 `\n`은 CT 기본 글꼴(Helvetica 12pt)로 조판돼
                // 그 줄의 상자(`HwpDrawnTextLayout.lineMetrics`)를 12pt로 부풀리고, 줄 뒤 문단
                // 간격도 앞 문단이 아니라 스타일 없는 글자에서 읽힌다 (#180). 장식·링크 같은 나머지
                // 속성은 싣지 않는다 — 구분자에 그려질 것이 없다.
                combined.append(NSAttributedString(
                    string: "\n", attributes: separatorAttributes(of: combined)
                ))
            }
            combined.append(string)
        }
        return combined
    }

    /// 문단 구분자에 물려줄 조판 속성 — 직전 글자의 글꼴·기본 크기·줄 간격 규칙·문단 스타일.
    static func separatorAttributes(
        of preceding: NSAttributedString
    ) -> [NSAttributedString.Key: Any] {
        guard preceding.length > 0 else { return [:] }
        let last = preceding.attributes(at: preceding.length - 1, effectiveRange: nil)
        var attributes: [NSAttributedString.Key: Any] = [
            HwpAttributedStringKey.combinedParagraphSeparator: NSNumber(value: true),
        ]
        for key in [
            kCTFontAttributeName as NSAttributedString.Key,
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            HwpAttributedStringKey.baseFontSize,
            HwpAttributedStringKey.lineSpacing,
        ] {
            if let value = last[key] {
                attributes[key] = value
            }
        }
        // 앞 문단이 줄 공간을 예약한 개체 마커로 끝나면 구분자는 그 문단 끝 글자(CR)의 크기를
        // 싣는다 — 구분자는 글자로 조판되므로 마커의 글자 모양을 물려받으면 줄 상자에 들지 않아야
        // 할 그 크기가 되살아난다 (#217). MS 워드 호환 줄 상자는 구분자 표식
        // (`combinedParagraphSeparator`)으로 구분자를 글자 상자에서 뺀다 (#223).
        if HwpInlineObjectReservation.reservesLineSpace(last),
           let end = last[HwpAttributedStringKey.paragraphEndBaseFontSize]
        {
            attributes[HwpAttributedStringKey.baseFontSize] = end
        }
        return attributes
    }
}
