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

    /// 한컴 폰트 모드로 스위트를 가르지 않는다 — 모드마다 기준선을 따로 두거나
    /// (렌더 해시의 `-nohancom` 접미사) 양 모드에서 성립하는 임계를 쓰는 쪽이,
    /// 한쪽 모드에서 영영 실행되지 않는 스위트를 만드는 것보다 낫다.
    static func skipUnlessOptedIn(recordVariables: [String] = []) throws {
        let optedIn = isEnabled("HWP_SNAPSHOT_TESTS")
            || recordVariables.contains(where: isEnabled)
        try XCTSkipIf(
            !optedIn,
            "기기/환경 의존 테스트 — HWP_SNAPSHOT_TESTS=1로 opt-in 실행"
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
    /// `pageCount`의 출처 — 한글.app 실측인지 렌더 잠금인지. 핀이 있으면 비어
    /// 있으면 안 된다 (`HwpxFixtures/README.md`).
    let pageCountSource: String?
}

/// manifest 키의 **존재**만 기록한다 — 값의 형태(`expectedError`의 code·
/// description 등)는 CoreHwpTests 하니스 몫이고 여기서는 "파싱 불가 픽스처인가"만
/// 알면 된다.
struct FixtureKeyPresence: Decodable {
    init(from _: Decoder) throws {}
}

struct FixtureManifestLite: Decodable {
    let id: String
    /// HWPX 픽스처만 — 등가 비교 축이 되는 원본 HWP fixture id (`Fixtures/<id>`).
    let sourceHwpFixture: String?
    /// 암호·배포용·DRM처럼 열 수 없는 픽스처의 표식 — 쪽수 핀 대상이 아니다.
    let expectedError: FixtureKeyPresence?
    let expectations: FixtureExpectations
}

struct FixtureCase {
    let id: String
    let documentURL: URL
    let expectedVisibleText: [String]
    let expectedPageCount: Int?
    let expectedPageCountSource: String?
    /// manifest에 `expectedError`가 있으면 true — 렌더 핀을 요구하지 않는다.
    let hasExpectedError: Bool
    /// HWPX 픽스처의 원본 HWP fixture id. HWP 픽스처는 nil.
    let sourceHwpFixture: String?
}

enum FixtureRoot {
    /// `Tests/CoreHwpTests/<subdirectory>` — 기본은 HWP 픽스처 루트(`Fixtures`),
    /// HWPX 변환 쌍은 별도 루트 `HwpxFixtures`다 (`Tests/CoreHwpTests/AGENTS.md`).
    static func url(from location: String, subdirectory: String = "Fixtures") -> URL {
        var url = URL(fileURLWithPath: location).deletingLastPathComponent()
        while url.lastPathComponent != "Tests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("CoreHwpTests")
            .appendingPathComponent(subdirectory)
    }

    /// HWPX 픽스처(`HwpxFixtures/<id>/document.hwpx`). 로더는 포맷을 모른다 —
    /// `HwpDocumentLoader` → `HwpFile` 선두 바이트 자동 감지로 열리므로 Sample 앱과
    /// 같은 경로다.
    static func loadAllHwpxFixtures(from location: String) throws -> [FixtureCase] {
        try loadAllFixtures(
            from: location, subdirectory: "HwpxFixtures", documentName: "document.hwpx"
        )
    }

    static func loadAllFixtures(
        from location: String,
        subdirectory: String = "Fixtures",
        documentName: String = "document.hwp"
    ) throws -> [FixtureCase] {
        let root = url(from: location, subdirectory: subdirectory)
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
            let documentURL = dir.appendingPathComponent(documentName)
            guard FileManager.default.fileExists(atPath: manifestURL.path),
                  FileManager.default.fileExists(atPath: documentURL.path)
            else { return nil }

            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(FixtureManifestLite.self, from: manifestData)
            return FixtureCase(
                id: id,
                documentURL: documentURL,
                expectedVisibleText: manifest.expectations.visibleTextContains ?? [],
                expectedPageCount: manifest.expectations.pageCount,
                expectedPageCountSource: manifest.expectations.pageCountSource,
                hasExpectedError: manifest.expectedError != nil,
                sourceHwpFixture: manifest.sourceHwpFixture
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
