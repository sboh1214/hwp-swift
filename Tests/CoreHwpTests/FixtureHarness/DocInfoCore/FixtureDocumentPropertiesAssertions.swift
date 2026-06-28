import CoreHwp
import Nimble

extension FixtureAssertions {
    static func assertDocumentProperties(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        guard let expected = expectations.documentProperties else {
            return
        }

        let actual = hwp.docInfo.documentProperties
        assertDocumentPropertiesPayload(expected, actual)
        if let sectionSize = expected.sectionSize {
            expect(actual.sectionSize) == sectionSize
        }
        if let startingIndex = expected.startingIndex {
            assertStartingIndex(startingIndex, actual.startingIndex)
        }
        if let caratLocation = expected.caratLocation {
            assertCaratLocation(caratLocation, actual.caratLocation)
        }
    }
}

private func assertDocumentPropertiesPayload(
    _ expected: FixtureDocumentPropertiesExpectations,
    _ actual: HwpDocumentProperties
) {
    FixtureAssertions.assertPayloadSample(
        actual.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
}

private func assertStartingIndex(
    _ expected: FixtureStartingIndexExpectations,
    _ actual: HwpStartingIndex
) {
    FixtureAssertions.assertPayloadSample(
        actual.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
    if let page = expected.page {
        expect(actual.page) == page
    }
    if let footnote = expected.footnote {
        expect(actual.footnote) == footnote
    }
    if let endnote = expected.endnote {
        expect(actual.endnote) == endnote
    }
    if let picture = expected.picture {
        expect(actual.picture) == picture
    }
    if let table = expected.table {
        expect(actual.table) == table
    }
    if let equation = expected.equation {
        expect(actual.equation) == equation
    }
}

private func assertCaratLocation(
    _ expected: FixtureCaratLocationExpectations,
    _ actual: HwpCaratLocation
) {
    FixtureAssertions.assertPayloadSample(
        actual.rawPayload,
        length: expected.rawPayloadLength,
        prefix: expected.rawPayloadPrefixBytes,
        suffix: expected.rawPayloadSuffixBytes
    )
    if let listId = expected.listId {
        expect(actual.listId) == listId
    }
    if let paragraphId = expected.paragraphId {
        expect(actual.paragraphId) == paragraphId
    }
    if let charIndex = expected.charIndex {
        expect(actual.charIndex) == charIndex
    }
}
