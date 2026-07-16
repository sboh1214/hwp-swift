@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpLoadOptions.preserveRawPayload` opt-out 검증.
///
/// 뷰어 옵션(`.viewer`)이 typed 파싱 결과를 바꾸지 않고 보존용 원본
/// 슬라이스만 비우는지 전체 픽스처를 default/viewer 양 모드로 로드해
/// 확인한다. on 모드의 원본 보존 자체는 기존 보존 테스트들이 커버한다.
final class RawPayloadOptOutTests: XCTestCase {
    func testViewerOptionsKeepParsedStructureIdentical() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let path = fixture.documentURL.path
            let preserved = try HwpFile(fromPath: path)
            let viewer = try HwpFile(fromPath: path, options: .viewer)

            assertStructurallyIdentical(viewer, preserved, fixture: fixture.manifest.id)
        }
    }

    func testViewerOptionsDropPreservationSlices() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let fixtureId = fixture.manifest.id
            let viewer = try HwpFile(fromPath: fixture.documentURL.path, options: .viewer)

            expect(viewer.docInfo.rawPayload.isEmpty).to(
                beTrue(),
                description: "\(fixtureId) viewer docInfo.rawPayload must be empty"
            )
            for section in viewer.sectionArray + viewer.viewSectionArray {
                expect(section.rawPayload.isEmpty).to(
                    beTrue(),
                    description: "\(fixtureId) viewer section.rawPayload must be empty"
                )
                guard let paragraph = section.paragraph.first else { continue }
                expect(paragraph.paraHeader.rawPayload.isEmpty).to(
                    beTrue(),
                    description: "\(fixtureId) viewer paraHeader.rawPayload must be empty"
                )
                if let paraText = paragraph.paraText {
                    expect(paraText.rawPayload.isEmpty).to(
                        beTrue(),
                        description: "\(fixtureId) viewer paraText.rawPayload must be empty"
                    )
                }
            }
            expect(viewer.summary.rawPayload.isEmpty).to(
                beTrue(),
                description: "\(fixtureId) viewer summary.rawPayload must be empty"
            )
            expect(viewer.previewImage.rawPayload.isEmpty).to(
                beTrue(),
                description: "\(fixtureId) viewer previewImage.rawPayload must be empty"
            )
            expect(viewer.previewImage.image.isEmpty).to(
                beTrue(),
                description: "\(fixtureId) viewer previewImage.image must be empty"
            )
        }
    }

    func testDefaultOptionsStillPreserveRawPayloadSmoke() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            // on 모드 원본 보존은 기존 보존 테스트가 상세 커버 — 여기서는 스모크만
            let preserved = try HwpFile(fromPath: fixture.documentURL.path)
            expect(preserved.sectionArray.first?.rawPayload.isEmpty).to(
                beFalse(),
                description: "\(fixture.manifest.id) default mode must keep section rawPayload"
            )
            expect(preserved.docInfo.rawPayload.isEmpty).to(
                beFalse(),
                description: "\(fixture.manifest.id) default mode must keep docInfo rawPayload"
            )
        }
    }

    func testUnparsableFixturesThrowIdenticallyInBothModes() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError != nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let path = fixture.documentURL.path
            expect(try HwpFile(fromPath: path)).to(
                throwError(),
                description: "\(fixture.manifest.id) must throw in default mode"
            )
            expect(try HwpFile(fromPath: path, options: .viewer)).to(
                throwError(),
                description: "\(fixture.manifest.id) must throw in viewer mode"
            )
        }
    }
}

private extension RawPayloadOptOutTests {
    func assertStructurallyIdentical(
        _ viewer: HwpFile,
        _ preserved: HwpFile,
        fixture fixtureId: String
    ) {
        expect(viewer.sectionArray.count).to(
            equal(preserved.sectionArray.count),
            description: "\(fixtureId) section count"
        )
        expect(viewer.viewSectionArray.count).to(
            equal(preserved.viewSectionArray.count),
            description: "\(fixtureId) view section count"
        )
        assertSectionsIdentical(
            viewer.sectionArray,
            preserved.sectionArray,
            fixture: fixtureId
        )
        assertSectionsIdentical(
            viewer.viewSectionArray,
            preserved.viewSectionArray,
            fixture: fixtureId
        )
        assertDocInfoCountsIdentical(viewer.docInfo, preserved.docInfo, fixture: fixtureId)
        expect(viewer.previewText.text).to(
            equal(preserved.previewText.text),
            description: "\(fixtureId) previewText.text"
        )
        expect(viewer.previewImage.format).to(
            equal(preserved.previewImage.format),
            description: "\(fixtureId) previewImage.format"
        )
    }

    func assertSectionsIdentical(
        _ viewerSections: [HwpSection],
        _ preservedSections: [HwpSection],
        fixture fixtureId: String
    ) {
        for (viewerSection, preservedSection) in zip(viewerSections, preservedSections) {
            expect(viewerSection.paragraph.count).to(
                equal(preservedSection.paragraph.count),
                description: "\(fixtureId) paragraph count"
            )
            for (viewerParagraph, preservedParagraph)
                in zip(viewerSection.paragraph, preservedSection.paragraph)
            {
                expect(viewerParagraph.paraText == nil).to(
                    equal(preservedParagraph.paraText == nil),
                    description: "\(fixtureId) paraText presence"
                )
                // HwpChar == 는 type/value 비교 — typed 텍스트 동치 확인
                expect(viewerParagraph.paraText?.charArray ?? []).to(
                    equal(preservedParagraph.paraText?.charArray ?? []),
                    description: "\(fixtureId) paraText charArray"
                )
                expect(viewerParagraph.paraHeader.charCount).to(
                    equal(preservedParagraph.paraHeader.charCount),
                    description: "\(fixtureId) paraHeader charCount"
                )
                expect(viewerParagraph.ctrlHeaderArray?.count ?? -1).to(
                    equal(preservedParagraph.ctrlHeaderArray?.count ?? -1),
                    description: "\(fixtureId) ctrlHeader count"
                )
            }
        }
    }

    func assertDocInfoCountsIdentical(
        _ viewer: HwpDocInfo,
        _ preserved: HwpDocInfo,
        fixture fixtureId: String
    ) {
        expect(viewer.idMappings.charShapeArray.count).to(
            equal(preserved.idMappings.charShapeArray.count),
            description: "\(fixtureId) charShape count"
        )
        expect(viewer.idMappings.paraShapeArray.count).to(
            equal(preserved.idMappings.paraShapeArray.count),
            description: "\(fixtureId) paraShape count"
        )
        expect(viewer.idMappings.faceNameKoreanArray.count).to(
            equal(preserved.idMappings.faceNameKoreanArray.count),
            description: "\(fixtureId) faceName count"
        )
        expect(viewer.idMappings.borderFillArray.count).to(
            equal(preserved.idMappings.borderFillArray.count),
            description: "\(fixtureId) borderFill count"
        )
        expect(viewer.idMappings.styleArray.count).to(
            equal(preserved.idMappings.styleArray.count),
            description: "\(fixtureId) style count"
        )
        expect(viewer.idMappings.binDataArray.count).to(
            equal(preserved.idMappings.binDataArray.count),
            description: "\(fixtureId) binData count"
        )
        expect(viewer.idMappings.numberingArray.count).to(
            equal(preserved.idMappings.numberingArray.count),
            description: "\(fixtureId) numbering count"
        )
        expect(viewer.idMappings.tabDefArray.count).to(
            equal(preserved.idMappings.tabDefArray.count),
            description: "\(fixtureId) tabDef count"
        )
        expect(viewer.memoShapeArray.count).to(
            equal(preserved.memoShapeArray.count),
            description: "\(fixtureId) memoShape count"
        )
        expect(viewer.trackChangeArray.count).to(
            equal(preserved.trackChangeArray.count),
            description: "\(fixtureId) trackChange count"
        )
    }
}
