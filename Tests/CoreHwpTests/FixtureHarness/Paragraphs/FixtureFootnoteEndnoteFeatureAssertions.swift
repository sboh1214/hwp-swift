func sectionHasFootnoteEndnoteSamples(_ section: FixtureSectionExpectations) -> Bool {
    let requiredSamples: [Any?] = [
        section.footNoteShapePropertyRawValue,
        section.footNoteShapeRawPayloadLength,
        section.footNoteShapeRawPayloadPrefixBytes,
        section.footNoteShapeRawPayloadSuffixBytes,
        section.footNoteShapeRawTrailingLength,
        section.footNoteShapeRawTrailingPrefixBytes,
        section.footNoteShapeRawTrailingSuffixBytes,
        section.footNoteShapeSymbolRawValues,
        section.footNoteShapeSymbolRawPayloadLengths,
        section.footNoteShapeSymbolRawPayloadPrefixBytes,
        section.footNoteShapeSymbolRawPayloadSuffixBytes,
        section.endNoteShapePropertyRawValue,
        section.endNoteShapeRawPayloadLength,
        section.endNoteShapeRawPayloadPrefixBytes,
        section.endNoteShapeRawPayloadSuffixBytes,
        section.endNoteShapeRawTrailingLength,
        section.endNoteShapeRawTrailingPrefixBytes,
        section.endNoteShapeRawTrailingSuffixBytes,
        section.endNoteShapeSymbolRawValues,
        section.endNoteShapeSymbolRawPayloadLengths,
        section.endNoteShapeSymbolRawPayloadPrefixBytes,
        section.endNoteShapeSymbolRawPayloadSuffixBytes,
    ]

    return requiredSamples.allSatisfy { $0 != nil }
}
