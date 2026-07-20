import Foundation

/// HWP face name → ordered fallback candidate family names.
///
/// 조회는 원문 이름 우선, 없으면 정규화한 이름 (`-`/`#` 접두 제거 + 공백 제거)으로
/// 재시도한다 — 실제 저장본의 "-윤고딕120", "#태명조", "신명 태명조" 같은 변형을
/// 흡수한다 (`candidates(forFaceName:)`).
public struct HwpFontMap: Sendable, Hashable {
    public let entries: [String: [String]]
    /// 정규화한 키 → 후보 (원문 키 조회 실패 시 폴백)
    private let normalizedEntries: [String: [String]]

    public init(entries: [String: [String]]) {
        self.entries = entries
        var normalized: [String: [String]] = [:]
        for (key, value) in entries {
            normalized[Self.normalize(key)] = value
        }
        normalizedEntries = normalized
    }

    /// faceName의 폴백 후보 (원문 → 정규화 순서로 조회, 없으면 빈 배열)
    public func candidates(forFaceName faceName: String) -> [String] {
        if let exact = entries[faceName] {
            return exact
        }
        return normalizedEntries[Self.normalize(faceName)] ?? []
    }

    /// `-`/`#` 접두와 공백을 제거한 조회용 이름
    public static func normalize(_ faceName: String) -> String {
        var name = faceName.trimmingCharacters(in: .whitespaces)
        while let first = name.first, first == "-" || first == "#" {
            name.removeFirst()
        }
        return name.replacingOccurrences(of: " ", with: "")
    }

    /// 명조 (바탕) 계열 폴백
    private static let serif = ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
    /// 고딕 (돋움) 계열 폴백 — family 표시명이라야 CT 매칭이 된다
    private static let gothic = ["Apple SD Gothic Neo", "Nanum Gothic"]
    /// 한컴바탕 계열 (함초롬바탕과 동계)
    private static let hancomBatang = ["HCR Batang", "Nanum Myeongjo", "AppleMyungjo"]

    public static let `default` = HwpFontMap(entries: [
        "함초롬바탕": hancomBatang,
        "함초롬돋움": ["HCR Dotum", "Nanum Gothic", "Apple SD Gothic Neo"],
        "한컴바탕": hancomBatang,
        "한컴바탕확장": hancomBatang,
        "HY신명조": ["HYSMyeongJo-Medium", "AppleMyungjo"],
        "HY견고딕": ["HYGothic", "Apple SD Gothic Neo"],
        "바탕": ["Batang", "AppleMyungjo"],
        "Batang": ["Batang", "AppleMyungjo"],
        "바탕체": ["BatangChe", "Batang", "AppleMyungjo"],
        "굴림": ["Gulim", "Apple SD Gothic Neo"],
        "Gulim": ["Gulim", "Apple SD Gothic Neo"],
        "돋움": ["Dotum", "Apple SD Gothic Neo"],
        "Dotum": ["Dotum", "Apple SD Gothic Neo"],
        "궁서": ["Gungsuh", "GungSeo", "AppleMyungjo"],
        "Gungsuh": ["Gungsuh", "GungSeo", "AppleMyungjo"],
        "명조": serif,
        "휴먼명조": serif,
        "한양신명조": serif,
        "한양신명조V": serif,
        "한양중고딕": gothic,
        "한양해서": ["GungSeo", "AppleMyungjo"],
        "신명태명조": serif,
        "신명견명조": serif,
        "신명조간자": serif,
        "신명조약자": serif,
        "신명중고딕": gothic,
        "신명디나루": gothic,
        "태명조": serif,
        "중고딕": gothic,
        "견명조": serif,
        "윤고딕": gothic,
        "윤고딕120": gothic,
        "HCI Poppy": ["Apple SD Gothic Neo"],
        "Times New Roman": ["Times New Roman", "Times"],
        // 한컴 수식 전용 폰트 — 세리프 수학체 근사
        "HancomEQN": ["Times New Roman", "Times", "AppleMyungjo"],
        "Arial": ["Arial", "Helvetica"],
        "Courier New": ["Courier New", "Menlo"],
        "Symbol": ["Symbol", "AppleSymbols"],
        "MS 명조": ["MS Mincho", "AppleMyungjo"],
        "MS 고딕": ["MS Gothic", "Apple SD Gothic Neo"],
        "Nanum Gothic": ["Nanum Gothic", "Apple SD Gothic Neo"],
    ])
}
