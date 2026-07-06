import Foundation
import HwpKitCore

struct FixtureVisibleText: Decodable {
    let visibleTextContains: [String]?

    enum CodingKeys: String, CodingKey {
        case visibleTextContains
    }
}

struct FixtureExpectations: Decodable {
    let visibleTextContains: [String]?
    /// 렌더 페이지 수 회귀 가드 (출처는 manifest의 pageCountSource 참조)
    let pageCount: Int?
}

struct FixtureManifestLite: Decodable {
    let id: String
    let expectations: FixtureExpectations
}

struct FixtureCase {
    let id: String
    let documentURL: URL
    let expectedVisibleText: [String]
    let expectedPageCount: Int?
}

enum FixtureRoot {
    static func url(from location: String) -> URL {
        var url = URL(fileURLWithPath: location).deletingLastPathComponent()
        while url.lastPathComponent != "Tests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("CoreHwpTests")
            .appendingPathComponent("Fixtures")
    }

    static func loadAllFixtures(from location: String) throws -> [FixtureCase] {
        let root = url(from: location)
        let dirs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try dirs.compactMap { dir -> FixtureCase? in
            let id = dir.lastPathComponent
            let manifestURL = dir.appendingPathComponent("manifest.json")
            let documentURL = dir.appendingPathComponent("document.hwp")
            guard FileManager.default.fileExists(atPath: manifestURL.path),
                  FileManager.default.fileExists(atPath: documentURL.path)
            else { return nil }

            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(FixtureManifestLite.self, from: manifestData)
            return FixtureCase(
                id: id,
                documentURL: documentURL,
                expectedVisibleText: manifest.expectations.visibleTextContains ?? [],
                expectedPageCount: manifest.expectations.pageCount
            )
        }
    }
}

enum FixtureText {
    static func extract(from document: HwpDocument) -> String {
        var text = ""
        for page in document.pages {
            for block in page.blocks {
                if let string = block.attributedString?.string {
                    if !text.isEmpty { text += "\n" }
                    text += stripInlineObjectMarkers(string)
                }
            }
        }
        return text
    }

    static func extractFromPaintList(_ document: HwpDocument) -> String {
        var text = ""
        for page in document.pages {
            for command in page.paintList.commands {
                if case let .drawText(attributedString, _, _) = command {
                    if !text.isEmpty { text += "\n" }
                    text += stripInlineObjectMarkers(attributedString.string)
                }
            }
        }
        return text
    }

    private static func stripInlineObjectMarkers(_ string: String) -> String {
        string.filter { $0 != "\u{FFFC}" }
    }
}
