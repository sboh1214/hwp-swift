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
    /// `inlineObjectHeight`)이 문자와 함께 사라지고, 남은 속성 범위
    /// (하이퍼링크 포함)는 `deleteCharacters`가 자동으로 당긴다.
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

    /// `strippingControlMarkers`의 attributed 판 — 뒤에서 앞으로 지워
    /// 앞쪽 탐색 범위가 밀리지 않는다.
    static func strippingControlMarkerRuns(
        _ attributed: NSAttributedString
    ) -> NSAttributedString {
        guard attributed.string.contains("\u{FFFC}") else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        var range = (mutable.string as NSString)
            .range(of: "\u{FFFC}", options: .backwards)
        while range.location != NSNotFound {
            mutable.deleteCharacters(in: range)
            range = (mutable.string as NSString)
                .range(of: "\u{FFFC}", options: .backwards)
        }
        return mutable
    }
}
