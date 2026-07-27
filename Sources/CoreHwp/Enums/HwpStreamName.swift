public enum HwpStreamName: String, HwpPrimitive, CaseIterable {
    case fileHeader = "FileHeader"
    case docInfo = "DocInfo"
    case bodyText = "BodyText"
    case summary = "\u{5}HwpSummaryInformation"
    case previewText = "PrvText"
    case previewImage = "PrvImage"
    case binData = "BinData"
    /// 표시용 본문 (변경 추적 저장본 등) — 있으면 한글.app은 BodyText 대신 이걸 그린다
    case viewText = "ViewText"
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
