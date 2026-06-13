import Foundation

public struct HwpChar: HwpPrimitive {
    public let type: HwpCharType
    public let value: WCHAR
}

public enum HwpCharType: String, Codable {
    case char
    case inline
    case extended
}
