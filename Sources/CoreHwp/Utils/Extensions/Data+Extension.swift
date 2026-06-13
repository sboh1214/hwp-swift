import Foundation

/// Data to [bytes]
extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }

    var bits: [Bool] {
        reduce([Bool]()) { $0 + $1.bits }
    }

    var stringASCII: String? {
        String(data: self, encoding: .ascii)
    }
}
