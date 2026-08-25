import CoreText
import Foundation

// MARK: - 범위 → 속성 문자열 (#118)

extension HwpSelectionGeometry {
    /// 선택 범위의 속성 문자열 — `plainText(for:)`와 같은 조각(`fragments`)·
    /// 같은 개행 규칙(`joinsWithPrevious`)으로 조립하므로 `.string`이 평문
    /// 결과와 항상 같다 (파리티는 `HwpSelectionGeometryAttributedTests`가
    /// 고정한다).
    ///
    /// 속성은 조판 그대로다 — CT 표준 키에 `HwpAttributedStringKey`의
    /// `hwp.*` 장식 키가 섞여 있다. 표준 NSAttributedString 키로의 정규화와
    /// RTF 직렬화는 플랫폼 색·문단 스타일 타입(AppKit/UIKit)이 필요해
    /// HwpKitNative(`HwpSelectionRTF`)가 맡는다. U+FFFC 개체 자리 표시
    /// run만 여기서 지운다 — 마커 전용 속성(run delegate·`controlIndex`·
    /// `inlineObjectHeight`)이 문자와 함께 사라지고, 마커를 가로지르던 속성
    /// 범위(하이퍼링크 포함)는 남은 글자에 이어 붙는다.
    public func attributedText(for selection: HwpTextSelection) -> NSAttributedString {
        let pieces = fragments(for: selection)
        let result = NSMutableAttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0, !Self.joinsWithPrevious(pieces[index - 1], piece) {
                result.append(NSAttributedString(
                    string: "\n", attributes: Self.newlineAttributes(endingAt: result)
                ))
            }
            result.append(Self.strippingControlMarkerRuns(piece.attributedText))
        }
        return result
    }

    /// 조각 사이 개행이 입는 속성 — 직전 글자에서 **문단 스타일과 폰트만**
    /// 옮긴다. Cocoa 텍스트 시스템은 문단 스타일을 종결 개행까지 적용하므로
    /// 속성 없는 개행은 RTF에서 앞 문단의 스타일을 잃고, 반대로 전체를
    /// 상속하면 하이퍼링크·밑줄 같은 글자 속성이 원문에 없던 개행까지 번진다
    /// (RTF에서 HYPERLINK 필드가 문단 나눔 문자를 덮는다).
    private static func newlineAttributes(
        endingAt result: NSAttributedString
    ) -> [NSAttributedString.Key: Any] {
        guard result.length > 0 else { return [:] }
        let previous = result.attributes(at: result.length - 1, effectiveRange: nil)
        let inherited = [
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            kCTFontAttributeName as NSAttributedString.Key,
        ]
        var attributes: [NSAttributedString.Key: Any] = [:]
        for key in inherited {
            attributes[key] = previous[key]
        }
        return attributes
    }

    /// `strippingControlMarkers`의 attributed 판. 마커를 가로지르는 속성 범위
    /// (개체를 감싼 하이퍼링크)는 양옆 구간이 같은 값으로 이어 붙어
    /// `longestEffectiveRange`에서 하나로 보인다.
    ///
    /// **제자리 삭제로 되돌리지 말 것** — `deleteCharacters`도
    /// `mutableString.replaceOccurrences`도 마커마다 접미를 밀어 이차가 되고,
    /// 복사는 `@MainActor`에서 돈다 (`testMarkerStrippingStaysLinear`).
    static func strippingControlMarkerRuns(
        _ attributed: NSAttributedString
    ) -> NSAttributedString {
        let text = attributed.string as NSString
        var marker = text.range(of: "\u{FFFC}")
        guard marker.location != NSNotFound else { return attributed }
        let result = NSMutableAttributedString()
        var cursor = 0
        while marker.location != NSNotFound {
            if marker.location > cursor {
                result.append(attributed.attributedSubstring(
                    from: NSRange(location: cursor, length: marker.location - cursor)
                ))
            }
            cursor = marker.location + marker.length
            marker = text.range(
                of: "\u{FFFC}",
                options: [],
                range: NSRange(location: cursor, length: text.length - cursor)
            )
        }
        if cursor < text.length {
            result.append(attributed.attributedSubstring(
                from: NSRange(location: cursor, length: text.length - cursor)
            ))
        }
        return result
    }
}
