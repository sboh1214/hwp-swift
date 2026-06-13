extension StringProtocol {
    var asciiValues: [UInt8] {
        compactMap(\.asciiValue)
    }
}
