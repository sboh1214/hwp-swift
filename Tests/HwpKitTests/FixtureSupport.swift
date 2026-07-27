import Foundation
import HwpKitCore
import XCTest

/// 기기/환경(설치 폰트·OS 버전·래스터라이저)에 따라 결과가 달라지는
/// 스냅샷·fidelity 테스트의 opt-in 게이트. 기본 `swift test`와 CI에서는
/// skip되고, `HWP_SNAPSHOT_TESTS=1` 또는 각 테스트의 `RECORD_*` 변수를
/// 줄 때만 실행된다.
enum EnvironmentSensitiveTests {
    /// nil·빈 값·"0"·"false"는 off — 그 외 값("1", "true", 픽스처 id 목록 등)은 on.
    static func isEnabled(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[name] else { return false }
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return !normalized.isEmpty && normalized != "0" && normalized != "false"
    }

    /// - Parameter requiresHancomFonts: 기준선이 한컴오피스 번들 폰트를 켠 상태에서
    ///   실측된 스위트인지. 한컴 폰트는 기본 off라 (`HwpInstalledHancomFonts.isEnabled`)
    ///   끈 채로 돌리면 임계를 벗어나는데, 그 실패가 렌더 회귀로 오독된다 —
    ///   임계 실패 대신 실행법을 알려주고 skip한다.
    static func skipUnlessOptedIn(
        recordVariables: [String] = [],
        requiresHancomFonts: Bool = false
    ) throws {
        let optedIn = isEnabled("HWP_SNAPSHOT_TESTS")
            || recordVariables.contains(where: isEnabled)
        try XCTSkipIf(
            !optedIn,
            "기기/환경 의존 테스트 — HWP_SNAPSHOT_TESTS=1로 opt-in 실행"
        )
        try XCTSkipIf(
            requiresHancomFonts && !HwpInstalledHancomFonts.isEnabled,
            "기준선이 한컴오피스 번들 폰트 기준 실측 — "
                + "HWP_SNAPSHOT_TESTS=1 \(HwpInstalledHancomFonts.enableEnvironmentKey)=1 로 실행"
        )
    }
}

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
                    if !text.isEmpty {
                        text += "\n"
                    }
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
                    if !text.isEmpty {
                        text += "\n"
                    }
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
