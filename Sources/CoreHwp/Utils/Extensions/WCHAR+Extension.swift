extension WCHAR {
    var character: Character {
        get throws {
            guard let scalar = UnicodeScalar(self) else {
                throw HwpError.invalidUnicodeScalar(value: self)
            }
            return Character(scalar)
        }
    }
}
