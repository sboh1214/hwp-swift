import Foundation

extension Array {
    /**
     * ## Examples:
     * var arr = [0,1,2,3]
     * arr.remove((0..<2)) // 0,1
     * arr // 2,3
     */
    mutating func pop(_ count: some BinaryInteger) -> Array {
        let values = Array(self[0 ..< Int(count)])
        removeSubrange(0 ..< Int(count))
        return values
    }
}

public extension [WCHAR] {
    var string: String {
        reduce("") { result, current in result + String(Character(UnicodeScalar(current)!)) }
    }

    init(_ string: String) {
        self = string.utf16.map { $0 }
    }
}

/// [bytes] to Data
extension [UInt8] {
    var data: Data {
        Data(self)
    }
}
