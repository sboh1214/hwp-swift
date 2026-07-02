import Foundation

/// The 7 script slots that `HwpCharShape.faceId[7]` indexes into, in order.
public enum HwpScript: String, Sendable, Hashable {
    case korean
    case english
    case chinese
    case japanese
    case etc
    case symbol
    case user
}

public extension HwpScript {
    var slotIndex: Int {
        switch self {
        case .korean: 0
        case .english: 1
        case .chinese: 2
        case .japanese: 3
        case .etc: 4
        case .symbol: 5
        case .user: 6
        }
    }
}
