/**
 ’문서 정보’의 데이터 레코드
 */
enum HwpDocInfoTag: UInt32, CaseIterable {
    case documentProperties = 16
    case idMappings = 17
    case binData = 18
    case faceName = 19
    case borderFill = 20
    case charShape = 21
    case tabDef = 22
    case numbering = 23
    case bullet = 24
    case paraShape = 25
    case style = 26
    case docData = 27
    case distributeDocData = 28
    case reserved = 29
    case compatibleDocument = 30
    case layoutCompatibility = 31
    case trackChange = 32
    case memoShape = 92
    case forbiddenChar = 94
    case trackChangeContent = 96
    case trackChangeAuthor = 97
}
