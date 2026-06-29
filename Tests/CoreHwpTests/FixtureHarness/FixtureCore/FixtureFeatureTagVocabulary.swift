let knownFixtureFeatureTags: Set<String> = [
    "auto-number",
    "bin-data",
    "blank",
    "bookmark",
    "bullets-numbering",
    "char-shape",
    "char-shape-property",
    "chart",
    "columns",
    "compatible-track-change-records",
    "deployment-document",
    "derived-drm",
    "derived-missing-preview-image",
    "derived-missing-preview-text",
    "derived-missing-summary",
    "doc-data",
    "doc-info",
    "doc-properties",
    "document-history",
    "drm",
    "embedded-image-reference",
    "encrypted",
    "equation",
    "file-header",
    "footnote-endnote",
    "forbidden-char",
    "hancom-mac2026",
    "header-footer",
    "hidden-comment",
    "hyperlink",
    "ignored-root-entries",
    "image",
    "indexmark",
    "kogl",
    "large-document",
    "layout-compatibility",
    "legacy-common-control-property",
    "license",
    "memo",
    "memo-shape",
    "missing-bin-data",
    "multi-paragraph",
    "multi-section",
    "new-number",
    "other-controls",
    "page-hide",
    "page-number",
    "paragraph-text",
    "plain-text-minimal",
    "preview-image",
    "preview-text",
    "section",
    "shape-object",
    "styles",
    "table",
    "text-box",
    "track-change-author",
    "track-change-content",
    "track-change-records",
    "track-changes",
    "track-changes-flag",
    "unsupported",
    "version",
]

let requiredReadableGoalFeatureTags: Set<String> = [
    "bin-data",
    "blank",
    "bookmark",
    "bullets-numbering",
    "chart",
    "columns",
    "compatible-track-change-records",
    "doc-data",
    "doc-info",
    "doc-properties",
    "embedded-image-reference",
    "equation",
    "forbidden-char",
    "footnote-endnote",
    "header-footer",
    "hyperlink",
    "image",
    "ignored-root-entries",
    "layout-compatibility",
    "memo",
    "memo-shape",
    "missing-bin-data",
    "multi-paragraph",
    "multi-section",
    "auto-number",
    "hidden-comment",
    "indexmark",
    "new-number",
    "page-hide",
    "page-number",
    "paragraph-text",
    "plain-text-minimal",
    "preview-image",
    "preview-text",
    "shape-object",
    "styles",
    "table",
    "text-box",
    "track-change-author",
    "track-change-content",
    "track-change-records",
    "track-changes",
    "track-changes-flag",
]

let readableReaderGoalFeatureTags = requiredReadableGoalFeatureTags.union([
    "derived-missing-preview-image",
    "derived-missing-preview-text",
    "derived-missing-summary",
])

func isCanonicalFeatureTag(_ value: String) -> Bool {
    let scalars = Array(value.unicodeScalars)
    guard !scalars.isEmpty else {
        return false
    }

    var previousWasHyphen = false
    for scalar in scalars {
        let isLowercaseASCII = scalar.value >= 97 && scalar.value <= 122
        let isDigit = scalar.value >= 48 && scalar.value <= 57
        if scalar.value == 45 {
            guard !previousWasHyphen else {
                return false
            }
            previousWasHyphen = true
        } else if isLowercaseASCII || isDigit {
            previousWasHyphen = false
        } else {
            return false
        }
    }
    return !previousWasHyphen
}
