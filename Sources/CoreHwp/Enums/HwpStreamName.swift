public enum HwpStreamName: String, HwpPrimitive, CaseIterable {
    case fileHeader = "FileHeader"
    case docInfo = "DocInfo"
    case bodyText = "BodyText"
    case summary = "\u{5}HwpSummaryInformation"
    case previewText = "PrvText"
    case previewImage = "PrvImage"
    case binData = "BinData"
}

extension HwpStreamName {
    static let requiredTopLevelEntries: Set<HwpStreamName> = [
        .fileHeader,
        .docInfo,
        .bodyText,
    ]

    static var optionalTopLevelEntries: Set<HwpStreamName> {
        Set(allCases).subtracting(requiredTopLevelEntries)
    }

    var isRequiredTopLevelEntry: Bool {
        Self.requiredTopLevelEntries.contains(self)
    }
}
