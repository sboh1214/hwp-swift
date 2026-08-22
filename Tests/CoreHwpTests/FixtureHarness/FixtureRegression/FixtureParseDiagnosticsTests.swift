@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

/// `HwpFile.parseDiagnostics()` (#66) — 실저장본 픽스처 전수 게이트.
///
/// 전 픽스처 무크래시·결정성·`.default`/`.viewer` 동일성·복구 kind 부재를
/// 확인하고, manifest의 section/DocInfo unknown record 기대값과 진단 개수를
/// 대조한다. 실저장본에서 실제 진단이 나오는 비-공허 앵커는
/// `legacy-common-control-property`의 hiddenComment 계열이다.
final class FixtureParseDiagnosticsTests: XCTestCase {
    private static let recoveredKinds: Set<HwpParseDiagnostic.Kind> = [
        .recoveredSection, .recoveredParagraph, .recoveredMemoParagraph,
    ]

    func testAllFixturesProduceIdenticalDeterministicDiagnosticsInBothModes() throws {
        let fixtures = try FixtureLoader.loadAll().filter { $0.manifest.expectedError == nil }
        expect(fixtures).notTo(beEmpty())

        var totalDiagnosticCount = 0
        for fixture in fixtures {
            let fixtureId = fixture.manifest.id
            let defaultFile = try HwpFile(fromPath: fixture.documentURL.path)
            let viewerFile = try HwpFile(
                fromPath: fixture.documentURL.path, options: .viewer
            )
            let diagnostics = defaultFile.parseDiagnostics()

            // 결정성: 같은 모델에서 두 번 걸어도 같다.
            expect(defaultFile.parseDiagnostics()).to(
                equal(diagnostics),
                description: "\(fixtureId): diagnostics must be deterministic"
            )
            // unknown record payload는 뷰어 모드에서도 분리 복사로 보존되므로
            // 두 로드 모드의 진단은 같아야 한다.
            expect(viewerFile.parseDiagnostics()).to(
                equal(diagnostics),
                description: "\(fixtureId): default/viewer diagnostics must match"
            )
            // 정상 픽스처에서 복구 kind는 절대 나오지 않는다.
            expect(diagnostics.filter { Self.recoveredKinds.contains($0.kind) }).to(
                beEmpty(),
                description: "\(fixtureId): recovered kinds must not fire on healthy fixtures"
            )
            // path 접두사 계약 — BodyText/ViewText/DocInfo 셋뿐이다.
            let invalidPaths = diagnostics.map(\.path).filter { path in
                !path.hasPrefix("docInfo")
                    && !path.hasPrefix("section[")
                    && !path.hasPrefix("viewSection[")
            }
            expect(invalidPaths).to(
                beEmpty(),
                description: "\(fixtureId): unexpected diagnostic path prefixes"
            )
            totalDiagnosticCount += diagnostics.count
        }
        // 공허 gate — 실저장본에서 실제 진단이 잡힌다
        // (legacy-common-control-property의 hiddenComment unknown child 3건 이상).
        expect(totalDiagnosticCount).to(beGreaterThanOrEqualTo(3))
    }

    func testSectionAndDocInfoUnknownRecordDiagnosticsMatchManifests() throws {
        let fixtures = try FixtureLoader.loadAll().filter { $0.manifest.expectedError == nil }
        var assertedFixtureCount = 0

        for fixture in fixtures {
            let expectations = fixture.manifest.expectations
            guard expectations.sectionUnknownRecordCount != nil
                || expectations.docInfoUnknownRecordCount != nil
            else {
                continue
            }
            assertedFixtureCount += 1
            let fixtureId = fixture.manifest.id
            let diagnostics = try HwpFile(fromPath: fixture.documentURL.path)
                .parseDiagnostics()

            if let expectedCount = expectations.sectionUnknownRecordCount {
                let records = diagnostics.filter {
                    Self.isTopLevelUnknownRecord($0, rootPattern: #"section\[\d+\]\."#)
                }
                expect(records.count).to(
                    equal(expectedCount),
                    description: "\(fixtureId): section unknown record diagnostic count"
                )
                if let expectedTagIds = expectations.sectionUnknownRecordTagIds {
                    expect(records.compactMap(\.tagId)).to(
                        equal(expectedTagIds),
                        description: "\(fixtureId): section unknown record tag ids"
                    )
                }
            }
            if let expectedCount = expectations.docInfoUnknownRecordCount {
                let records = diagnostics.filter {
                    Self.isTopLevelUnknownRecord($0, rootPattern: #"docInfo\."#)
                }
                expect(records.count).to(
                    equal(expectedCount),
                    description: "\(fixtureId): DocInfo unknown record diagnostic count"
                )
                if let expectedTagIds = expectations.docInfoUnknownRecordTagIds {
                    expect(records.compactMap(\.tagId)).to(
                        equal(expectedTagIds),
                        description: "\(fixtureId): DocInfo unknown record tag ids"
                    )
                }
            }
        }
        // 공허 gate — unknown record 기대값을 가진 manifest가 실제로 대조됐다.
        expect(assertedFixtureCount).to(beGreaterThanOrEqualTo(20))
    }

    func testManifestComparisonFilterDetectsSyntheticUnknownRecords() throws {
        // 실제 manifest의 unknown record 기대값은 현재 전부 0이라 위 대조가
        // 0 == 0로만 지나간다 — 필터 정규식이 깨져도 초록이 되지 않도록, 합성
        // manifest + 합성 문서로 양성 대조군을 둔다
        // (`FixtureSectionUnknownRecordManifestTests`의 합성 manifest 선례).
        let manifest = try JSONDecoder().decode(FixtureManifest.self, from: Data("""
        {
          "id": "synthetic-parse-diagnostics-positive-control",
          "generationTool": "synthetic",
          "hwpVersion": "5.1.0.1",
          "source": "synthetic",
          "features": ["unknown-section-record"],
          "expectations": {
            "sectionUnknownRecordCount": 1,
            "sectionUnknownRecordTagIds": [766],
            "docInfoUnknownRecordCount": 1,
            "docInfoUnknownRecordTagIds": [761]
          }
        }
        """.utf8))
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: syntheticControlDocInfoData(),
            sectionDataArray: [syntheticControlSectionData()]
        )
        let diagnostics = hwp.parseDiagnostics()

        let sectionRecords = diagnostics.filter {
            Self.isTopLevelUnknownRecord($0, rootPattern: #"section\[\d+\]\."#)
        }
        // 최상위 unknown record(766)에 child(765)를 달아 두었다 — count가 1이면
        // `.child[j]` 재귀 진단이 최상위 필터에서 제외됨도 함께 증명된다.
        expect(sectionRecords.count) == manifest.expectations.sectionUnknownRecordCount
        expect(sectionRecords.compactMap(\.tagId))
            == manifest.expectations.sectionUnknownRecordTagIds

        let docInfoRecords = diagnostics.filter {
            Self.isTopLevelUnknownRecord($0, rootPattern: #"docInfo\."#)
        }
        expect(docInfoRecords.count) == manifest.expectations.docInfoUnknownRecordCount
        expect(docInfoRecords.compactMap(\.tagId))
            == manifest.expectations.docInfoUnknownRecordTagIds
    }

    func testLegacyFixtureHiddenCommentUnknownChildrenReportNestedChild() throws {
        // manifest otherControlSamples의 hiddenComment는 unknownChildTagIds
        // [72(LIST_HEADER), 66(PARA_HEADER)]와 손자 [68(PARA_CHAR_SHAPE)]를
        // 보존한다 — 진단이 같은 record를 컨트롤 path 밑에 노출하는지 고정한다.
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let diagnostics = hwp.parseDiagnostics()

        let anchor = diagnostics.first { diagnostic in
            diagnostic.kind == .unknownRecord
                && diagnostic.tagId == HwpSectionTag.listHeader.rawValue
                && diagnostic.path.contains(".ctrl[")
                && diagnostic.path.hasSuffix(".unknownChild[0]")
        }
        guard let anchor else {
            return fail("Expected hiddenComment LIST_HEADER unknown-child diagnostic")
        }
        let controlPath = String(anchor.path.dropLast(".unknownChild[0]".count))
        expect(diagnostics).to(contain(HwpParseDiagnostic(
            kind: .unknownRecord,
            tagId: HwpSectionTag.paraHeader.rawValue,
            path: "\(controlPath).unknownChild[1]"
        )))
        expect(diagnostics).to(contain(HwpParseDiagnostic(
            kind: .unknownRecord,
            tagId: HwpSectionTag.paraCharShape.rawValue,
            path: "\(controlPath).unknownChild[1].child[0]"
        )))
    }

    func testTrackChangesFixtureSplitsBodyAndViewTextDiagnosticsByPath() throws {
        // ViewText 픽스처는 track-changes 하나뿐이다 (배포용문서는 expectedError).
        let url = hwpURL(#file, "track-changes")
        let original = try HwpFile(fromPath: url.path)
        expect(original.viewSectionArray.count) == original.sectionArray.count
        expect(original.viewSectionArray).notTo(beEmpty())
        // 실측: 이 저장본은 BodyText·ViewText 모두 전부 typed 파싱된다 —
        // 여기서 진단이 생기면 typed 파싱 회귀 신호다.
        expect(original.parseDiagnostics()).to(beEmpty())

        // 실제 BodyText/ViewText stream 각각에 서로 다른 unknown record를
        // 주입해, 두 본문의 진단이 섞이지 않고 path 접두사로 갈리는지 고정한다
        // (plain-text-minimal raw record 주입 검증과 같은 조립 경로).
        let ole = try OLEFile(url.path)
        let reader = StreamReader(
            ole,
            try StreamReader.rootStreams(from: ole.root.children)
        )
        let isCompressed = original.fileHeader.fileProperty.isCompressed
        var sectionDataArray = try reader.getDataFromStorage(
            .bodyText, isCompressed, expectedCount: original.sectionArray.count
        )
        let viewTextData = try reader.getOptionalNamedDataFromStorage(
            .viewText, isCompressed, expectedChildCount: sectionDataArray.count
        )
        sectionDataArray[0].append(
            SectionRecordBuilder.record(tagId: 0x2FE, level: 0, payload: Data([0xB0]))
        )
        let injectedViewTextData = viewTextData.map { child in
            child.name == "Section0"
                ? (
                    name: child.name,
                    data: child.data + SectionRecordBuilder.record(
                        tagId: 0x2F0, level: 0, payload: Data([0xB1])
                    )
                )
                : child
        }

        let injected = try HwpFile(
            fileHeader: original.fileHeader,
            docInfo: original.docInfo,
            sectionDataArray: sectionDataArray,
            viewTextData: injectedViewTextData
        )
        expect(injected.viewSectionArray.count) == original.viewSectionArray.count
        expect(injected.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2FE, path: "section[0].unknownRecord[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2F0, path: "viewSection[0].unknownRecord[0]"
            ),
        ]
    }
}

private extension FixtureParseDiagnosticsTests {
    /// `<root>unknownRecord[i]` 꼴의 최상위 unknown record 진단인지 —
    /// `.child[j]` 재귀 진단과 문단 `unknownChild` 진단은 제외한다.
    static func isTopLevelUnknownRecord(
        _ diagnostic: HwpParseDiagnostic,
        rootPattern: String
    ) -> Bool {
        diagnostic.kind == .unknownRecord
            && diagnostic.path.range(
                of: "^\(rootPattern)unknownRecord\\[\\d+\\]$",
                options: .regularExpression
            ) != nil
    }
}

// MARK: - 양성 대조군용 합성 스트림 (프레이밍은 SectionRecordBuilder 위임)

/// 최상위 unknown record(766, child 765 포함) + 최소 문단 하나를 가진 구역.
private func syntheticControlSectionData() -> Data {
    var data = SectionRecordBuilder.record(tagId: 0x2FE, level: 0, payload: Data([0xCA]))
    data.append(SectionRecordBuilder.record(tagId: 0x2FD, level: 1, payload: Data([0xFE])))
    data.append(SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: syntheticControlParaHeaderPayload()
    ))
    data.append(SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
    ))
    return data
}

/// 최상위 unknown record(761)를 심은 최소 DocInfo (HwpFileHeader() = 5.1.0.1).
private func syntheticControlDocInfoData() -> Data {
    var data = SectionRecordBuilder.record(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: concatenatedData(
            SectionRecordBuilder.littleEndian(UInt16(1)),
            Data(repeating: 0, count: 24)
        )
    )
    data.append(SectionRecordBuilder.record(
        tagId: HwpDocInfoTag.idMappings.rawValue,
        level: 0,
        payload: Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
            data.append(SectionRecordBuilder.littleEndian(count))
        }
    ))
    data.append(SectionRecordBuilder.record(tagId: 0x2F9, level: 0, payload: Data([0x11])))
    return data
}

/// PARA_HEADER payload (5.0.3.2 이상 24 byte, 카운트 전부 0).
private func syntheticControlParaHeaderPayload() -> Data {
    var data = Data()
    data.append(SectionRecordBuilder.littleEndian(UInt32(0x8000_0000)))
    data.append(SectionRecordBuilder.littleEndian(UInt32(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt8(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt8(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt32(1)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    return data
}
