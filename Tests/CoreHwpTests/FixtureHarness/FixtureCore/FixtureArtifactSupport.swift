import Foundation
import Nimble

func fixtureArtifactURLs(_ fixture: LoadedFixture) -> [URL] {
    [
        fixture.documentURL,
        fixture.readmeURL,
        fixture.fixtureURL.appendingPathComponent("manifest.json"),
    ]
}

func assertNonEmptyRegularFile(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    expect(values.isRegularFile) == true
    expect(values.fileSize ?? 0).to(beGreaterThan(0))
}

func assertOleCompoundDocumentMagic(_ url: URL) throws {
    let expectedMagic = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    let data = try Data(contentsOf: url)

    expect(data.count).to(beGreaterThanOrEqualTo(expectedMagic.count))
    expect(data.prefix(expectedMagic.count)) == expectedMagic
}
