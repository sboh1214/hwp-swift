@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// HwpxFixtures 루트의 구조 가드와 매니페스트 전수 검증.
final class HwpxFixtureManifestTests: XCTestCase {
    /// 각 fixture 디렉터리는 정확히 3개 산출물로 구성된다 — 기존 `Fixtures/`
    /// canonical layout 규칙의 HWPX 대응.
    func testHwpxFixtureDirectoriesUseCanonicalArtifactLayout() throws {
        for fixture in try HwpxFixtureLoader.loadAll() {
            let entries = try FileManager.default.contentsOfDirectory(
                at: fixture.fixtureURL, includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }

            expect(Set(entries)).to(
                equal(Set(["document.hwpx", "manifest.json", "README.md"])),
                description: "\(fixture.manifest.id) must contain exactly the canonical artifacts"
            )
        }
    }

    /// 저장소 전체를 훑어 `.hwpx`가 HwpxFixtures 루트 밖에 흩어지지 않았는지
    /// 확인한다 — `.hwp` 스윕 규칙의 HWPX 대응.
    func testAllRepositoryHwpxFilesAreUnderHwpxFixtureRoot() {
        let projectRoot = testsRoot(from: #file)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // 저장소 루트
        let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var strayFiles: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "hwpx" else {
                continue
            }
            if url.path.contains(".build/") {
                continue
            }
            let isCanonical = url.lastPathComponent == "document.hwpx"
                && url.deletingLastPathComponent().deletingLastPathComponent()
                == HwpxFixtureLoader.root
            if !isCanonical {
                strayFiles.append(url.path)
            }
        }
        expect(strayFiles).to(
            beEmpty(),
            description: "모든 .hwpx는 HwpxFixtures/<id>/document.hwpx여야 한다"
        )
    }

    func testHwpxFixtureDocumentsStartWithZipMagicAndHwpxMimetype() throws {
        for fixture in try HwpxFixtureLoader.loadAll() {
            let data = try Data(contentsOf: fixture.documentURL)
            expect(data.prefix(4)).to(
                equal(Data([0x50, 0x4B, 0x03, 0x04])),
                description: "\(fixture.manifest.id) must start with ZIP local header magic"
            )
            // 첫 로컬 헤더의 이름이 mimetype이고 stored여야 한다 (OCF 관례 —
            // 한글.app 저장본 실측).
            expect(try data.readLittleEndianUInt16(at: 8)) == 0
            let nameLength = Int(try data.readLittleEndianUInt16(at: 26))
            let name = String(bytes: data[30 ..< 30 + nameLength], encoding: .utf8)
            expect(name) == "mimetype"
        }
    }

    func testHwpxFixtureManifestsMatchParsedDocuments() throws {
        let fixtures = try HwpxFixtureLoader.loadAll()
        expect(fixtures.count) >= 10

        for fixture in fixtures {
            let manifest = fixture.manifest
            expect(manifest.id) == fixture.fixtureURL.lastPathComponent
            expect(FixtureVersionParser.isValid(manifest.owpmlVersion)) == true

            if let expectedError = manifest.expectedError {
                expect {
                    _ = try HwpFile(fromPath: fixture.documentURL.path)
                }.to(throwError { error in
                    expect(String(describing: type(of: error))).to(contain("HwpError"))
                    _ = expectedError
                })
                continue
            }

            let hwp = try HwpFile(fromPath: fixture.documentURL.path)
            expect(hwp.fileHeader.version) == (try FixtureVersionParser.parse(
                manifest.owpmlVersion
            ))
            HwpxFixtureAssertions.assert(hwp, manifest: manifest)
        }
    }

    func testHwpxFixtureReadmesDocumentRegeneration() throws {
        for fixture in try HwpxFixtureLoader.loadAll() {
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)
            expect(readme).to(contain("# \(fixture.manifest.id)"))
            expect(readme).to(contain("document.hwpx"))
            expect(readme).to(contain("재생성"))
            expect(readme).to(contain("manifest.json"))
        }
    }

    func testHwpxFixturesLinkToExistingHwpSources() throws {
        for fixture in try HwpxFixtureLoader.loadAll() {
            guard let sourceId = fixture.manifest.sourceHwpFixture else {
                continue
            }
            let source = try FixtureLoader.load(id: sourceId)
            expect(FileManager.default.fileExists(atPath: source.documentURL.path)).to(
                beTrue(),
                description: "\(fixture.manifest.id)의 sourceHwpFixture \(sourceId)가 실존해야 한다"
            )
        }
    }

    func testHwpxFixtureFeatureTagsAreCanonical() throws {
        for fixture in try HwpxFixtureLoader.loadAll() {
            let tags = fixture.manifest.features
            expect(Set(tags).count) == tags.count
            for tag in tags {
                expect(knownFixtureFeatureTags).to(
                    contain(tag),
                    description: "\(fixture.manifest.id)의 미등록 태그: \(tag)"
                )
            }
            expect(tags).to(contain("hwpx"))
        }
    }
}

/// 매니페스트 기대값 → 파싱 결과 단언. 적힌 값만 검사한다.
enum HwpxFixtureAssertions {
    // swiftlint:disable:next cyclomatic_complexity
    static func assert(_ hwp: HwpFile, manifest: HwpxFixtureManifest) {
        let id = manifest.id
        let expectations = manifest.expectations
        let idMappings = hwp.docInfo.idMappings

        if let count = expectations.sectionCount {
            expect(hwp.sectionArray.count).to(equal(count), description: "\(id) sectionCount")
        }
        if let counts = expectations.sectionParagraphCounts {
            expect(hwp.sectionArray.map(\.paragraph.count)).to(
                equal(counts), description: "\(id) sectionParagraphCounts"
            )
        }
        if let snippets = expectations.visibleTextContains {
            let text = FixtureDerivedValues.visibleText(from: hwp)
            for snippet in snippets {
                expect(text).to(contain(snippet), description: "\(id) visibleTextContains")
            }
        }
        if let count = expectations.charShapeCount {
            expect(idMappings.charShapeArray.count).to(
                equal(count), description: "\(id) charShapeCount"
            )
        }
        if let count = expectations.paraShapeCount {
            expect(idMappings.paraShapeArray.count).to(
                equal(count), description: "\(id) paraShapeCount"
            )
        }
        if let count = expectations.styleCount {
            expect(idMappings.styleArray.count).to(equal(count), description: "\(id) styleCount")
        }
        if let count = expectations.borderFillCount {
            expect(idMappings.borderFillArray.count).to(
                equal(count), description: "\(id) borderFillCount"
            )
        }
        if let count = expectations.tabDefCount {
            expect(idMappings.tabDefArray.count).to(
                equal(count), description: "\(id) tabDefCount"
            )
        }
        if let count = expectations.binDataCount {
            expect(idMappings.binDataArray.count).to(
                equal(count), description: "\(id) binDataCount"
            )
        }
        if let names = expectations.faceNamesKorean {
            expect(idMappings.faceNameKoreanArray.compactMap(\.faceName)).to(
                equal(names), description: "\(id) faceNamesKorean"
            )
        }
        if let pageDef = expectations.pageDef {
            assertPageDef(hwp, pageDef, id: id)
        }
        if let cellCounts = expectations.tableCellCounts {
            expect(FixtureDerivedValues.tables(from: hwp).map(\.cellArray.count)).to(
                equal(cellCounts), description: "\(id) tableCellCounts"
            )
        }
        if let binItemIds = expectations.imageBinItemIds {
            expect(Self.imageBinItemIds(from: hwp)).to(
                equal(binItemIds), description: "\(id) imageBinItemIds"
            )
        }
    }

    static func assertPageDef(
        _ hwp: HwpFile,
        _ expectation: HwpxPageDefExpectation,
        id: String
    ) {
        guard case let .section(sectionDef)? =
            hwp.sectionArray.first?.paragraph.first?.ctrlHeaderArray?.first
        else {
            return fail("\(id): first control must be .section")
        }
        let pageDef = sectionDef.pageDef
        expect(Int(pageDef.width)).to(equal(expectation.width), description: "\(id) width")
        expect(Int(pageDef.height)).to(equal(expectation.height), description: "\(id) height")
        expect(Int(pageDef.marginLeft)) == expectation.marginLeft
        expect(Int(pageDef.marginRight)) == expectation.marginRight
        expect(Int(pageDef.marginTop)) == expectation.marginTop
        expect(Int(pageDef.marginBottom)) == expectation.marginBottom
    }

    static func imageBinItemIds(from hwp: HwpFile) -> [Int] {
        var binItemIds: [Int] = []
        func walk(_ paragraphs: [HwpParagraph]) {
            for paragraph in paragraphs {
                for ctrl in paragraph.ctrlHeaderArray ?? [] {
                    var components: [HwpShapeComponent] = []
                    switch ctrl {
                    case let .table(table):
                        for cell in table.cellArray {
                            walk(cell.paragraphArray)
                        }
                    case let .genShapeObject(object):
                        components = object.shapeComponentArray
                    case let .picture(control), let .shape(control), let .line(control),
                         let .rectangle(control), let .ellipse(control), let .arc(control),
                         let .polygon(control), let .curve(control), let .equation(control),
                         let .equationLegacy(control), let .ole(control),
                         let .container(control):
                        components = control.shapeComponentArray
                    default:
                        break
                    }
                    for component in components {
                        for picture in component.pictureArray {
                            binItemIds.append(Int(picture.pictureProperty?.binItemId ?? 0))
                        }
                    }
                }
            }
        }
        for section in hwp.sectionArray {
            walk(section.paragraph)
        }
        return binItemIds
    }
}
