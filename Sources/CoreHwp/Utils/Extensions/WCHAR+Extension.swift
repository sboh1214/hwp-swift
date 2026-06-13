extension WCHAR {
    var character: Character {
        Character(UnicodeScalar(self)!)
    }
}
