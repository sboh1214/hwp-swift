import CoreHwp
import Foundation

/// HWPX fixture 매니페스트 — 바이너리 `FixtureManifest`와 별개다 (그쪽은
/// FileHeader raw byte 등 바이너리 전용 필수 필드를 요구한다).
struct HwpxFixtureManifest: Decodable {
    let id: String
    let generationTool: String
    let source: String
    /// version.xml에서 파싱될 버전 (M.n.P.r).
    let owpmlVersion: String
    /// 등가 비교 축이 되는 원본 HWP fixture id (`Fixtures/<id>`).
    let sourceHwpFixture: String?
    let features: [String]
    let expectations: HwpxFixtureExpectations
    let expectedError: FixtureExpectedError?

    private enum CodingKeys: String, CodingKey {
        case id, generationTool, source, owpmlVersion, sourceHwpFixture,
             features, expectations, expectedError
    }
}

/// 파싱 결과 기대값 — 전부 optional이고, 적힌 값만 단언한다.
struct HwpxFixtureExpectations: Decodable {
    let sectionCount: Int?
    let sectionParagraphCounts: [Int]?
    let visibleTextContains: [String]?
    let charShapeCount: Int?
    let paraShapeCount: Int?
    let styleCount: Int?
    let borderFillCount: Int?
    let tabDefCount: Int?
    let binDataCount: Int?
    let faceNamesKorean: [String]?
    let pageDef: HwpxPageDefExpectation?
    /// 문서 순서 표별 셀 수.
    let tableCellCounts: [Int]?
    /// 그림 개체가 참조하는 BinItem id (문서 순서).
    let imageBinItemIds: [Int]?
    /// 뷰어 렌더 쪽수 핀 — 출처는 `pageCountSource`. 소비자는
    /// `Tests/HwpKitTests/HwpxFixtureRenderTests`다 (이 타깃은 조판하지 않는다).
    let pageCount: Int?
    let pageCountSource: String?
}

struct HwpxPageDefExpectation: Decodable {
    let width: Int
    let height: Int
    let marginLeft: Int
    let marginRight: Int
    let marginTop: Int
    let marginBottom: Int
}

struct LoadedHwpxFixture {
    let manifest: HwpxFixtureManifest
    let fixtureURL: URL
    let documentURL: URL
    let readmeURL: URL
}

enum HwpxFixtureLoader {
    static var root: URL {
        testsRoot(from: #file).appendingPathComponent("HwpxFixtures")
    }

    static func loadAll() throws -> [LoadedHwpxFixture] {
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

    static func load(id: String) throws -> LoadedHwpxFixture {
        let fixtureURL = root.appendingPathComponent(id)
        let manifestURL = fixtureURL.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(HwpxFixtureManifest.self, from: data)
        return LoadedHwpxFixture(
            manifest: manifest,
            fixtureURL: fixtureURL,
            documentURL: fixtureURL.appendingPathComponent("document.hwpx"),
            readmeURL: fixtureURL.appendingPathComponent("README.md")
        )
    }
}

/// HWPX fixture를 public 자동 감지 진입점으로 연다 — Sample 앱과 같은 경로다.
func openHwpx(_ location: String, _ name: String) throws -> HwpFile {
    try HwpFile(fromPath: hwpxURL(location, name).path)
}

func hwpxURL(_ location: String, _ name: String) -> URL {
    testsRoot(from: location)
        .appendingPathComponent("HwpxFixtures")
        .appendingPathComponent(name)
        .appendingPathComponent("document.hwpx")
}
