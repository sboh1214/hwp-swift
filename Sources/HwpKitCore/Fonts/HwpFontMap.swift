import Foundation

/// HWP face name → ordered fallback candidate family names.
public struct HwpFontMap: Sendable, Hashable {
    public let entries: [String: [String]]

    public init(entries: [String: [String]]) {
        self.entries = entries
    }

    public static let `default` = HwpFontMap(entries: [
        "함초롬바탕": ["HCR Batang", "Nanum Myeongjo", "AppleMyungjo"],
        "함초롬돋움": ["HCR Dotum", "Nanum Gothic", "AppleSDGothicNeo"],
        "HY신명조": ["HYSMyeongJo-Medium", "AppleMyungjo"],
        "HY견고딕": ["HYGothic", "AppleSDGothicNeo"],
        "바탕": ["Batang", "AppleMyungjo"],
        "Batang": ["Batang", "AppleMyungjo"],
        "굴림": ["Gulim", "AppleSDGothicNeo"],
        "Gulim": ["Gulim", "AppleSDGothicNeo"],
        "돋움": ["Dotum", "AppleSDGothicNeo"],
        "Dotum": ["Dotum", "AppleSDGothicNeo"],
        "궁서": ["Gungsuh", "AppleMyungjo"],
        "Gungsuh": ["Gungsuh", "AppleMyungjo"],
        "Times New Roman": ["Times New Roman", "Times"],
        "Arial": ["Arial", "Helvetica"],
        "Courier New": ["Courier New", "Menlo"],
        "Symbol": ["Symbol", "AppleSymbols"],
        "MS 명조": ["MS Mincho", "AppleMyungjo"],
        "MS 고딕": ["MS Gothic", "AppleSDGothicNeo"],
        "Nanum Gothic": ["Nanum Gothic", "AppleSDGothicNeo"],
    ])
}
