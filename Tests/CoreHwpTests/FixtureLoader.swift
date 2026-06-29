import CoreHwp
import Foundation

struct FixtureExpectedError: Decodable {
    let code: String
    let description: String?
}

enum FixtureVersionParser {
    static func parse(_ version: String) throws -> HwpVersion {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            throw HwpError.invalidDataForString(data: Data(version.utf8), name: "hwpVersion")
        }

        let values = try parts.map { part in
            guard let value = Int(part), UInt8(exactly: value) != nil else {
                throw HwpError.invalidDataForString(data: Data(version.utf8), name: "hwpVersion")
            }
            return value
        }
        return HwpVersion(values[0], values[1], values[2], values[3])
    }

    static func isValid(_ version: String) -> Bool {
        (try? parse(version)) != nil
    }
}

struct LoadedFixture {
    let manifest: FixtureManifest
    let fixtureURL: URL
    let documentURL: URL
    let readmeURL: URL
}

enum FixtureLoader {
    static var root: URL {
        testsRoot(from: #file).appendingPathComponent("Fixtures")
    }

    static func loadAll() throws -> [LoadedFixture] {
        let fixtureIDs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        .map(\.lastPathComponent)
        .sorted()

        return try fixtureIDs.map(load(id:))
    }

    static func load(id: String) throws -> LoadedFixture {
        let fixtureURL = root.appendingPathComponent(id)
        let manifestURL = fixtureURL.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(FixtureManifest.self, from: data)
        let documentURL = fixtureURL.appendingPathComponent("document.hwp")
        let readmeURL = fixtureURL.appendingPathComponent("README.md")
        return LoadedFixture(
            manifest: manifest,
            fixtureURL: fixtureURL,
            documentURL: documentURL,
            readmeURL: readmeURL
        )
    }
}
