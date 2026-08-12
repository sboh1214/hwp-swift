import Foundation

/// 검색 매칭 옵션.
///
/// `OptionSet`이라 `[.caseInsensitive, .wholeWord]` 한 줄로 조합되고, 나중에
/// 옵션이 늘어도 기존 호출부가 그대로 컴파일된다.
public struct HwpSearchOptions: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 대소문자를 구분하지 않는다.
    public static let caseInsensitive = HwpSearchOptions(rawValue: 1 << 0)
    /// 발음 구별 부호를 구분하지 않는다 (é ≡ e).
    public static let diacriticInsensitive = HwpSearchOptions(rawValue: 1 << 1)
    /// 매치의 앞뒤가 단어 문자가 아니어야 한다.
    ///
    /// 경계 판정은 더블클릭 단어 선택이 쓰는 것과 **같은 규칙**
    /// (`HwpSelectionGeometry.isWordCharacter`)이다 — 규칙이 갈라지면 사용자가
    /// 더블클릭으로 고른 단어를 그대로 검색했을 때 결과가 어긋난다.
    public static let wholeWord = HwpSearchOptions(rawValue: 1 << 2)

    /// 대소문자·발음 구별 부호 무시. 한글은 이 옵션과 무관하게 조합형/완성형이
    /// 동치로 비교된다 (`.literal`을 쓰지 않는다 — `HwpTextSearcher` 참조).
    public static let `default`: HwpSearchOptions = [.caseInsensitive, .diacriticInsensitive]
}

/// 검색 질의 — 문자열과 옵션.
public struct HwpSearchQuery: Sendable, Hashable {
    public var text: String
    public var options: HwpSearchOptions

    public init(text: String = "", options: HwpSearchOptions = .default) {
        self.text = text
        self.options = options
    }

    /// 트림 후 비어 있으면 스캔하지 않는다 — 빈 질의는 전 문서가 매치가 된다.
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let empty = HwpSearchQuery()

    /// Foundation 비교 옵션으로 변환.
    ///
    /// **`.literal`을 절대 넣지 않는다.** 넣으면 한글 조합형(NFD)과
    /// 완성형(NFC)이 다른 문자열로 취급돼, 같은 글자를 눈으로 보면서 검색이
    /// 안 되는 상황이 생긴다. 대가는 반환 range의 길이가 질의의 UTF-16
    /// 길이와 다를 수 있다는 것 — 하이라이트 오프셋은 반드시 **반환된
    /// range**를 그대로 써야 한다.
    var compareOptions: NSString.CompareOptions {
        var options: NSString.CompareOptions = []
        if self.options.contains(.caseInsensitive) {
            options.insert(.caseInsensitive)
        }
        if self.options.contains(.diacriticInsensitive) {
            options.insert(.diacriticInsensitive)
        }
        return options
    }
}
